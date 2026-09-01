extends Node2D

## Two-process fog-of-war probe for LAN clients. Reproduces "the client sees
## an all-black map": after the match starts on both sides, the CLIENT prints
## its FogOfWar perspective (local_player_id) and how many cells its own
## units actually revealed. Run like check_net_smoke:
##   CALIMA_NET_ROLE=host   $GODOT --headless --path project res://tools/check_net_fog.tscn
##   CALIMA_NET_ROLE=client $GODOT --headless --path project res://tools/check_net_fog.tscn

const TIMEOUT: float = 45.0

func _ready() -> void:
	NetworkSession.auto_change_scene = false
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void:
		print("NET_FOG %s: TIMEOUT" % OS.get_environment("CALIMA_NET_ROLE").to_upper())
		get_tree().quit(1))
	var port_env: String = OS.get_environment("CALIMA_NET_PORT")
	var port: int = int(port_env) if not port_env.is_empty() else 8913
	if OS.get_environment("CALIMA_NET_ROLE") == "host":
		_run_host(port)
	else:
		_run_client(port)

func _base_config() -> void:
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242

func _boot_world() -> Node2D:
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	return world

func _run_host(port: int) -> void:
	_base_config()
	if NetworkSession.host_game(port) != OK:
		print("NET_FOG HOST: FAIL — could not open port %d" % port)
		get_tree().quit(1)
		return
	print("NET_FOG HOST: listening on %d" % port)
	while NetworkSession.player_count() < 2:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.8).timeout
	NetworkSession.start_match()
	var _world: Node2D = _boot_world()
	await get_tree().create_timer(25.0).timeout
	print("NET_FOG HOST: done")
	get_tree().quit(0)

func _run_client(port: int) -> void:
	NetworkSession.player_name = "FogBot"
	NetworkSession.match_started.connect(func() -> void:
		_base_config()
		var world: Node2D = _boot_world()
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			_report(world))
	, CONNECT_DEFERRED)
	if NetworkSession.join_game("127.0.0.1", port) != OK:
		print("NET_FOG CLIENT: FAIL — join error")
		get_tree().quit(1)

func _report(world: Node2D) -> void:
	var fog: FogOfWar = world.get("_fog") as FogOfWar
	if fog == null:
		print("NET_FOG CLIENT: FAIL — no fog node")
		get_tree().quit(1)
		return
	var visible_cells: int = 0
	var explored_cells: int = 0
	var cells: PackedByteArray = fog.get("_cells") as PackedByteArray
	for i: int in range(cells.size()):
		if cells[i] == FogOfWar.STATE_VISIBLE:
			visible_cells += 1
		elif cells[i] == FogOfWar.STATE_EXPLORED:
			explored_cells += 1
	var own_units: int = 0
	for unit: Node in (world.units_layer as Node).get_children():
		if is_instance_valid(unit) and unit.get("player_id") != null \
				and (unit.get("player_id") as int) == NetworkSession.local_player_id:
			own_units += 1
	print("NET_FOG CLIENT: local_player_id=%d fog_pid=%d own_units=%d visible=%d explored=%d total=%d" % [
		NetworkSession.local_player_id, fog.local_player_id, own_units,
		visible_cells, explored_cells, cells.size()])
	var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if not shot_dir.is_empty():
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(shot_dir)
		img.save_png(shot_dir + "/net_fog_client.png")
		print("NET_FOG CLIENT: screenshot saved")
	if visible_cells > 0:
		print("NET_FOG CLIENT: OK — fog reveals around own units")
		get_tree().quit(0)
	else:
		print("NET_FOG CLIENT: FAIL — nothing revealed, map is all shroud")
		get_tree().quit(1)

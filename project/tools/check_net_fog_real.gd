extends Node2D

## Like check_net_fog but through the REAL match-start path: default lobby
## settings (weather on), auto_change_scene = true so the client swaps to
## game_world.tscn exactly like a player does. Watcher timers parented to
## root survive the scene change (the probe scene itself is freed by it, so
## nothing may reference `self` after start) and report fog + screenshot.
##   CALIMA_NET_ROLE=host   $GODOT --headless --path project res://tools/check_net_fog_real.tscn
##   CALIMA_NET_ROLE=client $GODOT --path project res://tools/check_net_fog_real.tscn

const TIMEOUT: float = 60.0

class QuitTimer extends Timer:
	var message: String = ""
	var exit_code: int = 1
	func _init(msg: String, code: int, secs: float) -> void:
		message = msg
		exit_code = code
		wait_time = secs
		one_shot = true
		autostart = true
		timeout.connect(_fire)
	func _fire() -> void:
		print(message)
		get_tree().quit(exit_code)

class ClientWatcher extends Timer:
	func _init() -> void:
		wait_time = 10.0
		one_shot = true
		timeout.connect(_report)
	func _report() -> void:
		var world: Node = get_tree().current_scene
		print("NET_FOG_REAL CLIENT: current_scene=%s" % (world.scene_file_path if world != null else "<null>"))
		if world == null or not world.scene_file_path.contains("game_world"):
			print("NET_FOG_REAL CLIENT: FAIL — scene change never happened")
			get_tree().quit(1)
			return
		var fog: FogOfWar = world.get("_fog") as FogOfWar
		var visible_cells: int = 0
		if fog != null:
			var cells: PackedByteArray = fog.get("_cells") as PackedByteArray
			for i: int in range(cells.size()):
				if cells[i] == FogOfWar.STATE_VISIBLE:
					visible_cells += 1
		var own_units: int = 0
		for unit: Node in (world.get("units_layer") as Node).get_children():
			if is_instance_valid(unit) and unit.get("player_id") != null \
					and (unit.get("player_id") as int) == NetworkSession.local_player_id:
				own_units += 1
		var cam: Camera2D = world.get("camera") as Camera2D
		print("NET_FOG_REAL CLIENT: pid=%d own_units=%d visible=%d cam=%s zoom=%s" % [
			NetworkSession.local_player_id, own_units, visible_cells,
			str(cam.position) if cam != null else "<none>",
			str(cam.zoom) if cam != null else "-"])
		var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
		if not shot_dir.is_empty():
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(shot_dir)
			img.save_png(shot_dir + "/net_fog_real_client.png")
			print("NET_FOG_REAL CLIENT: screenshot saved")
		if visible_cells > 0:
			print("NET_FOG_REAL CLIENT: OK")
			get_tree().quit(0)
		else:
			print("NET_FOG_REAL CLIENT: FAIL — all shroud")
			get_tree().quit(1)

func _ready() -> void:
	var role: String = OS.get_environment("CALIMA_NET_ROLE")
	get_tree().root.add_child.call_deferred(
		QuitTimer.new("NET_FOG_REAL %s: TIMEOUT" % role.to_upper(), 1, TIMEOUT))
	var port_env: String = OS.get_environment("CALIMA_NET_PORT")
	var port: int = int(port_env) if not port_env.is_empty() else 8914
	if role == "host":
		_run_host(port)
	else:
		_run_client(port)

func _run_host(port: int) -> void:
	NetworkSession.auto_change_scene = true
	if NetworkSession.host_game(port) != OK:
		print("NET_FOG_REAL HOST: FAIL — could not open port %d" % port)
		get_tree().quit(1)
		return
	print("NET_FOG_REAL HOST: listening on %d" % port)
	var map_env: String = OS.get_environment("CALIMA_MAP")
	if not map_env.is_empty():
		MatchConfig.map_type = int(map_env)
	var size_env: String = OS.get_environment("CALIMA_MAP_SIZE")
	if not size_env.is_empty():
		MatchConfig.map_size = int(size_env)
	while NetworkSession.player_count() < 2:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.0).timeout
	get_tree().root.add_child(QuitTimer.new("NET_FOG_REAL HOST: done", 0, 30.0))
	NetworkSession.start_match()

func _run_client(port: int) -> void:
	NetworkSession.player_name = "FogBot"
	NetworkSession.auto_change_scene = true
	var watcher: ClientWatcher = ClientWatcher.new()
	get_tree().root.add_child.call_deferred(watcher)
	NetworkSession.match_started.connect(watcher.start.bind(10.0), CONNECT_DEFERRED)
	if NetworkSession.join_game("127.0.0.1", port) != OK:
		print("NET_FOG_REAL CLIENT: FAIL — join error")
		get_tree().quit(1)

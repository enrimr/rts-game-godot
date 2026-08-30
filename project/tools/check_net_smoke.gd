extends Node2D

## Two-process smoke gate for the multiplayer command pipe. Run one instance
## as host and one as client (same machine, localhost):
##   CALIMA_NET_ROLE=host   $GODOT --headless --path project res://tools/check_net_smoke.tscn
##   CALIMA_NET_ROLE=client $GODOT --headless --path project res://tools/check_net_smoke.tscn
## The host opens a session and starts the match once the client connects;
## both load the SAME world (shared seed → identical entity IDs); the client
## orders its scout to move through the redirected CommandBus, and the host
## asserts the command arrived stamped as player 1 AND that the scout actually
## moved in ITS simulation.

const TIMEOUT: float = 40.0

var _matched: bool = false

func _ready() -> void:
	NetworkSession.auto_change_scene = false
	NetworkSession.match_started.connect(func() -> void: _matched = true)
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void:
		print("NET_SMOKE %s: TIMEOUT" % OS.get_environment("CALIMA_NET_ROLE").to_upper())
		get_tree().quit(1))
	var port_env: String = OS.get_environment("CALIMA_NET_PORT")
	var port: int = int(port_env) if not port_env.is_empty() else 8911
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

func _own_scout(world: Node2D, pid: int) -> Node2D:
	for unit: Node in (world.units_layer as Node).get_children():
		if unit is Scout and (unit.get("player_id") as int) == pid:
			return unit as Node2D
	return null

func _run_host(port: int) -> void:
	_base_config()
	if NetworkSession.host_game(port) != OK:
		print("NET_SMOKE HOST: FAIL — could not open port %d" % port)
		get_tree().quit(1)
		return
	print("NET_SMOKE HOST: listening on %d" % port)
	while NetworkSession.player_count() < 2:
		await get_tree().create_timer(0.2).timeout
	# Lobby roster checks: the client's profile lands, colours stay unique.
	await get_tree().create_timer(0.8).timeout
	var roster: Dictionary = NetworkSession.get_roster()
	if roster.size() != 2 or str((roster.get(1, {}) as Dictionary).get("name")) != "SmokeBot":
		print("NET_SMOKE HOST: FAIL — roster %s" % str(roster))
		get_tree().quit(1)
		return
	NetworkSession.request_color(3)
	NetworkSession.request_color(3)   # idempotent for self
	if ((NetworkSession.get_roster()[0] as Dictionary)["color"] as int) != 3:
		print("NET_SMOKE HOST: FAIL — colour pick rejected")
		get_tree().quit(1)
		return
	print("NET_SMOKE HOST: roster ok (%s, colour 3), starting match"
		% str((roster[1] as Dictionary)["name"]))
	NetworkSession.start_match()
	var world: Node2D = _boot_world()
	await get_tree().create_timer(2.0).timeout

	var rival_scout: Node2D = _own_scout(world, 1)
	if rival_scout == null:
		print("NET_SMOKE HOST: FAIL — no player-1 scout in the host world")
		get_tree().quit(1)
		return
	var start_pos: Vector2 = rival_scout.global_position
	var deadline: float = Time.get_ticks_msec() / 1000.0 + 20.0
	var got_command: bool = false
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
		for entry: Dictionary in CommandBus.log_entries():
			if (entry.get("player", -1) as int) == 1 and (entry.get("kind", "") as String) == "unit_point":
				got_command = true
		if got_command and is_instance_valid(rival_scout) \
				and rival_scout.global_position.distance_to(start_pos) > 40.0:
			print("NET_SMOKE HOST: player-1 command executed, scout moved %.0f px"
				% rival_scout.global_position.distance_to(start_pos))
			print("NET_SMOKE HOST: done")
			get_tree().quit(0)
			return
	print("NET_SMOKE HOST: FAIL — command=%s moved=%.0f" % [str(got_command),
		rival_scout.global_position.distance_to(start_pos) if is_instance_valid(rival_scout) else -1.0])
	get_tree().quit(1)

func _run_client(port: int) -> void:
	NetworkSession.player_name = "SmokeBot"
	if NetworkSession.join_game("127.0.0.1", port) != OK:
		print("NET_SMOKE CLIENT: FAIL — join error")
		get_tree().quit(1)
		return
	while not _matched:
		await get_tree().create_timer(0.2).timeout
	if MatchConfig.forced_seed != 4242 or NetworkSession.local_player_id != 1:
		print("NET_SMOKE CLIENT: FAIL — seed=%d pid=%d" % [
			MatchConfig.forced_seed, NetworkSession.local_player_id])
		get_tree().quit(1)
		return
	if PlayerColors.get_color(0) != PlayerColors.COLORS[3]:
		print("NET_SMOKE CLIENT: FAIL — host colour pick did not replicate")
		get_tree().quit(1)
		return
	print("NET_SMOKE CLIENT: config received, booting mirror world")
	var world: Node2D = _boot_world()
	await get_tree().create_timer(2.5).timeout

	var scout: Node2D = _own_scout(world, NetworkSession.local_player_id)
	if scout == null:
		print("NET_SMOKE CLIENT: FAIL — no own scout in the mirror world")
		get_tree().quit(1)
		return
	# The redirected CommandBus ships this to the host instead of executing.
	CommandBus.submit(UnitPointCommand.make(NetworkSession.local_player_id, "move",
		[EntityRegistry.id_of(scout)] as Array[int],
		scout.global_position + Vector2(300.0, 120.0)))
	print("NET_SMOKE CLIENT: move command sent for scout id %d" % EntityRegistry.id_of(scout))
	assert(CommandBus.log_entries().is_empty(), "a client must never execute locally")
	await get_tree().create_timer(4.0).timeout
	print("NET_SMOKE CLIENT: done")
	get_tree().quit(0)

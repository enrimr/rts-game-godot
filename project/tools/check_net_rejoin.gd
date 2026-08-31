extends Node2D

## Three-process reconnection gate:
##   host    — starts a match with one human rival, survives its drop (seat
##             held), accepts the SAME name back mid-match and resyncs it.
##   drop    — first client: joins, moves its scout, then quits abruptly.
##   return  — second client (same name, launched within the grace window):
##             rejoins, must get its OLD player id and a mirror world whose
##             scout stands at the MOVED position (proof the resync landed).
## Run: host (bg) → drop → wait ~12 s → return. Same CALIMA_NET_PORT.

var _matched: bool = false
var _winner: int = -99
var _returned: bool = false

func _ready() -> void:
	NetworkSession.auto_change_scene = false
	NetworkSession.match_started.connect(func() -> void: _matched = true)
	GameManager.game_over.connect(func(w: int) -> void: _winner = w)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("REJOIN %s: TIMEOUT" % OS.get_environment("CALIMA_REJOIN_ROLE"))
		get_tree().quit(1))
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	var port: int = int(OS.get_environment("CALIMA_NET_PORT"))
	match OS.get_environment("CALIMA_REJOIN_ROLE"):
		"host": _run_host(port)
		"drop": _run_drop(port)
		"return": _run_return(port)

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
	NetworkSession.host_game(port)
	while NetworkSession.player_count() < 2:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.5).timeout
	NetworkSession.start_match()
	var world: Node2D = _boot_world()
	# Wait out: client moves, drops (ENet timeout), then returns.
	NetworkSession.system_chat_received.connect(func(kind: String, _n: String) -> void:
		if kind == "returned":
			_returned = true)
	var deadline: float = Time.get_ticks_msec() / 1000.0 + 70.0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
		if _winner != -99:
			print("REJOIN HOST: FAIL — match ended (winner %d) instead of holding the seat" % _winner)
			get_tree().quit(1)
			return
		if _returned and NetworkSession.get_roster().has(1):
			# Give the resync a moment, then confirm the match kept running.
			await get_tree().create_timer(6.0).timeout
			if _winner == -99:
				print("REJOIN HOST: seat held, player 1 returned, match still live")
				print("REJOIN HOST: done")
				get_tree().quit(0)
			else:
				print("REJOIN HOST: FAIL — match ended right after the rejoin")
				get_tree().quit(1)
			return
	print("REJOIN HOST: FAIL — the player never came back")
	get_tree().quit(1)

func _run_drop(port: int) -> void:
	NetworkSession.player_name = "Rejoiner"
	NetworkSession.join_game("127.0.0.1", port)
	while not _matched:
		await get_tree().create_timer(0.2).timeout
	var world: Node2D = _boot_world()
	await get_tree().create_timer(2.5).timeout
	var scout: Node2D = _own_scout(world, 1)
	CommandBus.submit(UnitPointCommand.make(1, "move",
		[EntityRegistry.id_of(scout)] as Array[int],
		scout.global_position + Vector2(260.0, 100.0)))
	print("REJOIN DROP: moved the scout, now dying abruptly")
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(0)

func _run_return(port: int) -> void:
	NetworkSession.player_name = "Rejoiner"
	NetworkSession.join_game("127.0.0.1", port)
	while not _matched:
		await get_tree().create_timer(0.2).timeout
	if NetworkSession.local_player_id != 1 or not NetworkSession.rejoin_pending:
		print("REJOIN RETURN: FAIL — pid=%d rejoin_pending=%s" % [
			NetworkSession.local_player_id, str(NetworkSession.rejoin_pending)])
		get_tree().quit(1)
		return
	print("REJOIN RETURN: old seat recovered (pid 1), booting mirror world")
	var world: Node2D = _boot_world()
	var deadline: float = Time.get_ticks_msec() / 1000.0 + 25.0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
		var scout: Node2D = _own_scout(world, 1)
		if scout != null and scout.global_position.distance_to(
				Vector2(-534.3273, -806.5097)) > 0.0:
			# The seed-fresh world spawns the scout at TC+(80,-60); after the
			# resync keyframe it must stand far from that spawn.
			var tcs: Dictionary = world.get("_ai_town_centers") as Dictionary
			var tc: Node2D = tcs.get(1) as Node2D
			var spawn: Vector2 = tc.global_position + Vector2(80.0, -60.0)
			if scout.global_position.distance_to(spawn) > 120.0:
				print("REJOIN RETURN: resync landed — scout %d px from its spawn"
					% int(scout.global_position.distance_to(spawn)))
				print("REJOIN RETURN: done")
				get_tree().quit(0)
				return
	print("REJOIN RETURN: FAIL — mirror world never caught up")
	get_tree().quit(1)

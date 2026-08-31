extends Node2D

## Two-process robustness gate (CALIMA_ROB_CASE = drop | resign | hostleft):
## drop — the client quits abruptly; the host must end the match (winner 0).
## resign — the client surrenders; local defeat + host ends the match.
## hostleft — the host quits; the client must get connection_lost + dialog.
## Run host first (backgrounded), then client, same CALIMA_NET_PORT.

var _matched: bool = false
# The drop case waits out the (shrunken) rejoin grace before the resignation.
var _lost: bool = false
var _winner: int = -99

func _ready() -> void:
	NetworkSession.auto_change_scene = false
	NetworkSession.match_started.connect(func() -> void: _matched = true)
	NetworkSession.connection_lost.connect(func() -> void: _lost = true)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("ROB %s: TIMEOUT" % OS.get_environment("CALIMA_NET_ROLE"))
		get_tree().quit(1))
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	var port: int = int(OS.get_environment("CALIMA_NET_PORT"))
	if OS.get_environment("CALIMA_NET_ROLE") == "host":
		_run_host(port)
	else:
		_run_client(port)

func _boot_world() -> Node2D:
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	return world

func _run_host(port: int) -> void:
	NetworkSession.host_game(port)
	while NetworkSession.player_count() < 2:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.5).timeout
	NetworkSession.start_match()
	var _world: Node2D = _boot_world()
	var case_name: String = OS.get_environment("CALIMA_ROB_CASE")
	if case_name == "hostleft":
		await get_tree().create_timer(4.0).timeout
		print("ROB HOST: quitting abruptly")
		get_tree().quit(0)
		return
	# drop / resign: wait for the match to END with the host as winner.
	GameManager.game_over.connect(func(w: int) -> void: _winner = w)
	var deadline: float = Time.get_ticks_msec() / 1000.0 + 30.0
	while _winner == -99 and Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
	if _winner == 0:
		print("ROB HOST: match ended, winner 0 (%s)" % case_name)
		await get_tree().create_timer(2.0).timeout
		print("ROB HOST: done")
		get_tree().quit(0)
	else:
		print("ROB HOST: FAIL — winner=%d" % _winner)
		get_tree().quit(1)

func _run_client(port: int) -> void:
	NetworkSession.player_name = "RobBot"
	NetworkSession.join_game("127.0.0.1", port)
	while not _matched:
		await get_tree().create_timer(0.2).timeout
	var world: Node2D = _boot_world()
	await get_tree().create_timer(3.0).timeout
	match OS.get_environment("CALIMA_ROB_CASE"):
		"drop":
			print("ROB CLIENT: quitting abruptly mid-match")
			get_tree().quit(0)
		"resign":
			GameManager.game_over.connect(func(w: int) -> void: _winner = w)
			print("ROB CLIENT: surrendering (resign + local defeat)")
			NetworkSession.resign()
			GameManager.declare_winner(-1)
			var deadline: float = Time.get_ticks_msec() / 1000.0 + 10.0
			while _winner == -99 and Time.get_ticks_msec() / 1000.0 < deadline:
				await get_tree().create_timer(0.3).timeout
			if _winner != NetworkSession.local_player_id and _winner != -99:
				print("ROB CLIENT: defeat shown locally (winner=%d)" % _winner)
				await get_tree().create_timer(3.0).timeout
				print("ROB CLIENT: done")
				get_tree().quit(0)
			else:
				print("ROB CLIENT: FAIL — winner=%d" % _winner)
				get_tree().quit(1)
		"hostleft":
			var deadline: float = Time.get_ticks_msec() / 1000.0 + 15.0
			while not _lost and Time.get_ticks_msec() / 1000.0 < deadline:
				await get_tree().create_timer(0.3).timeout
			if not _lost:
				print("ROB CLIENT: FAIL — connection_lost never fired")
				get_tree().quit(1)
				return
			await get_tree().create_timer(0.5).timeout
			var dialog_found: bool = false
			for c: Node in (world.get("hud") as Node).get_children():
				if c is AcceptDialog:
					dialog_found = true
			print("ROB CLIENT: connection_lost fired, dialog=%s" % str(dialog_found))
			get_tree().quit(0 if dialog_found else 1)

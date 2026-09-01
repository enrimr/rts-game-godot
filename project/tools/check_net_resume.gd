extends Node2D

## Two-phase, four-process gate for resuming a multiplayer save.
##   Phase 1 — create the save:
##     host_save   — hosts, starts the match, waits for the client's move,
##                   saves to SLOT (multiplayer sheet + per-player fog).
##     client_save — joins, moves its scout so the save has proof of life,
##                   stays connected until the host saved (fog collection).
##   Phase 2 — resume it:
##     host_resume   — hosts again, begin_resume(SLOT), waits for the seat
##                     claim, starts; the restored world must keep running.
##     client_resume — joins with the SAME name, must get pid 1 + the resumed
##                     flag, boot an EMPTY world, receive the resync (own
##                     scout + TC + explored fog) and round-trip a command.
## Run each phase's host backgrounded first; same CALIMA_NET_PORT everywhere.

const SLOT: int = 89

var _matched: bool = false
var _winner: int = -99

func _ready() -> void:
	NetworkSession.auto_change_scene = false
	NetworkSession.match_started.connect(func() -> void: _matched = true)
	GameManager.game_over.connect(func(w: int) -> void: _winner = w)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("RESUME %s: TIMEOUT" % OS.get_environment("CALIMA_RESUME_ROLE"))
		get_tree().quit(1))
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	var port: int = int(OS.get_environment("CALIMA_NET_PORT"))
	match OS.get_environment("CALIMA_RESUME_ROLE"):
		"host_save": _run_host_save(port)
		"client_save": _run_client_save(port)
		"host_resume": _run_host_resume(port)
		"client_resume": _run_client_resume(port)

func _boot_world() -> Node2D:
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	return world

func _own_scout(world: Node2D, pid: int) -> Node2D:
	for unit: Node in (world.units_layer as Node).get_children():
		if unit is Scout and (unit.get("player_id") as int) == pid:
			return unit as Node2D
	return null

func _own_tc(world: Node2D, pid: int) -> Node2D:
	for bld: Node in (world.buildings_layer as Node).get_children():
		if bld is TownCenterBuilding and (bld.get("player_id") as int) == pid:
			return bld as Node2D
	return null

# ── Phase 1 ──────────────────────────────────────────────────────────────────

func _run_host_save(port: int) -> void:
	SaveManager.delete_save(SLOT)
	NetworkSession.player_name = "Anfitrion"
	NetworkSession.host_game(port)
	while NetworkSession.player_count() < 2:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.5).timeout
	NetworkSession.start_match()
	var world: Node2D = _boot_world()
	# Let the client's move command land and the fog tick a few times.
	await get_tree().create_timer(6.0).timeout
	var ok: bool = await SaveManager.save_game(world, SLOT)
	if not ok:
		print("RESUME HOST_SAVE: FAIL — save_game returned false")
		get_tree().quit(1)
		return
	var meta: Dictionary = {}
	for entry: Dictionary in SaveManager.list_saves():
		if (entry.get("slot", 0) as int) == SLOT:
			meta = entry
	if not (meta.get("multiplayer", false) as bool):
		print("RESUME HOST_SAVE: FAIL — save has no multiplayer sheet")
		get_tree().quit(1)
		return
	if NetworkSession.client_fogs.is_empty():
		print("RESUME HOST_SAVE: FAIL — no client fog was collected")
		get_tree().quit(1)
		return
	print("RESUME HOST_SAVE: multiplayer save written (players: %s)"
		% str(meta.get("player_names", [])))
	print("RESUME HOST_SAVE: done")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

func _run_client_save(port: int) -> void:
	NetworkSession.player_name = "Resumer"
	NetworkSession.join_game("127.0.0.1", port)
	while not _matched:
		await get_tree().create_timer(0.2).timeout
	var world: Node2D = _boot_world()
	await get_tree().create_timer(2.5).timeout
	var scout: Node2D = _own_scout(world, 1)
	CommandBus.submit(UnitPointCommand.make(1, "move",
		[EntityRegistry.id_of(scout)] as Array[int],
		scout.global_position + Vector2(260.0, 100.0)))
	print("RESUME CLIENT_SAVE: moved the scout, holding for the host's save")
	# Stay connected: the host needs this peer alive to collect its fog.
	await get_tree().create_timer(9.0).timeout
	print("RESUME CLIENT_SAVE: done")
	get_tree().quit(0)

# ── Phase 2 ──────────────────────────────────────────────────────────────────

func _run_host_resume(port: int) -> void:
	NetworkSession.host_game(port)
	if not NetworkSession.begin_resume(SLOT):
		print("RESUME HOST_RESUME: FAIL — begin_resume refused the save")
		get_tree().quit(1)
		return
	if not NetworkSession.resume_active:
		print("RESUME HOST_RESUME: FAIL — resume_active not set")
		get_tree().quit(1)
		return
	# Wait for the original client to claim seat 1.
	while not NetworkSession.get_roster().has(1):
		await get_tree().create_timer(0.2).timeout
	print("RESUME HOST_RESUME: seat 1 reclaimed, starting the restored match")
	await get_tree().create_timer(0.5).timeout
	NetworkSession.start_match()
	var world: Node2D = _boot_world()
	# The restored world must hold: no spurious game-over, both scouts alive.
	await get_tree().create_timer(14.0).timeout
	if _winner != -99:
		print("RESUME HOST_RESUME: FAIL — match ended (winner %d) after restore" % _winner)
		get_tree().quit(1)
		return
	if _own_scout(world, 1) == null:
		print("RESUME HOST_RESUME: FAIL — restored world lost player 1's scout")
		get_tree().quit(1)
		return
	print("RESUME HOST_RESUME: restored match running with both players")
	print("RESUME HOST_RESUME: done")
	SaveManager.delete_save(SLOT)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

func _run_client_resume(port: int) -> void:
	NetworkSession.player_name = "Resumer"
	NetworkSession.join_game("127.0.0.1", port)
	while not _matched:
		await get_tree().create_timer(0.2).timeout
	if NetworkSession.local_player_id != 1 or not NetworkSession.resumed_match \
			or not NetworkSession.rejoin_pending:
		print("RESUME CLIENT_RESUME: FAIL — pid=%d resumed=%s rejoin_pending=%s" % [
			NetworkSession.local_player_id, str(NetworkSession.resumed_match),
			str(NetworkSession.rejoin_pending)])
		get_tree().quit(1)
		return
	print("RESUME CLIENT_RESUME: original seat + resumed flag, booting empty mirror")
	var world: Node2D = _boot_world()
	var scout: Node2D = null
	var deadline: float = Time.get_ticks_msec() / 1000.0 + 30.0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
		scout = _own_scout(world, 1)
		if scout != null and _own_tc(world, 1) != null:
			break
	if scout == null or _own_tc(world, 1) == null:
		print("RESUME CLIENT_RESUME: FAIL — resync never delivered our scout/TC")
		get_tree().quit(1)
		return
	var fog: FogOfWar = world.get("_fog") as FogOfWar
	var explored: int = 0
	for i: int in range(fog._cells.size()):
		if fog._cells[i] >= FogOfWar.STATE_EXPLORED:
			explored += 1
	if explored < 100:
		print("RESUME CLIENT_RESUME: FAIL — explored fog not restored (%d cells)" % explored)
		get_tree().quit(1)
		return
	print("RESUME CLIENT_RESUME: resync landed (%d explored cells), sending a command" % explored)
	var before: Vector2 = scout.global_position
	CommandBus.submit(UnitPointCommand.make(1, "move",
		[EntityRegistry.id_of(scout)] as Array[int],
		before + Vector2(200.0, 80.0)))
	deadline = Time.get_ticks_msec() / 1000.0 + 12.0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(scout) and scout.global_position.distance_to(before) > 60.0:
			print("RESUME CLIENT_RESUME: command round-tripped — scout moved %d px"
				% int(scout.global_position.distance_to(before)))
			print("RESUME CLIENT_RESUME: done")
			get_tree().quit(0)
			return
	print("RESUME CLIENT_RESUME: FAIL — the move command never reflected back")
	get_tree().quit(1)

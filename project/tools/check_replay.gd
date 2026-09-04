extends Node2D

## Replay round-trip gate: phase 1 plays a short SP match with recording on
## (a scout is ordered across the map so the stream has real movement) and
## finalizes the file by tearing the world down; phase 2 boots the replay —
## same seed, replay_mode puppets — and pumps it to the end, asserting the
## mirror world exists, the packet stream is consumed, and the recorded scout
## MOVED during playback (fidelity, not just liveness). Exit 1 on any miss.

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok: " + what)
	else:
		_fails.append(what)
		print("  FAIL: " + what)

func _ready() -> void:
	OS.set_environment("CALIMA_SEED", "4242")
	OS.set_environment("CALIMA_FORCE_REPLAY_RECORD", "1")
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.rival_count = 1
	MatchConfig.weather_enabled = false
	MatchConfig.campaign_mission = -1
	MatchConfig.replay_path = ""
	NetworkSession.replay_mode = false
	GameSettings.record_replays = true
	Engine.time_scale = 8.0

	# ── Phase 1: play and record ─────────────────────────────────────────────
	var before: int = ReplayFile.list_replays().size()
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene)\
		.instantiate() as Node2D
	add_child(world)
	for _i: int in range(60):
		await get_tree().physics_frame
	var recorder: StateReplicator = world.get_node_or_null("StateReplicator") as StateReplicator
	_check(recorder != null, "recorder mounted in a fresh SP match")

	var scout: Node2D = null
	for u: Node in (world.get("units_layer") as Node).get_children():
		if u is Scout and (u.get("player_id") as int) == 0:
			scout = u as Node2D
	_check(scout != null, "player scout found")
	var start_pos: Vector2 = scout.global_position if scout != null else Vector2.ZERO
	if scout != null:
		CommandBus.submit(UnitPointCommand.make(0, "move",
			[EntityRegistry.id_of(scout)] as Array[int],
			start_pos + Vector2(700, 300)))
	for _i: int in range(900):
		await get_tree().physics_frame
	var live_end: Vector2 = scout.global_position if scout != null else Vector2.ZERO
	var moved_live: float = live_end.distance_to(start_pos)
	_check(moved_live > 200.0, "scout travelled %.0f px live" % moved_live)
	world.free()
	await get_tree().process_frame

	var replays: Array[Dictionary] = ReplayFile.list_replays()
	_check(replays.size() == before + 1, "one new replay on disk")
	if replays.is_empty():
		return _finish()
	var header: Dictionary = replays[0]
	_check((header.get("config", {}) as Dictionary).get("seed", 0) as int != 0,
		"header carries the resolved seed")

	# ── Phase 2: watch it back ───────────────────────────────────────────────
	NetworkSession.apply_config(header.get("config", {}) as Dictionary)
	NetworkSession.replay_mode = true
	MatchConfig.replay_path = str(header.get("path", ""))
	var world2: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene)\
		.instantiate() as Node2D
	add_child(world2)
	for _i: int in range(30):
		await get_tree().physics_frame
	var player: StateReplicator = world2.get_node_or_null("StateReplicator") as StateReplicator
	_check(player != null, "playback replicator mounted")
	var scout2: Node2D = null
	for u: Node in (world2.get("units_layer") as Node).get_children():
		if u is Scout and (u.get("player_id") as int) == 0:
			scout2 = u as Node2D
	_check(scout2 != null, "mirror world holds the scout")
	var replay_start: Vector2 = scout2.global_position if scout2 != null else Vector2.ZERO
	_check(scout2 != null and replay_start.distance_to(start_pos) < 8.0,
		"same seed, same spawn — the mirror boots the identical world")
	for _i: int in range(1100):
		await get_tree().physics_frame
	var moved_replay: float = scout2.global_position.distance_to(replay_start) \
		if scout2 != null and is_instance_valid(scout2) else 0.0
	_check(moved_replay > 200.0, "the recorded journey replays (%.0f px)" % moved_replay)
	if scout2 != null and is_instance_valid(scout2):
		_check(scout2.global_position.distance_to(live_end) < 60.0,
			"…and ends where the live match ended (fidelity)")

	DirAccess.remove_absolute(str(header.get("path", "")))
	NetworkSession.replay_mode = false
	MatchConfig.replay_path = ""
	_finish()

func _finish() -> void:
	if _fails.is_empty():
		print("REPLAY_GATE: PASS")
		get_tree().quit(0)
	else:
		print("REPLAY_GATE: FAIL — " + ", ".join(_fails))
		get_tree().quit(1)

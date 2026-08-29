extends Node2D

## End-to-end gate for the command pattern layer: boots a real match and
## drives it exclusively through CommandBus — a move order, a Town Center
## train, a building placement — then checks the simulation reacted and the
## tick-stamped log holds every submitted command.
## Run: $GODOT --headless --path project res://tools/check_command_bus.tscn
## Env: CALIMA_SEED (default 4242)

var _world: Node2D = null
var _failures: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	print("COMMAND_BUS: match booted, log=%d entries" % CommandBus.log_entries().size())

	_check_move_command()
	await get_tree().create_timer(2.0).timeout
	_check_move_progress()
	_check_train_command()
	_check_place_command()
	# The AI ticks every ~2 s; a few ticks are enough for it to spawn villagers
	# and assign gathering — all of which must land in the log as player-1 commands.
	await get_tree().create_timer(6.0).timeout
	_check_ai_commands()
	_check_log()

	print("COMMAND_BUS: %s" % ("done" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

var _movers: Array[Node] = []
var _move_target: Vector2 = Vector2.ZERO
var _start_dist: float = 0.0

func _own_villagers() -> Array[Node]:
	var out: Array[Node] = []
	for unit: Node in (_world.units_layer as Node).get_children():
		if unit is Villager and (unit.get("player_id") as int) == 0:
			out.append(unit)
	return out

func _check_move_command() -> void:
	_movers = _own_villagers()
	if _movers.is_empty():
		print("    FAIL: no starting villagers found")
		_failures += 1
		return
	var tc: Node2D = _world.drop_off as Node2D
	_move_target = TerrainManager.nearest_passable(
		tc.global_position + Vector2(400.0, 240.0), MatchConfig.player_civ_id)
	_start_dist = (_movers[0] as Node2D).global_position.distance_to(_move_target)
	CommandBus.submit(UnitPointCommand.make(0, "move",
		EntityRegistry.ids_of(_movers), _move_target))
	print("    move command: %d villagers -> %s" % [_movers.size(), str(_move_target)])

func _check_move_progress() -> void:
	if _movers.is_empty():
		return
	var now: float = (_movers[0] as Node2D).global_position.distance_to(_move_target)
	if now < _start_dist - 50.0:
		print("    move OK: villager closed %.0f px" % (_start_dist - now))
	else:
		print("    FAIL: move command did not move the villager (%.0f -> %.0f px)" % [_start_dist, now])
		_failures += 1

func _check_train_command() -> void:
	var tc: Node = _world.drop_off
	var queued: Array = []
	var watcher: Callable = func(building: Node, queue: Array, _max: int) -> void:
		if building == tc:
			queued.append(queue.size())
	EventBus.train_queue_changed.connect(watcher)
	CommandBus.submit(ProductionCommand.make(0, "train", EntityRegistry.id_of(tc)))
	EventBus.train_queue_changed.disconnect(watcher)
	if queued.is_empty():
		print("    FAIL: TC train command produced no queue change")
		_failures += 1
	else:
		print("    train OK: TC queue -> %s" % str(queued))

func _check_place_command() -> void:
	var before: int = (_world.buildings_layer as Node).get_child_count()
	var wood_before: int = ResourceManager.get_resources(0).get("wood", 0) as int
	var pos: Vector2 = PlacementGrid.snap_footprint(
		(_world.drop_off as Node2D).global_position + Vector2(-260.0, 180.0), Vector2(64.0, 64.0))
	CommandBus.submit(PlaceBuildingCommand.make(0, "house",
		[pos] as Array[Vector2], 0.0, EntityRegistry.ids_of(_movers)))
	var after: int = (_world.buildings_layer as Node).get_child_count()
	var wood_after: int = ResourceManager.get_resources(0).get("wood", 0) as int
	if after != before + 1:
		print("    FAIL: place command did not add a building (%d -> %d)" % [before, after])
		_failures += 1
	elif wood_after >= wood_before:
		print("    FAIL: place command did not spend wood (%d -> %d)" % [wood_before, wood_after])
		_failures += 1
	else:
		print("    place OK: house site down, wood %d -> %d" % [wood_before, wood_after])

func _check_ai_commands() -> void:
	var ai_entries: int = 0
	var kinds: Dictionary = {}
	for entry: Dictionary in CommandBus.log_entries():
		if (entry.get("player", 0) as int) != 0:
			ai_entries += 1
			kinds[entry.get("kind", "?")] = true
	if ai_entries == 0:
		print("    FAIL: the AI issued no commands through the bus")
		_failures += 1
	else:
		print("    AI OK: %d rival commands logged (%s)" % [ai_entries, ", ".join(kinds.keys())])

func _check_log() -> void:
	var entries: Array[Dictionary] = CommandBus.log_entries()
	if entries.size() < 3:
		print("    FAIL: expected >= 3 log entries, found %d" % entries.size())
		_failures += 1
		return
	for entry: Dictionary in entries:
		if not entry.has("t") or not entry.has("kind"):
			print("    FAIL: malformed log entry %s" % str(entry))
			_failures += 1
			return
		if CommandBus.command_from_dict(entry) == null:
			print("    FAIL: log entry does not rebuild: %s" % str(entry))
			_failures += 1
			return
	var path: String = "user://replay_check.jsonl"
	if not CommandBus.save_log(path):
		print("    FAIL: save_log could not write %s" % path)
		_failures += 1
		return
	print("    log OK: %d entries, all rebuildable, written to %s" % [entries.size(), path])

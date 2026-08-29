extends GutTest

## The command pattern layer: EntityRegistry IDs, GameCommand serialization
## round-trips through the CommandBus factory, ownership validation at execute
## time, the tick-stamped command log, and the move formation fan-out.

## Minimal orderable unit: records every order it receives.
class StubUnit extends Node2D:
	var player_id: int = 0
	var orders: Array = []
	var drop_off_target: Node = null
	func order_move(destination: Vector2) -> void:
		orders.append({"verb": "move", "pos": destination})
	func order_attack_move(destination: Vector2) -> void:
		orders.append({"verb": "attack_move", "pos": destination})
	func order_attack(target: Node) -> void:
		orders.append({"verb": "attack", "target": target})
	func order_attack_ground(pos: Vector2) -> void:
		orders.append({"verb": "attack_ground", "pos": pos})

class StubBarracks extends Node2D:
	var player_id: int = 0
	var trained: Array = []
	var cancelled: Array = []
	var rally: Vector2 = Vector2.ZERO
	func order_train(unit_id: String = "militia") -> bool:
		trained.append(unit_id)
		return true
	func order_cancel_train(index: int) -> void:
		cancelled.append(index)
	func set_rally_point(pos: Vector2) -> void:
		rally = pos

var _world: Node2D = null
var _units_layer: Node2D = null

func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_units_layer = Node2D.new()
	_units_layer.name = "UnitsLayer"
	_world.add_child(_units_layer)
	CommandBus.start_match(_world)

func _spawn_unit(pid: int = 0, pos: Vector2 = Vector2.ZERO) -> StubUnit:
	var unit: StubUnit = StubUnit.new()
	unit.player_id = pid
	_units_layer.add_child(unit)
	unit.global_position = pos
	return unit


# ---------------------------------------------------------------------------
# 1. EntityRegistry
# ---------------------------------------------------------------------------

func test_registry_ids_are_sequential_and_stable() -> void:
	var a: StubUnit = _spawn_unit()
	var b: StubUnit = _spawn_unit()
	var id_a: int = EntityRegistry.id_of(a)
	var id_b: int = EntityRegistry.id_of(b)
	assert_eq(id_b, id_a + 1, "IDs are handed out sequentially")
	assert_eq(EntityRegistry.id_of(a), id_a, "asking again returns the same ID")
	assert_eq(EntityRegistry.resolve(id_a), a, "resolve returns the live node")

func test_rescan_assigns_ids_in_tree_order() -> void:
	var a: StubUnit = _spawn_unit()
	var b: StubUnit = _spawn_unit()
	CommandBus.start_match(_world)   # rescans: tree order, fresh sequence
	assert_eq(EntityRegistry.id_of(a) + 1, EntityRegistry.id_of(b),
		"tree order decides the deterministic sequence")

func test_resolve_of_freed_node_returns_null() -> void:
	var a: StubUnit = _spawn_unit()
	var id_a: int = EntityRegistry.id_of(a)
	a.free()
	assert_null(EntityRegistry.resolve(id_a))

func test_stale_id_from_previous_match_is_reassigned() -> void:
	var a: StubUnit = _spawn_unit()
	EntityRegistry.id_of(a)
	CommandBus.start_match(_world)   # reset: 'a' keeps its meta but the table is new
	var fresh: int = EntityRegistry.id_of(a)
	assert_eq(EntityRegistry.resolve(fresh), a,
		"after a reset the node is re-registered under a valid ID")


# ---------------------------------------------------------------------------
# 2. Serialization round-trips through the CommandBus factory
# ---------------------------------------------------------------------------

func test_every_command_kind_round_trips() -> void:
	var ids: Array[int] = [3, 7]
	var commands: Array[GameCommand] = [
		UnitPointCommand.make(0, "attack_move", ids, Vector2(100.0, -50.0)),
		UnitTargetCommand.make(1, "gather", ids, 42, 13),
		UnitActionCommand.make(0, "hero_ability", ids),
		TransportCommand.make(0, "unload_one", 9, 2, Vector2(5.0, 6.0)),
		ProductionCommand.make(0, "train", 4, "knight", -1),
		BuildingActionCommand.make(0, "set_rally", 4, Vector2(10.0, 20.0)),
		MarketCommand.make(0, "hire", 8, "trireme"),
		PlaceBuildingCommand.make(0, "house",
			[Vector2(1.0, 2.0), Vector2(3.0, 4.0)] as Array[Vector2], PI * 0.5, ids,
			true, {"wood": 100}),
		AdvanceAgeCommand.make(2),
		SpawnUnitCommand.make(1, "villager", Vector2(9.0, 9.0), {"food": 50}),
	]
	for cmd: GameCommand in commands:
		var d: Dictionary = cmd.to_dict()
		var back: GameCommand = CommandBus.command_from_dict(d)
		assert_not_null(back, "factory rebuilds kind '%s'" % cmd.kind())
		assert_eq(back.to_dict(), d, "round-trip is lossless for '%s'" % cmd.kind())

func test_factory_rejects_unknown_kind() -> void:
	assert_null(CommandBus.command_from_dict({"kind": "warp_drive"}))


# ---------------------------------------------------------------------------
# 3. Submission: execution, ownership, log
# ---------------------------------------------------------------------------

func test_submit_executes_and_logs_with_tick() -> void:
	var unit: StubUnit = _spawn_unit()
	var before: int = CommandBus.log_entries().size()
	CommandBus.submit(UnitPointCommand.make(0, "move",
		[EntityRegistry.id_of(unit)] as Array[int], Vector2(200.0, 0.0)))
	assert_eq(unit.orders.size(), 1, "the command reached the unit")
	assert_eq(unit.orders[0]["pos"], Vector2(200.0, 0.0), "single unit gets the exact point")
	var entries: Array[Dictionary] = CommandBus.log_entries()
	assert_eq(entries.size(), before + 1, "submit appended one log entry")
	assert_true(entries[entries.size() - 1].has("t"), "the entry is tick-stamped")
	assert_eq(entries[entries.size() - 1]["kind"], "unit_point")

func test_commands_ignore_units_of_other_players() -> void:
	var foreign: StubUnit = _spawn_unit(1)
	CommandBus.submit(UnitPointCommand.make(0, "move",
		[EntityRegistry.id_of(foreign)] as Array[int], Vector2(50.0, 50.0)))
	assert_eq(foreign.orders.size(), 0,
		"a player-0 command must not move player-1 units")

func test_attack_command_resolves_target_by_id() -> void:
	var attacker: StubUnit = _spawn_unit(0)
	var victim: StubUnit = _spawn_unit(1, Vector2(300.0, 0.0))
	CommandBus.submit(UnitTargetCommand.make(0, "attack",
		[EntityRegistry.id_of(attacker)] as Array[int], EntityRegistry.id_of(victim)))
	assert_eq(attacker.orders.size(), 1)
	assert_eq(attacker.orders[0]["target"], victim)

func test_attack_ground_sends_exact_point_to_all() -> void:
	var a: StubUnit = _spawn_unit(0, Vector2.ZERO)
	var b: StubUnit = _spawn_unit(0, Vector2(40.0, 0.0))
	CommandBus.submit(UnitPointCommand.make(0, "attack_ground",
		EntityRegistry.ids_of([a, b]), Vector2(500.0, 500.0)))
	assert_eq(a.orders[0]["pos"], Vector2(500.0, 500.0))
	assert_eq(b.orders[0]["pos"], Vector2(500.0, 500.0),
		"attack-ground has no formation fan-out")

func test_production_command_trains_and_cancels() -> void:
	var barracks: StubBarracks = StubBarracks.new()
	_world.add_child(barracks)
	var bid: int = EntityRegistry.id_of(barracks)
	CommandBus.submit(ProductionCommand.make(0, "train", bid, "pikeman"))
	CommandBus.submit(ProductionCommand.make(0, "train", bid))   # TC-style, no item
	CommandBus.submit(ProductionCommand.make(0, "cancel_train", bid, "", 0))
	# The no-arg call lands on the stub's default parameter ("militia"), same
	# as a real Town Center's order_train() training its only unit.
	assert_eq(barracks.trained, ["pikeman", "militia"])
	assert_eq(barracks.cancelled, [0])

func test_building_action_sets_rally_point() -> void:
	var barracks: StubBarracks = StubBarracks.new()
	_world.add_child(barracks)
	CommandBus.submit(BuildingActionCommand.make(0, "set_rally",
		EntityRegistry.id_of(barracks), Vector2(77.0, 88.0)))
	assert_eq(barracks.rally, Vector2(77.0, 88.0))

func test_replayed_log_entry_executes_identically() -> void:
	## The replay foundation: a command rebuilt from its own log dictionary
	## must order the same unit to the same place.
	var unit: StubUnit = _spawn_unit()
	CommandBus.submit(UnitPointCommand.make(0, "move",
		[EntityRegistry.id_of(unit)] as Array[int], Vector2(123.0, 45.0)))
	var entry: Dictionary = CommandBus.log_entries()[CommandBus.log_entries().size() - 1]
	var replayed: GameCommand = CommandBus.command_from_dict(entry)
	replayed.execute(_world)
	assert_eq(unit.orders.size(), 2)
	assert_eq(unit.orders[1], unit.orders[0], "replay reproduces the original order")


# ---------------------------------------------------------------------------
# 4. Formation fan-out
# ---------------------------------------------------------------------------

func test_move_formation_first_slot_is_the_click() -> void:
	var units: Array[Node] = []
	for i: int in range(4):
		units.append(_spawn_unit(0, Vector2(float(i) * 30.0, 0.0)))
	var slots: Array[Vector2] = UnitPointCommand.formation_slots(Vector2(400.0, 300.0), units)
	assert_eq(slots.size(), 4)
	assert_eq(slots[0], Vector2(400.0, 300.0), "slot 0 is the exact target point")
	for i: int in range(1, 4):
		assert_almost_eq(slots[i].distance_to(Vector2(400.0, 300.0)),
			UnitPointCommand.FORMATION_SPACING, 0.01, "ring 1 sits one spacing out")

func test_set_drop_off_reassigns_own_units_only() -> void:
	var camp: StubBarracks = StubBarracks.new()   # any own node with player_id
	_world.add_child(camp)
	var own: StubUnit = _spawn_unit(0)
	var foreign: StubUnit = _spawn_unit(1)
	CommandBus.submit(UnitTargetCommand.make(0, "set_drop_off",
		EntityRegistry.ids_of([own, foreign]), EntityRegistry.id_of(camp)))
	assert_eq(own.drop_off_target, camp, "own unit re-targets the new drop-off")
	assert_null(foreign.drop_off_target, "foreign units are untouched")

func test_spawn_unit_command_round_trips_costs() -> void:
	var cmd: SpawnUnitCommand = SpawnUnitCommand.make(1, "villager",
		Vector2(120.0, -40.0), {"food": 50})
	var back: SpawnUnitCommand = CommandBus.command_from_dict(cmd.to_dict()) as SpawnUnitCommand
	assert_eq(back.unit_type, "villager")
	assert_eq(back.costs, {"food": 50})
	assert_eq(back.pos, Vector2(120.0, -40.0))

func test_move_formation_is_deterministic() -> void:
	var units: Array[Node] = []
	for i: int in range(7):
		units.append(_spawn_unit(0, Vector2(float(i) * 25.0, 100.0)))
	var a: Array[Vector2] = UnitPointCommand.formation_slots(Vector2(-200.0, 0.0), units)
	var b: Array[Vector2] = UnitPointCommand.formation_slots(Vector2(-200.0, 0.0), units)
	assert_eq(a, b, "same units + same click = same slots, always")

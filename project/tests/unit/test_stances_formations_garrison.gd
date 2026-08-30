extends GutTest

## The AoE2 trio: combat stances (UnitBase.Stance + the auto-engage funnel),
## group formations (UnitPointCommand line/box/spread/rings) and building
## garrison (BuildingBase capacity/enter/eject, tower & TC volleys).

const MILITIA_SCENE: PackedScene = preload("res://scenes/units/militia.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watch_tower.tscn")

var _holder: Node2D = null

func before_each() -> void:
	_holder = Node2D.new()
	add_child_autofree(_holder)

func _militia(pid: int, pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit: Node2D = MILITIA_SCENE.instantiate() as Node2D
	unit.set("player_id", pid)
	_holder.add_child(unit)
	unit.global_position = pos
	return unit


# ---------------------------------------------------------------------------
# 1. Stances
# ---------------------------------------------------------------------------

func test_aggressive_auto_engages() -> void:
	var own: Node2D = _militia(0)
	var enemy: Node2D = _militia(1, Vector2(60.0, 0.0))
	own.call("_on_enemy_entered_range", enemy)
	assert_eq(own.get("attack_target"), enemy, "default stance chases what enters range")
	assert_true(own.get("_auto_engaged") as bool, "range acquisition is marked auto")

func test_passive_never_auto_engages() -> void:
	var own: Node2D = _militia(0)
	var enemy: Node2D = _militia(1, Vector2(60.0, 0.0))
	own.call("set_stance", UnitBase.Stance.PASSIVE)
	own.call("_on_enemy_entered_range", enemy)
	assert_null(own.get("attack_target"), "passive units ignore enemies in range")

func test_passive_still_obeys_explicit_attack_orders() -> void:
	var own: Node2D = _militia(0)
	var enemy: Node2D = _militia(1, Vector2(60.0, 0.0))
	own.call("set_stance", UnitBase.Stance.PASSIVE)
	own.call("order_attack", enemy)
	assert_eq(own.get("attack_target"), enemy, "an order is an order")
	assert_false(own.get("_auto_engaged") as bool, "ordered engagements are not auto")

func test_defensive_returning_home_does_not_reacquire() -> void:
	var own: Node2D = _militia(0, Vector2.ZERO)
	own.call("set_stance", UnitBase.Stance.DEFENSIVE)   # anchor = (0,0)
	own.global_position = Vector2(UnitBase.DEFENSIVE_LEASH + 100.0, 0.0)
	var enemy: Node2D = _militia(1, own.global_position + Vector2(50.0, 0.0))
	own.call("_on_enemy_entered_range", enemy)
	assert_null(own.get("attack_target"),
		"beyond the leash the unit is walking home, not picking new fights")

func test_stance_command_sets_stance_via_bus() -> void:
	CommandBus.start_match(_holder)
	var own: Node2D = _militia(0)
	CommandBus.submit(UnitActionCommand.make(0, "stance_stand_ground",
		[EntityRegistry.id_of(own)] as Array[int]))
	assert_eq(own.get("stance") as int, UnitBase.Stance.STAND_GROUND as int)

func test_order_move_re_anchors_defensive_units() -> void:
	var own: Node2D = _militia(0)
	own.call("set_stance", UnitBase.Stance.DEFENSIVE)
	own.call("order_move", Vector2(500.0, 250.0))
	assert_eq(own.get("_stance_anchor") as Vector2, Vector2(500.0, 250.0),
		"the held position follows the latest move order")


# ---------------------------------------------------------------------------
# 2. Formations
# ---------------------------------------------------------------------------

func _stub_units(count: int) -> Array[Node]:
	var out: Array[Node] = []
	for i: int in range(count):
		var n: Node2D = Node2D.new()
		_holder.add_child(n)
		# Centred on x=0 so the group's average origin sits straight below the
		# click and the approach direction is exactly +y.
		n.global_position = Vector2(float(i) * 20.0 - float(count - 1) * 10.0, 400.0)
		out.append(n)
	return out

func test_line_formation_rows_face_the_target() -> void:
	var units: Array[Node] = _stub_units(6)
	var center: Vector2 = Vector2(0.0, 0.0)   # units approach from +y
	var slots: Array[Vector2] = UnitPointCommand.formation_slots(center, units, "line")
	assert_eq(slots.size(), 6)
	# back_dir = +y: later rows have strictly larger y (behind the front row).
	assert_almost_eq(slots[0].y, slots[1].y, 0.01, "front row is level")
	assert_gt(slots[slots.size() - 1].y, slots[0].y + 1.0, "rear rows step back")

func test_spread_doubles_the_spacing() -> void:
	var units: Array[Node] = _stub_units(4)
	var line: Array[Vector2] = UnitPointCommand.formation_slots(Vector2.ZERO, units, "line")
	var spread: Array[Vector2] = UnitPointCommand.formation_slots(Vector2.ZERO, units, "spread")
	assert_almost_eq(spread[0].distance_to(spread[1]),
		line[0].distance_to(line[1]) * 2.0, 0.1)

func test_unknown_formation_falls_back_to_rings() -> void:
	var units: Array[Node] = _stub_units(3)
	var rings: Array[Vector2] = UnitPointCommand.formation_slots(Vector2.ZERO, units, "rings")
	var unknown: Array[Vector2] = UnitPointCommand.formation_slots(Vector2.ZERO, units, "wedge")
	assert_eq(unknown, rings)
	assert_eq(rings[0], Vector2.ZERO, "ring slot 0 is the exact click")

func test_rank_orders_melee_before_ranged() -> void:
	var archer: Node2D = (load("res://scenes/units/archer.tscn") as PackedScene).instantiate() as Node2D
	archer.set("player_id", 0)
	_holder.add_child(archer)
	var sword: Node2D = _militia(0)
	var ordered: Array[Node] = UnitPointCommand.rank_ordered([archer, sword] as Array[Node])
	assert_eq(ordered[0], sword, "melee screens the front row")
	assert_eq(ordered[1], archer, "ranged forms up behind")

func test_move_command_round_trips_formation() -> void:
	var cmd: UnitPointCommand = UnitPointCommand.make(0, "move",
		[1, 2] as Array[int], Vector2(10.0, 20.0), "box")
	var back: UnitPointCommand = CommandBus.command_from_dict(cmd.to_dict()) as UnitPointCommand
	assert_eq(back.formation, "box")


# ---------------------------------------------------------------------------
# 3. Garrison
# ---------------------------------------------------------------------------

func _tower(pid: int = 0) -> WatchTower:
	var tower: WatchTower = TOWER_SCENE.instantiate() as WatchTower
	tower.player_id = pid
	_holder.add_child(tower)
	tower.force_complete()
	return tower

func test_garrison_hides_and_ungarrison_restores() -> void:
	var tower: WatchTower = _tower()
	var unit: Node2D = _militia(0, tower.global_position + Vector2(30.0, 0.0))
	assert_true(tower.garrison_unit(unit))
	assert_false(unit.visible, "garrisoned units are hidden")
	assert_false(unit.is_physics_processing(), "and paused")
	assert_eq(tower.get_garrison().size(), 1)

	tower.ungarrison_all()
	assert_true(unit.visible, "ejected units come back")
	assert_true(unit.is_physics_processing())
	assert_eq(tower.get_garrison().size(), 0)

func test_garrison_rejects_siege_and_respects_capacity() -> void:
	var tower: WatchTower = _tower()
	var ram: Node2D = (load("res://scenes/units/battering_ram.tscn") as PackedScene).instantiate() as Node2D
	ram.set("player_id", 0)
	_holder.add_child(ram)
	assert_false(tower.can_garrison_unit(ram), "siege never garrisons")
	for i: int in range(WatchTower.GARRISON_CAPACITY):
		assert_true(tower.garrison_unit(_militia(0)))
	assert_false(tower.can_garrison_unit(_militia(0)), "tower is full")

func test_garrison_multiplies_the_tower_volley() -> void:
	var tower: WatchTower = _tower()
	assert_eq(tower._ranged_attack_arrows(), 1, "empty tower fires one arrow")
	tower.garrison_unit(_militia(0))
	tower.garrison_unit(_militia(0))
	assert_eq(tower._ranged_attack_arrows(), 3, "each occupant adds an arrow")

func test_tc_only_shoots_while_garrisoned() -> void:
	var tc: TownCenterBuildable = (load("res://scenes/buildings/town_center.tscn") as PackedScene)\
		.instantiate() as TownCenterBuildable
	tc.player_id = 0
	_holder.add_child(tc)
	tc.force_complete()
	assert_eq(tc._ranged_attack_arrows(), 0, "an empty TC does not attack")
	tc.garrison_unit(_militia(0, tc.global_position + Vector2(40.0, 0.0)))
	assert_eq(tc._ranged_attack_arrows(), 1)

func test_garrisoned_units_die_with_the_building() -> void:
	var tower: WatchTower = _tower()
	var unit: Node2D = _militia(0)
	tower.garrison_unit(unit)
	tower.take_damage(999999.0)
	assert_eq(unit.get("current_state") as int, UnitBase.UnitState.DEAD as int,
		"AoE2 rule: the garrison dies with the building")

func test_garrison_command_enters_when_close() -> void:
	CommandBus.start_match(_holder)
	var tower: WatchTower = _tower()
	var unit: Node2D = _militia(0, tower.global_position + Vector2(30.0, 0.0))
	CommandBus.submit(UnitTargetCommand.make(0, "garrison",
		[EntityRegistry.id_of(unit)] as Array[int], EntityRegistry.id_of(tower)))
	assert_eq(tower.get_garrison().size(), 1, "adjacent units enter immediately")

class FortStub extends Node2D:
	var capacity: int = 2
	var occupants: Array = []
	func garrison_capacity() -> int:
		return capacity
	func get_garrison() -> Array:
		return occupants

func _fort(pos: Vector2, capacity: int, occupied: int = 0) -> FortStub:
	var fort: FortStub = FortStub.new()
	fort.capacity = capacity
	for _i: int in range(occupied):
		fort.occupants.append(Node.new())
	_holder.add_child(fort)
	fort.global_position = pos
	return fort

func test_villagers_never_garrison_by_right_click() -> void:
	## The playtest bug: a villager's right-click on a damaged/under-construction
	## building must stay build/repair — sheltering is its Garrison button or
	## the town bell.
	var villager: Node2D = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate() as Node2D
	villager.set("player_id", 0)
	_holder.add_child(villager)
	assert_false(WorldCommands.garrisons_by_right_click(villager),
		"villager right-click must never garrison")
	assert_true(WorldCommands.garrison_eligible(villager),
		"…but the explicit Garrison button/town bell may shelter it")
	var soldier: Node2D = _militia(0)
	assert_true(WorldCommands.garrisons_by_right_click(soldier),
		"military right-click garrisons as before")

func test_bell_assignments_pick_nearest_with_room() -> void:
	var near: FortStub = _fort(Vector2(0.0, 0.0), 1)
	var far: FortStub = _fort(Vector2(500.0, 0.0), 5)
	var a: Node2D = _stub_units(1)[0]
	a.global_position = Vector2(20.0, 0.0)
	var b: Node2D = Node2D.new()
	_holder.add_child(b)
	b.global_position = Vector2(40.0, 0.0)
	var plan: Array[Array] = WorldCommands.bell_assignments(
		[a, b] as Array[Node], [near, far] as Array[Node])
	assert_eq(plan.size(), 2)
	assert_eq(plan[0][0], near)
	assert_eq((plan[0][1] as Array), [a], "first villager takes the near fort's only slot")
	assert_eq(plan[1][0], far)
	assert_eq((plan[1][1] as Array), [b], "overflow spills to the next building with room")

func test_bell_assignments_skip_full_shelters() -> void:
	var full: FortStub = _fort(Vector2.ZERO, 2, 2)
	var unit: Node2D = _stub_units(1)[0]
	var plan: Array[Array] = WorldCommands.bell_assignments(
		[unit] as Array[Node], [full] as Array[Node])
	assert_eq(plan, [] as Array[Array], "a full shelter takes nobody")

func test_ungarrison_command_ejects() -> void:
	CommandBus.start_match(_holder)
	var tower: WatchTower = _tower()
	tower.garrison_unit(_militia(0))
	CommandBus.submit(BuildingActionCommand.make(0, "ungarrison",
		EntityRegistry.id_of(tower)))
	assert_eq(tower.get_garrison().size(), 0)
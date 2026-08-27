extends GutTest

## SelectionManager control groups: assignment via save_group, pruning of
## dead/freed members on access, and unassignment of emptied groups (the
## HUD chips row relies on get_assigned_group_ids/get_group staying clean).

class FakeUnit:
	extends Node2D
	var current_state: int = UnitBase.UnitState.IDLE
	var selected: bool = false
	func set_selected(value: bool) -> void:
		selected = value

func after_each() -> void:
	SelectionManager.select([])
	SelectionManager._selection_groups.clear()

func _make_units(count: int) -> Array:
	var units: Array = []
	for _i: int in range(count):
		var u: FakeUnit = FakeUnit.new()
		add_child_autofree(u)
		units.append(u)
	return units

func test_save_group_registers_assigned_id() -> void:
	SelectionManager.select(_make_units(3))
	SelectionManager.save_group(2)
	assert_eq(SelectionManager.get_assigned_group_ids(), [2] as Array[int])
	assert_eq(SelectionManager.get_group(2).size(), 3)

func test_save_group_with_empty_selection_unassigns() -> void:
	SelectionManager.select(_make_units(2))
	SelectionManager.save_group(1)
	SelectionManager.select([])
	SelectionManager.save_group(1)
	assert_eq(SelectionManager.get_assigned_group_ids().size(), 0)

func test_dead_members_are_pruned() -> void:
	var units: Array = _make_units(3)
	SelectionManager.select(units)
	SelectionManager.save_group(1)
	(units[0] as FakeUnit).current_state = UnitBase.UnitState.DEAD
	var members: Array = SelectionManager.get_group(1)
	assert_eq(members.size(), 2)
	assert_does_not_have(members, units[0])

func test_freed_members_are_pruned() -> void:
	var units: Array = _make_units(3)
	SelectionManager.select(units)
	SelectionManager.save_group(4)
	(units[1] as Node).free()
	assert_eq(SelectionManager.get_group(4).size(), 2)

func test_fully_dead_group_becomes_unassigned() -> void:
	var units: Array = _make_units(2)
	SelectionManager.select(units)
	SelectionManager.save_group(5)
	for u: FakeUnit in units:
		u.current_state = UnitBase.UnitState.DEAD
	assert_eq(SelectionManager.get_group(5).size(), 0)
	assert_eq(SelectionManager.get_assigned_group_ids().size(), 0)

func test_recall_group_selects_live_members_only() -> void:
	var units: Array = _make_units(3)
	SelectionManager.select(units)
	SelectionManager.save_group(1)
	SelectionManager.select([])
	(units[2] as FakeUnit).current_state = UnitBase.UnitState.DEAD
	SelectionManager.recall_group(1)
	assert_eq(SelectionManager.selected_units.size(), 2)
	assert_true((units[0] as FakeUnit).selected)

func test_ids_are_sorted() -> void:
	SelectionManager.select(_make_units(1))
	SelectionManager.save_group(7)
	SelectionManager.save_group(2)
	assert_eq(SelectionManager.get_assigned_group_ids(), [2, 7] as Array[int])

func test_pruning_emits_groups_changed() -> void:
	var units: Array = _make_units(2)
	SelectionManager.select(units)
	SelectionManager.save_group(1)
	watch_signals(SelectionManager)
	(units[0] as FakeUnit).current_state = UnitBase.UnitState.DEAD
	SelectionManager.get_group(1)
	assert_signal_emitted(SelectionManager, "groups_changed")

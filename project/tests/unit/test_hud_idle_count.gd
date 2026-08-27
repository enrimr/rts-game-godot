extends GutTest

## HudControls.filter_idle_units — shared idle-unit filter behind the
## idle-villager / idle-military cycle buttons and their count badges.
##
## Covered:
##   1. villager mode counts only own idle gatherers
##   2. non-idle and enemy villagers are excluded
##   3. military mode excludes gatherers and units without unit_data
##   4. military mode counts only own idle military
##   5. freed / null entries are skipped safely

const IDLE: int = UnitBase.UnitState.IDLE
const MOVING: int = UnitBase.UnitState.MOVING

class StubVillager:
	extends Node
	var player_id: int = 0
	var current_state: int = 0
	var unit_data: Resource = Resource.new()
	func order_gather(_target: Node = null) -> void:
		pass

class StubMilitary:
	extends Node
	var player_id: int = 0
	var current_state: int = 0
	var unit_data: Resource = Resource.new()

func _villager(pid: int, state: int) -> StubVillager:
	var v: StubVillager = StubVillager.new()
	v.player_id = pid
	v.current_state = state
	return autofree(v) as StubVillager

func _military(pid: int, state: int) -> StubMilitary:
	var m: StubMilitary = StubMilitary.new()
	m.player_id = pid
	m.current_state = state
	return autofree(m) as StubMilitary

func test_counts_own_idle_villagers() -> void:
	var units: Array = [_villager(0, IDLE), _villager(0, IDLE), _military(0, IDLE)]
	var idle: Array[Node] = HudControls.filter_idle_units(units, 0, false)
	assert_eq(idle.size(), 2)

func test_excludes_busy_and_enemy_villagers() -> void:
	var units: Array = [_villager(0, IDLE), _villager(0, MOVING), _villager(1, IDLE)]
	var idle: Array[Node] = HudControls.filter_idle_units(units, 0, false)
	assert_eq(idle.size(), 1)

func test_military_excludes_gatherers_and_dataless_units() -> void:
	var no_data: StubMilitary = _military(0, IDLE)
	no_data.unit_data = null
	var units: Array = [_villager(0, IDLE), no_data, _military(0, IDLE)]
	var idle: Array[Node] = HudControls.filter_idle_units(units, 0, true)
	assert_eq(idle.size(), 1)

func test_military_counts_only_own_idle() -> void:
	var units: Array = [
		_military(0, IDLE), _military(0, IDLE),
		_military(0, MOVING), _military(1, IDLE),
	]
	var idle: Array[Node] = HudControls.filter_idle_units(units, 0, true)
	assert_eq(idle.size(), 2)

func test_skips_null_entries() -> void:
	var units: Array = [null, _villager(0, IDLE)]
	var idle: Array[Node] = HudControls.filter_idle_units(units, 0, false)
	assert_eq(idle.size(), 1)

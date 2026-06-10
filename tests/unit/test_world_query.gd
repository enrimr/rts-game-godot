extends GutTest

## WorldQuery — the read-only AI query service that will replace ~43 inline
## "walk the layer + filter" loops across scripts/ai/. These tests pin the exact
## behaviour the inline loops have today, so the upcoming module migrations can
## be checked for behavioural equivalence.
##
## Contract under test:
##   1.  own_units / own_buildings  -> player_id == owner
##   2.  enemy_units / enemy_buildings -> player_id != owner
##   3.  null player_id is always dropped
##   4.  invalid (freed) nodes are dropped
##   5.  enemy_units_visible drops cloaked units; enemy_units keeps them;
##       own_units never applies the cloak filter
##   6.  of_type / in_state / nearest_to refinements
##   7.  a null/empty layer yields an empty array (no crash)

const WQ := preload("res://scripts/ai/world_query.gd")

# Lightweight stand-ins exposing exactly the properties WorldQuery reads.
class UnitDouble:
	extends Node2D
	var player_id: int = 0
	var is_cloaked: bool = false
	var current_state: int = 0

class VillagerDouble:
	extends UnitDouble

var _units: Node2D
var _buildings: Node2D

func before_each() -> void:
	_units = Node2D.new()
	_buildings = Node2D.new()
	add_child_autofree(_units)
	add_child_autofree(_buildings)

func _unit(pid: int, cloaked: bool = false, state: int = 0, villager: bool = false) -> UnitDouble:
	var u: UnitDouble = (VillagerDouble.new() if villager else UnitDouble.new())
	u.player_id = pid
	u.is_cloaked = cloaked
	u.current_state = state
	_units.add_child(u)
	return u

func _building(pid: int) -> UnitDouble:
	var b: UnitDouble = UnitDouble.new()
	b.player_id = pid
	_buildings.add_child(b)
	return b

# 1 / 2 — own vs enemy partitioning
func test_own_and_enemy_units_partition() -> void:
	_unit(1); _unit(1); _unit(2); _unit(0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(q.own_units(1).size(), 2, "two units belong to player 1")
	assert_eq(q.enemy_units(1).size(), 2, "the other two are enemies of player 1")

func test_own_and_enemy_buildings_partition() -> void:
	_building(1); _building(2); _building(2)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(q.own_buildings(2).size(), 2)
	assert_eq(q.enemy_buildings(2).size(), 1)

# 3 — null player_id dropped (a bare Node2D has no player_id property -> get() == null)
func test_null_player_id_dropped() -> void:
	_unit(1)
	_units.add_child(Node2D.new())   # no player_id
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(q.own_units(1).size(), 1, "node without player_id must be skipped")
	assert_eq(q.enemy_units(1).size(), 0, "node without player_id must not count as enemy either")

# 4 — freed nodes dropped
func test_freed_nodes_dropped() -> void:
	var doomed: UnitDouble = _unit(2)
	_unit(2)
	_units.remove_child(doomed)
	doomed.free()
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(q.enemy_units(1).size(), 1, "freed node must not appear")

# 5 — cloak filter only on enemy_units_visible
func test_cloak_filter_semantics() -> void:
	_unit(2, false)            # visible enemy
	_unit(2, true)             # cloaked enemy
	_unit(1, true)             # cloaked own (cloak must NOT hide own units)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(q.enemy_units_visible(1).size(), 1, "cloaked enemy excluded from visible query")
	assert_eq(q.enemy_units(1).size(), 2, "cloaked enemy still present in unfiltered query")
	assert_eq(q.own_units(1).size(), 1, "own cloaked unit is never filtered out")

# 6a — of_type
func test_of_type_refinement() -> void:
	_unit(1, false, 0, false)  # plain unit
	_unit(1, false, 0, true)   # villager
	_unit(1, false, 0, true)   # villager
	var q: WorldQuery = WQ.new(_units, _buildings)
	var villagers: Array = WorldQuery.of_type(q.own_units(1), VillagerDouble)
	assert_eq(villagers.size(), 2, "two of the three own units are villagers")

# 6b — in_state
func test_in_state_refinement() -> void:
	_unit(1, false, 0)   # state 0
	_unit(1, false, 3)   # state 3
	_unit(1, false, 3)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(WorldQuery.in_state(q.own_units(1), 3).size(), 2, "two own units in state 3")

# 6c — nearest_to
func test_nearest_to() -> void:
	var near: UnitDouble = _unit(2); near.global_position = Vector2(10, 0)
	var far: UnitDouble = _unit(2);  far.global_position = Vector2(500, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(WorldQuery.nearest_to(q.enemy_units(1), Vector2.ZERO), near, "picks the closest enemy")
	assert_null(WorldQuery.nearest_to([], Vector2.ZERO), "empty -> null")

# 7 — all_* ignore ownership, keep every valid node (incl. no-pid)
func test_all_entities_ignore_owner() -> void:
	_unit(1); _unit(2); _units.add_child(Node2D.new())  # no-pid still counts as a node
	_building(1); _building(2)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_eq(q.all_units().size(), 3, "all_units keeps every valid node regardless of pid")
	assert_eq(q.all_buildings().size(), 2)

# 8 — null layer is safe
func test_null_layer_safe() -> void:
	var q: WorldQuery = WQ.new(null, null)
	assert_eq(q.own_units(1).size(), 0)
	assert_eq(q.enemy_buildings(1).size(), 0)
	assert_eq(q.all_units().size(), 0)

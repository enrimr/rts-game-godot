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

# ── 9 — Sighting layer (fog-honest targeting) ─────────────────────────────────
# Doubles carry no unit_data/.tres, so the FogOfWar defaults apply:
# unit LOS 5.0 × 64 = 320 px, building LOS 8.0 × 64 = 512 px.

const UNIT_LOS_PX: float = 5.0 * 64.0

func test_enemy_beyond_all_los_is_not_sighted() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var enemy: UnitDouble = _unit(2); enemy.global_position = Vector2(UNIT_LOS_PX + 200.0, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	q.refresh_sightings(1, true)
	assert_eq(q.enemies_sighted(1).size(), 0, "enemy outside every own LOS must not be sighted")
	assert_null(q.nearest_sighted_enemy(1, Vector2.ZERO))
	assert_false(q.is_sighted(1, enemy))
	assert_eq(q.remembered_enemy_positions(1).size(), 0, "never seen -> never remembered")

func test_enemy_inside_own_unit_los_is_sighted() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var enemy: UnitDouble = _unit(2); enemy.global_position = Vector2(100, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	q.refresh_sightings(1, true)
	assert_true(q.is_sighted(1, enemy))
	assert_eq(q.sighted_enemy_units(1), [enemy])
	assert_eq(q.nearest_sighted_enemy(1, Vector2.ZERO), enemy)

func test_sighted_then_hidden_is_remembered_at_last_position() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var enemy: UnitDouble = _unit(2); enemy.global_position = Vector2(100, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	q.refresh_sightings(1, true)
	assert_true(q.is_sighted(1, enemy), "precondition: seen once")
	enemy.global_position = Vector2(5000, 0)   # slips out of sight
	q.refresh_sightings(1, true)
	assert_false(q.is_sighted(1, enemy), "no longer in any LOS")
	var mem: Dictionary = q.remembered_enemy_positions(1)
	assert_eq(mem.get(enemy.get_instance_id()), Vector2(100, 0),
		"remembered at the LAST SEEN position, not the current one")

func test_known_enemy_buildings_keeps_remembered_drops_unseen() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var scouted: UnitDouble = _building(2); scouted.global_position = Vector2(200, 0)
	var hidden: UnitDouble = _building(2); hidden.global_position = Vector2(9000, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	q.refresh_sightings(1, true)
	assert_eq(q.known_enemy_buildings(1), [scouted], "only the scouted building is known")
	own.global_position = Vector2(-5000, 0)    # scout retreats: building leaves sight
	q.refresh_sightings(1, true)
	assert_false(q.is_sighted(1, scouted))
	assert_eq(q.known_enemy_buildings(1), [scouted],
		"a building once scouted stays a known target after leaving sight")

func test_cloaked_enemy_is_never_sighted() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var cloaked: UnitDouble = _unit(2, true); cloaked.global_position = Vector2(50, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	q.refresh_sightings(1, true)
	assert_false(q.is_sighted(1, cloaked), "cloak filter applies to sighting too")
	assert_eq(q.sighted_enemy_units(1).size(), 0)

func test_sighting_refresh_is_throttled() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var enemy: UnitDouble = _unit(2); enemy.global_position = Vector2(100, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	assert_true(q.is_sighted(1, enemy), "first query refreshes")
	enemy.global_position = Vector2(9000, 0)
	assert_true(q.is_sighted(1, enemy),
		"within the throttle window the cached sighting is served, not recomputed")
	q.refresh_sightings(1, true)
	assert_false(q.is_sighted(1, enemy), "forced refresh recomputes")

func test_freed_enemy_pruned_from_memory() -> void:
	var own: UnitDouble = _unit(1); own.global_position = Vector2.ZERO
	var enemy: UnitDouble = _unit(2); enemy.global_position = Vector2(100, 0)
	var q: WorldQuery = WQ.new(_units, _buildings)
	q.refresh_sightings(1, true)
	assert_eq(q.remembered_enemy_positions(1).size(), 1)
	_units.remove_child(enemy)
	enemy.free()
	q.refresh_sightings(1, true)
	assert_eq(q.remembered_enemy_positions(1).size(), 0, "dead entities are forgotten")

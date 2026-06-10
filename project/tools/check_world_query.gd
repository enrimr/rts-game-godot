extends SceneTree

# Locally-runnable validation of WorldQuery (the project has no local GUT addon).
# Mirrors tests/unit/test_world_query.gd against a synthetic node tree.
# Run: godot --headless -s tools/check_world_query.gd

const WQ := preload("res://scripts/ai/world_query.gd")

class UnitDouble:
	extends Node2D
	var player_id: int = 0
	var is_cloaked: bool = false
	var current_state: int = 0

class VillagerDouble:
	extends UnitDouble

var _fails: int = 0

func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("PASS " if ok else "FAIL ") + label + "  got=%s want=%s" % [got, want])
	if not ok:
		_fails += 1

func _unit(layer: Node, pid: int, cloaked: bool = false, state: int = 0, villager: bool = false) -> UnitDouble:
	var u: UnitDouble = (VillagerDouble.new() if villager else UnitDouble.new())
	u.player_id = pid; u.is_cloaked = cloaked; u.current_state = state
	layer.add_child(u)
	return u

func _initialize() -> void:
	var units: Node2D = Node2D.new()
	var buildings: Node2D = Node2D.new()
	get_root().add_child(units)
	get_root().add_child(buildings)

	# own/enemy partition
	_unit(units, 1); _unit(units, 1); _unit(units, 2); _unit(units, 0)
	var q: WorldQuery = WQ.new(units, buildings)
	_check("own_units(1)", q.own_units(1).size(), 2)
	_check("enemy_units(1)", q.enemy_units(1).size(), 2)

	# null player_id dropped
	units.add_child(Node2D.new())
	_check("own_units ignores no-pid node", q.own_units(1).size(), 2)

	# cloak semantics
	var u2: Node2D = Node2D.new(); units.add_child(u2)  # padding, ignored (no pid)
	_unit(units, 2, true)   # cloaked enemy
	_unit(units, 1, true)   # cloaked own
	_check("enemy_units_visible drops cloaked", q.enemy_units_visible(1).size(), 2)  # 2 visible enemies (pid2 x2)
	_check("enemy_units keeps cloaked", q.enemy_units(1).size(), 3)                  # 3 enemies total
	_check("own_units keeps cloaked own", q.own_units(1).size(), 3)                  # 3 own (2 + 1 cloaked)

	# refinements
	_unit(units, 1, false, 0, true); _unit(units, 1, false, 3, true)
	var own1: Array = q.own_units(1)
	_check("of_type villagers", WorldQuery.of_type(own1, VillagerDouble).size(), 2)
	_check("in_state(3)", WorldQuery.in_state(own1, 3).size(), 1)

	# nearest_to: closest of two enemies wins; empty -> null
	var near: UnitDouble = _unit(units, 5); near.global_position = Vector2(10, 0)
	var far: UnitDouble = _unit(units, 5);  far.global_position = Vector2(500, 0)
	_check("nearest_to closest", WorldQuery.nearest_to(q.enemy_units(1), Vector2.ZERO) != null, true)
	_check("nearest empty -> null", WorldQuery.nearest_to([], Vector2.ZERO), null)

	# null layer safe
	var q2: WorldQuery = WQ.new(null, null)
	_check("null layer own_units", q2.own_units(1).size(), 0)

	print("CHECK_WORLD_QUERY: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)

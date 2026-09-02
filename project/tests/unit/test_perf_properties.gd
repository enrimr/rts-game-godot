extends GutTest

## Performance PROPERTIES, not raw speed: these lock the algorithmic
## behaviours the big-battle work depends on, machine-independently.
##   1. Fog reveal is incremental — a stationary watcher's second tick does
##      (almost) no cell work, and only movement re-stamps circles.
##   2. Circle offset templates are cached per radius.
##   3. _repath_to has hysteresis — a chase goal drifting less than
##      REPATH_DISTANCE must NOT retarget the agent (that forced a full A*
##      per chaser per tick before).
## The wall-clock budget lives in tools/check_perf_gate.tscn instead, where
## a generous threshold suits a real match.

func _make_fog() -> FogOfWar:
	var fog: FogOfWar = FogOfWar.new()
	add_child_autofree(fog)
	return fog

func test_stationary_watcher_costs_no_cell_work_on_second_tick() -> void:
	var fog: FogOfWar = _make_fog()
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	unit.set("player_id", 0)
	add_child_autofree(unit)
	unit.global_position = Vector2(100.0, 100.0)
	var units_holder: Node = Node.new()
	add_child_autofree(units_holder)
	unit.reparent(units_holder)
	fog.setup(units_holder, null, null, null)

	# Drive the reveal pass directly: _tick() renders (and so clears the
	# dirty list) at its end, hiding exactly what this test observes.
	fog._update_watchers()
	assert_eq(fog._watch.size(), 1, "one watcher tracked after the first pass")
	assert_gt(fog._dirty_list.size(), 0, "the first stamp dirties its circle")
	fog._render()
	fog._update_watchers()
	assert_eq(fog._dirty_list.size(), 0,
		"a stationary watcher must dirty NO cells on its second pass")
	unit.global_position += Vector2(FogOfWar.CELL_SIZE * 2.0, 0.0)
	fog._update_watchers()
	assert_gt(fog._dirty_list.size(), 0, "moving a cell re-stamps the circle")

func test_circle_offsets_are_cached_per_radius() -> void:
	var a: PackedVector2Array = FogOfWar._offsets_for_radius(6)
	var b: PackedVector2Array = FogOfWar._offsets_for_radius(6)
	assert_eq(a, b, "same radius returns the cached template")
	assert_gt(a.size(), 80, "radius 6 covers a filled circle of cells")

func test_repath_skips_small_goal_drift() -> void:
	var unit: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as CharacterBody2D
	add_child_autofree(unit)
	var agent: NavigationAgent2D = unit.get("nav_agent") as NavigationAgent2D
	unit.call("_repath_to", Vector2(500.0, 500.0))
	var first_target: Vector2 = agent.target_position
	# Drift below REPATH_DISTANCE with an unfinished path: must NOT retarget.
	unit.call("_repath_to", Vector2(510.0, 505.0))
	assert_eq(agent.target_position, first_target,
		"a %d px drift must not recompute the path" % 11)
	unit.call("_repath_to", Vector2(600.0, 600.0))
	assert_ne(agent.target_position, first_target,
		"a drift beyond REPATH_DISTANCE must retarget")

func test_drive_agent_reconnects_after_stop() -> void:
	var unit: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as CharacterBody2D
	add_child_autofree(unit)
	var agent: NavigationAgent2D = unit.get("nav_agent") as NavigationAgent2D
	var cb: Callable = Callable(unit, "_on_velocity_computed")
	assert_true(agent.velocity_computed.is_connected(cb), "connected on ready")
	unit.call("_drive_agent", Vector2.ZERO)
	assert_false(agent.velocity_computed.is_connected(cb),
		"a parked unit must leave the avoidance dispatch")
	unit.call("_drive_agent", Vector2.ZERO)
	assert_false(agent.velocity_computed.is_connected(cb), "stop is idempotent")
	unit.call("_drive_agent", Vector2(50.0, 0.0))
	assert_true(agent.velocity_computed.is_connected(cb),
		"driving again must rejoin the avoidance dispatch")

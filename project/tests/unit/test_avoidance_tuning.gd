extends GutTest

## RVO avoidance tuning (UnitBase._tune_avoidance): the scenes ship engine
## defaults, and two of them were harmful — max_speed 100 clamped the
## avoidance-safe velocity of every faster unit (the 180 px/s Scout moved at
## 55 % of design speed), and neighbor_distance 500 made whole armies brake
## for each other from half a map away.

func _spawn(scene: String) -> Node2D:
	var unit: Node2D = (load("res://scenes/units/%s.tscn" % scene) as PackedScene).instantiate() as Node2D
	unit.set("player_id", 0)
	add_child_autofree(unit)
	return unit

func test_max_speed_follows_unit_data() -> void:
	var scout: Node2D = _spawn("scout")
	var agent: NavigationAgent2D = scout.get("nav_agent") as NavigationAgent2D
	var move_speed: float = (scout.get("unit_data") as UnitResource).move_speed
	assert_almost_eq(agent.max_speed, move_speed * UnitBase.AVOID_MAX_SPEED_HEADROOM, 0.01,
		"the RVO clamp must sit above the unit's real speed — the default 100 capped the Scout")
	assert_gt(agent.max_speed, 180.0, "the Scout is no longer capped below its 180 px/s")

func test_neighbourhood_is_local_not_half_the_map() -> void:
	var militia: Node2D = _spawn("militia")
	var agent: NavigationAgent2D = militia.get("nav_agent") as NavigationAgent2D
	assert_eq(agent.neighbor_distance, UnitBase.AVOID_NEIGHBOR_DISTANCE)
	assert_eq(agent.max_neighbors, UnitBase.AVOID_MAX_NEIGHBORS)
	assert_almost_eq(agent.time_horizon_agents, UnitBase.AVOID_TIME_HORIZON, 0.01)

func test_avoidance_radius_matches_collision() -> void:
	var militia: Node2D = _spawn("militia")
	var agent: NavigationAgent2D = militia.get("nav_agent") as NavigationAgent2D
	assert_almost_eq(agent.radius, (militia.call("_collision_radius") as float) + 1.0, 0.01,
		"the RVO disc mirrors the physics footprint")
	assert_gt(agent.radius, 10.0, "no longer the engine default")

func test_parked_units_yield_to_marching_ones() -> void:
	var militia: Node2D = _spawn("militia")
	var agent: NavigationAgent2D = militia.get("nav_agent") as NavigationAgent2D
	militia.call("_process", 0.016)
	assert_almost_eq(agent.avoidance_priority, UnitBase.AVOID_PRIORITY_IDLE, 0.01,
		"idle units carry the low priority")
	militia.set("current_state", UnitBase.UnitState.MOVING)
	militia.call("_process", 0.016)
	assert_almost_eq(agent.avoidance_priority, UnitBase.AVOID_PRIORITY_MOVING, 0.01,
		"marching units carry the high priority, so crowds part for them")
func test_nudge_side_vector_steps_off_the_path_line() -> void:
	# Mover travels +X; a blocker sitting slightly above the line steps UP.
	var side_up: Vector2 = UnitBase.nudge_side_vector(
		Vector2.RIGHT, Vector2(0, 0), Vector2(40, -5))
	assert_lt(side_up.y, 0.0, "blocker above the line leaves upward")
	# ...and one below the line steps DOWN — the shortest way out.
	var side_down: Vector2 = UnitBase.nudge_side_vector(
		Vector2.RIGHT, Vector2(0, 0), Vector2(40, 5))
	assert_gt(side_down.y, 0.0, "blocker below the line leaves downward")
	assert_almost_eq(side_up.length(), 1.0, 0.001, "unit vector")

func test_nudge_aside_sidesteps_only_idle_units() -> void:
	var militia: Node2D = _spawn("militia")
	var start: Vector2 = Vector2(500.0, 500.0)
	militia.global_position = start
	militia.call("nudge_aside", Vector2.RIGHT, start + Vector2(-40.0, 5.0))
	assert_eq(militia.get("current_state") as int, UnitBase.UnitState.MOVING as int,
		"an idle blocker starts its side-step")
	var agent: NavigationAgent2D = militia.get("nav_agent") as NavigationAgent2D
	assert_almost_ne(agent.target_position.y, start.y, 1.0,
		"the step is perpendicular to the mover's travel")
	assert_eq(militia.get("_destination_state") as int, UnitBase.UnitState.IDLE as int,
		"it settles back to idle afterwards")
	# A fighting unit must never be shuffled away from its strike.
	var fighter: Node2D = _spawn("militia")
	fighter.global_position = start
	fighter.set("current_state", UnitBase.UnitState.ATTACKING)
	fighter.call("nudge_aside", Vector2.RIGHT, start + Vector2(-40.0, 0.0))
	assert_eq(fighter.get("current_state") as int, UnitBase.UnitState.ATTACKING as int,
		"non-idle units refuse the nudge")

func test_nudge_has_a_cooldown() -> void:
	var militia: Node2D = _spawn("militia")
	militia.global_position = Vector2(500.0, 500.0)
	militia.call("nudge_aside", Vector2.RIGHT, Vector2(460.0, 505.0))
	militia.set("current_state", UnitBase.UnitState.IDLE)
	var agent: NavigationAgent2D = militia.get("nav_agent") as NavigationAgent2D
	var first_target: Vector2 = agent.target_position
	militia.call("nudge_aside", Vector2.UP, Vector2(500.0, 540.0))
	assert_eq(agent.target_position, first_target,
		"a second nudge inside the cooldown is ignored — no shuffle loops")

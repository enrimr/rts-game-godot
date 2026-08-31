extends GutTest

## Shift-queued waypoints and patrol (UnitBase movement plans).

func _militia() -> Node2D:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	unit.set("player_id", 0)
	add_child_autofree(unit)
	unit.global_position = Vector2(300.0, 300.0)
	return unit

func test_first_waypoint_starts_immediately_then_queues() -> void:
	var unit: Node2D = _militia()
	unit.call("queue_waypoint", Vector2(500.0, 300.0), false)
	assert_eq(unit.get("current_state") as int, UnitBase.UnitState.MOVING as int,
		"an idle unit starts its first leg at once")
	unit.call("queue_waypoint", Vector2(700.0, 300.0), true)
	assert_eq((unit.get("_waypoints") as Array).size(), 1, "the second leg waits its turn")

func test_explicit_order_clears_the_plan() -> void:
	var unit: Node2D = _militia()
	unit.call("queue_waypoint", Vector2(500.0, 300.0), false)
	unit.call("queue_waypoint", Vector2(700.0, 300.0), false)
	unit.call("clear_waypoints")
	assert_eq((unit.get("_waypoints") as Array).size(), 0)
	assert_false(unit.get("_patrol_active") as bool)

func test_patrol_bounces_between_the_two_points() -> void:
	var unit: Node2D = _militia()
	unit.call("order_patrol", Vector2(600.0, 300.0))
	assert_true(unit.get("_patrol_active") as bool)
	assert_true(unit.get("_attack_move_active") as bool,
		"patrol legs are attack-moves: enemies met on the way are engaged")
	# Simulate reaching the far point: the plan advances back toward home.
	var advanced: bool = unit.call("_advance_waypoints") as bool
	assert_true(advanced, "patrol never runs out of legs")
	assert_true(unit.get("_patrol_active") as bool, "still patrolling after the bounce")
	assert_eq((unit.get("nav_agent") as NavigationAgent2D).target_position,
		Vector2(300.0, 300.0), "second leg walks home")

func test_queued_point_command_round_trips() -> void:
	var cmd: UnitPointCommand = UnitPointCommand.make(0, "move",
		[7] as Array[int], Vector2(100.0, 50.0), "line", true)
	var back: UnitPointCommand = UnitPointCommand.new()
	back.read(cmd.to_dict())
	assert_true(back.queued, "the queued flag survives serialization")
	assert_eq(back.verb, "move")

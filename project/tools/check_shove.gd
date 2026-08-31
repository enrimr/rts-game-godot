extends Node2D

## Behavioural gate for collision phase B: a single-width corridor between two
## walls, packed with idle friendly militia, must always be traversable.
## Empirically the phase-A RVO tuning (movers priority 0.7 vs idle 0.4, no
## unit-vs-unit physics) lets the mover through on its own; when it ever does
## stall >0.45 s, the idle-sidestep "shove" (UnitBase.nudge_aside) kicks in.
## Success = traversal; the nudge count is informative, not required.

const MILITIA: PackedScene = preload("res://scenes/units/militia.tscn")

func _wall(rect: Rect2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rs: RectangleShape2D = RectangleShape2D.new()
	rs.size = rect.size
	shape.shape = rs
	body.add_child(shape)
	add_child(body)
	body.global_position = rect.get_center()

func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func() -> void:
		print("SHOVE: TIMEOUT")
		get_tree().quit(1))
	var region: NavigationRegion2D = NavigationRegion2D.new()
	var poly: NavigationPolygon = NavigationPolygon.new()
	poly.agent_radius = 10.5
	poly.add_outline(PackedVector2Array([
		Vector2(-800, -800), Vector2(800, -800), Vector2(800, 800), Vector2(-800, 800)]))
	# Two wall slabs leaving a 44 px corridor along y = 0.
	poly.add_outline(PackedVector2Array([
		Vector2(-200, -300), Vector2(200, -300), Vector2(200, -15), Vector2(-200, -15)]))
	poly.add_outline(PackedVector2Array([
		Vector2(-200, 15), Vector2(200, 15), Vector2(200, 300), Vector2(-200, 300)]))
	poly.make_polygons_from_outlines()
	region.navigation_polygon = poly
	add_child(region)
	_wall(Rect2(Vector2(-200, -300), Vector2(400, 285)))
	_wall(Rect2(Vector2(-200, 15), Vector2(400, 285)))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var blockers: Array[Node2D] = []
	var starts: Array[Vector2] = []
	for x: float in [-80.0, -35.0, 10.0, 55.0, 100.0]:
		var u: Node2D = MILITIA.instantiate() as Node2D
		u.set("player_id", 0)
		add_child(u)
		u.global_position = Vector2(x, 0.0)
		blockers.append(u)
		starts.append(u.global_position)
	var mover: Node2D = MILITIA.instantiate() as Node2D
	mover.set("player_id", 0)
	add_child(mover)
	mover.global_position = Vector2(-320.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	mover.call("order_move", Vector2(320.0, 0.0))
	print("SHOVE: mover ordered through the packed single-width corridor")

	var deadline: float = Time.get_ticks_msec() / 1000.0 + 30.0
	var nudges_seen: int = 0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.4).timeout
		for b: Node2D in blockers:
			if (b.get("current_state") as int) == UnitBase.UnitState.MOVING:
				nudges_seen += 1
		if mover.global_position.x > 280.0:
			var displaced: int = 0
			for i: int in range(blockers.size()):
				if blockers[i].global_position.distance_to(starts[i]) > 14.0:
					displaced += 1
			print("SHOVE: corridor traversed — %d blockers displaced, %d nudge ticks seen"
				% [displaced, nudges_seen])
			print("SHOVE: ok")
			get_tree().quit(0)
			return
	print("SHOVE: FAIL — mover stuck at x=%.0f (nudge ticks %d)"
		% [mover.global_position.x, nudges_seen])
	get_tree().quit(1)

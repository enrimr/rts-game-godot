extends GutTest

## Dock._water_spawn_pos — where a freshly trained ship is put down.
##
## The dock straddles land and water, and TerrainManager.nearest_ocean() returns
## the *first* ocean pixel around it — the shoreline. Spawning there put ships
## half on the pier and, since the answer is deterministic, dropped an entire
## training queue on one pixel. The spawn now moves offshore and spirals around
## occupied water.

const LAND_Y: float = 0.0
const DOCK_POS: Vector2 = Vector2(0.0, -8.0)

var _dock: Node2D = null

func before_each() -> void:
	TerrainManager.reset()
	# Island map: land is the y < 0 half of a square, everything else is ocean.
	TerrainManager.set_land_polys([PackedVector2Array([
		Vector2(-600.0, -600.0), Vector2(600.0, -600.0),
		Vector2(600.0, LAND_Y), Vector2(-600.0, LAND_Y)])], true)
	_dock = (load("res://scenes/buildings/dock.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(_dock)
	_dock.global_position = DOCK_POS

func after_each() -> void:
	TerrainManager.reset()

func _spawn() -> Vector2:
	return _dock.call("_water_spawn_pos") as Vector2

func test_spawn_is_open_water_not_the_shoreline() -> void:
	var pos: Vector2 = _spawn()
	assert_true(TerrainManager.is_ocean(pos), "ship spawns in the water")
	for i: int in range(4):
		var probe: Vector2 = pos + Vector2.from_angle(TAU * float(i) / 4.0) * Dock.SHIP_RADIUS
		assert_true(TerrainManager.is_ocean(probe),
			"the whole hull is afloat, not clipping the beach at %s" % probe)

func test_spawn_clears_the_pier() -> void:
	var pos: Vector2 = _spawn()
	assert_gt(pos.distance_to(DOCK_POS), Dock.WATER_CLEARANCE * 0.5 - 1.0,
		"ships appear off the dock, not on top of it")
	assert_gt(pos.y, LAND_Y, "ships appear on the seaward side")

func test_queued_ships_do_not_stack_on_one_pixel() -> void:
	var first: Vector2 = _spawn()
	var blocker: CharacterBody2D = CharacterBody2D.new()
	blocker.collision_layer = 2
	blocker.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = Dock.SHIP_RADIUS
	shape.shape = circle
	blocker.add_child(shape)
	add_child_autofree(blocker)
	blocker.global_position = first
	await get_tree().physics_frame
	await get_tree().physics_frame

	var second: Vector2 = _spawn()
	assert_gt(second.distance_to(first), 1.0, "the next ship is placed beside the first")
	assert_true(TerrainManager.is_ocean(second), "the dodged position is still water")

func test_no_water_anywhere_falls_back_instead_of_crashing() -> void:
	TerrainManager.reset()  # plain land map: no ocean, no land polygons
	var pos: Vector2 = _spawn()
	assert_eq(pos, DOCK_POS + Vector2(0.0, 60.0), "last-resort offset below the dock")

extends GutTest

## Sub-pixel bake nudge (`NavMeshBuilder.RADIUS_NUDGE`).
##
## Two buildings placed diagonally on the 16 px placement grid can leave a 20 px
## carved gap on both axes, so once each footprint is offset by the 10 px agent
## radius the two holes meet at EXACTLY one point. Godot's convex partition fails
## on that pinch and hands back an EMPTY navmesh — the whole board, not just the
## corner. Baking half a pixel wider merges the two holes instead.

const BOARD: Array = [Vector2(-3000.0, -3000.0), Vector2(3000.0, -3000.0),
	Vector2(3000.0, 3000.0), Vector2(-3000.0, 3000.0)]

# Footprint half extents BuildingBase.get_nav_obstacle_polygon() emits for a
# wall segment: 16 px collision shape + the 6 px carve margin.
const WALL_HALF: float = 14.0
# Diagonal offset that makes the two carved footprints touch at one point once
# they are inflated by the agent radius: 48 - 2 * 14 = 20 = 2 * 10.
const DIAGONAL_STEP: float = 48.0

func _board() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	out.append(PackedVector2Array(BOARD))
	return out

func _footprint(center: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-half, -half), center + Vector2(half, -half),
		center + Vector2(half, half), center + Vector2(-half, half)])

func _diagonal_pair() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	out.append(_footprint(Vector2(8.0, 8.0), WALL_HALF))
	out.append(_footprint(Vector2(8.0 + DIAGONAL_STEP, 8.0 + DIAGONAL_STEP), WALL_HALF))
	return out

func _scene_polygon() -> NavigationPolygon:
	# The agent settings the three navigation regions in game_world.tscn carry.
	var poly: NavigationPolygon = NavigationPolygon.new()
	poly.agent_radius = 10.0
	poly.cell_size = 4.0
	return poly

func test_nominal_radius_loses_the_whole_mesh() -> void:
	var poly: NavigationPolygon = _scene_polygon()
	NavigationServer2D.bake_from_source_geometry_data(
		poly, NavMeshBuilder.build_source(_board(), _diagonal_pair()))
	assert_eq(poly.get_polygon_count(), 0,
		"the regression: two diagonal footprints, unnudged, empty the whole navmesh")
	assert_engine_error("convex partition failed")

func test_nudged_bake_recovers_the_mesh() -> void:
	var poly: NavigationPolygon = NavMeshBuilder.bake_surface(
		_scene_polygon(), _board(), _diagonal_pair())
	assert_gt(poly.get_polygon_count(), 0,
		"the nudged bake produces a usable mesh for the same two buildings")

func test_nudge_survives_a_diagonal_chain() -> void:
	var chain: Array[PackedVector2Array] = _diagonal_pair()
	chain.append(_footprint(
		Vector2(8.0 + DIAGONAL_STEP * 2.0, 8.0 + DIAGONAL_STEP * 2.0), WALL_HALF))
	var poly: NavigationPolygon = NavMeshBuilder.bake_surface(_scene_polygon(), _board(), chain)
	assert_gt(poly.get_polygon_count(), 0, "a whole diagonal run of walls still bakes")

func test_nudge_only_widens_by_half_a_pixel() -> void:
	var target: NavigationPolygon = NavMeshBuilder.bake_target(_scene_polygon(), 0)
	assert_almost_eq(target.agent_radius, 10.5, 0.001,
		"the first attempt bakes half a pixel wider than the scene radius")
	assert_almost_eq(target.cell_size, 4.0, 0.001, "cell size is carried over untouched")

func test_ladder_offers_distinct_fallback_nudges() -> void:
	assert_gt(NavMeshBuilder.nudge_attempts(), 1, "there is at least one fallback attempt")
	var seen: Array[float] = []
	for attempt: int in range(NavMeshBuilder.nudge_attempts()):
		var nudge: float = NavMeshBuilder.nudge_for_attempt(attempt)
		assert_false(seen.has(nudge), "each attempt offsets the outlines differently")
		seen.append(nudge)

func test_clean_layout_still_bakes() -> void:
	var poly: NavigationPolygon = NavMeshBuilder.bake_surface(
		_scene_polygon(), _board(), [] as Array[PackedVector2Array])
	assert_gt(poly.get_polygon_count(), 0, "an empty obstruction set bakes the open board")

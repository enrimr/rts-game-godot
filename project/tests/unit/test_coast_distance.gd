extends GutTest

## TerrainManager.distance_to_coast — the query behind shallow water and the
## sea-fog coastal cloak. It used to be an outward ring search costing ~1.8 ms
## per call, which froze the game while sea fog was up (the fog query runs it
## once per unit and building, several times a second). It is now analytic and
## memoized per COAST_CACHE_CELL cell, so these tests pin both the values and
## the cache invalidation that the memo depends on.

const LAND_HALF: float = 400.0
# The memo answers at the centre of a COAST_CACHE_CELL cell, so a queried point
# can be off by at most half a cell diagonal.
const CELL_TOLERANCE: float = 20.0

func before_each() -> void:
	TerrainManager.reset()

func after_each() -> void:
	TerrainManager.reset()

func _square_island() -> void:
	TerrainManager.set_land_polys([PackedVector2Array([
		Vector2(-LAND_HALF, -LAND_HALF), Vector2(LAND_HALF, -LAND_HALF),
		Vector2(LAND_HALF, LAND_HALF), Vector2(-LAND_HALF, LAND_HALF),
	])], true)

# 1 — island maps measure to the land outline, from either side of it
func test_distance_to_island_outline() -> void:
	_square_island()
	assert_almost_eq(TerrainManager.distance_to_coast(Vector2(LAND_HALF + 200.0, 0.0)),
		200.0, CELL_TOLERANCE, "200 px offshore")
	assert_almost_eq(TerrainManager.distance_to_coast(Vector2.ZERO),
		LAND_HALF, CELL_TOLERANCE, "the island centre is LAND_HALF from its own shore")
	assert_almost_eq(TerrainManager.distance_to_coast(Vector2(LAND_HALF, 0.0)),
		0.0, CELL_TOLERANCE, "the shoreline itself")

# 2 — coastal maps have no land polygons; the coast is the ocean zone's edge
func test_distance_to_ocean_zone_edge() -> void:
	TerrainManager.add_zone(Vector2(1000.0, 0.0), 300.0, TerrainManager.TerrainType.OCEAN)
	assert_almost_eq(TerrainManager.distance_to_coast(Vector2(1000.0, 0.0)),
		300.0, CELL_TOLERANCE, "the zone centre is one radius from the water's edge")
	assert_almost_eq(TerrainManager.distance_to_coast(Vector2(1400.0, 0.0)),
		100.0, CELL_TOLERANCE, "100 px inland of the zone edge")

# 3 — a map with no water at all has no coast
func test_no_coast_is_infinite() -> void:
	assert_eq(TerrainManager.distance_to_coast(Vector2(120.0, 340.0)), INF,
		"a landlocked map never reports a coastline")

# 4 — the memo must not outlive the terrain it was computed from
func test_cache_is_invalidated_by_terrain_changes() -> void:
	var probe: Vector2 = Vector2(1000.0, 0.0)
	assert_eq(TerrainManager.distance_to_coast(probe), INF, "no water yet")
	TerrainManager.add_zone(probe, 300.0, TerrainManager.TerrainType.OCEAN)
	assert_almost_eq(TerrainManager.distance_to_coast(probe), 300.0, CELL_TOLERANCE,
		"add_zone drops the cached answer")
	# An island whose shore is nearer than the zone edge: the cached 300 would
	# survive an un-invalidated memo.
	TerrainManager.set_land_polys([PackedVector2Array([
		Vector2(-900.0, -900.0), Vector2(900.0, -900.0),
		Vector2(900.0, 900.0), Vector2(-900.0, 900.0),
	])], true)
	assert_almost_eq(TerrainManager.distance_to_coast(probe), 100.0, CELL_TOLERANCE,
		"set_land_polys drops it too — the island shore is now the nearest coast")
	TerrainManager.reset()
	assert_eq(TerrainManager.distance_to_coast(probe), INF, "reset clears the cache")

# 5 — the answer must not depend on which query filled the cell first
func test_answer_is_independent_of_query_order() -> void:
	_square_island()
	var a: float = TerrainManager.distance_to_coast(Vector2(LAND_HALF + 201.0, 1.0))
	var b: float = TerrainManager.distance_to_coast(Vector2(LAND_HALF + 200.0, 0.0))
	assert_eq(a, b, "two points in the same cell get the same memoized distance")

	TerrainManager.reset()
	_square_island()
	var reversed_first: float = TerrainManager.distance_to_coast(Vector2(LAND_HALF + 200.0, 0.0))
	assert_eq(reversed_first, b, "asking in the other order gives the same value")

# 6 — shallow water rides on this query, so keep the band honest
func test_shallow_band_matches_the_distance() -> void:
	_square_island()
	var inside: Vector2 = Vector2(LAND_HALF + TerrainManager.SHALLOW_WATER_DEPTH * 0.5, 0.0)
	var outside: Vector2 = Vector2(LAND_HALF + TerrainManager.SHALLOW_WATER_DEPTH * 3.0, 0.0)
	assert_true(TerrainManager.is_shallow_water(inside))
	assert_false(TerrainManager.is_shallow_water(outside))

extends GutTest

## EntityPlacer — occupancy grid plus every entity spawn of map generation.
##
## What is covered:
##   1.  place_tc_ring: one start position per player, inside the map, spread
##       around a ring so nobody starts on top of a rival.
##   2.  The occupancy registry keeps the town-center footprint clear of
##       resources.
##   3.  spawn_animals: starting sheep next to each TC, neutral deer kept away.
##   4.  spawn_resource_islets appends to the *shared* land-polygon array, which
##       is what lets the nav mesh carve islets it never saw being created.

const MAP_HALF: float = 1800.0

var _placer: EntityPlacer = null
var _painter: TerrainPainter = null

func before_each() -> void:
	TerrainManager.reset()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9001
	_painter = TerrainPainter.new()
	_painter.setup(rng, MAP_HALF)
	_placer = EntityPlacer.new()
	_placer.setup(rng, MAP_HALF, 1.0, _painter, [])

func after_each() -> void:
	TerrainManager.reset()

# 1 — start positions
func test_tc_ring_has_one_position_per_player() -> void:
	assert_eq(_placer.place_tc_ring(4).size(), 4)
	assert_eq(_placer.place_tc_ring(2).size(), 2)

func test_tc_ring_stays_inside_the_map() -> void:
	for tc: Vector2 in _placer.place_tc_ring(4):
		assert_between(tc.x, -MAP_HALF, MAP_HALF)
		assert_between(tc.y, -MAP_HALF, MAP_HALF)

func test_tc_ring_separates_players() -> void:
	var ring: Array[Vector2] = _placer.place_tc_ring(4)
	for i: int in range(ring.size()):
		for j: int in range(i + 1, ring.size()):
			assert_gt(ring[i].distance_to(ring[j]), 600.0,
				"rival start positions must not share a corner of the map")

# 2 — the registry protects the town center footprint
func test_resources_never_spawn_on_the_town_center() -> void:
	var parent: Node2D = Node2D.new()
	add_child_autofree(parent)
	_placer.register_town_center(Vector2.ZERO)
	_placer.spawn_player_resources(parent, Vector2.ZERO, 0.0)

	var found: int = 0
	for child: Node in parent.get_children():
		if child.get("resource_type") == null:
			continue
		found += 1
		assert_gt((child as Node2D).global_position.length(), EntityPlacer.R_TC,
			"nothing may be placed inside the town-center footprint")
	assert_gt(found, 0, "the starting layout must actually spawn resources")

# 3 — animals
func test_starting_sheep_spawn_next_to_each_town_center() -> void:
	var units: Node2D = Node2D.new()
	add_child_autofree(units)
	var tcs: Array[Vector2] = [Vector2(-800.0, 0.0), Vector2(800.0, 0.0)]
	for tc: Vector2 in tcs:
		_placer.register_town_center(tc)
	_placer.spawn_animals(units, tcs)

	var sheep: int = 0
	var deer: int = 0
	for child: Node in units.get_children():
		if child is Sheep:
			sheep += 1
			var d: float = mini(
				roundi((child as Node2D).global_position.distance_to(tcs[0])),
				roundi((child as Node2D).global_position.distance_to(tcs[1])))
			assert_lt(float(d), 400.0, "starting sheep graze within reach of a TC")
		else:
			deer += 1
			for tc: Vector2 in tcs:
				assert_gt((child as Node2D).global_position.distance_to(tc), 300.0,
					"neutral deer are hunted for, not handed over")
	assert_eq(sheep, 8, "4 sheep per town center")
	assert_gt(deer, 0, "the map holds neutral huntables")

# 4 — islets feed the same array the nav mesh reads
func test_islets_extend_the_shared_land_polygons() -> void:
	var parent: Node2D = Node2D.new()
	add_child_autofree(parent)
	var land_polys: Array = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	_painter = TerrainPainter.new()
	_painter.setup(rng, MAP_HALF)
	_placer = EntityPlacer.new()
	_placer.setup(rng, MAP_HALF, 1.0, _painter, land_polys)

	var island_radius: float = MAP_HALF * 0.30
	var centers: Array[Vector2] = [Vector2(-700.0, 0.0), Vector2(700.0, 0.0)]
	for c: Vector2 in centers:
		land_polys.append(_painter.make_island_poly(c, island_radius))
	TerrainManager.set_land_polys(land_polys, true)

	_placer.spawn_resource_islets(parent, centers[0], centers[1], island_radius)

	assert_gt(land_polys.size(), 2,
		"islets are appended to the array the generator handed over")
	assert_eq(TerrainManager.get_land_polys().size(), land_polys.size(),
		"TerrainManager sees every islet as land")

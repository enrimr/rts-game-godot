extends GutTest

## NavMeshBuilder — navigation geometry of a generated map.
##
## What is covered:
##   1.  Impassable terrain zones become NavigationObstacle2D nodes on the land
##       region; passable ground (dune, grass) does not.
##   2.  A civ that traverses malpaís gets no obstacle there (nav mesh must not
##       undo the civ bonus) while cliffs still block everyone.
##   3.  Islands maps bake both meshes: land covers the islands only, ocean
##       covers the water only, and the map edge is walled off.
##   4.  Overlapping islands still produce usable meshes (the old
##       make_polygons_from_outlines() path failed its convex partition there and
##       left ships with an empty ocean mesh).
##   5.  Non-island maps leave the ocean region alone.

const MAP_HALF: float = 1800.0

var _saved_map_type: int = 0
var _saved_civ: String = ""

func before_each() -> void:
	_saved_map_type = MatchConfig.map_type
	_saved_civ = MatchConfig.player_civ_id
	TerrainManager.reset()

func after_each() -> void:
	MatchConfig.map_type = _saved_map_type
	MatchConfig.player_civ_id = _saved_civ
	TerrainManager.reset()

func _make_root() -> Node2D:
	var root: Node2D = Node2D.new()
	var land: NavigationRegion2D = NavigationRegion2D.new()
	land.name = "NavigationRegion2D"
	root.add_child(land)
	var ocean: NavigationRegion2D = NavigationRegion2D.new()
	ocean.name = "OceanNavigationRegion2D"
	root.add_child(ocean)
	add_child_autofree(root)
	return root

## True when `p` lies on the baked walkable surface. The baker keeps no source
## outlines, so coverage has to be probed through the triangles themselves.
func _mesh_covers(poly: NavigationPolygon, p: Vector2) -> bool:
	if poly == null:
		return false
	var verts: PackedVector2Array = poly.get_vertices()
	for i: int in range(poly.get_polygon_count()):
		var face: PackedVector2Array = PackedVector2Array()
		for idx: int in poly.get_polygon(i):
			face.append(verts[idx])
		if Geometry2D.is_point_in_polygon(p, face):
			return true
	return false

func _obstacles(root: Node2D) -> int:
	var n: int = 0
	for child: Node in root.get_node("NavigationRegion2D").get_children():
		if child is NavigationObstacle2D:
			n += 1
	return n

# 1 — impassable zones become obstacles
func test_impassable_zones_become_obstacles() -> void:
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.player_civ_id = "franks"
	TerrainManager.add_zone(Vector2(400.0, 0.0), 200.0, TerrainManager.TerrainType.RISCO)
	TerrainManager.add_zone(Vector2(-400.0, 0.0), 200.0, TerrainManager.TerrainType.MALPAIS)
	TerrainManager.add_zone(Vector2(0.0, 600.0), 200.0, TerrainManager.TerrainType.CALDERA)
	TerrainManager.add_zone(Vector2(0.0, -600.0), 200.0, TerrainManager.TerrainType.DUNE)

	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF, [])
	assert_eq(_obstacles(root), 3, "cliff, malpaís and caldera block, dune does not")

# 2 — civ traversal bonuses survive the nav mesh
func test_traversing_civ_skips_lava_obstacles() -> void:
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.player_civ_id = "guanches"
	TerrainManager.add_zone(Vector2(400.0, 0.0), 200.0, TerrainManager.TerrainType.RISCO)
	TerrainManager.add_zone(Vector2(-400.0, 0.0), 200.0, TerrainManager.TerrainType.MALPAIS)
	TerrainManager.add_zone(Vector2(0.0, 600.0), 200.0, TerrainManager.TerrainType.CALDERA)

	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF, [])
	assert_eq(_obstacles(root), 1,
		"Guanches walk malpaís and caldera; only the cliff stays impassable")

func test_obstacle_matches_its_zone() -> void:
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.player_civ_id = "franks"
	TerrainManager.add_zone(Vector2(320.0, -180.0), 250.0, TerrainManager.TerrainType.RISCO)

	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF, [])
	var obstacle: NavigationObstacle2D = null
	for child: Node in root.get_node("NavigationRegion2D").get_children():
		if child is NavigationObstacle2D:
			obstacle = child as NavigationObstacle2D
	assert_not_null(obstacle)
	assert_eq(obstacle.position, Vector2(320.0, -180.0), "obstacle sits on its zone")
	assert_true(obstacle.avoidance_enabled)
	for v: Vector2 in obstacle.vertices:
		assert_almost_eq(v.length(), 250.0, 1.0, "outline traces the zone radius")

# 3 — islands bake both meshes
func test_islands_carve_land_and_ocean_meshes() -> void:
	var root: Node2D = _build_islands([Vector2(-700.0, 0.0), Vector2(700.0, 0.0)], 500.0)
	var land: NavigationPolygon = (root.get_node("NavigationRegion2D") as NavigationRegion2D).navigation_polygon
	var ocean: NavigationPolygon = (root.get_node("OceanNavigationRegion2D") as NavigationRegion2D).navigation_polygon
	assert_not_null(land)
	assert_not_null(ocean)
	assert_gt(land.get_polygon_count(), 0, "land mesh has walkable polygons")
	assert_gt(ocean.get_polygon_count(), 0, "ocean mesh has sailable polygons")

	for center: Vector2 in [Vector2(-700.0, 0.0), Vector2(700.0, 0.0)]:
		assert_true(_mesh_covers(land, center), "units walk the island at %s" % center)
		assert_false(_mesh_covers(ocean, center), "ships cannot sail onto the island at %s" % center)
	assert_true(_mesh_covers(ocean, Vector2.ZERO), "ships sail the channel between the islands")
	assert_false(_mesh_covers(land, Vector2.ZERO), "the channel is not walkable")

# 4 — overlapping islands still bake (the old convex-partition path did not)
func test_overlapping_islands_still_bake_a_sailable_ocean() -> void:
	var root: Node2D = _build_islands([Vector2(-200.0, 0.0), Vector2(200.0, 0.0)], 500.0)
	var land: NavigationPolygon = (root.get_node("NavigationRegion2D") as NavigationRegion2D).navigation_polygon
	var ocean: NavigationPolygon = (root.get_node("OceanNavigationRegion2D") as NavigationRegion2D).navigation_polygon
	assert_gt(land.get_polygon_count(), 0, "merged land mass is still walkable")
	assert_gt(ocean.get_polygon_count(), 0,
		"overlapping holes must not wipe the ocean mesh — that freezes every ship")
	assert_true(_mesh_covers(ocean, Vector2(0.0, MAP_HALF - 200.0)), "open water still sailable")

func _build_islands(centers: Array, radius: float) -> Node2D:
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	MatchConfig.player_civ_id = "franks"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var painter: TerrainPainter = TerrainPainter.new()
	painter.setup(rng, MAP_HALF)
	var land_polys: Array = []
	for c: Vector2 in centers:
		land_polys.append(painter.make_island_poly(c, radius))
	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF, land_polys)
	return root

func test_islands_wall_off_the_map_edge() -> void:
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	MatchConfig.player_civ_id = "franks"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var painter: TerrainPainter = TerrainPainter.new()
	painter.setup(rng, MAP_HALF)

	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF,
		[painter.make_island_poly(Vector2.ZERO, 500.0)])

	var walls: int = 0
	for child: Node in root.get_children():
		if child is StaticBody2D:
			walls += 1
			assert_eq((child as StaticBody2D).collision_layer, 1,
				"boundary walls live on the world layer")
	assert_eq(walls, 4, "ships are fenced in on all four sides")

# 5 — other map types keep the default ocean region
func test_land_map_leaves_the_ocean_region_untouched() -> void:
	MatchConfig.map_type = MatchConfig.MapType.PLAINS
	MatchConfig.player_civ_id = "franks"
	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF, [])
	assert_null((root.get_node("OceanNavigationRegion2D") as NavigationRegion2D).navigation_polygon)
	assert_null((root.get_node("NavigationRegion2D") as NavigationRegion2D).navigation_polygon)

func test_missing_land_region_is_tolerated() -> void:
	MatchConfig.map_type = MatchConfig.MapType.PLAINS
	var root: Node2D = Node2D.new()
	add_child_autofree(root)
	NavMeshBuilder.new().build(root, MAP_HALF, [])
	assert_eq(root.get_child_count(), 0, "no regions in the scene — nothing to carve")

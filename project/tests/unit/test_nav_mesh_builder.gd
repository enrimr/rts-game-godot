extends GutTest

## NavMeshBuilder — navigation geometry of a generated map.
##
## What is covered:
##   1.  Impassable terrain zones become NavigationObstacle2D nodes on the land
##       region; passable ground (dune, grass) does not.
##   2.  A civ that traverses malpaís gets no obstacle there (nav mesh must not
##       undo the civ bonus) while cliffs still block everyone.
##   3.  Islands maps carve both meshes: land = one outline per island, ocean =
##       map rect plus one hole per island, walled off at the map edge.
##   4.  Non-island maps leave the ocean region alone.

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

# NavigationPolygon.make_polygons_from_outlines() is deprecated in Godot 4.6 but
# is still the only synchronous way to carve a polygon; the async
# NavigationServer2D baking path would not be ready when generation returns.
# GUT fails a test on any engine error, so absorb that one notice here.
func _absorb_navpoly_deprecation() -> void:
	for err: GutTrackedError in get_errors():
		if err.contains_text("make_polygons_from_outlines"):
			err.handled = true

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

# 3 — islands carve both meshes
func test_islands_carve_land_and_ocean_meshes() -> void:
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	MatchConfig.player_civ_id = "franks"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var painter: TerrainPainter = TerrainPainter.new()
	painter.setup(rng, MAP_HALF)
	var land_polys: Array = [
		painter.make_island_poly(Vector2(-700.0, 0.0), 500.0),
		painter.make_island_poly(Vector2(700.0, 0.0), 500.0),
	]

	var root: Node2D = _make_root()
	NavMeshBuilder.new().build(root, MAP_HALF, land_polys)

	var land: NavigationRegion2D = root.get_node("NavigationRegion2D") as NavigationRegion2D
	var ocean: NavigationRegion2D = root.get_node("OceanNavigationRegion2D") as NavigationRegion2D
	assert_not_null(land.navigation_polygon)
	assert_eq(land.navigation_polygon.get_outline_count(), 2, "one walkable outline per island")
	assert_not_null(ocean.navigation_polygon)
	assert_eq(ocean.navigation_polygon.get_outline_count(), 3,
		"ocean = map rect + one hole per island")
	_absorb_navpoly_deprecation()

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
	_absorb_navpoly_deprecation()

# 4 — other map types keep the default ocean region
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

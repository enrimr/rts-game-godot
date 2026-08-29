class_name NavMeshBuilder extends RefCounted

## Carves the three navigation meshes of a generated map and walls off the ocean.
##
## Layer 1 (NavigationRegion2D)            → land units: covers land, excludes ocean
## Layer 2 (OceanNavigationRegion2D)       → ships:      covers ocean, excludes land
## Layer 4 (AmphibiousNavigationRegion2D)  → amphibious units: the whole board
##
## On Islands maps the first two meshes are carved from the land polygons. The
## amphibious mesh is never carved — that is the point: land and ocean are baked
## with an agent radius, so each one ends ~10 px short of the shoreline and the
## two never share an edge. An amphibious unit given both layers would still be
## stuck on its island, so it gets its own single continuous mesh instead.
##
## On other maps there is no ocean, so the ocean region stays as the full-map
## default (ships won't be trained on those map types anyway).

## Navigation layer bit of the amphibious mesh. Units that walk into water set
## their NavigationAgent2D.navigation_layers to this (see Tidecaller).
const AMPHIBIOUS_LAYER: int = 4

func build(parent: Node2D, map_half: float, land_polys: Array) -> void:
	var land_region: NavigationRegion2D = parent.get_node_or_null("NavigationRegion2D") as NavigationRegion2D
	var ocean_region: NavigationRegion2D = parent.get_node_or_null("OceanNavigationRegion2D") as NavigationRegion2D
	var amphibious_region: NavigationRegion2D = parent.get_node_or_null("AmphibiousNavigationRegion2D") as NavigationRegion2D

	if land_region == null:
		return

	var half: float = map_half  # exact boundary — no overshoot
	var board: Array[PackedVector2Array] = [PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half,  half),  Vector2(-half,  half),
	])]

	# Amphibious mesh: everything inside the playable area, land and water alike.
	if amphibious_region != null:
		_bake(amphibious_region, board, [])

	if MatchConfig.map_type == MatchConfig.MapType.ISLANDS and land_polys.size() > 0:
		var islands: Array[PackedVector2Array] = []
		for lp: Variant in land_polys:
			islands.append(lp as PackedVector2Array)

		# Land mesh: the islands are the walkable surface.
		_bake(land_region, islands, [])

		# Ocean mesh: the whole board minus the islands, so ships sail
		# everywhere except over land.
		if ocean_region != null:
			_bake(ocean_region, board, islands)
			# Physical walls so ships cannot sail past the map edge
			_add_ocean_boundary_walls(parent, half)

	# Solid impassable zones → NavigationObstacle2D on the land region.
	# Skip obstacle types that the player's civ can traverse freely.
	var player_civ_id: String = MatchConfig.player_civ_id
	var player_civ: CivilizationResource = load(
		"res://resources/civilizations/%s.tres" % player_civ_id) as CivilizationResource
	var skip_malpais: bool = player_civ != null and player_civ.can_traverse_malpais
	var skip_caldera: bool = skip_malpais  # Guanches treat caldera like malpais

	for z: Dictionary in TerrainManager.get_zones():
		var t: TerrainManager.TerrainType = z["type"] as TerrainManager.TerrainType
		match t:
			TerrainManager.TerrainType.RISCO:
				pass  # always an obstacle
			TerrainManager.TerrainType.MALPAIS:
				if skip_malpais:
					continue
			TerrainManager.TerrainType.CALDERA:
				if skip_caldera:
					continue
			_:
				continue
		var center: Vector2 = z["center"] as Vector2
		var radius: float   = z["radius"] as float
		var obstacle: NavigationObstacle2D = NavigationObstacle2D.new()
		obstacle.avoidance_enabled = true
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(16):
			var a: float = TAU * i / 16
			pts.append(Vector2(cos(a), sin(a)) * radius)
		obstacle.vertices = pts
		obstacle.position = center
		land_region.add_child(obstacle)

## Bakes `region`'s mesh from outline geometry, keeping the agent settings the
## scene's polygon carries. Uses the source-geometry baker (the same one the
## runtime rebake in WorldPlacement uses) rather than
## NavigationPolygon.make_polygons_from_outlines(): that one is deprecated and,
## worse, its convex partition fails outright on outlines that touch or overlap
## — which left the ocean mesh empty and every ship unable to move.
func _bake(region: NavigationRegion2D, traversable: Array[PackedVector2Array],
		obstructions: Array[PackedVector2Array]) -> void:
	var poly: NavigationPolygon = NavigationPolygon.new()
	var current: NavigationPolygon = region.navigation_polygon
	if current != null:
		poly.agent_radius = current.agent_radius
		poly.cell_size = current.cell_size
	var source: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	for outline: PackedVector2Array in traversable:
		source.add_traversable_outline(outline)
	for outline: PackedVector2Array in obstructions:
		source.add_obstruction_outline(outline)
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	if poly.get_polygon_count() > 0:
		region.navigation_polygon = poly
	else:
		push_warning("NavMeshBuilder: empty bake for %s; keeping the scene default." % region.name)

# Places four thin StaticBody2D walls along the map edges so ships
# (CharacterBody2D on the ocean layer) cannot navigate outside the playable area.
func _add_ocean_boundary_walls(parent: Node2D, half: float) -> void:
	const THICKNESS: float = 40.0
	# [position, half-size]
	var walls: Array = [
		[Vector2(0.0,        -half - THICKNESS * 0.5), Vector2(half + THICKNESS, THICKNESS)],  # top
		[Vector2(0.0,         half + THICKNESS * 0.5), Vector2(half + THICKNESS, THICKNESS)],  # bottom
		[Vector2(-half - THICKNESS * 0.5, 0.0),        Vector2(THICKNESS, half + THICKNESS)],  # left
		[Vector2( half + THICKNESS * 0.5, 0.0),        Vector2(THICKNESS, half + THICKNESS)],  # right
	]
	for w: Array in walls:
		var body: StaticBody2D = StaticBody2D.new()
		body.position = w[0] as Vector2
		body.collision_layer = 1
		body.collision_mask  = 0
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = (w[1] as Vector2) * 2.0
		shape.shape = rect
		body.add_child(shape)
		parent.add_child(body)

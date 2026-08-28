class_name NavMeshBuilder extends RefCounted

## Carves the two navigation meshes of a generated map and walls off the ocean.
##
## Layer 1 (NavigationRegion2D)      → land units: covers land, excludes ocean
## Layer 2 (OceanNavigationRegion2D) → ships:      covers ocean, excludes land
##
## On Islands maps both meshes are carved from the land polygons.
## On other maps there is no ocean so the ocean region stays as the full-map
## default (ships won't be trained on those map types anyway).

func build(parent: Node2D, map_half: float, land_polys: Array) -> void:
	var land_region: NavigationRegion2D = parent.get_node_or_null("NavigationRegion2D") as NavigationRegion2D
	var ocean_region: NavigationRegion2D = parent.get_node_or_null("OceanNavigationRegion2D") as NavigationRegion2D

	if land_region == null:
		return

	if MatchConfig.map_type == MatchConfig.MapType.ISLANDS and land_polys.size() > 0:
		# Land mesh: one polygon per island (CCW outline = walkable interior)
		var land_poly: NavigationPolygon = NavigationPolygon.new()
		for lp: Variant in land_polys:
			land_poly.add_outline(lp as PackedVector2Array)
		land_poly.make_polygons_from_outlines()
		land_region.navigation_polygon = land_poly

		# Ocean mesh: full-map rect with each land island as a CW hole,
		# so ships can navigate everywhere except the land blobs.
		if ocean_region != null:
			var half: float = map_half  # exact boundary — no overshoot
			# Outer boundary CCW
			var ocean_poly: NavigationPolygon = NavigationPolygon.new()
			ocean_poly.add_outline(PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half),
				Vector2(half,  half),  Vector2(-half,  half),
			]))
			# Each land polygon as a CW hole (reverse winding)
			for lp: Variant in land_polys:
				var fwd: PackedVector2Array = lp as PackedVector2Array
				var rev: PackedVector2Array = PackedVector2Array()
				for j: int in range(fwd.size() - 1, -1, -1):
					rev.append(fwd[j])
				ocean_poly.add_outline(rev)
			ocean_poly.make_polygons_from_outlines()
			ocean_region.navigation_polygon = ocean_poly
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

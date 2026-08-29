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

## Half-pixel widening added to the agent radius of every bake.
##
## Player footprints snap to a 16 px grid and carve with a 6 px margin
## (BuildingBase._nav_bake_half_extents), so the carved gaps between them are
## fixed grid multiples — and a 20 px gap pinches to EXACTLY zero width once both
## sides are offset by the 10 px agent radius. Godot's convex partition fails
## outright on that degenerate contact and returns an EMPTY mesh: fuzzing dense
## grid-snapped layouts hit it in ~5 % of cases, and a 20 px gap is one wall
## segment missing from a wall run. Baking half a pixel wider turns the pinch
## into a clean merge (0 failures in the same 1500-layout fuzz), at the cost of
## closing a gap that was never reliably walkable anyway.
const RADIUS_NUDGE: float = 0.5

## Further nudges tried, in order, when a bake still comes back empty — a
## different sub-pixel offset breaks a different degenerate contact.
const RADIUS_FALLBACKS: Array[float] = [0.25, 1.0, -0.5]

## Total bake attempts available: the standard nudge plus the fallbacks.
static func nudge_attempts() -> int:
	return 1 + RADIUS_FALLBACKS.size()

static func nudge_for_attempt(attempt: int) -> float:
	if attempt <= 0:
		return RADIUS_NUDGE
	return RADIUS_FALLBACKS[mini(attempt, RADIUS_FALLBACKS.size()) - 1]

## Fresh polygon carrying `current`'s agent settings plus the attempt's nudge.
## Baking into a fresh resource (never the live one) keeps the region's current
## mesh intact while the bake runs and if it fails.
static func bake_target(current: NavigationPolygon, attempt: int) -> NavigationPolygon:
	var poly: NavigationPolygon = NavigationPolygon.new()
	if current != null:
		poly.agent_radius = current.agent_radius + nudge_for_attempt(attempt)
		poly.cell_size = current.cell_size
	else:
		poly.agent_radius = 10.0 + nudge_for_attempt(attempt)
	return poly

static func build_source(traversable: Array[PackedVector2Array],
		obstructions: Array[PackedVector2Array]) -> NavigationMeshSourceGeometryData2D:
	var source: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	for outline: PackedVector2Array in traversable:
		source.add_traversable_outline(outline)
	for outline: PackedVector2Array in obstructions:
		source.add_obstruction_outline(outline)
	return source

## Synchronous bake walking the nudge ladder until the partition succeeds.
## Returns an empty polygon if every attempt failed.
static func bake_surface(current: NavigationPolygon, traversable: Array[PackedVector2Array],
		obstructions: Array[PackedVector2Array]) -> NavigationPolygon:
	var poly: NavigationPolygon = null
	for attempt: int in range(nudge_attempts()):
		poly = bake_target(current, attempt)
		NavigationServer2D.bake_from_source_geometry_data(
			poly, build_source(traversable, obstructions))
		if poly.get_polygon_count() > 0:
			return poly
	return poly

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
	var poly: NavigationPolygon = bake_surface(
		region.navigation_polygon, traversable, obstructions)
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

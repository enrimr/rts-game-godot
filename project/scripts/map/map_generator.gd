class_name MapGenerator

## Generates a symmetric random map and paints procedural terrain zones.
## Placement order: background → terrain zones → TCs → units → animals → resources.


var _rng: RandomNumberGenerator = null
var _map_half: float = 1800.0
var _res_mult: float = 1.0

# Polygon2D pool reused for terrain patches
var _terrain_root: Node2D = null
# Land polygons for island map (used by TerrainManager)
var _land_polys: Array = []

# Terrain visuals for this generation (owns MapMaterials + TerrainDetail)
var _painter: TerrainPainter = TerrainPainter.new()
# Occupancy grid + every entity spawn (town centers, animals, resources)
var _placer: EntityPlacer = EntityPlacer.new()
var _nav: NavMeshBuilder = NavMeshBuilder.new()

# ── Public entry point ──────────────────────────────────────────────────────

static func generate(parent: Node2D, units_layer: Node2D,
		rng: RandomNumberGenerator) -> Dictionary:
	var gen: MapGenerator = MapGenerator.new()
	gen._map_half = MatchConfig.get_map_half()
	gen._res_mult = MatchConfig.get_resource_multiplier()
	TerrainManager.reset()
	return gen._run(parent, units_layer, rng)

# ── Main pipeline ───────────────────────────────────────────────────────────

func _run(parent: Node2D, units_layer: Node2D,
		rng: RandomNumberGenerator) -> Dictionary:
	_rng = rng
	_painter.setup(rng, _map_half)
	_placer.setup(rng, _map_half, _res_mult, _painter, _land_polys)

	# Terrain root — plain Node2D; polygon clipping is done in _add_polygon_clipped
	_terrain_root = Node2D.new()
	_terrain_root.z_index = -9
	parent.add_child(_terrain_root as Node2D)

	var player_count: int = 1 + MatchConfig.rival_count
	var tc_positions: Array[Vector2] = []

	match MatchConfig.map_type:
		MatchConfig.MapType.ISLANDS:
			tc_positions = _run_islands(parent, units_layer, player_count)
		MatchConfig.MapType.PLAINS:
			tc_positions = _placer.place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_placer.register_town_center(tc)
			# No terrain zones — scatter grass variants over the flat base
			_painter.paint_rect_bg(parent, _map_half, MapMaterials.color_for(TerrainManager.TerrainType.GRASS))
			_painter.paint_ground_scatter(parent, _map_half, TerrainManager.TerrainType.GRASS)
			_placer.spawn_animals(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_placer.spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_placer.spawn_neutral_resources(parent)
			_placer.spawn_scattered_resources(parent, tc_positions)
		MatchConfig.MapType.VOLCANIC_COAST:
			tc_positions = _placer.place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_placer.register_town_center(tc)
			_painter.paint_volcanic_coast(parent)
			_placer.spawn_animals(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_placer.spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_placer.spawn_neutral_resources(parent)
			_placer.spawn_scattered_resources(parent, tc_positions)
		MatchConfig.MapType.DESERT_COAST:
			tc_positions = _placer.place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_placer.register_town_center(tc)
			_painter.paint_desert_coast(parent)
			_placer.spawn_animals(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_placer.spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_placer.spawn_neutral_resources(parent)
			_placer.spawn_scattered_resources(parent, tc_positions)
		_: # STANDARD
			tc_positions = _placer.place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_placer.register_town_center(tc)
			_painter.paint_standard(parent)
			_placer.spawn_animals(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_placer.spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_placer.spawn_neutral_resources(parent)
			_placer.spawn_scattered_resources(parent, tc_positions)

	_placer.spawn_laurisilva_forests(parent)
	_nav.build(parent, _map_half, _land_polys)
	TerrainManager.bake_minimap_texture(_map_half, 256)
	return {"tc_positions": tc_positions}


# ── Islands map ─────────────────────────────────────────────────────────────

func _run_islands(parent: Node2D, units_layer: Node2D,
		player_count: int) -> Array[Vector2]:
	_painter.paint_ocean_bg(parent, _map_half * 1.05)

	# Scale island size down slightly when more players fit more islands
	var island_radius: float = _map_half * (0.38 if player_count <= 2 else 0.30)
	var ring_dist: float = _map_half * (0.50 if player_count <= 2 else 0.46)
	var base_angle: float = _rng.randf() * TAU

	var island_centers: Array[Vector2] = []
	_land_polys.clear()

	for i: int in range(player_count):
		var angle: float = base_angle + TAU * float(i) / float(player_count)
		var center: Vector2 = Vector2(cos(angle), sin(angle)) * ring_dist
		center += Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
		island_centers.append(center)
		var poly: PackedVector2Array = _painter.make_island_poly(center, island_radius)
		_land_polys.append(poly)
		TerrainManager.set_land_polys(_land_polys, true)
		_painter.paint_shore(parent, poly, center)
		_painter.paint_polygon(parent, poly, MapMaterials.color_for(TerrainManager.TerrainType.GRASS))
		_painter.scatter_island_terrain(center, island_radius)

	_painter.flush_zone_visuals(parent)

	# TC per island
	var tc_positions: Array[Vector2] = []
	for center: Vector2 in island_centers:
		var tc: Vector2 = center + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60))
		_placer.register_town_center(tc)
		tc_positions.append(tc)

	# Resources per island
	for i: int in range(player_count):
		_placer.spawn_island_resources(parent, tc_positions[i], island_centers[i], island_radius)

	# Animals, fish, islets
	_placer.spawn_animals(units_layer, tc_positions)
	var map_center: Vector2 = Vector2.ZERO
	for c: Vector2 in island_centers:
		map_center += c
	map_center /= float(island_centers.size())
	_placer.spawn_fish(parent, island_centers, island_radius)
	_placer.spawn_resource_islets(parent, island_centers[0],
		island_centers[island_centers.size() - 1], island_radius)

	return tc_positions

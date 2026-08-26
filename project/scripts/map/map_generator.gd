class_name MapGenerator

## Generates a symmetric random map and paints procedural terrain zones.
## Placement order: background → terrain zones → TCs → units → animals → resources.

const MAX_PLACE_TRIES: int = 30

# --- Radii used when registering objects ---
const R_TC: float             = 130.0
const R_UNIT: float           = 22.0
const R_ANIMAL: float         = 28.0
const R_RES_WOOD: float       = 22.0
const R_RES_OTHER: float      = 22.0
# Tighter packing radius for forest zones — trees placed at 26 px minimum spacing
const FOREST_NODE_RADIUS: float = 13.0

# Laurisilva zone forests: tree count per 100 px of zone radius, and per-tree
# wood amount (regular forests carry 180) — the laurel forest yields more.
const LAURISILVA_TREES_PER_100PX: float = 6.0
const LAURISILVA_WOOD_AMOUNT: float = 260.0

const RES_COLORS: Dictionary = {
	ResourceNode.ResourceType.WOOD:       Color(0.10, 0.55, 0.10, 1.0),
	ResourceNode.ResourceType.GOLD:       Color(0.90, 0.75, 0.10, 1.0),
	ResourceNode.ResourceType.STONE:      Color(0.62, 0.60, 0.58, 1.0),
	ResourceNode.ResourceType.FOOD_HUNT:  Color(0.65, 0.28, 0.10, 1.0),
	ResourceNode.ResourceType.FOOD_FISH:  Color(0.18, 0.55, 0.75, 1.0),
	ResourceNode.ResourceType.OLIVINA:    Color(0.20, 0.62, 0.22, 1.0),
}
const RES_LABELS: Dictionary = {
	ResourceNode.ResourceType.WOOD:       "Wood",
	ResourceNode.ResourceType.GOLD:       "Gold",
	ResourceNode.ResourceType.STONE:      "Stone",
	ResourceNode.ResourceType.FOOD_HUNT:  "Food",
	ResourceNode.ResourceType.FOOD_FISH:  "Fish",
	ResourceNode.ResourceType.OLIVINA:    "Olivina",
}

const ANIMAL_SCENE: String   = "res://scenes/units/animal.tscn"
const SHEEP_SCENE:  String   = "res://scenes/units/sheep.tscn"

# --- Terrain visual colours ---
static func _tc(t: TerrainManager.TerrainType) -> Color:
	return TerrainManager.COLORS[t]

# Placement registry — flat arrays for fast iteration
var _placed_pos: PackedVector2Array = PackedVector2Array()
var _placed_rad: PackedFloat32Array = PackedFloat32Array()

# Spatial hash — cell size = max placement radius (R_TC = 130).
# Each cell key = Vector2i(floor(x/CELL), floor(y/CELL)) → Array of indices.
const SPATIAL_CELL: float = 140.0
var _spatial: Dictionary = {}

var _rng: RandomNumberGenerator = null
var _map_half: float = 1800.0
var _res_mult: float = 1.0

# Polygon2D pool reused for terrain patches
var _terrain_root: Node2D = null
# Land polygons for island map (used by TerrainManager)
var _land_polys: Array = []

# Cached resource node script — loaded once per generation
var _res_node_script: Script = null

# Shared shader materials — one instance reused across all base terrain / ocean
# polygons so we never allocate hundreds of ShaderMaterials.
const WATER_SHADER: Shader = preload("res://assets/shaders/water.gdshader")
const TERRAIN_SHADER: Shader = preload("res://assets/shaders/terrain.gdshader")
const LAVA_SHADER: Shader = preload("res://assets/shaders/lava.gdshader")
var _terrain_material: ShaderMaterial = null
var _water_material: ShaderMaterial = null
var _shallow_material: ShaderMaterial = null
var _lava_material: ShaderMaterial = null
# Per-terrain-type base material (grain/variation tuned to the surface).
var _terrain_materials_by_type: Dictionary = {}

# Terrain types whose edges get a soft fade-out halo into neighbouring ground.
# Contrasting, impassable special zones — grass/dune backgrounds are excluded.
const _GRADIENT_TERRAINS: Array = [
	TerrainManager.TerrainType.MALPAIS,
	TerrainManager.TerrainType.CALDERA,
	TerrainManager.TerrainType.RISCO,
	TerrainManager.TerrainType.LAURISILVA,
]

# Grain/variation tuning per terrain type: rougher surfaces get more grain.
# `mottle`/`dirt_amount` drive the shader's tile checker: only the open ground
# types (grass, dune) swap cells toward the dry-dirt tint.
const _TERRAIN_SHADER_PARAMS: Dictionary = {
	TerrainManager.TerrainType.GRASS:      {"variation": 0.16, "grain": 0.06, "detail_scale": 0.022, "mottle": 0.16, "dirt_amount": 0.10},
	TerrainManager.TerrainType.DUNE:       {"variation": 0.10, "grain": 0.04, "detail_scale": 0.018, "mottle": 0.10, "dirt_amount": 0.06, "dirt_tint": Color(0.62, 0.52, 0.30)},
	TerrainManager.TerrainType.MALPAIS:    {"variation": 0.22, "grain": 0.10, "detail_scale": 0.030, "mottle": 0.12, "dirt_amount": 0.0},
	TerrainManager.TerrainType.RISCO:      {"variation": 0.20, "grain": 0.09, "detail_scale": 0.028, "mottle": 0.12, "dirt_amount": 0.0},
	TerrainManager.TerrainType.LAURISILVA: {"variation": 0.18, "grain": 0.05, "detail_scale": 0.024, "mottle": 0.10, "dirt_amount": 0.0},
	TerrainManager.TerrainType.CALDERA:    {"variation": 0.24, "grain": 0.08, "detail_scale": 0.032, "mottle": 0.14, "dirt_amount": 0.0},
}

# World-space edge of the terrain shader's tile checker (`tile_size`). The
# tile-dithered stains and zone borders snap to the same grid so decals and
# shader mottling read as one tileset.
const STAIN_TILE: float = 26.0

func _get_terrain_material() -> ShaderMaterial:
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = TERRAIN_SHADER
	return _terrain_material

# Returns a shared terrain material tuned for `terrain`, or the default grass-tuned
# one when the type has no specific entry.
func _get_terrain_material_for(terrain: int) -> ShaderMaterial:
	if not _TERRAIN_SHADER_PARAMS.has(terrain):
		return _get_terrain_material()
	if _terrain_materials_by_type.has(terrain):
		return _terrain_materials_by_type[terrain] as ShaderMaterial
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	var params: Dictionary = _TERRAIN_SHADER_PARAMS[terrain] as Dictionary
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	_terrain_materials_by_type[terrain] = mat
	return mat

func _get_water_material() -> ShaderMaterial:
	if _water_material == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = WATER_SHADER
	return _water_material

# Brighter, choppier water tuning for the coastal shelf: shoals read turquoise
# with more visible foam than the open deep-blue ocean.
func _get_shallow_material() -> ShaderMaterial:
	if _shallow_material == null:
		_shallow_material = ShaderMaterial.new()
		_shallow_material.shader = WATER_SHADER
		_shallow_material.set_shader_parameter("water_deep", Color(0.10, 0.36, 0.55))
		_shallow_material.set_shader_parameter("water_shallow", Color(0.30, 0.64, 0.72))
		_shallow_material.set_shader_parameter("foam_amount", 0.30)
		_shallow_material.set_shader_parameter("wave_scale", 0.016)
		_shallow_material.set_shader_parameter("wave_speed", 0.75)
	return _shallow_material

func _get_lava_material() -> ShaderMaterial:
	if _lava_material == null:
		_lava_material = ShaderMaterial.new()
		_lava_material.shader = LAVA_SHADER
	return _lava_material

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
	_res_node_script = load("res://scripts/economy/resource_node.gd") as Script

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
			tc_positions = _place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_register(tc, R_TC)
				_register_unit_cluster(tc)
			# No terrain zones — scatter grass variants over the flat base
			_paint_rect_bg(parent, _map_half, _tc(TerrainManager.TerrainType.GRASS))
			_paint_ground_scatter(parent, _map_half, TerrainManager.TerrainType.GRASS)
			_spawn_animals_multi(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_spawn_neutral_resources(parent)
			_spawn_scattered_resources(parent, tc_positions)
		MatchConfig.MapType.VOLCANIC_COAST:
			tc_positions = _place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_register(tc, R_TC)
				_register_unit_cluster(tc)
			_paint_volcanic_coast(parent)
			_spawn_animals_multi(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_spawn_neutral_resources(parent)
			_spawn_scattered_resources(parent, tc_positions)
		MatchConfig.MapType.DESERT_COAST:
			tc_positions = _place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_register(tc, R_TC)
				_register_unit_cluster(tc)
			_paint_desert_coast(parent)
			_spawn_animals_multi(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_spawn_neutral_resources(parent)
			_spawn_scattered_resources(parent, tc_positions)
		_: # STANDARD
			tc_positions = _place_tc_ring(player_count)
			for tc: Vector2 in tc_positions:
				_register(tc, R_TC)
				_register_unit_cluster(tc)
			_paint_standard(parent)
			_spawn_animals_multi(units_layer, tc_positions)
			for i: int in range(tc_positions.size()):
				_spawn_player_resources(parent, tc_positions[i],
					TAU * float(i) / float(tc_positions.size()))
			_spawn_neutral_resources(parent)
			_spawn_scattered_resources(parent, tc_positions)

	_spawn_laurisilva_forests(parent)
	_add_nav_obstacles(parent)
	TerrainManager.bake_minimap_texture(_map_half, 256)
	return {"tc_positions": tc_positions}

# Laurisilva is the wood-rich biome (GDD M6): fill each laurel-forest zone
# with a tight, high-yield tree cluster so controlling it is an economic
# decision. Runs after zone painting and regular resource spawning so the
# occupancy grid already contains everything else.
func _spawn_laurisilva_forests(parent: Node2D) -> void:
	for z: Dictionary in TerrainManager.get_zones():
		if (z["type"] as TerrainManager.TerrainType) != TerrainManager.TerrainType.LAURISILVA:
			continue
		var radius: float = z["radius"] as float
		var count: int = maxi(3, roundi(radius / 100.0 * LAURISILVA_TREES_PER_100PX * _res_mult))
		_spawn_forest_zone(parent, z["center"] as Vector2, count,
			LAURISILVA_WOOD_AMOUNT * _res_mult, radius * 0.75, true)

# Distribute N TCs evenly around a ring, with small random jitter per position.
# For 2 players this reproduces the classic face-to-face layout.
func _place_tc_ring(count: int) -> Array[Vector2]:
	var ring_dist: float = _map_half * 0.48
	# For 2 players start angle is random; for 3+ also random so no axis alignment
	var base_angle: float = _rng.randf() * TAU
	var result: Array[Vector2] = []
	for i: int in range(count):
		var angle: float = base_angle + TAU * float(i) / float(count)
		var jitter: Vector2 = Vector2(
			_rng.randf_range(-_map_half * 0.07, _map_half * 0.07),
			_rng.randf_range(-_map_half * 0.07, _map_half * 0.07))
		var pos: Vector2 = _clamp_map(
			Vector2(cos(angle), sin(angle)) * ring_dist + jitter)
		result.append(pos)
	return result

# ── Islands map ─────────────────────────────────────────────────────────────

func _run_islands(parent: Node2D, units_layer: Node2D,
		player_count: int) -> Array[Vector2]:
	_paint_ocean_bg(parent, _map_half * 1.05)

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
		var poly: PackedVector2Array = _make_island_poly(center, island_radius)
		_land_polys.append(poly)
		TerrainManager.set_land_polys(_land_polys, true)
		_paint_shore(parent, poly, center)
		_paint_polygon(parent, poly, _tc(TerrainManager.TerrainType.GRASS))
		_scatter_island_terrain(center, island_radius)

	_flush_terrain_zones_visual(parent)

	# TC per island
	var tc_positions: Array[Vector2] = []
	for center: Vector2 in island_centers:
		var tc: Vector2 = center + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60))
		_register(tc, R_TC)
		_register_unit_cluster(tc)
		tc_positions.append(tc)

	# Resources per island
	for i: int in range(player_count):
		_spawn_island_resources(parent, tc_positions[i], island_centers[i], island_radius)

	# Animals, fish, islets
	_spawn_animals_multi(units_layer, tc_positions)
	var map_center: Vector2 = Vector2.ZERO
	for c: Vector2 in island_centers:
		map_center += c
	map_center /= float(island_centers.size())
	_spawn_fish_multi(parent, island_centers, island_radius)
	_spawn_resource_islets(parent, island_centers[0],
		island_centers[island_centers.size() - 1], island_radius)

	return tc_positions

# Builds a blob outline. A smooth low-frequency base (sum of sine harmonics with
# random phases) gives soft lobes, and a small per-vertex `jitter` adds irregular
# bite on top — a middle ground between a perfectly round blob and the old spiky
# per-vertex random radius. `roughness` scales the smooth lobe depth; `jitter`
# scales the fine random wobble; `steps` controls vertex density.
func _smooth_blob(center: Vector2, radius: float, steps: int = 40,
		roughness: float = 0.16, jitter: float = 0.06) -> PackedVector2Array:
	# Three harmonics: a few big lobes + gentle medium + faint fine detail.
	var freq_a: int = _rng.randi_range(2, 3)
	var freq_b: int = _rng.randi_range(4, 5)
	var freq_c: int = _rng.randi_range(6, 8)
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	var phase_c: float = _rng.randf() * TAU
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps):
		var a: float = TAU * float(i) / float(steps)
		var wave: float = sin(a * float(freq_a) + phase_a) * 0.60 \
				+ sin(a * float(freq_b) + phase_b) * 0.28 \
				+ sin(a * float(freq_c) + phase_c) * 0.12
		var r: float = radius * (1.0 + wave * roughness + _rng.randf_range(-jitter, jitter))
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

# Build a bumpy circle polygon for an island
func _make_island_poly(center: Vector2, radius: float) -> PackedVector2Array:
	return _smooth_blob(center, radius, 52, 0.17, 0.045)

func _scatter_island_terrain(center: Vector2, island_radius: float) -> void:
	var inner: float = island_radius * 0.70
	# 1–2 laurisilva patches
	for _i: int in range(_rng.randi_range(1, 2)):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, inner * 0.6)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var r: float = _rng.randf_range(island_radius * 0.12, island_radius * 0.22)
		TerrainManager.add_zone(pos, r, TerrainManager.TerrainType.LAURISILVA)
	# 1 malpaís or risco on edge
	for _i: int in range(1):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(inner * 0.5, inner)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var r: float = _rng.randf_range(island_radius * 0.08, island_radius * 0.15)
		var t: TerrainManager.TerrainType = TerrainManager.TerrainType.MALPAIS \
			if _rng.randf() > 0.5 else TerrainManager.TerrainType.RISCO
		TerrainManager.add_zone(pos, r, t)

func _spawn_island_resources(parent: Node2D, tc: Vector2,
		island_center: Vector2, island_radius: float) -> void:
	var angle_offset: float = (island_center - tc).angle()
	_spawn_player_resources_clamped(parent, tc, angle_offset, island_center, island_radius * 0.85)

# ── Standard terrain painting ────────────────────────────────────────────────

func _paint_standard(parent: Node2D) -> void:
	var h: float = _map_half
	_paint_rect_bg(parent, h, _tc(TerrainManager.TerrainType.GRASS))
	_paint_ground_scatter(parent, h, TerrainManager.TerrainType.GRASS)
	var configs: Array = [
		[3, h * 0.06, h * 0.14, TerrainManager.TerrainType.LAURISILVA],
		[2, h * 0.08, h * 0.18, TerrainManager.TerrainType.MALPAIS],
		[2, h * 0.07, h * 0.15, TerrainManager.TerrainType.DUNE],
		[4, h * 0.03, h * 0.07, TerrainManager.TerrainType.RISCO],
	]
	for cfg: Array in configs:
		for _i: int in range(cfg[0] as int):
			var pos: Vector2 = Vector2(
				_rng.randf_range(-h * 0.80, h * 0.80),
				_rng.randf_range(-h * 0.80, h * 0.80))
			var r: float = _rng.randf_range(cfg[1] as float, cfg[2] as float)
			TerrainManager.add_zone(pos, r, cfg[3] as TerrainManager.TerrainType)
	_flush_terrain_zones_visual(parent)

func _paint_volcanic_coast(parent: Node2D) -> void:
	var h: float = _map_half
	_paint_coastal_ocean(parent, h, _tc(TerrainManager.TerrainType.GRASS))
	_paint_rect_bg(parent, h, _tc(TerrainManager.TerrainType.GRASS))
	_paint_ground_scatter(parent, h, TerrainManager.TerrainType.GRASS)
	# Large central caldera + malpaís bands radiating from it
	var caldera_pos: Vector2 = Vector2(_rng.randf_range(-h * 0.1, h * 0.1),
		_rng.randf_range(-h * 0.1, h * 0.1))
	TerrainManager.add_zone(caldera_pos, h * 0.16, TerrainManager.TerrainType.CALDERA)
	# 3–4 malpaís rings around caldera
	for i: int in range(4):
		var a: float = TAU * i / 4.0 + _rng.randf_range(-0.3, 0.3)
		var d: float = _rng.randf_range(h * 0.18, h * 0.35)
		var pos: Vector2 = caldera_pos + Vector2(cos(a), sin(a)) * d
		TerrainManager.add_zone(pos, _rng.randf_range(h * 0.06, h * 0.12),
			TerrainManager.TerrainType.MALPAIS)
	# Risco edges
	for _i: int in range(4):
		var pos: Vector2 = Vector2(_rng.randf_range(-h * 0.7, h * 0.7),
			_rng.randf_range(-h * 0.7, h * 0.7))
		TerrainManager.add_zone(pos, _rng.randf_range(h * 0.03, h * 0.07),
			TerrainManager.TerrainType.RISCO)
	# Some laurisilva on northern half
	for _i: int in range(2):
		var pos: Vector2 = Vector2(_rng.randf_range(-h * 0.6, h * 0.6),
			_rng.randf_range(-h * 0.6, -h * 0.1))
		TerrainManager.add_zone(pos, _rng.randf_range(h * 0.08, h * 0.15),
			TerrainManager.TerrainType.LAURISILVA)
	_flush_terrain_zones_visual(parent)

func _paint_desert_coast(parent: Node2D) -> void:
	var h: float = _map_half
	_paint_coastal_ocean(parent, h, _tc(TerrainManager.TerrainType.DUNE))
	_paint_rect_bg(parent, h, _tc(TerrainManager.TerrainType.DUNE),
		TerrainManager.TerrainType.DUNE)
	_paint_ground_scatter(parent, h, TerrainManager.TerrainType.DUNE)
	# Register full map as dune zone so TerrainManager knows
	TerrainManager.add_zone(Vector2.ZERO, h * 1.5, TerrainManager.TerrainType.DUNE)
	# Add small grass oases near TCs (registered last = highest priority)
	for side: int in [-1, 1]:
		var oasis: Vector2 = Vector2(side * h * 0.35, _rng.randf_range(-h * 0.2, h * 0.2))
		TerrainManager.add_zone(oasis, h * 0.18, TerrainManager.TerrainType.GRASS)
		_paint_circle_patch(parent, oasis, h * 0.18,
			_tc(TerrainManager.TerrainType.GRASS), _rng.randi() % 3)
	# Risco ridge on east edge
	for _i: int in range(3):
		var rpos: Vector2 = Vector2(_rng.randf_range(h * 0.55, h * 0.75),
			_rng.randf_range(-h * 0.5, h * 0.5))
		var rr: float = _rng.randf_range(h * 0.04, h * 0.09)
		TerrainManager.add_zone(rpos, rr, TerrainManager.TerrainType.RISCO)
		_paint_risco(parent, rpos, rr, _rng.randi() % 3)

# ── Terrain visual helpers ───────────────────────────────────────────────────

# Paints all registered terrain zones with type-specific visuals.
func _flush_terrain_zones_visual(parent: Node2D) -> void:
	var zones: Array = TerrainManager._zones
	for z: Dictionary in zones:
		var t: TerrainManager.TerrainType = z["type"] as TerrainManager.TerrainType
		var center: Vector2 = z["center"] as Vector2
		var radius: float   = z["radius"] as float
		var variant: int = _rng.randi() % 3
		match t:
			TerrainManager.TerrainType.LAURISILVA:
				_paint_laurisilva(parent, center, radius, variant)
			TerrainManager.TerrainType.RISCO:
				_paint_risco(parent, center, radius, variant)
			TerrainManager.TerrainType.MALPAIS:
				_paint_malpais(parent, center, radius, variant)
			TerrainManager.TerrainType.CALDERA:
				_paint_caldera(parent, center, radius, variant)
			_:
				_paint_circle_patch(parent, center, radius, _tc(t), variant)

# ── Per-terrain painters ──────────────────────────────────────────────────────

func _paint_laurisilva(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	# Base: dark green blob
	_paint_circle_patch(parent, center, radius, _tc(TerrainManager.TerrainType.LAURISILVA), variant, TerrainManager.TerrainType.LAURISILVA)
	# Batch all canopies into a single Polygon2D per colour group to minimise
	# scene-tree nodes. We use 3 colour groups; each gets one Polygon2D with
	# all canopy outlines appended as a single closed polygon (separated by a
	# degenerate edge back to the first point, which is invisible at this scale).
	const CSTEPS: int = 6   # hexagonal canopy — fewer vertices, still round
	const GROUPS: int = 3
	var group_pts: Array = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var group_colors: Array[Color] = [
		Color(0.06, 0.44, 0.08),
		Color(0.10, 0.52, 0.10),
		Color(0.14, 0.38, 0.08),
	]

	var tree_count: int = _rng.randi_range(10, 16)
	for _i: int in range(tree_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.90)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var tr_r: float = _rng.randf_range(radius * 0.05, radius * 0.10)
		var group: int = _rng.randi() % GROUPS
		var pts: PackedVector2Array = group_pts[group] as PackedVector2Array
		# Append canopy polygon; if not empty, add a degenerate bridge back
		if pts.size() > 0:
			pts.append(pts[0])   # close previous sub-polygon
		var start_pt: Vector2 = pos + Vector2(tr_r, 0.0)
		for ci: int in range(CSTEPS):
			var ca: float = TAU * float(ci) / float(CSTEPS)
			var cr: float = tr_r * _rng.randf_range(0.80, 1.20)
			pts.append(pos + Vector2(cos(ca), sin(ca)) * cr)
		pts.append(start_pt)   # close this sub-polygon

	for g: int in range(GROUPS):
		var pts: PackedVector2Array = group_pts[g] as PackedVector2Array
		if pts.size() < 3:
			continue
		var canopy: Polygon2D = Polygon2D.new()
		canopy.color = group_colors[g]
		canopy.z_index = -6
		canopy.polygon = pts
		parent.add_child(canopy)
	_paint_terrain_variant(parent, center, radius, TerrainManager.TerrainType.LAURISILVA, variant)

func _paint_risco(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	_paint_circle_patch(parent, center, radius, _tc(TerrainManager.TerrainType.RISCO), variant, TerrainManager.TerrainType.RISCO)

	# Scattered ground pebbles across the rock zone base for texture
	var pebble_count: int = _rng.randi_range(14, 22)
	for _pi: int in range(pebble_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.90)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var pr: float = _rng.randf_range(radius * 0.018, radius * 0.045)
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.38, 0.35, 0.31, 0.85)
		ppoly.z_index = -7
		var ppts: PackedVector2Array = PackedVector2Array()
		const PBSTEPS: int = 6
		for psi: int in range(PBSTEPS):
			var psa: float = TAU * psi / PBSTEPS + _rng.randf_range(-0.3, 0.3)
			ppts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.6, 1.2))
		ppoly.polygon = ppts
		parent.add_child(ppoly)
	_paint_terrain_variant(parent, center, radius, TerrainManager.TerrainType.RISCO, variant)

	# Peaks — upright rock outcrops. The silhouette is authored in screen space
	# and mounted on an IsoBillboard-uprighted child so the camera projection
	# doesn't shear it into a smeared grey parallelogram; only the cast shadow
	# stays ground-flat (projected). Each peak anchor sits in the entity depth
	# band so units in front of / behind the crag occlude correctly.
	var peak_count: int = _rng.randi_range(3, 6)
	for _pi: int in range(peak_count):
		# Spread peaks across most of the zone so the base is well covered
		var spread: float = _rng.randf_range(0.0, radius * 0.60)
		var dir_angle: float = _rng.randf() * TAU
		var peak_center: Vector2 = center + Vector2(cos(dir_angle), sin(dir_angle)) * spread

		var ph: float = _rng.randf_range(radius * 0.45, radius * 0.85)
		var pw: float = _rng.randf_range(radius * 0.70, radius * 1.1)
		var tilt: float = _rng.randf_range(-0.18, 0.18)

		# Cast shadow: flat ellipse pooled at the peak base, offset toward the
		# shadow side (left, since the sunlit face is the right flank). Stays in
		# world space so it hugs the ground plane under projection.
		var shadow_cast: Polygon2D = Polygon2D.new()
		shadow_cast.color = Color(0.10, 0.09, 0.08, 0.30)
		shadow_cast.z_index = -8
		var sh_rx: float = pw * 0.55
		var sh_ry: float = pw * 0.30
		var sh_center: Vector2 = peak_center + Vector2(-pw * 0.20, pw * 0.05)
		var sh_pts: PackedVector2Array = PackedVector2Array()
		for ssi: int in range(14):
			var ssa: float = TAU * float(ssi) / 14.0
			sh_pts.append(sh_center + Vector2(cos(ssa) * sh_rx, sin(ssa) * sh_ry))
		shadow_cast.polygon = sh_pts
		parent.add_child(shadow_cast)

		var anchor: Node2D = Node2D.new()
		anchor.position = peak_center
		anchor.z_index = IsoBillboard.depth_z(peak_center)
		parent.add_child(anchor)
		var body: Node2D = Node2D.new()
		anchor.add_child(body)
		IsoBillboard.make_upright(body)

		# Silhouette vertices relative to the base centre, screen space (Y up).
		var tip: Vector2 = Vector2(tilt * pw, -ph)
		var base_l: Vector2 = Vector2(-pw * 0.5 + _rng.randf_range(-pw * 0.08, pw * 0.08), _rng.randf_range(-ph * 0.05, ph * 0.10))
		var base_r: Vector2 = Vector2( pw * 0.5 + _rng.randf_range(-pw * 0.08, pw * 0.08), _rng.randf_range(-ph * 0.05, ph * 0.10))
		# Extra mid-flank jagged vertices for more craggy silhouette
		var jag_l: Vector2 = Vector2(-pw * 0.30 + _rng.randf_range(-pw * 0.08, pw * 0.06), -ph * _rng.randf_range(0.38, 0.58))
		var jag_r: Vector2 = Vector2( pw * 0.30 + _rng.randf_range(-pw * 0.06, pw * 0.08), -ph * _rng.randf_range(0.35, 0.55))
		var jag2_l: Vector2 = Vector2(-pw * 0.42 + _rng.randf_range(-pw * 0.05, pw * 0.05), -ph * _rng.randf_range(0.15, 0.32))
		var jag2_r: Vector2 = Vector2( pw * 0.42 + _rng.randf_range(-pw * 0.05, pw * 0.05), -ph * _rng.randf_range(0.12, 0.30))

		# Dark rock base — full wide mountain silhouette
		var base_poly: Polygon2D = Polygon2D.new()
		base_poly.color = Color(0.32, 0.29, 0.25)
		base_poly.polygon = PackedVector2Array([base_l, jag2_l, jag_l, tip, jag_r, jag2_r, base_r])
		body.add_child(base_poly)

		# Mid-slope face — right half lighter (sunlit side)
		var face: Polygon2D = Polygon2D.new()
		face.color = Color(0.54, 0.50, 0.45)
		var mid_base: Vector2 = (tip + base_r) * 0.5 + Vector2(0.0, ph * 0.08)
		face.polygon = PackedVector2Array([tip, jag_r, jag2_r, base_r, mid_base])
		body.add_child(face)

		# Shadow side — left darker area
		var shadow: Polygon2D = Polygon2D.new()
		shadow.color = Color(0.18, 0.16, 0.14, 0.75)
		var mid_left: Vector2 = base_l + (tip - base_l) * 0.38
		shadow.polygon = PackedVector2Array([base_l, jag2_l, jag_l, mid_left])
		body.add_child(shadow)

		# Snow cap — only the taller crags carry one
		if ph > radius * 0.62:
			var snow_h: float = ph * _rng.randf_range(0.20, 0.32)
			var snow_w: float = pw * _rng.randf_range(0.18, 0.28)
			var snow: Polygon2D = Polygon2D.new()
			snow.color = Color(0.90, 0.89, 0.87, 0.92)
			snow.polygon = PackedVector2Array([
				tip,
				tip + Vector2(-snow_w * 0.6, snow_h * 0.4) + Vector2(_rng.randf_range(-2.0, 2.0), 0.0),
				tip + Vector2(-snow_w, snow_h),
				tip + Vector2( snow_w, snow_h),
				tip + Vector2( snow_w * 0.6, snow_h * 0.4) + Vector2(_rng.randf_range(-2.0, 2.0), 0.0),
			])
			body.add_child(snow)

func _paint_malpais(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	_paint_circle_patch(parent, center, radius, _tc(TerrainManager.TerrainType.MALPAIS), variant, TerrainManager.TerrainType.MALPAIS)

	# Dark lava rock fragments scattered across the zone
	var all_pts: PackedVector2Array = PackedVector2Array()
	var frag_count: int = _rng.randi_range(10, 18)
	for _i: int in range(frag_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.88)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var fr: float = _rng.randf_range(radius * 0.04, radius * 0.10)
		var fsides: int = _rng.randi_range(4, 6)
		if all_pts.size() > 0:
			all_pts.append(all_pts[0])
		for fi: int in range(fsides):
			var fa: float = TAU * fi / fsides + _rng.randf_range(-0.2, 0.2)
			all_pts.append(pos + Vector2(cos(fa), sin(fa)) * fr * _rng.randf_range(0.5, 1.0))

	if all_pts.size() >= 3:
		var frag: Polygon2D = Polygon2D.new()
		frag.color = Color(0.24, 0.21, 0.20)
		frag.z_index = -7
		frag.polygon = all_pts
		parent.add_child(frag)

	# Glowing crack lines — thin orange-red veins suggesting cooling lava
	var crack_count: int = _rng.randi_range(3, 6)
	for _ci: int in range(crack_count):
		var start_a: float = _rng.randf() * TAU
		var start_d: float = _rng.randf_range(0.0, radius * 0.55)
		var crack_start: Vector2 = center + Vector2(cos(start_a), sin(start_a)) * start_d
		var crack_line: Line2D = Line2D.new()
		crack_line.default_color = Color(0.72, 0.22, 0.05, 0.65)
		crack_line.width = _rng.randf_range(1.0, 2.0)
		crack_line.z_index = -6
		crack_line.material = _get_lava_material()
		crack_line.add_point(crack_start)
		var seg_len: float = _rng.randf_range(radius * 0.15, radius * 0.35)
		var dir_a: float = _rng.randf() * TAU
		var segs: int = _rng.randi_range(3, 5)
		var cur: Vector2 = crack_start
		for _si: int in range(segs):
			dir_a += _rng.randf_range(-0.6, 0.6)
			cur += Vector2(cos(dir_a), sin(dir_a)) * (seg_len / segs)
			crack_line.add_point(cur)
		parent.add_child(crack_line)
	_paint_terrain_variant(parent, center, radius, TerrainManager.TerrainType.MALPAIS, variant)

func _paint_caldera(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	_paint_circle_patch(parent, center, radius, _tc(TerrainManager.TerrainType.CALDERA), 0, TerrainManager.TerrainType.CALDERA)
	_paint_circle_patch(parent, center, radius * 0.55, Color(0.06, 0.04, 0.04))

	var crack_count: int = _rng.randi_range(3, 5)
	# Collect glow dot positions to place at crack tips and branch junctions
	var glow_positions: PackedVector2Array = PackedVector2Array()

	for ci: int in range(crack_count):
		var ca: float = TAU * ci / crack_count + _rng.randf_range(-0.2, 0.2)
		var segments: int = _rng.randi_range(3, 5)

		# Build main crack point list
		var main_pts: PackedVector2Array = PackedVector2Array()
		main_pts.append(center)
		var cp: Vector2 = center
		for _si: int in range(segments):
			cp += Vector2(cos(ca), sin(ca)) * _rng.randf_range(radius * 0.10, radius * 0.20)
			cp += Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
			main_pts.append(cp)
		glow_positions.append(cp)   # tip

		# Draw main crack: dark wide underlay then bright narrow overlay
		var crack_dark: Line2D = Line2D.new()
		crack_dark.default_color = Color(0.15, 0.05, 0.02, 0.9)
		crack_dark.width = _rng.randf_range(3.5, 5.0)
		crack_dark.z_index = -6
		for pt: Vector2 in main_pts:
			crack_dark.add_point(pt)
		parent.add_child(crack_dark)

		var crack_bright: Line2D = Line2D.new()
		crack_bright.default_color = Color(1.0, 0.45, 0.05, 0.85)
		crack_bright.width = _rng.randf_range(1.5, 3.0)
		crack_bright.z_index = -6
		crack_bright.material = _get_lava_material()
		for pt: Vector2 in main_pts:
			crack_bright.add_point(pt)
		parent.add_child(crack_bright)

		# 1–2 branches from random points along the main crack
		var branch_count: int = _rng.randi_range(1, 2)
		for _bi: int in range(branch_count):
			if main_pts.size() < 2:
				break
			var branch_start_idx: int = _rng.randi_range(0, main_pts.size() - 2)
			var branch_start: Vector2 = main_pts[branch_start_idx]
			var branch_angle: float = ca + _rng.randf_range(PI * 0.25, PI * 0.65) * (1.0 if _rng.randf() > 0.5 else -1.0)
			var branch_segs: int = _rng.randi_range(2, 3)
			var bp: Vector2 = branch_start
			var branch_pts: PackedVector2Array = PackedVector2Array()
			branch_pts.append(bp)
			for _bs: int in range(branch_segs):
				bp += Vector2(cos(branch_angle), sin(branch_angle)) * _rng.randf_range(radius * 0.06, radius * 0.14)
				bp += Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
				branch_pts.append(bp)
			glow_positions.append(bp)   # branch tip
			glow_positions.append(branch_start)   # junction

			var bdark: Line2D = Line2D.new()
			bdark.default_color = Color(0.15, 0.05, 0.02, 0.9)
			bdark.width = _rng.randf_range(2.5, 3.5)
			bdark.z_index = -6
			for pt: Vector2 in branch_pts:
				bdark.add_point(pt)
			parent.add_child(bdark)

			var bbright: Line2D = Line2D.new()
			bbright.default_color = Color(1.0, 0.45, 0.05, 0.85)
			bbright.width = _rng.randf_range(1.0, 2.0)
			bbright.z_index = -6
			bbright.material = _get_lava_material()
			for pt: Vector2 in branch_pts:
				bbright.add_point(pt)
			parent.add_child(bbright)

	# Glowing dots at crack tips and junctions — batch all into one Polygon2D per group
	# to minimise scene-tree nodes: pick up to 6 positions, draw circles individually
	var dot_limit: int = mini(glow_positions.size(), 6)
	# Shuffle by picking random indices without replacement via rng
	var available_indices: Array[int] = []
	for di: int in range(glow_positions.size()):
		available_indices.append(di)
	var dot_pts: PackedVector2Array = PackedVector2Array()
	for _d: int in range(dot_limit):
		if available_indices.is_empty():
			break
		var pick: int = _rng.randi() % available_indices.size()
		var chosen_idx: int = available_indices[pick]
		available_indices.remove_at(pick)
		var dpos: Vector2 = glow_positions[chosen_idx]
		var dot_r: float = _rng.randf_range(3.0, 6.0)
		const DOT_STEPS: int = 8
		if dot_pts.size() > 0:
			dot_pts.append(dot_pts[0])
		for di2: int in range(DOT_STEPS):
			var da: float = TAU * di2 / DOT_STEPS
			dot_pts.append(dpos + Vector2(cos(da), sin(da)) * dot_r)

	if dot_pts.size() >= 3:
		var dot_poly: Polygon2D = Polygon2D.new()
		dot_poly.color = Color(1.0, 0.6, 0.1, 0.7)
		dot_poly.z_index = -5
		dot_poly.material = _get_lava_material()
		dot_poly.polygon = dot_pts
		parent.add_child(dot_poly)
	_paint_terrain_variant(parent, center, radius, TerrainManager.TerrainType.CALDERA, variant)

func _paint_circle_patch(parent: Node2D, center: Vector2,
		radius: float, col: Color, variant: int = 0, terrain: int = -1) -> void:
	# Main feathered-edge blob — 32 vertices with larger noise-driven jitter so
	# zone boundaries bleed organically into adjacent terrain instead of
	# cutting as hard circles.
	# A terrain-tuned grain/variation shader runs on the base blobs so the zone
	# floor isn't a flat colour beneath its detail decals.
	var base_mat: ShaderMaterial = _get_terrain_material_for(terrain) if terrain >= 0 else null

	# Smooth, rounded base outline (low-frequency harmonics instead of per-vertex
	# jitter so the edge undulates in soft lobes rather than spikes).
	var pts: PackedVector2Array = _smooth_blob(center, radius, 40, 0.15)

	# Soft edge: blend the zone colour into the surrounding terrain so the
	# boundary isn't a hard cut. Follows the base outline exactly (scaled bands)
	# so the blend hugs the real silhouette instead of a circle. Drawn first
	# (below the opaque base blob) so only the outer fringe shows. Only
	# contrasting special zones get this — grass/dune patches don't need it.
	if terrain in _GRADIENT_TERRAINS:
		_paint_edge_gradient(parent, pts, center, col)

	var pts_clipped: PackedVector2Array = _clip_poly_to_map(pts)
	if pts_clipped.size() >= 3:
		var poly: Polygon2D = Polygon2D.new()
		poly.color = col
		poly.z_index = -8
		poly.material = base_mat
		poly.polygon = pts_clipped
		parent.add_child(poly)

	# Fringe blobs — small rounded overlap patches around the perimeter that
	# break the edge and fray softly into adjacent terrain.
	var fringe_count: int = _rng.randi_range(8, 12)
	for _fi: int in range(fringe_count):
		var fa: float = _rng.randf() * TAU
		var fd: float = radius * _rng.randf_range(0.75, 1.0)
		var fr: float = radius * _rng.randf_range(0.15, 0.30)
		var fpos: Vector2 = center + Vector2(cos(fa), sin(fa)) * fd
		var fpts: PackedVector2Array = _smooth_blob(fpos, fr, 16, 0.18)
		var fpts_clipped: PackedVector2Array = _clip_poly_to_map(fpts)
		if fpts_clipped.size() < 3:
			continue
		var fpoly: Polygon2D = Polygon2D.new()
		fpoly.color = col
		fpoly.z_index = -8
		fpoly.material = base_mat
		fpoly.polygon = fpts_clipped
		parent.add_child(fpoly)

	# Terrain-specific surface detail variants — only for grass/dune callers that
	# rely on colour inference. The special painters (malpaís, risco, laurisilva,
	# caldera) invoke _paint_terrain_variant themselves, so the explicit `terrain`
	# arg here drives ONLY the base material, never the variant (avoids painting
	# the detail decals twice).
	var t_int: int = -1
	if col.r > 0.70 and col.g > 0.60 and col.b < 0.55:
		t_int = TerrainManager.TerrainType.DUNE
	elif col.r < 0.30 and col.g > 0.38 and col.b < 0.25:
		t_int = TerrainManager.TerrainType.GRASS
	if t_int >= 0:
		_paint_terrain_variant(parent, center, radius, t_int, variant)

# Appends one STAIN_TILE-grid square to a batched multi-square polygon,
# bridging back through the first point (same degenerate-edge batching used by
# the laurisilva canopies) so hundreds of squares cost one Polygon2D.
func _append_tile_square(pts: PackedVector2Array, origin: Vector2) -> void:
	if pts.size() > 0:
		pts.append(pts[0])
	var t: float = STAIN_TILE
	pts.append(origin)
	pts.append(origin + Vector2(t, 0.0))
	pts.append(origin + Vector2(t, t))
	pts.append(origin + Vector2(0.0, t))
	pts.append(origin)

# Tile-quantised stain: squares snapped to the shader's tile grid, dense at the
# centre and dithering out toward `radius` — the classic RTS tileset dirt patch
# instead of an amorphous soft-alpha blob. Appends into `pts` for batching.
func _append_tile_stain(pts: PackedVector2Array, center: Vector2,
		radius: float, coverage: float) -> void:
	var t: float = STAIN_TILE
	var x: float = floor((center.x - radius) / t) * t
	while x < center.x + radius:
		var y: float = floor((center.y - radius) / t) * t
		while y < center.y + radius:
			var d: float = (Vector2(x, y) + Vector2(t, t) * 0.5).distance_to(center) / maxf(radius, 1.0)
			if d < 1.0 and _rng.randf() < coverage * (1.0 - d * d):
				_append_tile_square(pts, Vector2(x, y))
			y += t
		x += t

# Dithers a zone's edge into the surrounding terrain: tile-grid squares of the
# zone colour scattered just outside the outline, thinning outward — the hard,
# dithered tileset transition of classic isometric RTS maps instead of the old
# soft alpha halo (which read as a stain around every zone).
func _paint_edge_gradient(parent: Node2D, outline: PackedVector2Array,
		center: Vector2, col: Color, _rings: int = 3, _spread: float = 0.14, z: int = -8) -> void:
	if outline.size() < 3:
		return
	var t: float = STAIN_TILE
	var limit: float = _map_half - t
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = outline.size()
	for i: int in range(n):
		# Sample each outline vertex and the segment midpoint so big zones have
		# no dither gaps between vertices.
		for sample: Vector2 in [outline[i], (outline[i] + outline[(i + 1) % n]) * 0.5]:
			var dir: Vector2 = (sample - center).normalized()
			for ring: int in range(3):
				var prob: float = 0.85 / float(ring + 1) - 0.15
				if _rng.randf() >= prob:
					continue
				var pos: Vector2 = sample + dir * t * (float(ring) * 0.9 + 0.25)
				var origin: Vector2 = (pos / t).floor() * t
				if absf(origin.x) > limit or absf(origin.y) > limit:
					continue
				_append_tile_square(pts, origin)
	if pts.size() < 3:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.color = Color(col.r, col.g, col.b, minf(col.a, 0.92))
	poly.z_index = z
	poly.polygon = pts
	parent.add_child(poly)

# Covers the whole map base with overlapping scatter patches so the flat
# background shows terrain variants instead of a single solid colour.
# Patches are large (15–25 % of map_half radius) and laid on a loose grid
# with random offset so every area gets coverage.
func _paint_ground_scatter(parent: Node2D, map_half: float,
		terrain: TerrainManager.TerrainType) -> void:
	var patch_r: float = map_half * 0.22
	var step: float = map_half * 0.30
	# Keep centers inset by patch_r so no polygon vertex escapes the map bounds.
	var inner: float = map_half - patch_r
	var x: float = -map_half
	while x <= map_half:
		var y: float = -map_half
		while y <= map_half:
			var jx: float = _rng.randf_range(-step * 0.45, step * 0.45)
			var jy: float = _rng.randf_range(-step * 0.45, step * 0.45)
			var center: Vector2 = Vector2(x + jx, y + jy).clamp(
				Vector2(-inner, -inner), Vector2(inner, inner))
			var v: int = _rng.randi() % 3
			_paint_terrain_variant(parent, center, patch_r, terrain, v)
			y += step
		x += step

func _paint_terrain_variant(parent: Node2D, center: Vector2,
		radius: float, terrain: int, variant: int) -> void:
	match terrain:
		TerrainManager.TerrainType.GRASS:
			match variant:
				0: _paint_grass_v0(parent, center, radius)
				1: _paint_grass_v1(parent, center, radius)
				_: _paint_grass_v2(parent, center, radius)
		TerrainManager.TerrainType.DUNE:
			match variant:
				0: _paint_dune_v0(parent, center, radius)
				1: _paint_dune_v1(parent, center, radius)
				_: _paint_dune_v2(parent, center, radius)
		TerrainManager.TerrainType.MALPAIS:
			match variant:
				0: _paint_malpais_detail_v0(parent, center, radius)
				1: _paint_malpais_detail_v1(parent, center, radius)
				_: _paint_malpais_detail_v2(parent, center, radius)
		TerrainManager.TerrainType.RISCO:
			match variant:
				0: _paint_risco_detail_v0(parent, center, radius)
				1: _paint_risco_detail_v1(parent, center, radius)
				_: _paint_risco_detail_v2(parent, center, radius)
		TerrainManager.TerrainType.LAURISILVA:
			match variant:
				0: _paint_laurisilva_detail_v0(parent, center, radius)
				1: _paint_laurisilva_detail_v1(parent, center, radius)
				_: _paint_laurisilva_detail_v2(parent, center, radius)
		TerrainManager.TerrainType.CALDERA:
			match variant:
				0: _paint_caldera_detail_v0(parent, center, radius)
				1: _paint_caldera_detail_v1(parent, center, radius)
				_: _paint_caldera_detail_v2(parent, center, radius)

# Adds one batched multi-square stain polygon (no-op for empty batches).
func _add_stain_poly(parent: Node2D, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -7
	poly.polygon = pts
	parent.add_child(poly)

# Grass v0: tile-dithered dark/light clumps + blade strokes. The clumps used to
# be soft-alpha blobs that read as amorphous stains; snapping them to the
# shader's tile grid makes mid-zoom ground read like a tileset.
func _paint_grass_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var blob_count: int = _rng.randi_range(6, 10)
	var light_pts: PackedVector2Array = PackedVector2Array()
	var dark_pts: PackedVector2Array = PackedVector2Array()
	for _gi: int in range(blob_count):
		var ga: float = _rng.randf() * TAU
		var gd: float = _rng.randf_range(0.0, radius * 0.82)
		var gr: float = radius * _rng.randf_range(0.07, 0.16)
		var gpos: Vector2 = center + Vector2(cos(ga), sin(ga)) * gd
		var target: PackedVector2Array = light_pts if _rng.randi() % 3 == 0 else dark_pts
		_append_tile_stain(target, gpos, maxf(gr, STAIN_TILE), 0.85)
	_add_stain_poly(parent, light_pts, Color(0.28, 0.52, 0.18, 0.45))
	_add_stain_poly(parent, dark_pts, Color(0.16, 0.36, 0.12, 0.55))
	var blade_count: int = _rng.randi_range(12, 20)
	for _bi: int in range(blade_count):
		var ba: float = _rng.randf() * TAU
		var bd: float = _rng.randf_range(0.0, radius * 0.75)
		var bpos: Vector2 = center + Vector2(cos(ba), sin(ba)) * bd
		var blade: Line2D = Line2D.new()
		blade.default_color = Color(0.20, 0.50, 0.14, 0.35)
		blade.width = 1.2
		blade.z_index = -7
		var blade_len: float = _rng.randf_range(radius * 0.025, radius * 0.055)
		var blade_angle: float = _rng.randf_range(-PI * 0.3, PI * 0.3) - PI * 0.5
		blade.add_point(bpos)
		blade.add_point(bpos + Vector2(cos(blade_angle), sin(blade_angle)) * blade_len)
		parent.add_child(blade)

# Grass v1: scattered wildflower dots (tiny coloured circles — white, yellow, violet)
func _paint_grass_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var base_count: int = _rng.randi_range(4, 7)
	var base_pts: PackedVector2Array = PackedVector2Array()
	for _gi: int in range(base_count):
		var ga: float = _rng.randf() * TAU
		var gd: float = _rng.randf_range(0.0, radius * 0.85)
		var gr: float = radius * _rng.randf_range(0.08, 0.18)
		var gpos: Vector2 = center + Vector2(cos(ga), sin(ga)) * gd
		_append_tile_stain(base_pts, gpos, maxf(gr, STAIN_TILE), 0.8)
	_add_stain_poly(parent, base_pts, Color(0.14, 0.34, 0.10, 0.50))
	var flower_colors: Array = [
		Color(0.95, 0.95, 0.90, 0.85),
		Color(0.95, 0.85, 0.15, 0.80),
		Color(0.70, 0.40, 0.80, 0.75),
		Color(0.95, 0.45, 0.45, 0.75),
	]
	var flower_count: int = _rng.randi_range(10, 18)
	var all_fpts: PackedVector2Array = PackedVector2Array()
	var cur_col_idx: int = 0
	for _fi: int in range(flower_count):
		var fa: float = _rng.randf() * TAU
		var fd: float = _rng.randf_range(0.0, radius * 0.85)
		var fpos: Vector2 = center + Vector2(cos(fa), sin(fa)) * fd
		var fr: float = _rng.randf_range(radius * 0.012, radius * 0.028)
		if all_fpts.size() > 0:
			all_fpts.append(all_fpts[0])
		for fsi: int in range(6):
			var fsa: float = TAU * fsi / 6.0
			all_fpts.append(fpos + Vector2(cos(fsa), sin(fsa)) * fr)
		cur_col_idx = (cur_col_idx + 1) % flower_colors.size()
	if all_fpts.size() >= 3:
		var fpoly: Polygon2D = Polygon2D.new()
		fpoly.color = flower_colors[_rng.randi() % flower_colors.size()]
		fpoly.z_index = -7
		fpoly.polygon = all_fpts
		parent.add_child(fpoly)

# Grass v2: dry/golden-tint patches — late-summer burnt look, tile-dithered so
# the dry ground reads as tileset patches instead of muddy olive stains.
func _paint_grass_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var patch_count: int = _rng.randi_range(5, 9)
	var gold_pts: PackedVector2Array = PackedVector2Array()
	var olive_pts: PackedVector2Array = PackedVector2Array()
	for _pi: int in range(patch_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.80)
		var pr: float = radius * _rng.randf_range(0.09, 0.20)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var target: PackedVector2Array = gold_pts if _rng.randi() % 2 == 0 else olive_pts
		_append_tile_stain(target, ppos, maxf(pr, STAIN_TILE), 0.8)
	_add_stain_poly(parent, gold_pts, Color(0.52, 0.48, 0.18, 0.45))
	_add_stain_poly(parent, olive_pts, Color(0.42, 0.38, 0.14, 0.40))
	var blade_count: int = _rng.randi_range(10, 16)
	for _bi: int in range(blade_count):
		var ba: float = _rng.randf() * TAU
		var bd: float = _rng.randf_range(0.0, radius * 0.75)
		var bpos: Vector2 = center + Vector2(cos(ba), sin(ba)) * bd
		var blade: Line2D = Line2D.new()
		blade.default_color = Color(0.55, 0.50, 0.20, 0.38)
		blade.width = 1.2
		blade.z_index = -7
		var blade_len: float = _rng.randf_range(radius * 0.030, radius * 0.060)
		var blade_angle: float = _rng.randf_range(-PI * 0.25, PI * 0.25) - PI * 0.5
		blade.add_point(bpos)
		blade.add_point(bpos + Vector2(cos(blade_angle), sin(blade_angle)) * blade_len)
		parent.add_child(blade)

# Dune v0: sine ripple lines + grain dots (current style)
func _paint_dune_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var ripple_count: int = _rng.randi_range(5, 8)
	for ri: int in range(ripple_count):
		var ry: float = center.y - radius * 0.8 + (radius * 1.6 / float(ripple_count)) * float(ri) \
				+ _rng.randf_range(-radius * 0.06, radius * 0.06)
		var line: Line2D = Line2D.new()
		line.default_color = Color(0.68, 0.58, 0.33, 0.28)
		line.width = _rng.randf_range(1.5, 3.0)
		line.z_index = -7
		var seg_count: int = _rng.randi_range(7, 10)
		for si: int in range(seg_count):
			var sx: float = center.x - radius * 0.9 + (radius * 1.8 / float(seg_count - 1)) * float(si)
			var sy: float = ry + sin(float(si) * 1.4) * 3.5 + _rng.randf_range(-2.5, 2.5)
			line.add_point(Vector2(sx, sy))
		parent.add_child(line)
	var grain_count: int = _rng.randi_range(20, 35)
	var grain_pts: PackedVector2Array = PackedVector2Array()
	for _gri: int in range(grain_count):
		var gra: float = _rng.randf() * TAU
		var grd: float = _rng.randf_range(0.0, radius * 0.88)
		var grpos: Vector2 = center + Vector2(cos(gra), sin(gra)) * grd
		var grr: float = _rng.randf_range(radius * 0.008, radius * 0.022)
		if grain_pts.size() > 0:
			grain_pts.append(grain_pts[0])
		for gsi: int in range(5):
			var gsa: float = TAU * gsi / 5.0
			grain_pts.append(grpos + Vector2(cos(gsa), sin(gsa)) * grr)
	if grain_pts.size() >= 3:
		var grain_poly: Polygon2D = Polygon2D.new()
		grain_poly.color = Color(0.88, 0.80, 0.55, 0.55)
		grain_poly.z_index = -7
		grain_poly.polygon = grain_pts
		parent.add_child(grain_poly)

# Dune v1: crescent dunes — curved arc shapes suggesting wind-blown sand mounds
func _paint_dune_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var dune_count: int = _rng.randi_range(3, 5)
	for _di: int in range(dune_count):
		var da: float = _rng.randf() * TAU
		var dd: float = _rng.randf_range(0.0, radius * 0.70)
		var dpos: Vector2 = center + Vector2(cos(da), sin(da)) * dd
		var dw: float = _rng.randf_range(radius * 0.25, radius * 0.45)
		var dh: float = dw * _rng.randf_range(0.18, 0.32)
		var dpts: PackedVector2Array = PackedVector2Array()
		var arc_steps: int = 10
		for i: int in range(arc_steps + 1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 2.0
			var ay: float = dpos.y - sin(t * PI) * dh
			dpts.append(Vector2(ax, ay))
		for i: int in range(arc_steps, -1, -1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 2.0
			var ay: float = dpos.y - sin(t * PI) * dh * 0.4
			dpts.append(Vector2(ax, ay))
		var dpoly: Polygon2D = Polygon2D.new()
		dpoly.color = Color(0.82, 0.72, 0.44, 0.45)
		dpoly.z_index = -7
		dpoly.polygon = dpts
		parent.add_child(dpoly)
		var shadow_pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(arc_steps + 1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 1.8
			var ay: float = dpos.y - sin(t * PI) * dh * 0.4
			shadow_pts.append(Vector2(ax, ay))
		for i: int in range(arc_steps, -1, -1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 1.8
			var ay: float = dpos.y - sin(t * PI) * dh * 0.05 + dh * 0.35
			shadow_pts.append(Vector2(ax, ay))
		var spoly: Polygon2D = Polygon2D.new()
		spoly.color = Color(0.60, 0.50, 0.28, 0.35)
		spoly.z_index = -7
		spoly.polygon = shadow_pts
		parent.add_child(spoly)

# Dune v2: rocky desert floor — small flat pebbles and gravel patches on sand
func _paint_dune_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var streak_count: int = _rng.randi_range(4, 7)
	for _si: int in range(streak_count):
		var sa: float = _rng.randf_range(-0.3, 0.3)
		var sd: float = _rng.randf_range(0.0, radius * 0.80)
		var spos: Vector2 = center + Vector2(cos(sa + PI * 0.5), sin(sa + PI * 0.5)) * sd
		var streak: Line2D = Line2D.new()
		streak.default_color = Color(0.72, 0.62, 0.38, 0.22)
		streak.width = _rng.randf_range(2.0, 4.5)
		streak.z_index = -7
		var slen: float = _rng.randf_range(radius * 0.20, radius * 0.55)
		streak.add_point(spos + Vector2(-slen, 0.0))
		streak.add_point(spos + Vector2( slen, _rng.randf_range(-4.0, 4.0)))
		parent.add_child(streak)
	var pebble_count: int = _rng.randi_range(8, 14)
	var pebble_pts: PackedVector2Array = PackedVector2Array()
	for _pi: int in range(pebble_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.82)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var pr: float = _rng.randf_range(radius * 0.015, radius * 0.040)
		if pebble_pts.size() > 0:
			pebble_pts.append(pebble_pts[0])
		for psi: int in range(6):
			var psa: float = TAU * psi / 6.0
			pebble_pts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.6, 1.3))
	if pebble_pts.size() >= 3:
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.58, 0.50, 0.32, 0.60)
		ppoly.z_index = -7
		ppoly.polygon = pebble_pts
		parent.add_child(ppoly)

# Malpais v0: cooled lava surface — flat dark polygonal plates
func _paint_malpais_detail_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var plate_count: int = _rng.randi_range(4, 7)
	for _pi: int in range(plate_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.80)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var pr: float = _rng.randf_range(radius * 0.08, radius * 0.18)
		var ppts: PackedVector2Array = PackedVector2Array()
		var sides: int = _rng.randi_range(5, 7)
		for psi: int in range(sides):
			var psa: float = TAU * psi / sides + _rng.randf_range(-0.3, 0.3)
			ppts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.7, 1.2))
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.18, 0.15, 0.13, 0.70)
		ppoly.z_index = -7
		ppoly.polygon = ppts
		parent.add_child(ppoly)

# Malpais v1: obsidian sheen — small bright-edged dark blobs suggesting glassy rock
func _paint_malpais_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var shard_count: int = _rng.randi_range(6, 10)
	for _si: int in range(shard_count):
		var sa: float = _rng.randf() * TAU
		var sd: float = _rng.randf_range(0.0, radius * 0.85)
		var spos: Vector2 = center + Vector2(cos(sa), sin(sa)) * sd
		var sr: float = _rng.randf_range(radius * 0.04, radius * 0.10)
		var spts: PackedVector2Array = PackedVector2Array()
		for ssi: int in range(5):
			var ssa: float = TAU * ssi / 5.0 + _rng.randf_range(-0.4, 0.4)
			spts.append(spos + Vector2(cos(ssa), sin(ssa)) * sr * _rng.randf_range(0.5, 1.2))
		var spoly: Polygon2D = Polygon2D.new()
		spoly.color = Color(0.08, 0.07, 0.08, 0.85)
		spoly.z_index = -7
		spoly.polygon = spts
		parent.add_child(spoly)
		if spts.size() >= 3:
			var shine: Polygon2D = Polygon2D.new()
			shine.color = Color(0.55, 0.55, 0.60, 0.30)
			shine.z_index = -7
			shine.polygon = PackedVector2Array([spts[0], spts[1], spts[2]])
			parent.add_child(shine)

# Malpais v2: ash dusting — light grey powder patches over the dark rock
func _paint_malpais_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var ash_count: int = _rng.randi_range(5, 9)
	for _ai: int in range(ash_count):
		var aa: float = _rng.randf() * TAU
		var ad: float = _rng.randf_range(0.0, radius * 0.85)
		var ar: float = _rng.randf_range(radius * 0.06, radius * 0.16)
		var apos: Vector2 = center + Vector2(cos(aa), sin(aa)) * ad
		var apts: PackedVector2Array = PackedVector2Array()
		for asi: int in range(10):
			var asa: float = TAU * asi / 10.0
			apts.append(apos + Vector2(cos(asa), sin(asa)) * ar * _rng.randf_range(0.70, 1.25))
		var apoly: Polygon2D = Polygon2D.new()
		apoly.color = Color(0.40, 0.38, 0.36, 0.30)
		apoly.z_index = -7
		apoly.polygon = apts
		parent.add_child(apoly)

# Risco v0: current style (pebbles already drawn in _paint_risco); no-op variant
func _paint_risco_detail_v0(_parent: Node2D, _center: Vector2, _radius: float) -> void:
	pass

# Risco v1: scree field — dense small angular rubble scattered across the base
func _paint_risco_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var scree_count: int = _rng.randi_range(18, 28)
	var all_pts: PackedVector2Array = PackedVector2Array()
	for _si: int in range(scree_count):
		var sa: float = _rng.randf() * TAU
		var sd: float = _rng.randf_range(0.0, radius * 0.92)
		var spos: Vector2 = center + Vector2(cos(sa), sin(sa)) * sd
		var sr: float = _rng.randf_range(radius * 0.015, radius * 0.038)
		if all_pts.size() > 0:
			all_pts.append(all_pts[0])
		for ssi: int in range(4):
			var ssa: float = TAU * ssi / 4.0 + _rng.randf_range(-0.5, 0.5)
			all_pts.append(spos + Vector2(cos(ssa), sin(ssa)) * sr * _rng.randf_range(0.5, 1.4))
	if all_pts.size() >= 3:
		var spoly: Polygon2D = Polygon2D.new()
		spoly.color = Color(0.32, 0.29, 0.26, 0.75)
		spoly.z_index = -7
		spoly.polygon = all_pts
		parent.add_child(spoly)

# Risco v2: mossy rock — pale green lichen patches on the stone surface
func _paint_risco_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var lichen_count: int = _rng.randi_range(6, 10)
	for _li: int in range(lichen_count):
		var la: float = _rng.randf() * TAU
		var ld: float = _rng.randf_range(0.0, radius * 0.85)
		var lr: float = _rng.randf_range(radius * 0.05, radius * 0.14)
		var lpos: Vector2 = center + Vector2(cos(la), sin(la)) * ld
		var lpts: PackedVector2Array = PackedVector2Array()
		for lsi: int in range(9):
			var lsa: float = TAU * lsi / 9.0
			lpts.append(lpos + Vector2(cos(lsa), sin(lsa)) * lr * _rng.randf_range(0.65, 1.30))
		var lpoly: Polygon2D = Polygon2D.new()
		lpoly.color = Color(0.30, 0.42, 0.18, 0.45)
		lpoly.z_index = -7
		lpoly.polygon = lpts
		parent.add_child(lpoly)

# Laurisilva v0: dark undergrowth blobs (dense shadow floor)
func _paint_laurisilva_detail_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var blob_count: int = _rng.randi_range(5, 8)
	for _bi: int in range(blob_count):
		var ba: float = _rng.randf() * TAU
		var bd: float = _rng.randf_range(0.0, radius * 0.75)
		var br: float = _rng.randf_range(radius * 0.08, radius * 0.18)
		var bpos: Vector2 = center + Vector2(cos(ba), sin(ba)) * bd
		var bpts: PackedVector2Array = PackedVector2Array()
		for bsi: int in range(8):
			var bsa: float = TAU * bsi / 8.0
			bpts.append(bpos + Vector2(cos(bsa), sin(bsa)) * br * _rng.randf_range(0.70, 1.25))
		var bpoly: Polygon2D = Polygon2D.new()
		bpoly.color = Color(0.04, 0.18, 0.05, 0.55)
		bpoly.z_index = -7
		bpoly.polygon = bpts
		parent.add_child(bpoly)

# Laurisilva v1: fern fronds — thin radiating lines from scattered points
func _paint_laurisilva_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var fern_count: int = _rng.randi_range(6, 10)
	for _fi: int in range(fern_count):
		var fa: float = _rng.randf() * TAU
		var fd: float = _rng.randf_range(0.0, radius * 0.80)
		var fpos: Vector2 = center + Vector2(cos(fa), sin(fa)) * fd
		var frond_count: int = _rng.randi_range(5, 8)
		var flen: float = _rng.randf_range(radius * 0.06, radius * 0.14)
		for fri: int in range(frond_count):
			var fra: float = TAU * fri / frond_count
			var fline: Line2D = Line2D.new()
			fline.default_color = Color(0.10, 0.38, 0.10, 0.50)
			fline.width = 1.0
			fline.z_index = -7
			fline.add_point(fpos)
			fline.add_point(fpos + Vector2(cos(fra), sin(fra)) * flen)
			parent.add_child(fline)

# Laurisilva v2: moss patches + fallen log hint
func _paint_laurisilva_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var moss_count: int = _rng.randi_range(4, 7)
	for _mi: int in range(moss_count):
		var ma: float = _rng.randf() * TAU
		var md: float = _rng.randf_range(0.0, radius * 0.78)
		var mr: float = _rng.randf_range(radius * 0.07, radius * 0.16)
		var mpos: Vector2 = center + Vector2(cos(ma), sin(ma)) * md
		var mpts: PackedVector2Array = PackedVector2Array()
		for msi: int in range(9):
			var msa: float = TAU * msi / 9.0
			mpts.append(mpos + Vector2(cos(msa), sin(msa)) * mr * _rng.randf_range(0.65, 1.30))
		var mpoly: Polygon2D = Polygon2D.new()
		mpoly.color = Color(0.18, 0.48, 0.14, 0.45)
		mpoly.z_index = -7
		mpoly.polygon = mpts
		parent.add_child(mpoly)
	var log_angle: float = _rng.randf() * PI
	var log_len: float = _rng.randf_range(radius * 0.20, radius * 0.40)
	var log_w: float = _rng.randf_range(radius * 0.025, radius * 0.055)
	var log_center: Vector2 = center + Vector2(
		_rng.randf_range(-radius * 0.45, radius * 0.45),
		_rng.randf_range(-radius * 0.45, radius * 0.45))
	var perp: Vector2 = Vector2(-sin(log_angle), cos(log_angle)) * log_w
	var fwd: Vector2  = Vector2( cos(log_angle), sin(log_angle)) * log_len
	var log_poly: Polygon2D = Polygon2D.new()
	log_poly.color = Color(0.22, 0.14, 0.07, 0.65)
	log_poly.z_index = -7
	log_poly.polygon = PackedVector2Array([
		log_center - fwd + perp,
		log_center + fwd + perp,
		log_center + fwd - perp,
		log_center - fwd - perp,
	])
	parent.add_child(log_poly)

# Caldera v0: extra central lava pool
func _paint_caldera_detail_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var pool_pts: PackedVector2Array = PackedVector2Array()
	var pool_r: float = radius * _rng.randf_range(0.10, 0.18)
	for i: int in range(12):
		var a: float = TAU * i / 12.0
		pool_pts.append(center + Vector2(cos(a), sin(a)) * pool_r * _rng.randf_range(0.80, 1.20))
	var pool: Polygon2D = Polygon2D.new()
	pool.color = Color(1.0, 0.35, 0.02, 0.75)
	pool.z_index = -5
	pool.material = _get_lava_material()
	pool.polygon = pool_pts
	parent.add_child(pool)

# Caldera v1: solidified lava ripple rings — concentric faint circles
func _paint_caldera_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var ring_count: int = _rng.randi_range(3, 5)
	for ri: int in range(ring_count):
		var rr: float = radius * (0.15 + float(ri) * 0.15) * _rng.randf_range(0.88, 1.12)
		var ring_line: Line2D = Line2D.new()
		ring_line.default_color = Color(0.55, 0.18, 0.04, 0.35)
		ring_line.width = _rng.randf_range(1.5, 3.0)
		ring_line.z_index = -6
		var ring_segs: int = 24
		for rsi: int in range(ring_segs + 1):
			var ra: float = TAU * rsi / ring_segs
			ring_line.add_point(center + Vector2(cos(ra), sin(ra)) * rr * _rng.randf_range(0.92, 1.08))
		parent.add_child(ring_line)

# Caldera v2: sulphur deposits — pale yellow-green patches near the rim
func _paint_caldera_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var patch_count: int = _rng.randi_range(4, 7)
	for _pi: int in range(patch_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(radius * 0.30, radius * 0.80)
		var pr: float = _rng.randf_range(radius * 0.06, radius * 0.14)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var ppts: PackedVector2Array = PackedVector2Array()
		for psi: int in range(8):
			var psa: float = TAU * psi / 8.0
			ppts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.65, 1.35))
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.62, 0.58, 0.10, 0.45)
		ppoly.z_index = -6
		ppoly.polygon = ppts
		parent.add_child(ppoly)

func _paint_rect_bg(parent: Node2D, half: float, col: Color,
		terrain: int = TerrainManager.TerrainType.GRASS) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -9
	poly.material = _get_terrain_material_for(terrain)
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	parent.add_child(poly)

func _paint_ocean_bg(parent: Node2D, half: float) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = Color(1, 1, 1, 1)   # tinted by shader
	poly.z_index = -9
	poly.material = _get_water_material()
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	parent.add_child(poly)

# Surrounds a coast-type map with animated ocean. The water sheet sits behind
# the opaque land background (z -10), so it only shows in the outer ring beyond
# the playable rectangle — the continent reads as sea-girt without any walkable
# water inside the play area. The land-water transition is built from irregular
# multi-harmonic outlines (never a ruler-straight frame): sand beach, a thin
# surf-foam rim, then an animated turquoise shallow-water shelf fading into the
# deep ocean.
func _paint_coastal_ocean(parent: Node2D, half: float, land_col: Color) -> void:
	var ocean_half: float = half * 1.35
	var water: Polygon2D = Polygon2D.new()
	water.color = Color(1, 1, 1, 1)   # tinted by shader
	water.z_index = -10
	water.material = _get_water_material()
	water.polygon = PackedVector2Array([
		Vector2(-ocean_half, -ocean_half), Vector2(ocean_half, -ocean_half),
		Vector2(ocean_half, ocean_half),   Vector2(-ocean_half, ocean_half),
	])
	parent.add_child(water)

	# Shallow-water shelf: brighter animated water hugging the coast so the map
	# border reads as shoals. Translucent so the deep ocean tints it and the
	# outer boundary blends instead of stepping.
	var shallow: Polygon2D = Polygon2D.new()
	shallow.color = Color(1, 1, 1, 0.85)
	shallow.z_index = -10
	shallow.material = _get_shallow_material()
	shallow.polygon = _wavy_rect_outline(half * 1.055, half * 0.10)
	parent.add_child(shallow)

	# Surf-foam rim: pale sliver between the beach and the shallows. Its outline
	# wanders independently of the sand's, so the rim breathes from nothing to a
	# wide wash along the coast.
	var foam: Polygon2D = Polygon2D.new()
	foam.color = SHORE_FOAM
	foam.z_index = -9
	foam.polygon = _wavy_rect_outline(half * 1.030, half * 0.045)
	parent.add_child(foam)

	# Sand beach: opaque band from the land edge out into the surf.
	var sand: Polygon2D = Polygon2D.new()
	sand.color = SHORE_SAND
	sand.z_index = -9
	sand.material = _get_terrain_material()
	sand.polygon = _wavy_rect_outline(half * 1.005, half * 0.050)
	parent.add_child(sand)

	# Irregular shoreline fringe: a band of land-coloured blobs hugging the inner
	# edge of the border so the coast bleeds organically into the sea.
	var step: float = half * 0.12
	var t: float = -half
	while t <= half:
		for side: int in range(4):
			var base: Vector2
			match side:
				0: base = Vector2(t, -half)   # top
				1: base = Vector2(t,  half)   # bottom
				2: base = Vector2(-half, t)   # left
				_: base = Vector2( half, t)   # right
			var inward: Vector2 = base.normalized() * -1.0 * _rng.randf_range(0.0, half * 0.04)
			var blob_pos: Vector2 = base + inward
			var br: float = _rng.randf_range(half * 0.04, half * 0.085)
			var bpts: PackedVector2Array = _smooth_blob(blob_pos, br, 14, 0.20)
			var bpoly: Polygon2D = Polygon2D.new()
			bpoly.color = land_col
			bpoly.z_index = -9
			bpoly.material = _get_terrain_material()
			bpoly.polygon = bpts
			parent.add_child(bpoly)
		t += step

# Returns pts intersected with the map rectangle — i.e. clipped to map bounds.
func _clip_poly_to_map(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var mh: float = _map_half
	var map_rect: PackedVector2Array = PackedVector2Array([
		Vector2(-mh, -mh), Vector2(mh, -mh),
		Vector2(mh,  mh),  Vector2(-mh, mh),
	])
	var result: Array[PackedVector2Array] = Geometry2D.intersect_polygons(pts, map_rect)
	if result.is_empty():
		return PackedVector2Array()
	return result[0]

func _paint_polygon(parent: Node2D, pts: PackedVector2Array, col: Color) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -8
	poly.material = _get_terrain_material_for(TerrainManager.TerrainType.GRASS)
	poly.polygon = pts
	parent.add_child(poly)

# Paints a beach + foam ring around a land outline so land meets water through a
# soft sand band instead of a hard green/blue cut. The land polygon is drawn on
# top afterwards (z -8), covering the inner part of these rings; only the outer
# sand and foam show beyond the shoreline.
const SHORE_SAND: Color = Color(0.80, 0.72, 0.48, 1.0)
const SHORE_FOAM: Color = Color(0.82, 0.90, 0.94, 0.45)

func _paint_shore(parent: Node2D, land_pts: PackedVector2Array, center: Vector2) -> void:
	if land_pts.size() < 3:
		return
	# Outside-in: an animated turquoise shallow-water shelf (widest, translucent
	# so the deep ocean blends through), a pale surf-foam rim, then the opaque
	# sand beach hugging the land edge. All three widths breathe independently
	# around the coastline (variation arg) so the shore is broad in places and
	# thin in others, like a real coast.
	_paint_shore_ring(parent, land_pts, center, 1.17, 0.055, Color(1, 1, 1, 0.85), -9,
		_get_shallow_material())
	_paint_shore_ring(parent, land_pts, center, 1.085, 0.030, SHORE_FOAM, -9)
	_paint_shore_ring(parent, land_pts, center, 1.06, 0.035, SHORE_SAND, -9)

# Draws one ring by scaling the land outline outward from `center`. The scale
# isn't constant: it wanders by `variation` via low-frequency harmonics around
# the perimeter, so the band's width varies along the coast instead of being a
# uniform offset. Follows the (already smooth) land outline so no new spikes.
func _paint_shore_ring(parent: Node2D, land_pts: PackedVector2Array,
		center: Vector2, base_scale: float, variation: float, col: Color, z: int,
		mat: ShaderMaterial = null) -> void:
	var n: int = land_pts.size()
	var freq_a: int = _rng.randi_range(2, 3)
	var freq_b: int = _rng.randi_range(4, 6)
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		var w: float = sin(a * float(freq_a) + phase_a) * 0.65 \
				+ sin(a * float(freq_b) + phase_b) * 0.35
		var scale: float = base_scale + w * variation
		var out: Vector2 = (land_pts[i] - center) * scale
		pts.append(center + out)
	var clipped: PackedVector2Array = _clip_poly_to_map(pts)
	if clipped.size() < 3:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = z
	if mat != null:
		poly.material = mat
	elif col.a >= 0.99:
		poly.material = _get_terrain_material()
	poly.polygon = clipped
	parent.add_child(poly)

# Closed outline of a square of half-extent `base_half` whose border bulges
# outward by up to `amp`, driven by two sine harmonics plus a slow width
# envelope. Enough low- and mid-frequency movement that the coast undulates in
# capes and coves instead of reading as a straight frame. The bulge is always
# >= 0 so the outline never dents inside the base square.
func _wavy_rect_outline(base_half: float, amp: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	const PER_SIDE: int = 36
	var corners: Array = [
		[Vector2(-base_half, -base_half), Vector2( base_half, -base_half)],
		[Vector2( base_half, -base_half), Vector2( base_half,  base_half)],
		[Vector2( base_half,  base_half), Vector2(-base_half,  base_half)],
		[Vector2(-base_half,  base_half), Vector2(-base_half, -base_half)],
	]
	# Random phases/frequencies per call so no two bands are identical.
	var freq_a: float = float(_rng.randi_range(4, 6))
	var freq_b: float = float(_rng.randi_range(9, 14))
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	# A slow wave modulates the bulge amplitude so the band's width varies
	# along the coast (broad here, thin there) rather than a uniform roll.
	var amp_freq: float = float(_rng.randi_range(2, 3))
	var amp_phase: float = _rng.randf() * TAU
	var total: int = PER_SIDE * corners.size()
	var idx: float = 0.0
	for edge: Array in corners:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		for s: int in range(PER_SIDE):
			var f: float = float(s) / float(PER_SIDE)
			var p: Vector2 = a.lerp(b, f)
			var perim: float = idx / float(total)   # 0..1 around the whole frame
			# Width envelope wanders between ~30% and 100% of amp.
			var env: float = 0.30 + (sin(perim * TAU * amp_freq + amp_phase) * 0.5 + 0.5) * 0.70
			var wave: float = sin(perim * TAU * freq_a + phase_a) * 0.62 \
					+ sin(perim * TAU * freq_b + phase_b) * 0.38
			var bulge: float = (wave * 0.5 + 0.5) * amp * env
			var n: Vector2 = p.normalized()
			pts.append(p + n * bulge)
			idx += 1.0
	return pts

# ── Registry helpers ─────────────────────────────────────────────────────────

func _register(pos: Vector2, radius: float) -> void:
	var idx: int = _placed_pos.size()
	_placed_pos.append(pos)
	_placed_rad.append(radius)
	# Insert into every spatial cell the object's bounding box overlaps.
	var half_r: float = radius
	var x0: int = floori((pos.x - half_r) / SPATIAL_CELL)
	var x1: int = floori((pos.x + half_r) / SPATIAL_CELL)
	var y0: int = floori((pos.y - half_r) / SPATIAL_CELL)
	var y1: int = floori((pos.y + half_r) / SPATIAL_CELL)
	for cx: int in range(x0, x1 + 1):
		for cy: int in range(y0, y1 + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _spatial.has(key):
				_spatial[key] = []
			(_spatial[key] as Array).append(idx)

func _is_free(pos: Vector2, radius: float) -> bool:
	var cx: int = floori(pos.x / SPATIAL_CELL)
	var cy: int = floori(pos.y / SPATIAL_CELL)
	# Check the 3×3 neighbourhood of cells around the query point.
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			var key: Vector2i = Vector2i(cx + dx, cy + dy)
			if not _spatial.has(key):
				continue
			for idx: int in (_spatial[key] as Array):
				var min_dist: float = radius + _placed_rad[idx]
				if pos.distance_squared_to(_placed_pos[idx]) < min_dist * min_dist:
					return false
	return true

func _find_free_arc(center: Vector2, dist_min: float, dist_max: float,
		obj_radius: float, angle_hint: float = -1.0) -> Vector2:
	for _i: int in range(MAX_PLACE_TRIES):
		var angle: float = _rng.randf() * TAU if angle_hint < 0.0 \
				else angle_hint + _rng.randf_range(-0.8, 0.8)
		var dist: float = _rng.randf_range(dist_min, dist_max)
		var pos: Vector2 = _clamp_map(center + Vector2(cos(angle), sin(angle)) * dist)
		if _is_free(pos, obj_radius):
			return pos
	return Vector2.INF

func _find_free_near(center: Vector2, zone_radius: float,
		obj_radius: float) -> Vector2:
	for _i: int in range(MAX_PLACE_TRIES):
		var angle: float = _rng.randf() * TAU
		var dist: float  = _rng.randf_range(0.0, zone_radius) * _rng.randf_range(0.4, 1.0)
		var pos: Vector2 = _clamp_map(center + Vector2(cos(angle), sin(angle)) * dist)
		if _is_free(pos, obj_radius):
			return pos
	return Vector2.INF

# For island maps: find a free position constrained to a circle around island_center.
func _find_free_on_island(island_center: Vector2, island_radius: float,
		obj_radius: float) -> Vector2:
	for _i: int in range(MAX_PLACE_TRIES * 3):
		var angle: float = _rng.randf() * TAU
		var dist: float  = _rng.randf_range(0.0, island_radius * 0.80)
		var pos: Vector2 = island_center + Vector2(cos(angle), sin(angle)) * dist
		if not TerrainManager._point_in_any_land(pos):
			continue
		if not TerrainManager.is_buildable(pos):
			continue
		if _is_free(pos, obj_radius):
			return pos
	return Vector2.INF

func _clamp_map(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -_map_half, _map_half), clampf(p.y, -_map_half, _map_half))

# ── TC placement ─────────────────────────────────────────────────────────────

func _random_tc_pos() -> Vector2:
	return Vector2(
		_rng.randf_range(-_map_half * 0.55, -_map_half * 0.25),
		_rng.randf_range(-_map_half * 0.40,  _map_half * 0.40))

func _register_unit_cluster(tc: Vector2) -> void:
	for off: Vector2 in [Vector2(-40, 60), Vector2(0, 60), Vector2(40, 60), Vector2(80, -60)]:
		_register(tc + off, R_UNIT)

# ── Animals ──────────────────────────────────────────────────────────────────

func _spawn_animals_multi(units_layer: Node2D, tc_positions: Array[Vector2]) -> void:
	var deer_scene:  PackedScene = load(ANIMAL_SCENE) as PackedScene
	var sheep_scene: PackedScene = load(SHEEP_SCENE)  as PackedScene

	# 4 sheep near each TC
	for tc: Vector2 in tc_positions:
		var placed: int = 0
		for _attempt: int in range(MAX_PLACE_TRIES * 4):
			if placed >= 4:
				break
			var pos: Vector2 = _find_free_arc(tc, 180.0, 340.0, R_ANIMAL)
			if pos == Vector2.INF:
				break
			if TerrainManager.is_impassable_for(pos, ""):
				continue
			_register(pos, R_ANIMAL)
			_place_animal(sheep_scene, units_layer, pos, true)
			placed += 1

	# Neutral deer away from all TCs
	var placed_deer: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * 8):
		if placed_deer >= 8:
			break
		var pos: Vector2 = Vector2(
			_rng.randf_range(-_map_half * 0.85, _map_half * 0.85),
			_rng.randf_range(-_map_half * 0.85, _map_half * 0.85))
		var too_close: bool = false
		for tc: Vector2 in tc_positions:
			if pos.distance_to(tc) < 300.0:
				too_close = true
				break
		if too_close:
			continue
		if TerrainManager.is_impassable_for(pos, ""):
			continue
		if not _is_free(pos, R_ANIMAL):
			continue
		_register(pos, R_ANIMAL)
		_place_animal(deer_scene, units_layer, pos, false)
		placed_deer += 1

func _place_animal(scene: PackedScene, units_layer: Node2D,
		pos: Vector2, is_sheep: bool) -> void:
	var animal: Node2D = scene.instantiate() as Node2D
	units_layer.add_child(animal)
	animal.global_position = pos
	if is_sheep:
		animal.set("max_health", 8.0)
		animal.set("health", 8.0)
	else:
		var hp: float = _rng.randf_range(30.0, 50.0)
		animal.set("max_health", hp)
		animal.set("health", hp)

# ── Resources ─────────────────────────────────────────────────────────────────

func _spawn_player_resources(parent: Node2D, tc: Vector2,
		angle_offset: float) -> void:
	var gold_angle:  float = _rng.randf_range(0.0, TAU)
	var stone_angle: float = gold_angle + _rng.randf_range(PI * 0.55, PI * 0.85)

	_spawn_deposit(parent, tc, ResourceNode.ResourceType.GOLD,
		roundi(4.0 * _res_mult), 160.0 * _res_mult, gold_angle + angle_offset, 320.0, 480.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.GOLD,
		roundi(3.0 * _res_mult), 160.0 * _res_mult, gold_angle + angle_offset + PI * 0.5, 340.0, 500.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(4.0 * _res_mult), 180.0 * _res_mult, stone_angle + angle_offset, 360.0, 530.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(3.0 * _res_mult), 180.0 * _res_mult, stone_angle + angle_offset + PI * 0.5, 380.0, 540.0)

	var forest_base: float = _rng.randf_range(0.0, TAU)
	# Size variants: [tree_min, tree_max, zone_radius]
	# Close forests (< 320 px) are limited to small/medium so they don't crowd the TC.
	const FOREST_SIZES_SMALL:  Array = [[12, 18, 50], [22, 28, 70]]
	const FOREST_SIZES_ALL:    Array = [[12, 18, 50], [22, 30, 75], [35, 45, 105]]
	for i: int in range(8):
		var fangle: float = forest_base + (TAU / 8.0) * float(i) \
				+ _rng.randf_range(-0.3, 0.3) + angle_offset
		var fdist:  float = _rng.randf_range(280.0, 520.0)
		var fcenter: Vector2 = _clamp_map(tc + Vector2(cos(fangle), sin(fangle)) * fdist)
		if not TerrainManager.is_impassable_for(fcenter, ""):
			var pool: Array = FOREST_SIZES_SMALL if fdist < 360.0 else FOREST_SIZES_ALL
			var sz: Array = pool[_rng.randi() % pool.size()] as Array
			_spawn_forest_zone(parent, fcenter,
				roundi(_rng.randf_range(float(sz[0]), float(sz[1])) * _res_mult),
				200.0 * _res_mult, float(sz[2]), true)

	var food_angle: float = _rng.randf_range(0.0, TAU) + angle_offset
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_BERRY,
		roundi(6.0 * _res_mult), 110.0 * _res_mult, food_angle,            160.0, 280.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_BERRY,
		roundi(3.0 * _res_mult), 110.0 * _res_mult, food_angle + PI * 0.6, 180.0, 300.0)

# Island-constrained version: resources must land within the island poly
func _spawn_player_resources_clamped(parent: Node2D, tc: Vector2,
		angle_offset: float, island_center: Vector2, island_radius: float) -> void:
	# Reduce distances so deposits fit within island bounds
	var max_dist: float = island_radius * 0.65

	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.GOLD,
		roundi(5.0 * _res_mult), 140.0 * _res_mult,
		_rng.randf_range(0.0, TAU) + angle_offset, 160.0, max_dist, island_center, island_radius)
	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(5.0 * _res_mult), 160.0 * _res_mult,
		_rng.randf_range(0.0, TAU) + angle_offset, 160.0, max_dist, island_center, island_radius)

	var forest_count: int = _rng.randi_range(6, 8)
	for i: int in range(forest_count):
		var fangle: float = angle_offset + TAU / float(forest_count) * float(i) + _rng.randf_range(-0.4, 0.4)
		var fcenter: Vector2 = island_center + \
			Vector2(cos(fangle), sin(fangle)) * _rng.randf_range(island_radius * 0.1, island_radius * 0.55)
		if TerrainManager._point_in_any_land(fcenter) and TerrainManager.is_buildable(fcenter):
			var ifsz: Array = [[12, 18, 50], [22, 30, 75], [35, 45, 105]][_rng.randi() % 3]
			_spawn_forest_zone(parent, fcenter,
				roundi(_rng.randf_range(float(ifsz[0]), float(ifsz[1])) * _res_mult),
				180.0 * _res_mult, float(ifsz[2]), true)

	var food_angle: float = _rng.randf_range(0.0, TAU) + angle_offset
	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.FOOD_BERRY,
		roundi(6.0 * _res_mult), 100.0 * _res_mult,
		food_angle, 120.0, max_dist, island_center, island_radius)

func _spawn_neutral_resources(parent: Node2D) -> void:
	var base_angle: float = _rng.randf_range(0.0, TAU)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		roundi(4.0 * _res_mult), 200.0 * _res_mult, base_angle,            400.0, 700.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		roundi(4.0 * _res_mult), 200.0 * _res_mult, base_angle + PI,       400.0, 700.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		roundi(4.0 * _res_mult), 200.0 * _res_mult, base_angle + PI * 0.5, 450.0, 720.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		roundi(4.0 * _res_mult), 200.0 * _res_mult, base_angle + PI * 1.5, 450.0, 720.0)
	const FOREST_SIZES: Array = [[12, 18, 50], [22, 30, 75], [35, 45, 105]]
	var fangle: float = _rng.randf_range(0.0, TAU)
	var neutral_forest_angles: Array[float] = [
		fangle, fangle + PI * 0.4, fangle + PI * 0.8,
		fangle + PI * 1.2, fangle + PI * 1.6,
		fangle + PI * 0.2, fangle + PI * 1.0,
	]
	for fa: float in neutral_forest_angles:
		var fc: Vector2 = _clamp_map(Vector2(cos(fa), sin(fa)) * _rng.randf_range(250.0, 700.0))
		if not TerrainManager.is_impassable_for(fc, ""):
			var sz: Array = FOREST_SIZES[_rng.randi() % FOREST_SIZES.size()] as Array
			_spawn_forest_zone(parent, fc,
				roundi(_rng.randf_range(float(sz[0]), float(sz[1])) * _res_mult),
				220.0 * _res_mult, float(sz[2]), true)

## Places additional gold, stone and forest deposits randomly across the full map,
## keeping a minimum distance from any TC so they supplement (not replace) per-player
## resources and neutral clusters.
func _spawn_scattered_resources(parent: Node2D, tc_positions: Array[Vector2]) -> void:
	const MIN_FROM_TC: float   = 380.0
	const AREA_FRAC:   float   = 0.85   # stay within 85 % of map half
	const FOREST_SIZES: Array  = [[12, 18, 50], [22, 30, 75], [35, 45, 105]]

	# Attempt to place groups; each group is at a random map position
	# that passes the TC distance filter
	var scatter_gold:   int = roundi(6.0 * _res_mult)
	var scatter_stone:  int = roundi(5.0 * _res_mult)
	var scatter_forest: int = roundi(10.0 * _res_mult)

	# Gold deposits
	var placed_gold: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * scatter_gold * 4):
		if placed_gold >= scatter_gold:
			break
		var pos: Vector2 = Vector2(
			_rng.randf_range(-_map_half * AREA_FRAC, _map_half * AREA_FRAC),
			_rng.randf_range(-_map_half * AREA_FRAC, _map_half * AREA_FRAC))
		if TerrainManager.is_impassable_for(pos, ""):
			continue
		var too_close: bool = false
		for tc: Vector2 in tc_positions:
			if pos.distance_to(tc) < MIN_FROM_TC:
				too_close = true
				break
		if too_close:
			continue
		var count: int = roundi(_rng.randf_range(4.0, 7.0) * _res_mult)
		_spawn_deposit(parent, pos, ResourceNode.ResourceType.GOLD,
			count, 200.0 * _res_mult, _rng.randf() * TAU, 0.0, 60.0)
		placed_gold += 1

	# Stone deposits
	var placed_stone: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * scatter_stone * 4):
		if placed_stone >= scatter_stone:
			break
		var pos: Vector2 = Vector2(
			_rng.randf_range(-_map_half * AREA_FRAC, _map_half * AREA_FRAC),
			_rng.randf_range(-_map_half * AREA_FRAC, _map_half * AREA_FRAC))
		if TerrainManager.is_impassable_for(pos, ""):
			continue
		var too_close: bool = false
		for tc: Vector2 in tc_positions:
			if pos.distance_to(tc) < MIN_FROM_TC:
				too_close = true
				break
		if too_close:
			continue
		var count: int = roundi(_rng.randf_range(4.0, 6.0) * _res_mult)
		_spawn_deposit(parent, pos, ResourceNode.ResourceType.STONE,
			count, 200.0 * _res_mult, _rng.randf() * TAU, 0.0, 60.0)
		placed_stone += 1

	# Scattered forest patches
	var placed_forest: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * scatter_forest * 4):
		if placed_forest >= scatter_forest:
			break
		var pos: Vector2 = Vector2(
			_rng.randf_range(-_map_half * AREA_FRAC, _map_half * AREA_FRAC),
			_rng.randf_range(-_map_half * AREA_FRAC, _map_half * AREA_FRAC))
		if TerrainManager.is_impassable_for(pos, ""):
			continue
		var too_close: bool = false
		for tc: Vector2 in tc_positions:
			if pos.distance_to(tc) < MIN_FROM_TC:
				too_close = true
				break
		if too_close:
			continue
		var sz: Array = FOREST_SIZES[_rng.randi() % FOREST_SIZES.size()] as Array
		_spawn_forest_zone(parent, pos,
			roundi(_rng.randf_range(float(sz[0]), float(sz[1])) * _res_mult),
			200.0 * _res_mult, float(sz[2]), true)
		placed_forest += 1

	# ── Edge pass: resources along the map border (75–95 % of map half) ──────
	# Distributes 8 groups around the ring so every corner/edge gets content.
	const EDGE_INNER: float = 0.75
	const EDGE_OUTER: float = 0.95
	var edge_angle_base: float = _rng.randf() * TAU
	for ei: int in range(8):
		var ea: float = edge_angle_base + TAU * float(ei) / 8.0 + _rng.randf_range(-0.2, 0.2)
		var ed: float = _rng.randf_range(_map_half * EDGE_INNER, _map_half * EDGE_OUTER)
		var ep: Vector2 = _clamp_map(Vector2(cos(ea), sin(ea)) * ed)
		if TerrainManager.is_impassable_for(ep, ""):
			continue
		# Alternate: forest → gold → forest → stone → forest → gold → forest → stone
		match ei % 4:
			0, 2:
				var sz: Array = FOREST_SIZES[_rng.randi() % FOREST_SIZES.size()] as Array
				_spawn_forest_zone(parent, ep,
					roundi(_rng.randf_range(float(sz[0]), float(sz[1])) * _res_mult),
					200.0 * _res_mult, float(sz[2]), true)
			1:
				_spawn_deposit(parent, ep, ResourceNode.ResourceType.GOLD,
					roundi(_rng.randf_range(4.0, 6.0) * _res_mult),
					200.0 * _res_mult, _rng.randf() * TAU, 0.0, 55.0)
			3:
				_spawn_deposit(parent, ep, ResourceNode.ResourceType.STONE,
					roundi(_rng.randf_range(3.0, 5.0) * _res_mult),
					200.0 * _res_mult, _rng.randf() * TAU, 0.0, 55.0)

func _spawn_fish_multi(parent: Node2D, island_centers: Array[Vector2],
		island_radius: float) -> void:
	var map_center: Vector2 = Vector2.ZERO
	for c: Vector2 in island_centers:
		map_center += c
	map_center /= float(island_centers.size())

	# Each node is a shoal of 5 fish — fewer nodes, higher amount each.
	var total: int = roundi(5.0 * _res_mult * float(island_centers.size()) * 0.75)
	var placed: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * total * 2):
		if placed >= total:
			break
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(island_radius * 0.5, island_radius * 2.0)
		var pos: Vector2 = map_center + Vector2(cos(a), sin(a)) * d
		pos = _clamp_map(pos)
		if not TerrainManager.is_ocean(pos):
			continue
		if not _is_free(pos, R_RES_OTHER):
			continue
		_register(pos, R_RES_OTHER)
		_create_resource_node(parent, pos, ResourceNode.ResourceType.FOOD_FISH,
			280.0 * _rng.randf_range(0.8, 1.2))
		placed += 1

# Spawns small resource islets in the open ocean between and around the two main islands.
# Each islet is a small land polygon with one random resource type.
func _spawn_resource_islets(parent: Node2D, center0: Vector2, center1: Vector2,
		island_radius: float) -> void:
	# Possible islet compositions: list of resource types to place on each
	const ISLET_TEMPLATES: Array = [
		[ResourceNode.ResourceType.GOLD],
		[ResourceNode.ResourceType.WOOD, ResourceNode.ResourceType.STONE],
		[ResourceNode.ResourceType.STONE],
		[ResourceNode.ResourceType.WOOD],
		[ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE],
	]

	var islet_count: int = _rng.randi_range(3, 4)
	var min_dist_from_main: float = island_radius * 1.25
	var islet_radius: float = _map_half * 0.09

	for _i: int in range(islet_count):
		# Find a position in the ocean not too close to any existing land
		var islet_center: Vector2 = Vector2.ZERO
		var found: bool = false
		for _attempt: int in range(60):
			var a: float = _rng.randf() * TAU
			var d: float = _rng.randf_range(island_radius * 1.3, _map_half * 0.75)
			var mid: Vector2 = (center0 + center1) * 0.5
			var candidate: Vector2 = mid + Vector2(cos(a), sin(a)) * d
			candidate = _clamp_map(candidate)
			if not TerrainManager.is_ocean(candidate):
				continue
			if candidate.distance_to(center0) < min_dist_from_main:
				continue
			if candidate.distance_to(center1) < min_dist_from_main:
				continue
			# Check no existing land poly nearby
			var too_close: bool = false
			for poly: Variant in _land_polys:
				for pt: Vector2 in (poly as PackedVector2Array):
					if candidate.distance_to(pt) < island_radius * 0.8:
						too_close = true
						break
				if too_close:
					break
			if too_close:
				continue
			islet_center = candidate
			found = true
			break
		if not found:
			continue

		# Build and paint the islet polygon (same shore treatment as the main
		# islands so it doesn't sit as a hard green cut on the ocean)
		var poly: PackedVector2Array = _make_island_poly(islet_center, islet_radius)
		_land_polys.append(poly)
		TerrainManager.set_land_polys(_land_polys, true)
		_paint_shore(parent, poly, islet_center)
		_paint_polygon(parent, poly, _tc(TerrainManager.TerrainType.GRASS))

		# Pick a random template and spawn its resources on the islet
		var template: Array = ISLET_TEMPLATES[_rng.randi() % ISLET_TEMPLATES.size()] as Array
		for rtype: Variant in template:
			var res: ResourceNode.ResourceType = rtype as ResourceNode.ResourceType
			var is_wood: bool = res == ResourceNode.ResourceType.WOOD
			var obj_r: float = R_RES_WOOD if is_wood else R_RES_OTHER
			var count: int = _rng.randi_range(3, 5) if is_wood else _rng.randi_range(2, 4)
			var amount: float = (180.0 if is_wood else 200.0) * _res_mult
			var placed: int = 0
			for _j: int in range(MAX_PLACE_TRIES * count):
				if placed >= count:
					break
				var a: float = _rng.randf() * TAU
				var d: float = _rng.randf_range(0.0, islet_radius * 0.75)
				var pos: Vector2 = islet_center + Vector2(cos(a), sin(a)) * d
				if not TerrainManager._point_in_any_land(pos):
					continue
				if not _is_free(pos, obj_r):
					continue
				_register(pos, obj_r)
				_create_resource_node(parent, pos, res, amount * _rng.randf_range(0.85, 1.15))
				placed += 1

func _spawn_deposit(parent: Node2D, center: Vector2,
		rtype: ResourceNode.ResourceType, count: int, amount: float,
		anchor_angle: float, dist_min: float, dist_max: float) -> void:
	var obj_r: float = R_RES_WOOD if rtype == ResourceNode.ResourceType.WOOD else R_RES_OTHER
	var deposit_center: Vector2 = _find_free_arc(center, dist_min, dist_max, obj_r, anchor_angle)
	if deposit_center == Vector2.INF or TerrainManager.is_impassable_for(deposit_center, ""):
		return
	_register(deposit_center, obj_r)
	_create_resource_node(parent, deposit_center, rtype, amount * _rng.randf_range(0.5, 1.5))
	var placed: int = 1
	for _i: int in range(MAX_PLACE_TRIES * count):
		if placed >= count:
			break
		var pos: Vector2 = _find_free_near(deposit_center, 48.0, obj_r)
		if pos == Vector2.INF or TerrainManager.is_impassable_for(pos, ""):
			continue
		_register(pos, obj_r)
		_create_resource_node(parent, pos, rtype, amount * _rng.randf_range(0.5, 1.5))
		placed += 1

func _spawn_deposit_clamped(parent: Node2D, center: Vector2,
		rtype: ResourceNode.ResourceType, count: int, amount: float,
		anchor_angle: float, dist_min: float, dist_max: float,
		island_center: Vector2, island_radius: float) -> void:
	var obj_r: float = R_RES_WOOD if rtype == ResourceNode.ResourceType.WOOD else R_RES_OTHER
	# Try to find a spot within the island
	var deposit_center: Vector2 = Vector2.INF
	for _i: int in range(MAX_PLACE_TRIES * 2):
		var a: float = anchor_angle + _rng.randf_range(-0.6, 0.6)
		var d: float = _rng.randf_range(dist_min, dist_max)
		var p: Vector2 = center + Vector2(cos(a), sin(a)) * d
		if not TerrainManager._point_in_any_land(p):
			continue
		if not TerrainManager.is_buildable(p):
			continue
		if _is_free(p, obj_r):
			deposit_center = p
			break
	if deposit_center == Vector2.INF:
		return
	_register(deposit_center, obj_r)
	_create_resource_node(parent, deposit_center, rtype, amount * _rng.randf_range(0.5, 1.5))
	var placed: int = 1
	for _i: int in range(MAX_PLACE_TRIES * count):
		if placed >= count:
			break
		var pos: Vector2 = _find_free_near(deposit_center, 48.0, obj_r)
		if pos == Vector2.INF:
			continue
		if not TerrainManager._point_in_any_land(pos):
			continue
		_register(pos, obj_r)
		_create_resource_node(parent, pos, rtype, amount * _rng.randf_range(0.5, 1.5))
		placed += 1

func _spawn_forest_zone(parent: Node2D, zone_center: Vector2,
		count: int, amount: float, zone_radius: float, tight: bool = false) -> void:
	var node_r: float = FOREST_NODE_RADIUS if tight else R_RES_WOOD
	var max_iter: int = count * 16
	for _i: int in range(max_iter):
		if count <= 0:
			break
		var pos: Vector2 = _find_free_near(zone_center, zone_radius, node_r)
		if pos == Vector2.INF or TerrainManager.is_impassable_for(pos, ""):
			continue
		_register(pos, node_r)
		_create_resource_node(parent, pos, ResourceNode.ResourceType.WOOD,
			amount * _rng.randf_range(0.8, 1.2))
		count -= 1

# ── Resource node factory ────────────────────────────────────────────────────

func _create_resource_node(parent: Node2D, pos: Vector2,
		rtype: ResourceNode.ResourceType, amount: float) -> void:
	MapGenerator.create_resource_node(parent, pos, rtype, amount, _rng,
		load("res://scripts/economy/resource_node.gd") as Script)

## Public static factory — call this from SaveManager when restoring nodes.
## Pass a seeded RNG (or null for fixed-size defaults).
static func create_resource_node(parent: Node2D, pos: Vector2,
		rtype: ResourceNode.ResourceType, amount: float,
		rng: RandomNumberGenerator = null,
		res_script: Script = null) -> void:
	var node: Node2D = Node2D.new()
	if res_script == null:
		res_script = load("res://scripts/economy/resource_node.gd") as Script
	node.set_script(res_script)
	node.set("resource_type", rtype)
	node.set("initial_amount", amount)
	parent.add_child(node)
	node.global_position = pos

	var jitter: float = rng.randf_range(0.85, 1.15) if rng != null else 1.0
	var collision_r: float = _build_resource_visual(node, rtype, jitter, amount)

	var area: Area2D = Area2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = collision_r + 4.0
	shape.shape = circle
	area.add_child(shape)
	node.add_child(area)

	# Fish nodes live in the ocean — only land resources need physics blocking.
	if rtype != ResourceNode.ResourceType.FOOD_FISH:
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var body_shape: CollisionShape2D = CollisionShape2D.new()
		var body_circle: CircleShape2D = CircleShape2D.new()
		body_circle.radius = maxf(collision_r * 0.7, 8.0)
		body_shape.shape = body_circle
		body.add_child(body_shape)
		node.add_child(body)

		var obstacle: NavigationObstacle2D = NavigationObstacle2D.new()
		obstacle.radius = collision_r + 4.0
		obstacle.avoidance_enabled = true
		node.add_child(obstacle)

	IsoBillboard.setup_drawn_node(node)

# Builds the visual Polygon2D children for a resource node.
# Returns the effective collision radius.
static func _build_resource_visual(node: Node2D,
		rtype: ResourceNode.ResourceType, scale: float, amount: float = 0.0) -> float:
	match rtype:
		ResourceNode.ResourceType.WOOD:
			return _draw_tree(node, scale)
		ResourceNode.ResourceType.GOLD:
			return _draw_gold(node, scale, amount)
		ResourceNode.ResourceType.STONE:
			return _draw_stone(node, scale, amount)
		ResourceNode.ResourceType.FOOD_BERRY:
			return _draw_berry_bush(node, scale, amount)
		ResourceNode.ResourceType.FOOD_HUNT:
			return _draw_deer(node, scale)
		ResourceNode.ResourceType.FOOD_FISH:
			return _draw_fish(node, scale)
		ResourceNode.ResourceType.OLIVINA:
			return _draw_olivina(node, scale, amount)
	return 12.0

# ── Tree (wood) ──────────────────────────────────────────────────────────────
static func _draw_tree(node: Node2D, s: float) -> float:
	# Trunk
	var trunk: Polygon2D = Polygon2D.new()
	trunk.color = Color(0.38, 0.24, 0.12)
	var tw: float = 3.0 * s
	var th: float = 10.0 * s
	trunk.polygon = PackedVector2Array([
		Vector2(-tw, 0.0), Vector2(tw, 0.0),
		Vector2(tw * 0.7, -th), Vector2(-tw * 0.7, -th),
	])
	node.add_child(trunk)
	# Three layered canopy circles using Polygon2D octagons
	const LAYERS: Array = [
		[0.0,  -8.0,  13.0, Color(0.10, 0.48, 0.12)],
		[0.0,  -16.0, 11.0, Color(0.14, 0.58, 0.16)],
		[0.0,  -23.0,  8.0, Color(0.18, 0.65, 0.20)],
	]
	for layer: Variant in LAYERS:
		var la: Array = layer as Array
		var cx: float = (la[0] as float) * s
		var cy: float = (la[1] as float) * s
		var r: float  = (la[2] as float) * s
		var col: Color = la[3] as Color
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(8):
			var a: float = TAU * i / 8.0 - PI / 8.0
			pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
		var canopy: Polygon2D = Polygon2D.new()
		canopy.color = col
		canopy.polygon = pts
		node.add_child(canopy)
	# Shadow ellipse under the tree
	var shadow: Polygon2D = Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	var sw: float = 11.0 * s
	var sh: float = 4.0 * s
	var spts: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var a: float = TAU * i / 10.0
		spts.append(Vector2(cos(a) * sw, sin(a) * sh))
	shadow.polygon = spts
	shadow.z_index = -1
	node.add_child(shadow)
	return 13.0 * s

# ── Tree stump (shown while a villager is actively chopping) ─────────────────
static func _draw_tree_stump(node: Node2D, s: float) -> void:
	# Shadow ellipse — keep same footprint so it still reads as a ground object
	var shadow: Polygon2D = Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	var sw: float = 11.0 * s
	var sh: float = 4.0 * s
	var spts: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var a: float = TAU * i / 10.0
		spts.append(Vector2(cos(a) * sw, sin(a) * sh))
	shadow.polygon = spts
	shadow.z_index = -1
	node.add_child(shadow)
	# Short wide stump
	var stump: Polygon2D = Polygon2D.new()
	stump.color = Color(0.38, 0.24, 0.12)
	var sw2: float = 5.0 * s
	var sh2: float = 4.0 * s
	stump.polygon = PackedVector2Array([
		Vector2(-sw2, 0.0), Vector2(sw2, 0.0),
		Vector2(sw2 * 0.8, -sh2), Vector2(-sw2 * 0.8, -sh2),
	])
	node.add_child(stump)
	# Horizontal log lying to the right, rotated slightly
	var log: Polygon2D = Polygon2D.new()
	log.color = Color(0.42, 0.27, 0.14)
	var lw: float = 10.0 * s
	var lh: float = 2.0 * s
	log.polygon = PackedVector2Array([
		Vector2(-lw, -lh), Vector2(lw, -lh),
		Vector2(lw,  lh),  Vector2(-lw,  lh),
	])
	log.position = Vector2(12.0 * s, -2.0 * s)
	log.rotation = deg_to_rad(15.0)
	node.add_child(log)

# ── Gold rocks ───────────────────────────────────────────────────────────────
static func _draw_gold(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int = 2 if amount <= 160.0 else 3
	const LAYOUTS_2: Array = [[-7.0, 2.0, 1.00], [ 6.0, 0.0, 0.90]]
	const LAYOUTS_3: Array = [[-9.0, 2.0, 1.00], [ 4.0, 0.0, 0.88], [ 0.0,-7.0, 0.75]]
	var layout: Array = LAYOUTS_2 if count == 2 else LAYOUTS_3
	for entry: Variant in layout:
		var e: Array = entry as Array
		var container: Node2D = Node2D.new()
		container.position = Vector2((e[0] as float) * s, (e[1] as float) * s)
		node.add_child(container)
		_draw_single_gold_rock(container, s * (e[2] as float))
	return (14.0 if count == 3 else 11.0) * s

static func _draw_single_gold_rock(node: Node2D, s: float) -> void:
	# Ground shadow ellipse
	var ground: Polygon2D = Polygon2D.new()
	ground.color = Color(0.40, 0.32, 0.08, 0.5)
	var gpts: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var a: float = TAU * i / 10.0
		gpts.append(Vector2(cos(a) * 9.0 * s, sin(a) * 4.0 * s))
	ground.polygon = gpts
	ground.z_index = -1
	node.add_child(ground)
	# Rock blob — dark earthy brown
	var rpts: PackedVector2Array = PackedVector2Array()
	const RANGLES: Array = [0.0, 0.9, 1.8, 2.7, 3.6, 4.5, 5.4]
	const RRADII:  Array = [8.0, 6.5, 9.0, 7.5, 6.0, 8.5, 7.0]
	for i: int in range(7):
		var a: float = (RANGLES[i] as float)
		var rr: float = (RRADII[i] as float) * s
		rpts.append(Vector2(cos(a) * rr, sin(a) * rr * 0.62))
	var rock_poly: Polygon2D = Polygon2D.new()
	rock_poly.color = Color(0.40, 0.33, 0.16)
	rock_poly.polygon = rpts
	node.add_child(rock_poly)
	# Top highlight — lighter warm stone
	var hi: Polygon2D = Polygon2D.new()
	hi.color = Color(0.60, 0.50, 0.26, 0.55)
	hi.polygon = PackedVector2Array([rpts[6], rpts[0], rpts[1], rpts[2]])
	node.add_child(hi)
	# Gold vein streaks
	const VEINS: Array = [[-5.0,-2.5, 1.0,-1.0, 4.5, 0.5], [-1.0, 0.5, 3.5,-0.8, 2.0, 2.0]]
	for v: Variant in VEINS:
		var vd: Array = v as Array
		var vein: Line2D = Line2D.new()
		vein.default_color = Color(0.95, 0.80, 0.10, 0.85)
		vein.width = 1.5 * s
		vein.add_point(Vector2((vd[0] as float) * s, (vd[1] as float) * s))
		vein.add_point(Vector2((vd[2] as float) * s, (vd[3] as float) * s))
		vein.add_point(Vector2((vd[4] as float) * s, (vd[5] as float) * s))
		node.add_child(vein)

# ── Olivina crystals ──────────────────────────────────────────────────────────
static func _draw_olivina(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int
	if amount <= 100.0:
		count = 2
	elif amount <= 180.0:
		count = 3
	else:
		count = 4
	# [offset_x, offset_y, half_width, height, angle, Color]
	const CRYSTAL_2: Array = [
		[-4.0,  0.0, 3.2, 11.0, -0.25, Color(0.35, 0.82, 0.28)],
		[ 4.0, -1.0, 2.8, 10.0,  0.30, Color(0.28, 0.70, 0.20)],
	]
	const CRYSTAL_3: Array = [
		[-5.0,  0.0, 3.5, 12.0, -0.25, Color(0.35, 0.82, 0.28)],
		[ 1.0,  1.0, 3.0, 14.0,  0.10, Color(0.45, 0.92, 0.35)],
		[ 5.0, -1.0, 2.5, 10.0,  0.35, Color(0.28, 0.70, 0.20)],
	]
	const CRYSTAL_4: Array = [
		[-7.0,  1.0, 3.5, 13.0, -0.30, Color(0.35, 0.82, 0.28)],
		[ 0.0,  0.0, 3.2, 15.0,  0.08, Color(0.45, 0.92, 0.35)],
		[ 5.0, -1.0, 2.5, 10.0,  0.32, Color(0.28, 0.70, 0.20)],
		[-2.0, -5.0, 2.2,  9.0, -0.15, Color(0.38, 0.78, 0.26)],
	]
	var crystals: Array
	match count:
		2: crystals = CRYSTAL_2
		4: crystals = CRYSTAL_4
		_: crystals = CRYSTAL_3

	# Ground patch scales with count
	var ground: Polygon2D = Polygon2D.new()
	ground.color = Color(0.12, 0.38, 0.10, 0.6)
	var gw: float = (7.0 + float(count) * 2.0) * s
	ground.polygon = PackedVector2Array([
		Vector2(-gw, 0.0), Vector2(gw, 0.0),
		Vector2(gw * 0.72, 4.0 * s), Vector2(-gw * 0.72, 4.0 * s),
	])
	node.add_child(ground)

	for c: Variant in crystals:
		var ca: Array = c as Array
		var bx: float = (ca[0] as float) * s
		var by: float = (ca[1] as float) * s
		var hw: float = (ca[2] as float) * s
		var ht: float = (ca[3] as float) * s
		var angle: float = ca[4] as float
		var col: Color = ca[5] as Color
		var raw: PackedVector2Array = PackedVector2Array([
			Vector2(0.0, -ht),
			Vector2(hw, -ht * 0.35),
			Vector2(hw * 0.6, 0.0),
			Vector2(-hw * 0.6, 0.0),
			Vector2(-hw, -ht * 0.35),
		])
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in raw:
			pts.append(Vector2(
				bx + p.x * cos(angle) - p.y * sin(angle),
				by + p.x * sin(angle) + p.y * cos(angle)
			))
		var shard: Polygon2D = Polygon2D.new()
		shard.color = col
		shard.polygon = pts
		node.add_child(shard)
		var face_bright: Polygon2D = Polygon2D.new()
		face_bright.color = Color(0.75, 1.0, 0.65, 0.50)
		face_bright.polygon = PackedVector2Array([pts[0], pts[1], pts[2]])
		node.add_child(face_bright)
	return (10.0 + float(count) * 2.0) * s

# ── Stone rocks ──────────────────────────────────────────────────────────────
static func _draw_stone(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int = 2 if amount <= 180.0 else 3
	const LAYOUTS_2: Array = [[-6.0, 1.0, 1.00], [ 5.0, 0.0, 0.92]]
	const LAYOUTS_3: Array = [[-8.0, 1.0, 1.00], [ 4.0, 0.0, 0.90], [-1.0,-7.0, 0.78]]
	var layout: Array = LAYOUTS_2 if count == 2 else LAYOUTS_3
	for entry: Variant in layout:
		var e: Array = entry as Array
		var container: Node2D = Node2D.new()
		container.position = Vector2((e[0] as float) * s, (e[1] as float) * s)
		node.add_child(container)
		_draw_single_stone_rock(container, s * (e[2] as float))
	return (14.0 if count == 3 else 11.0) * s

static func _draw_single_stone_rock(node: Node2D, s: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	const ANGLES: Array = [0.0, 0.9, 1.8, 2.7, 3.6, 4.5, 5.4]
	const RADII:  Array = [9.0, 7.5, 10.0, 8.0, 6.5, 9.5, 7.0]
	for i: int in range(7):
		var a: float = (ANGLES[i] as float)
		var rr: float = (RADII[i] as float) * s
		pts.append(Vector2(cos(a) * rr, sin(a) * rr * 0.6))
	var rock_poly: Polygon2D = Polygon2D.new()
	rock_poly.color = Color(0.52, 0.50, 0.47)
	rock_poly.polygon = pts
	node.add_child(rock_poly)
	var hi: Polygon2D = Polygon2D.new()
	hi.color = Color(0.75, 0.73, 0.70, 0.55)
	hi.polygon = PackedVector2Array([pts[6], pts[0], pts[1], pts[2]])
	node.add_child(hi)

# ── Berry bush (food) ────────────────────────────────────────────────────────
static func _draw_berry_bush(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int
	if amount <= 88.0:
		count = 2
	elif amount <= 132.0:
		count = 3
	else:
		count = 4
	const LAYOUTS_2: Array = [[-7.0, 0.0, 1.00], [ 6.0, 0.0, 0.88]]
	const LAYOUTS_3: Array = [[-8.0, 0.0, 1.00], [ 4.0, 0.0, 0.88], [-1.0,-8.0, 0.80]]
	const LAYOUTS_4: Array = [[-9.0, 0.0, 1.00], [ 5.0,-1.0, 0.88], [-2.0,-8.0, 0.82], [ 7.0,-6.0, 0.75]]
	var layout: Array
	match count:
		2: layout = LAYOUTS_2
		4: layout = LAYOUTS_4
		_: layout = LAYOUTS_3
	for entry: Variant in layout:
		var e: Array = entry as Array
		var container: Node2D = Node2D.new()
		container.position = Vector2((e[0] as float) * s, (e[1] as float) * s)
		node.add_child(container)
		_draw_single_berry_bush(container, s * (e[2] as float))
	return (12.0 + float(count) * 2.5) * s

static func _draw_single_berry_bush(node: Node2D, s: float) -> void:
	const BLOBS: Array = [
		[-4.0, -2.0, 9.0, Color(0.15, 0.48, 0.12)],
		[ 4.0, -1.0, 8.0, Color(0.18, 0.55, 0.15)],
		[ 0.0, -7.0, 7.0, Color(0.20, 0.52, 0.14)],
	]
	for bl: Variant in BLOBS:
		var bla: Array = bl as Array
		var bx: float = (bla[0] as float) * s
		var by: float = (bla[1] as float) * s
		var br: float = (bla[2] as float) * s
		var col: Color = bla[3] as Color
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(9):
			var a: float = TAU * i / 9.0
			pts.append(Vector2(bx + cos(a) * br, by + sin(a) * br * 0.85))
		var blob: Polygon2D = Polygon2D.new()
		blob.color = col
		blob.polygon = pts
		node.add_child(blob)
	const BERRIES: Array = [
		[-5.0, -4.0], [0.0, -9.0], [5.0, -5.0],
		[-3.0, -1.0], [4.0, -2.0], [1.0, -6.0],
	]
	for bpos: Variant in BERRIES:
		var bp: Array = bpos as Array
		var bx: float = (bp[0] as float) * s
		var by: float = (bp[1] as float) * s
		var br: float = 1.8 * s
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(6):
			var a: float = TAU * i / 6.0
			pts.append(Vector2(bx + cos(a) * br, by + sin(a) * br))
		var berry: Polygon2D = Polygon2D.new()
		berry.color = Color(0.85, 0.15, 0.10)
		berry.polygon = pts
		node.add_child(berry)

# ── Deer (hunt food) ─────────────────────────────────────────────────────────
static func _draw_deer(node: Node2D, s: float) -> float:
	# Body — oval
	var body: Polygon2D = Polygon2D.new()
	body.color = Color(0.65, 0.38, 0.15)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(12):
		var a: float = TAU * i / 12.0
		pts.append(Vector2(cos(a) * 9.0 * s, sin(a) * 5.5 * s - 2.0 * s))
	body.polygon = pts
	node.add_child(body)
	# Head
	var head: Polygon2D = Polygon2D.new()
	head.color = Color(0.60, 0.34, 0.13)
	var hpts: PackedVector2Array = PackedVector2Array()
	for i: int in range(8):
		var a: float = TAU * i / 8.0
		hpts.append(Vector2(8.0 * s + cos(a) * 4.0 * s, -4.0 * s + sin(a) * 3.0 * s))
	head.polygon = hpts
	node.add_child(head)
	# Antlers — two small lines as thin polygons
	const ANTLERS: Array = [
		[8.0, -7.0, 10.0, -13.0],
		[10.0, -7.0, 13.0, -13.0],
	]
	for ant: Variant in ANTLERS:
		var aa: Array = ant as Array
		var ax1: float = (aa[0] as float) * s
		var ay1: float = (aa[1] as float) * s
		var ax2: float = (aa[2] as float) * s
		var ay2: float = (aa[3] as float) * s
		var dir: Vector2 = (Vector2(ax2, ay2) - Vector2(ax1, ay1)).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x) * 0.8 * s
		var antler: Polygon2D = Polygon2D.new()
		antler.color = Color(0.35, 0.20, 0.08)
		antler.polygon = PackedVector2Array([
			Vector2(ax1, ay1) - perp, Vector2(ax1, ay1) + perp,
			Vector2(ax2, ay2) + perp, Vector2(ax2, ay2) - perp,
		])
		node.add_child(antler)
	# Legs — four thin rectangles
	const LEGS: Array = [-6.0, -2.0, 2.0, 6.0]
	for lx: Variant in LEGS:
		var leg: Polygon2D = Polygon2D.new()
		leg.color = Color(0.50, 0.28, 0.10)
		var lxf: float = (lx as float) * s
		leg.polygon = PackedVector2Array([
			Vector2(lxf - 1.2 * s, 3.0 * s), Vector2(lxf + 1.2 * s, 3.0 * s),
			Vector2(lxf + 1.0 * s, 9.0 * s), Vector2(lxf - 1.0 * s, 9.0 * s),
		])
		node.add_child(leg)
	return 11.0 * s

# ── Fish ─────────────────────────────────────────────────────────────────────
static func _draw_fish(node: Node2D, s: float) -> float:
	# School layout: [offset_x, offset_y, angle_deg, size_mult]
	# Fish are spread in a loose shoal formation around the resource point.
	const SCHOOL: Array = [
		[ 0.0,   0.0,   0.0,  1.00],
		[22.0, -14.0,  20.0,  0.80],
		[26.0,  13.0, -14.0,  0.85],
		[-18.0, -10.0,  8.0,  0.75],
		[ 12.0,  22.0, -24.0, 0.72],
	]
	for entry: Array in SCHOOL:
		var container: Node2D = Node2D.new()
		container.position = Vector2((entry[0] as float) * s, (entry[1] as float) * s)
		container.rotation = deg_to_rad(entry[2] as float)
		node.add_child(container)
		_draw_single_fish(container, s * (entry[3] as float))
	return 38.0 * s

static func _draw_single_fish(node: Node2D, s: float) -> void:
	# Body
	var body: Polygon2D = Polygon2D.new()
	body.color = Color(0.25, 0.55, 0.75)
	body.polygon = PackedVector2Array([
		Vector2(-9.0 * s, 0.0),
		Vector2(-4.0 * s, -3.5 * s),
		Vector2(6.0 * s, -2.5 * s),
		Vector2(9.0 * s, 0.0),
		Vector2(6.0 * s, 2.5 * s),
		Vector2(-4.0 * s, 3.5 * s),
	])
	node.add_child(body)
	# Tail fin
	var tail: Polygon2D = Polygon2D.new()
	tail.color = Color(0.20, 0.45, 0.65)
	tail.polygon = PackedVector2Array([
		Vector2(-9.0 * s, 0.0),
		Vector2(-14.0 * s, -4.0 * s),
		Vector2(-12.0 * s, 0.0),
		Vector2(-14.0 * s, 4.0 * s),
	])
	node.add_child(tail)
	# Eye
	var eye: Polygon2D = Polygon2D.new()
	eye.color = Color(0.05, 0.05, 0.05)
	var epts: PackedVector2Array = PackedVector2Array()
	for i: int in range(6):
		var a: float = TAU * i / 6.0
		epts.append(Vector2(6.0 * s + cos(a) * 1.5 * s, sin(a) * 1.5 * s))
	eye.polygon = epts
	node.add_child(eye)
	# Shimmer stripe
	var shimmer: Polygon2D = Polygon2D.new()
	shimmer.color = Color(0.7, 0.9, 1.0, 0.35)
	shimmer.polygon = PackedVector2Array([
		Vector2(0.0, -1.5 * s), Vector2(5.0 * s, -2.0 * s),
		Vector2(5.5 * s, -0.5 * s), Vector2(0.0, 0.5 * s),
	])
	node.add_child(shimmer)

# ── Navigation mesh carving ─────────────────────────────────────────────────
#
# Layer 1 (NavigationRegion2D)      → land units: covers land, excludes ocean
# Layer 2 (OceanNavigationRegion2D) → ships:      covers ocean, excludes land
#
# On Islands maps both meshes are carved from the land polygons.
# On other maps there is no ocean so the ocean region stays as the full-map
# default (ships won't be trained on those map types anyway).

func _add_nav_obstacles(parent: Node2D) -> void:
	var land_region: NavigationRegion2D = parent.get_node_or_null("NavigationRegion2D") as NavigationRegion2D
	var ocean_region: NavigationRegion2D = parent.get_node_or_null("OceanNavigationRegion2D") as NavigationRegion2D

	if land_region == null:
		return

	if MatchConfig.map_type == MatchConfig.MapType.ISLANDS and _land_polys.size() > 0:
		# Land mesh: one polygon per island (CCW outline = walkable interior)
		var land_poly: NavigationPolygon = NavigationPolygon.new()
		for lp: Variant in _land_polys:
			land_poly.add_outline(lp as PackedVector2Array)
		land_poly.make_polygons_from_outlines()
		land_region.navigation_polygon = land_poly

		# Ocean mesh: full-map rect with each land island as a CW hole,
		# so ships can navigate everywhere except the land blobs.
		if ocean_region != null:
			var half: float = _map_half  # exact boundary — no overshoot
			# Outer boundary CCW
			var ocean_poly: NavigationPolygon = NavigationPolygon.new()
			ocean_poly.add_outline(PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half),
				Vector2(half,  half),  Vector2(-half,  half),
			]))
			# Each land polygon as a CW hole (reverse winding)
			for lp: Variant in _land_polys:
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

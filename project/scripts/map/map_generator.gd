class_name MapGenerator

## Generates a symmetric random map and paints procedural terrain zones.
## Placement order: background → terrain zones → TCs → units → animals → resources.

const MAX_PLACE_TRIES: int = 30

# --- Radii used when registering objects ---
const R_TC: float             = 130.0
const R_UNIT: float           = 22.0
const R_ANIMAL: float         = 28.0
const R_RES_WOOD: float       = 22.0
const R_RES_OTHER: float      = 32.0
# Tighter packing radius for forest zones — trees placed at 26 px minimum spacing
const FOREST_NODE_RADIUS: float = 13.0

const RES_COLORS: Dictionary = {
	ResourceNode.ResourceType.WOOD:       Color(0.10, 0.55, 0.10, 1.0),
	ResourceNode.ResourceType.GOLD:       Color(0.90, 0.75, 0.10, 1.0),
	ResourceNode.ResourceType.STONE:      Color(0.62, 0.60, 0.58, 1.0),
	ResourceNode.ResourceType.FOOD_HUNT:  Color(0.65, 0.28, 0.10, 1.0),
	ResourceNode.ResourceType.FOOD_FISH:  Color(0.18, 0.55, 0.75, 1.0),
}
const RES_LABELS: Dictionary = {
	ResourceNode.ResourceType.WOOD:       "Wood",
	ResourceNode.ResourceType.GOLD:       "Gold",
	ResourceNode.ResourceType.STONE:      "Stone",
	ResourceNode.ResourceType.FOOD_HUNT:  "Food",
	ResourceNode.ResourceType.FOOD_FISH:  "Fish",
}

const ANIMAL_SCENE: String   = "res://scenes/units/animal.tscn"
const SHEEP_SCENE:  String   = "res://scenes/units/sheep.tscn"

# --- Terrain visual colours ---
const TERRAIN_COLORS: Dictionary = {
	TerrainManager.TerrainType.GRASS:      Color(0.22, 0.45, 0.18),
	TerrainManager.TerrainType.MALPAIS:    Color(0.14, 0.12, 0.11),
	TerrainManager.TerrainType.DUNE:       Color(0.78, 0.68, 0.42),
	TerrainManager.TerrainType.LAURISILVA: Color(0.08, 0.30, 0.12),
	TerrainManager.TerrainType.RISCO:      Color(0.48, 0.44, 0.40),
	TerrainManager.TerrainType.OCEAN:      Color(0.10, 0.28, 0.52),
	TerrainManager.TerrainType.CALDERA:    Color(0.30, 0.08, 0.04),
}

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

	# Terrain root sits below everything else
	_terrain_root = Node2D.new()
	_terrain_root.z_index = -9
	parent.add_child(_terrain_root)

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
			# No terrain zones — pure flat grass, just paint the base green
			_paint_rect_bg(parent, _map_half, TERRAIN_COLORS[TerrainManager.TerrainType.GRASS])
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

	_add_nav_obstacles(parent)
	TerrainManager.bake_minimap_texture(_map_half, 256)
	return {"tc_positions": tc_positions}

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
		_paint_polygon(parent, poly, TERRAIN_COLORS[TerrainManager.TerrainType.GRASS])
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

# Build a bumpy circle polygon for an island
func _make_island_poly(center: Vector2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 24
	for i: int in range(steps):
		var angle: float = TAU * i / steps
		var r: float = radius * _rng.randf_range(0.72, 1.10)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	return pts

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
	# Base grass already present on the Ground polygon in scene.
	# Scatter: laurisilva patches, malpaís blob, dune patches, risco edge
	var configs: Array = [
		# [count, radius_min, radius_max, terrain_type]
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
	# Paint base as dune (paint large covering rect)
	_paint_rect_bg(parent, h, TERRAIN_COLORS[TerrainManager.TerrainType.DUNE])
	# Register full map as dune zone so TerrainManager knows
	TerrainManager.add_zone(Vector2.ZERO, h * 1.5, TerrainManager.TerrainType.DUNE)
	# Add small grass oases near TCs (registered last = highest priority)
	for side: int in [-1, 1]:
		var oasis: Vector2 = Vector2(side * h * 0.35, _rng.randf_range(-h * 0.2, h * 0.2))
		TerrainManager.add_zone(oasis, h * 0.18, TerrainManager.TerrainType.GRASS)
		_paint_circle_patch(parent, oasis, h * 0.18,
			TERRAIN_COLORS[TerrainManager.TerrainType.GRASS])
	# Risco ridge on east edge
	for _i: int in range(3):
		var rpos: Vector2 = Vector2(_rng.randf_range(h * 0.55, h * 0.75),
			_rng.randf_range(-h * 0.5, h * 0.5))
		var rr: float = _rng.randf_range(h * 0.04, h * 0.09)
		TerrainManager.add_zone(rpos, rr, TerrainManager.TerrainType.RISCO)
		_paint_risco(parent, rpos, rr)

# ── Terrain visual helpers ───────────────────────────────────────────────────

# Paints all registered terrain zones with type-specific visuals.
func _flush_terrain_zones_visual(parent: Node2D) -> void:
	var zones: Array = TerrainManager._zones
	for z: Dictionary in zones:
		var t: TerrainManager.TerrainType = z["type"] as TerrainManager.TerrainType
		var center: Vector2 = z["center"] as Vector2
		var radius: float   = z["radius"] as float
		match t:
			TerrainManager.TerrainType.LAURISILVA:
				_paint_laurisilva(parent, center, radius)
			TerrainManager.TerrainType.RISCO:
				_paint_risco(parent, center, radius)
			TerrainManager.TerrainType.MALPAIS:
				_paint_malpais(parent, center, radius)
			TerrainManager.TerrainType.CALDERA:
				_paint_caldera(parent, center, radius)
			_:
				_paint_circle_patch(parent, center, radius,
					TERRAIN_COLORS.get(t, Color(0.5, 0.5, 0.5)) as Color)

# ── Per-terrain painters ──────────────────────────────────────────────────────

func _paint_laurisilva(parent: Node2D, center: Vector2, radius: float) -> void:
	# Base: dark green blob
	_paint_circle_patch(parent, center, radius, Color(0.08, 0.28, 0.10))
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

func _paint_risco(parent: Node2D, center: Vector2, radius: float) -> void:
	_paint_circle_patch(parent, center, radius, Color(0.46, 0.42, 0.38))
	# Batch all rock shards into two Polygon2D nodes (light / dark)
	var pts_light: PackedVector2Array = PackedVector2Array()
	var pts_dark:  PackedVector2Array = PackedVector2Array()
	var rock_count: int = _rng.randi_range(5, 8)
	for _i: int in range(rock_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.80)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var sides: int = _rng.randi_range(5, 7)
		var rr: float = _rng.randf_range(radius * 0.10, radius * 0.22)
		var rot: float = _rng.randf() * TAU
		var pts: PackedVector2Array = pts_light if _rng.randf() > 0.5 else pts_dark
		if pts.size() > 0:
			pts.append(pts[0])
		for ri: int in range(sides):
			var ra: float = rot + TAU * ri / sides
			pts.append(pos + Vector2(cos(ra), sin(ra)) * rr * _rng.randf_range(0.55, 1.0))

	for data: Array in [[pts_light, Color(0.60, 0.57, 0.53)], [pts_dark, Color(0.32, 0.30, 0.28)]]:
		var pts: PackedVector2Array = data[0] as PackedVector2Array
		if pts.size() < 3:
			continue
		var rock: Polygon2D = Polygon2D.new()
		rock.color = data[1] as Color
		rock.z_index = -7
		rock.polygon = pts
		parent.add_child(rock)

func _paint_malpais(parent: Node2D, center: Vector2, radius: float) -> void:
	_paint_circle_patch(parent, center, radius, Color(0.12, 0.10, 0.09))
	# Batch all fragments into a single Polygon2D
	var all_pts: PackedVector2Array = PackedVector2Array()
	var frag_count: int = _rng.randi_range(8, 14)
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
		frag.color = Color(0.26, 0.23, 0.22)
		frag.z_index = -7
		frag.polygon = all_pts
		parent.add_child(frag)

func _paint_caldera(parent: Node2D, center: Vector2, radius: float) -> void:
	# Outer ring: dark red
	_paint_circle_patch(parent, center, radius, Color(0.28, 0.07, 0.04))
	# Inner crater: almost black
	_paint_circle_patch(parent, center, radius * 0.55, Color(0.06, 0.04, 0.04))
	# 3–5 lava cracks radiating from center
	var crack_count: int = _rng.randi_range(3, 5)
	for ci: int in range(crack_count):
		var ca: float = TAU * ci / crack_count + _rng.randf_range(-0.2, 0.2)
		var crack: Line2D = Line2D.new()
		crack.default_color = Color(0.90, 0.35, 0.05, 0.80)
		crack.width = _rng.randf_range(1.5, 3.0)
		crack.z_index = -6
		var segments: int = _rng.randi_range(3, 5)
		var cp: Vector2 = center
		for _si: int in range(segments):
			cp += Vector2(cos(ca), sin(ca)) * _rng.randf_range(radius * 0.10, radius * 0.20)
			cp += Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
			crack.add_point(cp)
		parent.add_child(crack)

func _paint_circle_patch(parent: Node2D, center: Vector2,
		radius: float, col: Color) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -8
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 20
	for i: int in range(steps):
		var a: float = TAU * i / steps
		var r: float = radius * _rng.randf_range(0.88, 1.08)
		pts.append(Vector2(cos(a), sin(a)) * r)
	poly.polygon = pts
	poly.position = center
	parent.add_child(poly)

func _paint_rect_bg(parent: Node2D, half: float, col: Color) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -9
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	parent.add_child(poly)

func _paint_ocean_bg(parent: Node2D, half: float) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = Color(1, 1, 1, 1)   # tinted by shader
	poly.z_index = -9
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 water_deep : source_color = vec4(0.07, 0.22, 0.48, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.18, 0.44, 0.70, 1.0);
uniform float wave_speed : hint_range(0.1, 4.0) = 1.2;
void fragment() {
	vec2 uv = UV;
	float t = TIME * wave_speed;
	float wave = sin((uv.x + uv.y) * 18.0 + t) * 0.5
			   + sin((uv.x - uv.y) * 12.0 + t * 1.3) * 0.3
			   + sin(uv.x * 25.0 + t * 0.7) * 0.2;
	float blend = wave * 0.5 + 0.5;
	COLOR = mix(water_deep, water_shallow, clamp(blend, 0.0, 1.0));
}
"""
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	poly.material = mat
	parent.add_child(poly)

func _paint_polygon(parent: Node2D, pts: PackedVector2Array, col: Color) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -8
	poly.polygon = pts
	parent.add_child(poly)

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
			if TerrainManager.is_ocean(pos):
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
		if TerrainManager.is_ocean(pos):
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
		roundi(7.0 * _res_mult), 160.0 * _res_mult, gold_angle + angle_offset, 320.0, 480.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.GOLD,
		roundi(4.0 * _res_mult), 160.0 * _res_mult, gold_angle + angle_offset + PI * 0.5, 320.0, 480.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(7.0 * _res_mult), 180.0 * _res_mult, stone_angle + angle_offset, 360.0, 530.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(4.0 * _res_mult), 180.0 * _res_mult, stone_angle + angle_offset + PI * 0.5, 360.0, 530.0)

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
		if not TerrainManager.is_ocean(fcenter):
			var pool: Array = FOREST_SIZES_SMALL if fdist < 360.0 else FOREST_SIZES_ALL
			var sz: Array = pool[_rng.randi() % pool.size()] as Array
			_spawn_forest_zone(parent, fcenter,
				roundi(_rng.randf_range(float(sz[0]), float(sz[1])) * _res_mult),
				200.0 * _res_mult, float(sz[2]), true)

	var food_angle: float = _rng.randf_range(0.0, TAU) + angle_offset
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		roundi(6.0 * _res_mult), 110.0 * _res_mult, food_angle,            160.0, 280.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		roundi(3.0 * _res_mult), 110.0 * _res_mult, food_angle + PI * 0.6, 180.0, 300.0)

# Island-constrained version: resources must land within the island poly
func _spawn_player_resources_clamped(parent: Node2D, tc: Vector2,
		angle_offset: float, island_center: Vector2, island_radius: float) -> void:
	# Reduce distances so deposits fit within island bounds
	var max_dist: float = island_radius * 0.65

	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.GOLD,
		roundi(8.0 * _res_mult), 140.0 * _res_mult,
		_rng.randf_range(0.0, TAU) + angle_offset, 160.0, max_dist, island_center, island_radius)
	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(8.0 * _res_mult), 160.0 * _res_mult,
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
	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		roundi(6.0 * _res_mult), 100.0 * _res_mult,
		food_angle, 120.0, max_dist, island_center, island_radius)

func _spawn_neutral_resources(parent: Node2D) -> void:
	var base_angle: float = _rng.randf_range(0.0, TAU)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		roundi(6.0 * _res_mult), 200.0 * _res_mult, base_angle,            400.0, 700.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		roundi(6.0 * _res_mult), 200.0 * _res_mult, base_angle + PI,       400.0, 700.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		roundi(5.0 * _res_mult), 200.0 * _res_mult, base_angle + PI * 0.5, 450.0, 720.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		roundi(5.0 * _res_mult), 200.0 * _res_mult, base_angle + PI * 1.5, 450.0, 720.0)
	const FOREST_SIZES: Array = [[12, 18, 50], [22, 30, 75], [35, 45, 105]]
	var fangle: float = _rng.randf_range(0.0, TAU)
	var neutral_forest_angles: Array[float] = [
		fangle, fangle + PI * 0.4, fangle + PI * 0.8,
		fangle + PI * 1.2, fangle + PI * 1.6,
		fangle + PI * 0.2, fangle + PI * 1.0,
	]
	for fa: float in neutral_forest_angles:
		var fc: Vector2 = _clamp_map(Vector2(cos(fa), sin(fa)) * _rng.randf_range(250.0, 700.0))
		if not TerrainManager.is_ocean(fc):
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
		if TerrainManager.is_ocean(pos):
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
		if TerrainManager.is_ocean(pos):
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
		if TerrainManager.is_ocean(pos):
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
		if TerrainManager.is_ocean(ep):
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

	var total: int = roundi(8.0 * _res_mult * float(island_centers.size()) * 0.75)
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
			200.0 * _rng.randf_range(0.8, 1.2))
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

		# Build and paint the islet polygon
		var poly: PackedVector2Array = _make_island_poly(islet_center, islet_radius)
		_land_polys.append(poly)
		TerrainManager.set_land_polys(_land_polys, true)
		_paint_polygon(parent, poly, TERRAIN_COLORS[TerrainManager.TerrainType.GRASS])

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
	if deposit_center == Vector2.INF or TerrainManager.is_ocean(deposit_center):
		return
	_register(deposit_center, obj_r)
	_create_resource_node(parent, deposit_center, rtype, amount * _rng.randf_range(0.85, 1.15))
	var placed: int = 1
	for _i: int in range(MAX_PLACE_TRIES * count):
		if placed >= count:
			break
		var pos: Vector2 = _find_free_near(deposit_center, 85.0, obj_r)
		if pos == Vector2.INF or TerrainManager.is_ocean(pos):
			continue
		_register(pos, obj_r)
		_create_resource_node(parent, pos, rtype, amount * _rng.randf_range(0.85, 1.15))
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
	_create_resource_node(parent, deposit_center, rtype, amount * _rng.randf_range(0.85, 1.15))
	var placed: int = 1
	for _i: int in range(MAX_PLACE_TRIES * count):
		if placed >= count:
			break
		var pos: Vector2 = _find_free_near(deposit_center, 85.0, obj_r)
		if pos == Vector2.INF:
			continue
		if not TerrainManager._point_in_any_land(pos):
			continue
		_register(pos, obj_r)
		_create_resource_node(parent, pos, rtype, amount * _rng.randf_range(0.85, 1.15))
		placed += 1

func _spawn_forest_zone(parent: Node2D, zone_center: Vector2,
		count: int, amount: float, zone_radius: float, tight: bool = false) -> void:
	var node_r: float = FOREST_NODE_RADIUS if tight else R_RES_WOOD
	var max_iter: int = count * 16
	for _i: int in range(max_iter):
		if count <= 0:
			break
		var pos: Vector2 = _find_free_near(zone_center, zone_radius, node_r)
		if pos == Vector2.INF or TerrainManager.is_ocean(pos):
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

	var is_wood: bool = rtype == ResourceNode.ResourceType.WOOD
	var w: float = (12.0 if not is_wood else 16.0)
	var h: float = (w if not is_wood else w * 1.6)
	if rng != null:
		w += rng.randf_range(-2.0, 4.0)
		h += rng.randf_range(0.0, 6.0)

	var rect: ColorRect = ColorRect.new()
	rect.color = RES_COLORS.get(rtype, Color(1, 1, 1)) as Color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.offset_left   = -w
	rect.offset_top    = -h
	rect.offset_right  =  w
	rect.offset_bottom =  w * 0.4
	node.add_child(rect)

	if not is_wood:
		var label: Label = Label.new()
		label.text = RES_LABELS.get(rtype, "") as String
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.offset_left   = -20.0
		label.offset_top    = -h - 14.0
		label.offset_right  =  20.0
		label.offset_bottom = -h - 2.0
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		node.add_child(label)

	var area: Area2D = Area2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = w + 4.0
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
		body_circle.radius = maxf(w * 0.7, 8.0)
		body_shape.shape = body_circle
		body.add_child(body_shape)
		node.add_child(body)

		var obstacle: NavigationObstacle2D = NavigationObstacle2D.new()
		obstacle.radius = w + 4.0
		obstacle.avoidance_enabled = true
		node.add_child(obstacle)

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

	# Solid impassable zones → NavigationObstacle2D on the land region
	const IMPASSABLE: Array = [
		TerrainManager.TerrainType.MALPAIS,
		TerrainManager.TerrainType.RISCO,
		TerrainManager.TerrainType.CALDERA,
	]
	for z: Dictionary in TerrainManager._zones:
		var t: TerrainManager.TerrainType = z["type"] as TerrainManager.TerrainType
		if not (t in IMPASSABLE):
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

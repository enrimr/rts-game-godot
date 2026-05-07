class_name MapGenerator

## Generates a symmetric random map and paints procedural terrain zones.
## Placement order: background → terrain zones → TCs → units → animals → resources.

const MAX_PLACE_TRIES: int = 40

# --- Radii used when registering objects ---
const R_TC: float        = 130.0
const R_UNIT: float      = 22.0
const R_ANIMAL: float    = 28.0
const R_RES_WOOD: float  = 22.0
const R_RES_OTHER: float = 30.0

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

# Placement registry
var _placed: Array[Dictionary] = []
var _rng: RandomNumberGenerator = null
var _map_half: float = 1800.0
var _res_mult: float = 1.0

# Polygon2D pool reused for terrain patches
var _terrain_root: Node2D = null
# Land polygons for island map (used by TerrainManager)
var _land_polys: Array = []

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

	# Terrain root sits below everything else
	_terrain_root = Node2D.new()
	_terrain_root.z_index = -9
	parent.add_child(_terrain_root)

	var tc0: Vector2
	var tc1: Vector2

	match MatchConfig.map_type:
		MatchConfig.MapType.ISLANDS:
			var result: Dictionary = _run_islands(parent, units_layer)
			tc0 = result["tc0"]
			tc1 = result["tc1"]
		MatchConfig.MapType.VOLCANIC_COAST:
			tc0 = _random_tc_pos()
			tc1 = -tc0
			_register(tc0, R_TC)
			_register(tc1, R_TC)
			_register_unit_cluster(tc0)
			_register_unit_cluster(tc1)
			_paint_volcanic_coast(parent)
			_spawn_animals(units_layer, tc0, tc1)
			_spawn_player_resources(parent, tc0, 0.0)
			_spawn_player_resources(parent, tc1, PI)
			_spawn_neutral_resources(parent)
		MatchConfig.MapType.DESERT_COAST:
			tc0 = _random_tc_pos()
			tc1 = -tc0
			_register(tc0, R_TC)
			_register(tc1, R_TC)
			_register_unit_cluster(tc0)
			_register_unit_cluster(tc1)
			_paint_desert_coast(parent)
			_spawn_animals(units_layer, tc0, tc1)
			_spawn_player_resources(parent, tc0, 0.0)
			_spawn_player_resources(parent, tc1, PI)
			_spawn_neutral_resources(parent)
		_: # STANDARD
			tc0 = _random_tc_pos()
			tc1 = -tc0
			_register(tc0, R_TC)
			_register(tc1, R_TC)
			_register_unit_cluster(tc0)
			_register_unit_cluster(tc1)
			_paint_standard(parent)
			_spawn_animals(units_layer, tc0, tc1)
			_spawn_player_resources(parent, tc0, 0.0)
			_spawn_player_resources(parent, tc1, PI)
			_spawn_neutral_resources(parent)

	_add_nav_obstacles(parent)
	return {"tc0": tc0, "tc1": tc1}

# ── Islands map ─────────────────────────────────────────────────────────────

func _run_islands(parent: Node2D, units_layer: Node2D) -> Dictionary:
	# Ocean background — full map (animated water shader)
	_paint_ocean_bg(parent, _map_half * 1.05)

	# Generate two land blobs, one per player, on opposite sides
	var island_radius: float = _map_half * 0.38
	var offset_x: float = _map_half * 0.50

	var center0: Vector2 = Vector2(-offset_x, _rng.randf_range(-_map_half * 0.15, _map_half * 0.15))
	var center1: Vector2 = Vector2( offset_x, -center0.y)

	var poly0: PackedVector2Array = _make_island_poly(center0, island_radius)
	var poly1: PackedVector2Array = _make_island_poly(center1, island_radius)
	_land_polys = [poly0, poly1]
	TerrainManager.set_land_polys(_land_polys, true)

	# Paint land blobs
	_paint_polygon(parent, poly0, TERRAIN_COLORS[TerrainManager.TerrainType.GRASS])
	_paint_polygon(parent, poly1, TERRAIN_COLORS[TerrainManager.TerrainType.GRASS])

	# Scatter terrain on each island
	_scatter_island_terrain(center0, island_radius)
	_scatter_island_terrain(center1, island_radius)

	# Paint terrain patches
	_flush_terrain_zones_visual(parent)

	# TC placement: near centre of each island
	var tc0: Vector2 = center0 + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60))
	var tc1: Vector2 = center1 + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60))
	_register(tc0, R_TC)
	_register(tc1, R_TC)
	_register_unit_cluster(tc0)
	_register_unit_cluster(tc1)

	# Resources constrained to land
	_spawn_island_resources(parent, tc0, center0, island_radius)
	_spawn_island_resources(parent, tc1, center1, island_radius)
	_spawn_animals(units_layer, tc0, tc1)
	_spawn_fish(parent, center0, center1, island_radius)

	return {"tc0": tc0, "tc1": tc1}

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
	# 18–26 individual tree canopies scattered inside the zone
	var tree_count: int = _rng.randi_range(18, 26)
	for _i: int in range(tree_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.90)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var tr_r: float = _rng.randf_range(radius * 0.04, radius * 0.09)
		# Trunk — thin dark brown rectangle
		var trunk: Polygon2D = Polygon2D.new()
		trunk.color = Color(0.28, 0.18, 0.08)
		trunk.z_index = -7
		var tw: float = tr_r * 0.25
		var th: float = tr_r * 0.55
		trunk.polygon = PackedVector2Array([
			Vector2(-tw, 0.0), Vector2(tw, 0.0),
			Vector2(tw, th),   Vector2(-tw, th),
		])
		trunk.position = pos
		parent.add_child(trunk)
		# Canopy — irregular green circle
		var canopy: Polygon2D = Polygon2D.new()
		canopy.color = Color(
			_rng.randf_range(0.05, 0.18),
			_rng.randf_range(0.38, 0.58),
			_rng.randf_range(0.05, 0.18))
		canopy.z_index = -6
		var cpts: PackedVector2Array = PackedVector2Array()
		var csteps: int = 8
		for ci: int in range(csteps):
			var ca: float = TAU * ci / csteps
			var cr: float = tr_r * _rng.randf_range(0.75, 1.25)
			cpts.append(Vector2(cos(ca), sin(ca)) * cr)
		canopy.polygon = cpts
		canopy.position = pos + Vector2(0.0, -tr_r * 0.3)
		parent.add_child(canopy)

func _paint_risco(parent: Node2D, center: Vector2, radius: float) -> void:
	# Base: mid-grey irregular blob
	_paint_circle_patch(parent, center, radius, Color(0.46, 0.42, 0.38))
	# 6–10 angular rock shards on top
	var rock_count: int = _rng.randi_range(6, 10)
	for _i: int in range(rock_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.80)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var rock: Polygon2D = Polygon2D.new()
		# Angular polygon — 5 to 7 points with NO wobble (straight edges = rock)
		var sides: int = _rng.randi_range(5, 7)
		var rr: float = _rng.randf_range(radius * 0.10, radius * 0.22)
		var rot: float = _rng.randf() * TAU
		var rpts: PackedVector2Array = PackedVector2Array()
		for ri: int in range(sides):
			var ra: float = rot + TAU * ri / sides
			# Deliberately uneven radii for jagged look
			var rlen: float = rr * _rng.randf_range(0.55, 1.0)
			rpts.append(Vector2(cos(ra), sin(ra)) * rlen)
		rock.polygon = rpts
		rock.position = pos
		# Alternating light/dark grey to suggest depth
		var shade: float = _rng.randf_range(0.30, 0.65)
		rock.color = Color(shade, shade * 0.96, shade * 0.90)
		rock.z_index = -7
		parent.add_child(rock)
		# Small shadow line along bottom edge
		var shadow: Line2D = Line2D.new()
		shadow.default_color = Color(0.10, 0.10, 0.10, 0.45)
		shadow.width = 1.5
		shadow.z_index = -6
		shadow.add_point(pos + Vector2(-rr * 0.5, rr * 0.35))
		shadow.add_point(pos + Vector2( rr * 0.5, rr * 0.35))
		parent.add_child(shadow)

func _paint_malpais(parent: Node2D, center: Vector2, radius: float) -> void:
	# Base: near-black blob
	_paint_circle_patch(parent, center, radius, Color(0.12, 0.10, 0.09))
	# Scatter of small sharp dark fragments
	var frag_count: int = _rng.randi_range(12, 20)
	for _i: int in range(frag_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.88)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var frag: Polygon2D = Polygon2D.new()
		var fr: float = _rng.randf_range(radius * 0.04, radius * 0.10)
		var fpts: PackedVector2Array = PackedVector2Array()
		var fsides: int = _rng.randi_range(4, 6)
		for fi: int in range(fsides):
			var fa: float = TAU * fi / fsides + _rng.randf_range(-0.2, 0.2)
			fpts.append(Vector2(cos(fa), sin(fa)) * fr * _rng.randf_range(0.5, 1.0))
		frag.polygon = fpts
		frag.position = pos
		var grey: float = _rng.randf_range(0.18, 0.32)
		frag.color = Color(grey, grey * 0.90, grey * 0.85)
		frag.z_index = -7
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
	_placed.append({"pos": pos, "radius": radius})

func _is_free(pos: Vector2, radius: float) -> bool:
	for entry: Dictionary in _placed:
		if pos.distance_to(entry["pos"] as Vector2) < radius + (entry["radius"] as float):
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

func _spawn_animals(units_layer: Node2D, tc0: Vector2, tc1: Vector2) -> void:
	var deer_scene:  PackedScene = load(ANIMAL_SCENE) as PackedScene
	var sheep_scene: PackedScene = load(SHEEP_SCENE)  as PackedScene

	for tc: Vector2 in [tc0, tc1]:
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

	var placed_deer: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * 8):
		if placed_deer >= 8:
			break
		var pos: Vector2 = Vector2(
			_rng.randf_range(-_map_half * 0.85, _map_half * 0.85),
			_rng.randf_range(-_map_half * 0.85, _map_half * 0.85))
		if pos.distance_to(tc0) < 300.0 or pos.distance_to(tc1) < 300.0:
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
		roundi(5.0 * _res_mult), 160.0 * _res_mult, gold_angle + angle_offset, 320.0, 480.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(5.0 * _res_mult), 180.0 * _res_mult, stone_angle + angle_offset, 360.0, 530.0)

	var forest_base: float = _rng.randf_range(0.0, TAU)
	for i: int in range(3):
		var fangle: float = forest_base + (TAU / 3.0) * float(i) \
				+ _rng.randf_range(-0.3, 0.3) + angle_offset
		var fdist:  float = _rng.randf_range(200.0, 420.0)
		var fcenter: Vector2 = _clamp_map(tc + Vector2(cos(fangle), sin(fangle)) * fdist)
		if not TerrainManager.is_ocean(fcenter):
			_spawn_forest_zone(parent, fcenter, roundi(_rng.randf_range(12.0, 16.0) * _res_mult),
				180.0 * _res_mult, 70.0)

	var food_angle: float = _rng.randf_range(0.0, TAU) + angle_offset
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		roundi(3.0 * _res_mult), 110.0 * _res_mult, food_angle,            160.0, 280.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		roundi(3.0 * _res_mult), 110.0 * _res_mult, food_angle + PI * 0.6, 180.0, 300.0)

# Island-constrained version: resources must land within the island poly
func _spawn_player_resources_clamped(parent: Node2D, tc: Vector2,
		angle_offset: float, island_center: Vector2, island_radius: float) -> void:
	# Reduce distances so deposits fit within island bounds
	var max_dist: float = island_radius * 0.65

	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.GOLD,
		roundi(4.0 * _res_mult), 140.0 * _res_mult,
		_rng.randf_range(0.0, TAU) + angle_offset, 160.0, max_dist, island_center, island_radius)
	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.STONE,
		roundi(4.0 * _res_mult), 160.0 * _res_mult,
		_rng.randf_range(0.0, TAU) + angle_offset, 160.0, max_dist, island_center, island_radius)

	for i: int in range(2):
		var fangle: float = angle_offset + TAU * 0.5 * float(i) + _rng.randf_range(-0.4, 0.4)
		var fcenter: Vector2 = island_center + \
			Vector2(cos(fangle), sin(fangle)) * _rng.randf_range(island_radius * 0.1, island_radius * 0.45)
		if TerrainManager._point_in_any_land(fcenter) and TerrainManager.is_buildable(fcenter):
			_spawn_forest_zone(parent, fcenter, roundi(_rng.randf_range(8.0, 12.0) * _res_mult),
				140.0 * _res_mult, 55.0)

	var food_angle: float = _rng.randf_range(0.0, TAU) + angle_offset
	_spawn_deposit_clamped(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		roundi(3.0 * _res_mult), 100.0 * _res_mult,
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
	var fangle: float = _rng.randf_range(0.0, TAU)
	for fa: float in [fangle, fangle + PI]:
		var fc: Vector2 = _clamp_map(Vector2(cos(fa), sin(fa)) * _rng.randf_range(300.0, 600.0))
		if not TerrainManager.is_ocean(fc):
			_spawn_forest_zone(parent, fc, roundi(18.0 * _res_mult), 200.0 * _res_mult, 90.0)

# Spawns fish (FOOD_FISH) in ocean water between the two islands.
func _spawn_fish(parent: Node2D, center0: Vector2, center1: Vector2, island_radius: float) -> void:
	var mid: Vector2 = (center0 + center1) * 0.5
	var total: int = roundi(8.0 * _res_mult)
	var placed: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * total * 2):
		if placed >= total:
			break
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(island_radius * 0.5, island_radius * 1.8)
		var pos: Vector2 = mid + Vector2(cos(a), sin(a)) * d
		pos = _clamp_map(pos)
		if not TerrainManager.is_ocean(pos):
			continue
		if not _is_free(pos, R_RES_OTHER):
			continue
		_register(pos, R_RES_OTHER)
		_create_resource_node(parent, pos, ResourceNode.ResourceType.FOOD_FISH,
			200.0 * _rng.randf_range(0.8, 1.2))
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
		var pos: Vector2 = _find_free_near(deposit_center, 90.0, obj_r)
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
		var pos: Vector2 = _find_free_near(deposit_center, 80.0, obj_r)
		if pos == Vector2.INF:
			continue
		if not TerrainManager._point_in_any_land(pos):
			continue
		_register(pos, obj_r)
		_create_resource_node(parent, pos, rtype, amount * _rng.randf_range(0.85, 1.15))
		placed += 1

func _spawn_forest_zone(parent: Node2D, zone_center: Vector2,
		count: int, amount: float, zone_radius: float) -> void:
	for _i: int in range(MAX_PLACE_TRIES * count):
		if count <= 0:
			break
		var pos: Vector2 = _find_free_near(zone_center, zone_radius, R_RES_WOOD)
		if pos == Vector2.INF or TerrainManager.is_ocean(pos):
			continue
		_register(pos, R_RES_WOOD)
		_create_resource_node(parent, pos, ResourceNode.ResourceType.WOOD,
			amount * _rng.randf_range(0.8, 1.2))
		count -= 1

# ── Resource node factory ────────────────────────────────────────────────────

func _create_resource_node(parent: Node2D, pos: Vector2,
		rtype: ResourceNode.ResourceType, amount: float) -> void:
	var node: Node2D = Node2D.new()
	node.set_script(load("res://scripts/economy/resource_node.gd"))
	node.set("resource_type", rtype)
	node.set("initial_amount", amount)
	parent.add_child(node)
	node.global_position = pos

	var is_wood: bool = rtype == ResourceNode.ResourceType.WOOD
	var w: float = (12.0 if not is_wood else 16.0) + _rng.randf_range(-2.0, 4.0)
	var h: float = (w if not is_wood else w * 1.6) + _rng.randf_range(0.0, 6.0)

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
			var half: float = _map_half * 1.05
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

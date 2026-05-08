extends Node

## TerrainManager — stores terrain zones painted by MapGenerator and
## answers per-position speed/buildability queries for units and buildings.

enum TerrainType {
	GRASS       = 0,   # default — no penalty
	MALPAIS     = 1,   # volcanic rock — impassable except Guanches
	DUNE        = 2,   # desert sand — slow heavy infantry, Mahos immune
	LAURISILVA  = 3,   # dense laurel forest — slow all, high wood
	RISCO       = 4,   # cliff edge — impassable, range bonus nearby
	OCEAN       = 5,   # water — land units blocked, Atlantes immune
	CALDERA     = 6,   # volcanic crater — impassable, +stone for controller
}

# Speed multipliers for each terrain type.
# Index = TerrainType int. Value = fraction of normal speed (1.0 = no penalty).
const SPEED_MULT: Array[float] = [
	1.00,  # GRASS
	0.20,  # MALPAIS
	0.80,  # DUNE (heavy infantry penalty applied in unit_base via civ check)
	0.65,  # LAURISILVA
	0.00,  # RISCO (impassable)
	0.00,  # OCEAN (land units blocked)
	0.00,  # CALDERA (impassable)
]

const BUILDABLE: Array[bool] = [
	true,   # GRASS
	false,  # MALPAIS
	true,   # DUNE
	false,  # LAURISILVA
	false,  # RISCO
	false,  # OCEAN
	false,  # CALDERA
]

# Each zone: { center: Vector2, radius: float, type: TerrainType }
var _zones: Array[Dictionary] = []

# Ocean polygon points (Islands map only) — Array of PackedVector2Array outlines
# A position is "ocean" if it falls outside all land polygons.
var _land_polys: Array = []    # Array of PackedVector2Array
var _is_island_map: bool = false

# Baked terrain texture — set by MapGenerator after generation completes.
var minimap_texture: ImageTexture = null

func reset() -> void:
	_zones.clear()
	_land_polys.clear()
	_is_island_map = false
	minimap_texture = null

func add_zone(center: Vector2, radius: float, type: TerrainType) -> void:
	_zones.append({"center": center, "radius": radius, "type": type})

func set_land_polys(polys: Array, is_island: bool) -> void:
	_land_polys = polys
	_is_island_map = is_island

# Returns the dominant TerrainType at world_pos.
# On island maps, positions outside land polygons are OCEAN.
func get_terrain(world_pos: Vector2) -> TerrainType:
	if _is_island_map and not _point_in_any_land(world_pos):
		return TerrainType.OCEAN
	# Walk zones in reverse so later-added (higher priority) zones win.
	for i: int in range(_zones.size() - 1, -1, -1):
		var z: Dictionary = _zones[i]
		if world_pos.distance_to(z["center"] as Vector2) <= (z["radius"] as float):
			return z["type"] as TerrainType
	return TerrainType.GRASS

# Speed multiplier for a unit at world_pos, taking civ immunity into account.
func get_speed_mult(world_pos: Vector2, civ_id: String) -> float:
	var t: TerrainType = get_terrain(world_pos)
	match t:
		TerrainType.MALPAIS:
			if civ_id == "guanches":
				return 1.0
			return SPEED_MULT[TerrainType.MALPAIS]
		TerrainType.DUNE:
			if civ_id == "mahos":
				return 1.0
			return SPEED_MULT[TerrainType.DUNE]
		TerrainType.OCEAN:
			if civ_id == "atlantes":
				return 0.60   # slowed but not blocked
			return 0.0
		_:
			return SPEED_MULT[t]

func is_buildable(world_pos: Vector2) -> bool:
	var t: TerrainType = get_terrain(world_pos)
	return BUILDABLE[t]

func is_ocean(world_pos: Vector2) -> bool:
	return get_terrain(world_pos) == TerrainType.OCEAN

# Returns true if a unit with given civ_id cannot enter world_pos at all.
func is_impassable_for(world_pos: Vector2, civ_id: String) -> bool:
	var t: TerrainType = get_terrain(world_pos)
	match t:
		TerrainType.OCEAN:
			return civ_id != "atlantes"
		TerrainType.RISCO, TerrainType.CALDERA:
			return true
		TerrainType.MALPAIS:
			return civ_id != "guanches"
		_:
			return false

# Returns the nearest passable position to world_pos for a unit with given civ_id.
# Searches outward in concentric rings until a passable tile is found.
# Returns world_pos itself if it is already passable (fast path).
func nearest_passable(world_pos: Vector2, civ_id: String) -> Vector2:
	if not is_impassable_for(world_pos, civ_id):
		return world_pos
	var step: float = 24.0
	for ring: int in range(1, 30):
		var r: float = step * ring
		var checks: int = maxi(8, ring * 8)
		for i: int in range(checks):
			var a: float = TAU * i / checks
			var candidate: Vector2 = world_pos + Vector2(cos(a), sin(a)) * r
			if not is_impassable_for(candidate, civ_id):
				return candidate
	return world_pos  # fallback — could not find passable tile

# Bakes a terrain overview texture by sampling get_terrain() on a grid.
# map_half: half-size of the playable world in world units.
# resolution: pixel dimensions of the output square texture.
func bake_minimap_texture(map_half: float, resolution: int) -> void:
	const TERRAIN_COLORS: Array[Color] = [
		Color(0.22, 0.45, 0.18),   # GRASS
		Color(0.14, 0.12, 0.11),   # MALPAIS
		Color(0.78, 0.68, 0.42),   # DUNE
		Color(0.08, 0.30, 0.12),   # LAURISILVA
		Color(0.48, 0.44, 0.40),   # RISCO
		Color(0.10, 0.28, 0.52),   # OCEAN
		Color(0.30, 0.08, 0.04),   # CALDERA
	]
	# Flatten zones into parallel arrays — avoids per-pixel Dictionary access
	var z_count: int = _zones.size()
	var z_cx: PackedFloat32Array = PackedFloat32Array()
	var z_cy: PackedFloat32Array = PackedFloat32Array()
	var z_r2: PackedFloat32Array = PackedFloat32Array()
	var z_t:  PackedInt32Array   = PackedInt32Array()
	z_cx.resize(z_count)
	z_cy.resize(z_count)
	z_r2.resize(z_count)
	z_t.resize(z_count)
	for i: int in range(z_count):
		var z: Dictionary = _zones[i]
		var c: Vector2 = z["center"] as Vector2
		var r: float   = z["radius"] as float
		z_cx[i] = c.x
		z_cy[i] = c.y
		z_r2[i] = r * r
		z_t[i]  = z["type"] as int

	var img: Image = Image.create(resolution, resolution, false, Image.FORMAT_RGB8)
	var world_min: float = -map_half
	var world_size: float = map_half * 2.0
	var ocean_color: Color = TERRAIN_COLORS[TerrainType.OCEAN]

	for py: int in range(resolution):
		var wy: float = world_min + (float(py) + 0.5) / float(resolution) * world_size
		for px: int in range(resolution):
			var wx: float = world_min + (float(px) + 0.5) / float(resolution) * world_size

			# Island map: check if outside all land polygons → ocean
			if _is_island_map:
				var in_land: bool = false
				for poly: Variant in _land_polys:
					if Geometry2D.is_point_in_polygon(Vector2(wx, wy), poly as PackedVector2Array):
						in_land = true
						break
				if not in_land:
					img.set_pixel(px, py, ocean_color)
					continue

			# Walk zones in reverse (last zone = highest priority)
			var terrain: int = TerrainType.GRASS
			var wv: Vector2 = Vector2(wx, wy)
			for i: int in range(z_count - 1, -1, -1):
				var dx: float = wx - z_cx[i]
				var dy: float = wy - z_cy[i]
				if dx * dx + dy * dy <= z_r2[i]:
					terrain = z_t[i]
					break
			img.set_pixel(px, py, TERRAIN_COLORS[terrain])
	minimap_texture = ImageTexture.create_from_image(img)

# Returns the nearest ocean position to world_pos, searching outward in rings.
# Returns Vector2.ZERO if none found within the search radius.
func nearest_ocean(world_pos: Vector2) -> Vector2:
	if is_ocean(world_pos):
		return world_pos
	var step: float = 20.0
	for ring: int in range(1, 40):
		var r: float = step * ring
		var checks: int = maxi(8, ring * 8)
		for i: int in range(checks):
			var a: float = TAU * i / checks
			var candidate: Vector2 = world_pos + Vector2(cos(a), sin(a)) * r
			if is_ocean(candidate):
				return candidate
	return Vector2.ZERO

# Returns true if world_pos is within any of the land polygons.
func _point_in_any_land(p: Vector2) -> bool:
	for poly: Variant in _land_polys:
		if Geometry2D.is_point_in_polygon(p, poly as PackedVector2Array):
			return true
	return false

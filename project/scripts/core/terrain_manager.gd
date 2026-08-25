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

# Canonical display colours — index matches TerrainType int.
# MapGenerator reads these so the minimap always matches the painted terrain.
const COLORS: Array[Color] = [
	Color(0.22, 0.45, 0.18),   # GRASS
	Color(0.12, 0.10, 0.09),   # MALPAIS
	Color(0.78, 0.68, 0.42),   # DUNE
	Color(0.08, 0.28, 0.10),   # LAURISILVA
	Color(0.46, 0.42, 0.38),   # RISCO
	Color(0.10, 0.25, 0.50),   # OCEAN
	Color(0.28, 0.07, 0.04),   # CALDERA
]

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

# LOS fraction kept by a unit under the laurisilva canopy.
const LAURISILVA_VISION_MULT: float = 0.70

# Ocean within this distance of the coast counts as shallow water (GDD M6):
# amphibious units wade it at full speed instead of the deep-water 0.60.
const SHALLOW_WATER_DEPTH: float = 120.0

# Risco vantage (GDD M6): ranged units within this distance of a cliff edge
# gain extra reach. The zone itself is impassable, so the GDD's "units on
# top" translates to "standing beside the cliff".
const RISCO_BONUS_DISTANCE: float = 48.0
# Extra attack range (in tiles, 1 tile = 32 px) granted by the vantage.
const RISCO_RANGE_BONUS_TILES: float = 2.0

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
var _civ_cache: Dictionary = {}  # civ_id -> CivilizationResource

# Ocean polygon points (Islands map only) — Array of PackedVector2Array outlines
# A position is "ocean" if it falls outside all land polygons.
var _land_polys: Array = []    # Array of PackedVector2Array
var _is_island_map: bool = false

# Baked terrain texture — set by MapGenerator after generation completes.
var minimap_texture: ImageTexture = null
# World half-size used when baking — needed by MinimapRenderer for coordinate mapping.
var minimap_map_half: float = 1800.0

func reset() -> void:
	_zones.clear()
	_land_polys.clear()
	_civ_cache.clear()
	_is_island_map = false
	minimap_texture = null

func _get_civ(civ_id: String) -> CivilizationResource:
	if civ_id.is_empty():
		return null
	if _civ_cache.has(civ_id):
		return _civ_cache[civ_id] as CivilizationResource
	var path: String = "res://resources/civilizations/%s.tres" % civ_id
	var civ: CivilizationResource = load(path) as CivilizationResource
	_civ_cache[civ_id] = civ
	return civ

func get_zones() -> Array[Dictionary]:
	return _zones

func get_land_polys() -> Array:
	return _land_polys

func is_island_map() -> bool:
	return _is_island_map

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
	var civ: CivilizationResource = _get_civ(civ_id)
	match t:
		TerrainType.MALPAIS:
			if civ != null and civ.can_traverse_malpais:
				return 1.0
			return SPEED_MULT[TerrainType.MALPAIS]
		TerrainType.DUNE:
			if civ != null and civ.can_traverse_dune:
				return 1.0
			return SPEED_MULT[TerrainType.DUNE]
		TerrainType.OCEAN:
			if civ != null and civ.can_traverse_ocean:
				# Shallows are waded at full speed; deep water swims slowly.
				return 1.0 if is_shallow_water(world_pos) else 0.60
			return 0.0
		_:
			return SPEED_MULT[t]

func is_buildable(world_pos: Vector2) -> bool:
	var t: TerrainType = get_terrain(world_pos)
	return BUILDABLE[t]

# Vision multiplier for a unit standing at world_pos — the laurisilva canopy
# shortens line of sight (GDD M6). Multiplied into the fog-of-war LOS radius.
func get_vision_mult(world_pos: Vector2) -> float:
	if get_terrain(world_pos) == TerrainType.LAURISILVA:
		return LAURISILVA_VISION_MULT
	return 1.0

# True for ocean positions within SHALLOW_WATER_DEPTH of the coastline.
func is_shallow_water(world_pos: Vector2) -> bool:
	return is_ocean(world_pos) and distance_to_coast(world_pos) <= SHALLOW_WATER_DEPTH

# True when world_pos stands beside a risco cliff — within `dist` px of the
# zone edge.
func is_near_risco(world_pos: Vector2, dist: float = RISCO_BONUS_DISTANCE) -> bool:
	for z: Dictionary in _zones:
		if (z["type"] as TerrainType) != TerrainType.RISCO:
			continue
		if world_pos.distance_to(z["center"] as Vector2) <= (z["radius"] as float) + dist:
			return true
	return false

func is_ocean(world_pos: Vector2) -> bool:
	return get_terrain(world_pos) == TerrainType.OCEAN

# Returns true if a unit with given civ_id cannot enter world_pos at all.
func is_impassable_for(world_pos: Vector2, civ_id: String) -> bool:
	var t: TerrainType = get_terrain(world_pos)
	var civ: CivilizationResource = _get_civ(civ_id)
	match t:
		TerrainType.OCEAN:
			return civ == null or not civ.can_traverse_ocean
		TerrainType.RISCO, TerrainType.CALDERA:
			return true
		TerrainType.MALPAIS:
			return civ == null or not civ.can_traverse_malpais
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
	minimap_map_half = map_half
	var TERRAIN_COLORS: Array[Color] = COLORS
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

## Returns the approximate distance in pixels from world_pos to the nearest
## ocean/land boundary. On non-island maps (no ocean) always returns INF.
func distance_to_coast(world_pos: Vector2) -> float:
	# Fast path: on non-island maps there is no coast
	if not _is_island_map and not is_ocean(world_pos):
		# Check whether there are any ocean zones at all
		var has_ocean: bool = false
		for z: Dictionary in _zones:
			if (z["type"] as int) == TerrainType.OCEAN:
				has_ocean = true
				break
		if not has_ocean:
			return INF
	var on_ocean: bool = is_ocean(world_pos)
	# Search outward until we cross the land/ocean boundary
	var step: float = 24.0
	for ring: int in range(1, 32):
		var r: float = step * ring
		var checks: int = maxi(8, ring * 6)
		for i: int in range(checks):
			var a: float = TAU * i / float(checks)
			var candidate: Vector2 = world_pos + Vector2(cos(a), sin(a)) * r
			if is_ocean(candidate) != on_ocean:
				return r
	return INF

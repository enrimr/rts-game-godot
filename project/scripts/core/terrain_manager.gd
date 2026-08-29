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
# amphibious units wade it at full speed instead of the deep-water fraction.
const SHALLOW_WATER_DEPTH: float = 120.0

# Speed kept by an amphibious unit swimming outside the shallow band. Civs may
# override it with a "deep_water_speed" entry in their stat_multipliers.
const DEEP_WATER_SPEED: float = 0.60

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

# Coastal distance is memoized per grid cell of this size, evaluated at the cell
# centre so the answer never depends on which query filled the cell first. The
# sea-fog weather query asks for it once per unit and building ~8 times a second
# and the coast does not move during a match.
const COAST_CACHE_CELL: float = 24.0

# Each zone: { center: Vector2, radius: float, type: TerrainType }
var _zones: Array[Dictionary] = []
var _civ_cache: Dictionary = {}  # civ_id -> CivilizationResource

# Ocean polygon points (Islands map only) — Array of PackedVector2Array outlines
# A position is "ocean" if it falls outside all land polygons.
var _land_polys: Array = []    # Array of PackedVector2Array
var _land_bounds: Array[Rect2] = []   # bounding box per land polygon, same order
var _is_island_map: bool = false

var _coast_cache: Dictionary = {}   # Vector2i cell -> float distance to coast

# Baked terrain texture — set by MapGenerator after generation completes.
var minimap_texture: ImageTexture = null
# World half-size used when baking — needed by MinimapRenderer for coordinate mapping.
var minimap_map_half: float = 1800.0

func reset() -> void:
	_zones.clear()
	_land_polys.clear()
	_land_bounds.clear()
	_civ_cache.clear()
	_coast_cache.clear()
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
	_coast_cache.clear()

## Every mutation of the land-polygon array must come back through here: the
## bounding boxes and the coastal cache are derived from it.
func set_land_polys(polys: Array, is_island: bool) -> void:
	_land_polys = polys
	_is_island_map = is_island
	_land_bounds.clear()
	for poly: Variant in polys:
		_land_bounds.append(_outline_bounds(poly as PackedVector2Array))
	_coast_cache.clear()

func _outline_bounds(outline: PackedVector2Array) -> Rect2:
	if outline.is_empty():
		return Rect2()
	var bounds: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for i: int in range(1, outline.size()):
		bounds = bounds.expand(outline[i])
	# Rect2.has_point excludes the right/bottom edge; keep boundary points inside.
	return bounds.grow(1.0)

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
# `amphibious` is the unit's own capability (UnitBase.is_amphibious): the civ flag
# alone is not enough, or every Atlantes land unit would count as a swimmer.
func get_speed_mult(world_pos: Vector2, civ_id: String, amphibious: bool = false) -> float:
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
			if amphibious:
				# Shallows are waded at full speed; deep water swims slowly.
				return 1.0 if is_shallow_water(world_pos) else deep_water_speed(civ_id)
			return 0.0
		_:
			return SPEED_MULT[t]

## Swim speed fraction in deep water for `civ_id`. Read straight off the civ
## resource rather than through CivBonusManager: this is a terrain query with no
## player_id in scope, and no technology touches the number.
func deep_water_speed(civ_id: String) -> float:
	var civ: CivilizationResource = _get_civ(civ_id)
	if civ == null:
		return DEEP_WATER_SPEED
	return civ.stat_multipliers.get("deep_water_speed", DEEP_WATER_SPEED) as float

## True when `civ_id` is allowed to field units that enter water at all. The unit
## still has to declare itself amphibious — this is the civ-level gate.
func civ_can_traverse_ocean(civ_id: String) -> bool:
	var civ: CivilizationResource = _get_civ(civ_id)
	return civ != null and civ.can_traverse_ocean

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
# Water is only open to units that declare themselves amphibious (see
# UnitBase.is_amphibious); ordering a regular land unit into the sea has to fail
# here, or its nav target lands off the mesh and the unit freezes on the spot.
func is_impassable_for(world_pos: Vector2, civ_id: String, amphibious: bool = false) -> bool:
	var t: TerrainType = get_terrain(world_pos)
	var civ: CivilizationResource = _get_civ(civ_id)
	match t:
		TerrainType.OCEAN:
			return not amphibious
		TerrainType.RISCO, TerrainType.CALDERA:
			return true
		TerrainType.MALPAIS:
			return civ == null or not civ.can_traverse_malpais
		_:
			return false

# Returns the nearest passable position to world_pos for a unit with given civ_id.
# Searches outward in concentric rings until a passable tile is found.
# Returns world_pos itself if it is already passable (fast path).
func nearest_passable(world_pos: Vector2, civ_id: String, amphibious: bool = false) -> Vector2:
	if not is_impassable_for(world_pos, civ_id, amphibious):
		return world_pos
	var step: float = 24.0
	for ring: int in range(1, 30):
		var r: float = step * ring
		var checks: int = maxi(8, ring * 8)
		for i: int in range(checks):
			var a: float = TAU * i / checks
			var candidate: Vector2 = world_pos + Vector2(cos(a), sin(a)) * r
			if not is_impassable_for(candidate, civ_id, amphibious):
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
	for i: int in range(_land_polys.size()):
		# Bounding-box reject first: is_ocean() runs per unit per frame and the
		# polygon test walks every vertex of every island.
		if i < _land_bounds.size() and not _land_bounds[i].has_point(p):
			continue
		if Geometry2D.is_point_in_polygon(p, _land_polys[i] as PackedVector2Array):
			return true
	return false

## Returns the distance in pixels from world_pos to the nearest ocean/land
## boundary, INF on a map without any coast. Memoized per COAST_CACHE_CELL cell.
func distance_to_coast(world_pos: Vector2) -> float:
	var key: Vector2i = Vector2i(
		floori(world_pos.x / COAST_CACHE_CELL), floori(world_pos.y / COAST_CACHE_CELL))
	if _coast_cache.has(key):
		return _coast_cache[key] as float
	var cell_center: Vector2 = (Vector2(key) + Vector2(0.5, 0.5)) * COAST_CACHE_CELL
	var d: float = _compute_distance_to_coast(cell_center)
	_coast_cache[key] = d
	return d

# The coastline is the land outlines on island maps and the ocean-zone circles on
# coastal maps, so the distance is analytic. This used to be an outward ring
# search probing is_ocean() up to ~3000 times per call (1.8 ms each): with sea
# fog active the weather query ran it for every unit and building 8 times a
# second, which alone cost more than a frame budget per frame.
func _compute_distance_to_coast(world_pos: Vector2) -> float:
	var best: float = INF
	for poly: Variant in _land_polys:
		var outline: PackedVector2Array = poly as PackedVector2Array
		var n: int = outline.size()
		if n < 2:
			continue
		for i: int in range(n):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				world_pos, outline[i], outline[(i + 1) % n])
			best = minf(best, world_pos.distance_to(closest))
	for z: Dictionary in _zones:
		if (z["type"] as int) != TerrainType.OCEAN:
			continue
		best = minf(best, absf(
			world_pos.distance_to(z["center"] as Vector2) - (z["radius"] as float)))
	return best

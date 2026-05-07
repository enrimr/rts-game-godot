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

func reset() -> void:
	_zones.clear()
	_land_polys.clear()
	_is_island_map = false

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

# Returns true if world_pos is within any of the land polygons.
func _point_in_any_land(p: Vector2) -> bool:
	for poly: Variant in _land_polys:
		if Geometry2D.is_point_in_polygon(p, poly as PackedVector2Array):
			return true
	return false

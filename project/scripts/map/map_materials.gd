class_name MapMaterials extends RefCounted

## Shared shader materials and visual tuning for generated terrain.
##
## One instance is created per map generation and reused across every terrain /
## ocean polygon, so a map with hundreds of patches still allocates a handful of
## ShaderMaterials. Getters are lazy: a material only exists once a painter asks
## for it.

const WATER_SHADER: Shader = preload("res://assets/shaders/water.gdshader")
const TERRAIN_SHADER: Shader = preload("res://assets/shaders/terrain.gdshader")
const LAVA_SHADER: Shader = preload("res://assets/shaders/lava.gdshader")

# Terrain types whose edges get a soft fade-out halo into neighbouring ground.
# Contrasting, impassable special zones — grass/dune backgrounds are excluded.
const GRADIENT_TERRAINS: Array = [
	TerrainManager.TerrainType.MALPAIS,
	TerrainManager.TerrainType.CALDERA,
	TerrainManager.TerrainType.RISCO,
	TerrainManager.TerrainType.LAURISILVA,
]

# Grain/variation tuning per terrain type: rougher surfaces get more grain.
# `mottle`/`dirt_amount` drive the shader's tile checker: only the open ground
# types (grass, dune) swap cells toward the dry-dirt tint.
const TERRAIN_SHADER_PARAMS: Dictionary = {
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

var _terrain: ShaderMaterial = null
var _water: ShaderMaterial = null
var _shallow: ShaderMaterial = null
var _lava: ShaderMaterial = null
# Per-terrain-type base material (grain/variation tuned to the surface).
var _terrain_by_type: Dictionary = {}

## Canonical display colour of a terrain type — the same table the minimap bakes
## from, so painted ground and minimap always agree.
static func color_for(t: TerrainManager.TerrainType) -> Color:
	return TerrainManager.COLORS[t]

func terrain() -> ShaderMaterial:
	if _terrain == null:
		_terrain = ShaderMaterial.new()
		_terrain.shader = TERRAIN_SHADER
	return _terrain

# Returns a shared terrain material tuned for `terrain_type`, or the default
# grass-tuned one when the type has no specific entry.
func terrain_for(terrain_type: int) -> ShaderMaterial:
	if not TERRAIN_SHADER_PARAMS.has(terrain_type):
		return terrain()
	if _terrain_by_type.has(terrain_type):
		return _terrain_by_type[terrain_type] as ShaderMaterial
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	var params: Dictionary = TERRAIN_SHADER_PARAMS[terrain_type] as Dictionary
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	_terrain_by_type[terrain_type] = mat
	return mat

func water() -> ShaderMaterial:
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
	return _water

# Brighter, choppier water tuning for the coastal shelf: shoals read turquoise
# with more visible foam than the open deep-blue ocean.
func shallow() -> ShaderMaterial:
	if _shallow == null:
		_shallow = ShaderMaterial.new()
		_shallow.shader = WATER_SHADER
		_shallow.set_shader_parameter("water_deep", Color(0.10, 0.36, 0.55))
		_shallow.set_shader_parameter("water_shallow", Color(0.30, 0.64, 0.72))
		_shallow.set_shader_parameter("foam_amount", 0.30)
		_shallow.set_shader_parameter("wave_scale", 0.016)
		_shallow.set_shader_parameter("wave_speed", 0.75)
	return _shallow

func lava() -> ShaderMaterial:
	if _lava == null:
		_lava = ShaderMaterial.new()
		_lava.shader = LAVA_SHADER
	return _lava

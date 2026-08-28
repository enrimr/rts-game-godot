extends GutTest

## MapMaterials — shared shader materials for generated terrain.
##
## What is covered:
##   1.  color_for agrees with the table the minimap bakes from.
##   2.  Getters are lazy and cached: one ShaderMaterial per kind, not per call.
##   3.  terrain_for applies the per-type tuning, and falls back to the default
##       material for types with no entry (ocean is painted by water()).
##   4.  The shallow-water variant really is tuned differently from open ocean.

var _mat: MapMaterials = null

func before_each() -> void:
	_mat = MapMaterials.new()

# 1 — colours come from the single source of truth
func test_color_for_matches_terrain_manager() -> void:
	for t: int in range(TerrainManager.COLORS.size()):
		assert_eq(MapMaterials.color_for(t as TerrainManager.TerrainType),
			TerrainManager.COLORS[t],
			"painted ground and minimap must use the same colour")

# 2 — caching
func test_materials_are_cached() -> void:
	assert_same(_mat.terrain(), _mat.terrain(), "terrain material is built once")
	assert_same(_mat.water(), _mat.water(), "water material is built once")
	assert_same(_mat.lava(), _mat.lava(), "lava material is built once")
	assert_same(_mat.terrain_for(TerrainManager.TerrainType.GRASS),
		_mat.terrain_for(TerrainManager.TerrainType.GRASS),
		"per-type terrain material is built once")

func test_materials_use_expected_shaders() -> void:
	assert_same(_mat.terrain().shader, MapMaterials.TERRAIN_SHADER)
	assert_same(_mat.water().shader, MapMaterials.WATER_SHADER)
	assert_same(_mat.shallow().shader, MapMaterials.WATER_SHADER)
	assert_same(_mat.lava().shader, MapMaterials.LAVA_SHADER)

# 3 — per-type tuning
func test_terrain_for_applies_tuning() -> void:
	var grass: ShaderMaterial = _mat.terrain_for(TerrainManager.TerrainType.GRASS)
	var expected: Dictionary = MapMaterials.TERRAIN_SHADER_PARAMS[TerrainManager.TerrainType.GRASS] as Dictionary
	for key: String in expected:
		assert_eq(grass.get_shader_parameter(key), expected[key],
			"grass terrain material carries its tuned '%s'" % key)

func test_terrain_for_distinguishes_types() -> void:
	assert_ne(_mat.terrain_for(TerrainManager.TerrainType.GRASS),
		_mat.terrain_for(TerrainManager.TerrainType.MALPAIS),
		"rougher surfaces get their own material")

func test_terrain_for_unknown_type_falls_back() -> void:
	assert_same(_mat.terrain_for(TerrainManager.TerrainType.OCEAN), _mat.terrain(),
		"ocean has no terrain tuning — it is painted with water()")

# 4 — shallow vs deep water
func test_shallow_water_is_tuned_apart_from_ocean() -> void:
	var shallow: ShaderMaterial = _mat.shallow()
	assert_ne(shallow, _mat.water(), "shoals and open ocean are separate materials")
	assert_gt(shallow.get_shader_parameter("foam_amount") as float, 0.0,
		"shoals show foam")
	assert_null(_mat.water().get_shader_parameter("foam_amount"),
		"open ocean keeps the shader defaults")

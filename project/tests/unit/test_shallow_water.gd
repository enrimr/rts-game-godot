extends GutTest

## Shallow water (GDD M6): ocean within SHALLOW_WATER_DEPTH of the coastline.
## Amphibious *units* (UnitBase.is_amphibious — the Atlantes Tidecaller and every
## ship) wade shallows at full speed and swim deep water at the civ's
## "deep_water_speed"; everything else is blocked, including the rest of the
## Atlantes army.
##
## Uses an island map: a square land polygon centred on the origin, so any
## point outside it is OCEAN and the coast sits on the square's edge.

const LAND_HALF: float = 400.0
const SHALLOW: Vector2 = Vector2(LAND_HALF + 50.0, 0.0)
const DEEP: Vector2 = Vector2(LAND_HALF + 500.0, 0.0)

func before_each() -> void:
	TerrainManager.reset()
	var poly: PackedVector2Array = PackedVector2Array([
		Vector2(-LAND_HALF, -LAND_HALF), Vector2(LAND_HALF, -LAND_HALF),
		Vector2(LAND_HALF, LAND_HALF), Vector2(-LAND_HALF, LAND_HALF),
	])
	TerrainManager.set_land_polys([poly], true)

func after_each() -> void:
	TerrainManager.reset()

# 1 — shallow band geometry
func test_shallow_band() -> void:
	assert_true(TerrainManager.is_shallow_water(SHALLOW), "50 px off the coast is shallow")
	assert_false(TerrainManager.is_shallow_water(DEEP), "500 px offshore is deep water")
	assert_false(TerrainManager.is_shallow_water(Vector2.ZERO), "land is never shallow water")

# 2 — amphibious unit speeds
func test_amphibious_wades_shallow_at_full_speed() -> void:
	assert_eq(TerrainManager.get_speed_mult(SHALLOW, "atlantes", true), 1.0,
		"an amphibious unit wades the shallows at full speed")
	assert_eq(TerrainManager.get_speed_mult(DEEP, "atlantes", true), 0.60,
		"deep water still slows amphibious units")
	assert_false(TerrainManager.is_impassable_for(DEEP, "atlantes", true),
		"open water is passable for an amphibious unit")

# 3 — the civ bonus alone does not put a land unit in the water
func test_atlantes_land_units_stay_dry() -> void:
	assert_eq(TerrainManager.get_speed_mult(SHALLOW, "atlantes"), 0.0,
		"an Atlantes footman is still a land unit")
	assert_true(TerrainManager.is_impassable_for(SHALLOW, "atlantes"),
		"ordering a land unit into the surf must fail, or its nav target goes off-mesh")
	assert_false(TerrainManager.is_ocean(TerrainManager.nearest_passable(SHALLOW, "atlantes")),
		"the destination is clamped back onto the beach")

# 4 — land civs remain blocked everywhere in the ocean
func test_land_civ_blocked_in_shallow() -> void:
	assert_eq(TerrainManager.get_speed_mult(SHALLOW, "guanches"), 0.0,
		"shallow water does not open the ocean to land units")
	assert_true(TerrainManager.is_impassable_for(SHALLOW, "guanches"))

# 5 — the deep-water speed is civ data, not a constant in the script
func test_deep_water_speed_is_data_driven() -> void:
	assert_eq(TerrainManager.deep_water_speed("atlantes"), 0.60,
		"atlantes.tres declares deep_water_speed")
	assert_eq(TerrainManager.deep_water_speed("guanches"), TerrainManager.DEEP_WATER_SPEED,
		"civs without the key fall back to the default")
	assert_eq(TerrainManager.deep_water_speed(""), TerrainManager.DEEP_WATER_SPEED,
		"an unknown civ falls back to the default")

# 6 — only the civ flagged can_traverse_ocean may field amphibious units
func test_civ_gate() -> void:
	assert_true(TerrainManager.civ_can_traverse_ocean("atlantes"))
	assert_false(TerrainManager.civ_can_traverse_ocean("guanches"))
	assert_false(TerrainManager.civ_can_traverse_ocean(""))

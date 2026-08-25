extends GutTest

## Shallow water (GDD M6): ocean within SHALLOW_WATER_DEPTH of the coastline.
## Amphibious civs (can_traverse_ocean, i.e. Atlantes) wade shallows at full
## speed and swim deep water at the 0.60 multiplier; land civs stay blocked.
##
## Uses an island map: a square land polygon centred on the origin, so any
## point outside it is OCEAN and the coast sits on the square's edge.

const LAND_HALF: float = 400.0

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
	assert_true(TerrainManager.is_shallow_water(Vector2(LAND_HALF + 50.0, 0.0)),
		"50 px off the coast is shallow")
	assert_false(TerrainManager.is_shallow_water(Vector2(LAND_HALF + 500.0, 0.0)),
		"500 px offshore is deep water")
	assert_false(TerrainManager.is_shallow_water(Vector2.ZERO), "land is never shallow water")

# 2 — amphibious civ speeds
func test_amphibious_wades_shallow_at_full_speed() -> void:
	assert_eq(TerrainManager.get_speed_mult(Vector2(LAND_HALF + 50.0, 0.0), "atlantes"), 1.0,
		"Atlantes are immune to the shallow-water penalty")
	assert_eq(TerrainManager.get_speed_mult(Vector2(LAND_HALF + 500.0, 0.0), "atlantes"), 0.60,
		"deep water still slows amphibious units")

# 3 — land civs remain blocked everywhere in the ocean
func test_land_civ_blocked_in_shallow() -> void:
	assert_eq(TerrainManager.get_speed_mult(Vector2(LAND_HALF + 50.0, 0.0), "guanches"), 0.0,
		"shallow water does not open the ocean to land units")
	assert_true(TerrainManager.is_impassable_for(Vector2(LAND_HALF + 50.0, 0.0), "guanches"))

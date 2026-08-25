extends GutTest

## Risco cliff vantage (GDD M6): ranged (PIERCE) units standing within
## RISCO_BONUS_DISTANCE of a risco zone edge gain RISCO_RANGE_BONUS_TILES of
## extra attack reach. The zone itself is impassable, so the GDD's "units on
## top" is implemented as "standing beside the cliff".
##
## What is covered:
##   1.  TerrainManager.is_near_risco geometry: edge band in/out, other zones.
##   2.  An archer's _attack_reach_to grows by the bonus beside a cliff.
##   3.  A melee unit gets nothing from the vantage.

const ARCHER_SCENE:  PackedScene = preload("res://scenes/units/archer.tscn")
const MILITIA_SCENE: PackedScene = preload("res://scenes/units/militia.tscn")

func before_each() -> void:
	TerrainManager.reset()

func after_each() -> void:
	TerrainManager.reset()

func _add_risco(center: Vector2, radius: float) -> void:
	TerrainManager.add_zone(center, radius, TerrainManager.TerrainType.RISCO)

# 1 — geometry of the vantage band
func test_near_risco_band() -> void:
	_add_risco(Vector2.ZERO, 100.0)
	var reach: float = 100.0 + TerrainManager.RISCO_BONUS_DISTANCE
	assert_true(TerrainManager.is_near_risco(Vector2(reach - 1.0, 0.0)), "inside the band")
	assert_false(TerrainManager.is_near_risco(Vector2(reach + 1.0, 0.0)), "outside the band")

func test_other_zones_grant_no_vantage() -> void:
	TerrainManager.add_zone(Vector2.ZERO, 100.0, TerrainManager.TerrainType.MALPAIS)
	assert_false(TerrainManager.is_near_risco(Vector2(50.0, 0.0)))

func test_no_zones_no_vantage() -> void:
	assert_false(TerrainManager.is_near_risco(Vector2.ZERO))

# 2 — archer reach grows beside the cliff
func test_archer_reach_bonus_beside_cliff() -> void:
	var archer: UnitBase = ARCHER_SCENE.instantiate() as UnitBase
	add_child_autofree(archer)
	archer.global_position = Vector2(2000.0, 0.0)
	var base_reach: float = archer._attack_reach_to(null)
	_add_risco(Vector2(2000.0, 120.0), 100.0)   # edge 20 px away — inside the band
	var cliff_reach: float = archer._attack_reach_to(null)
	assert_almost_eq(cliff_reach - base_reach, TerrainManager.RISCO_RANGE_BONUS_TILES * 32.0, 0.01,
		"the vantage adds exactly the bonus tiles")

# 3 — melee units gain nothing
func test_melee_gets_no_bonus() -> void:
	var militia: UnitBase = MILITIA_SCENE.instantiate() as UnitBase
	add_child_autofree(militia)
	militia.global_position = Vector2(2000.0, 0.0)
	var base_reach: float = militia._attack_reach_to(null)
	_add_risco(Vector2(2000.0, 120.0), 100.0)
	assert_eq(militia._attack_reach_to(null), base_reach, "melee reach is unchanged beside a cliff")

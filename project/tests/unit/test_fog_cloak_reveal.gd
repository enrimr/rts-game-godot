extends GutTest

## Sea-fog stealth: who the fog is allowed to hide.
##
## The cloak used to hide every enemy unit inside the coastal band (400 px from
## any shore) regardless of line of sight. On an Islands map the whole map is
## coastal, so whole armies vanished even while standing next to your own units.
## Two things now break the cloak: standing within WeatherManager.fog_spot_range
## of one of your units/buildings, and attacking (firing gives you away). The
## Atlantes hide better — their "fog_stealth" multiplier shrinks the spot range.

const LAND_HALF: float = 400.0
# In the ocean but inside the 400 px coastal band, so sea fog applies.
const ENEMY_POS: Vector2 = Vector2(500.0, 0.0)

class UnitDouble extends Node2D:
	var player_id: int = 1
	var revealed: bool = false
	func is_revealed_by_combat() -> bool:
		return revealed

var _fow: FogOfWar = null
var _units: Node2D = null

func before_each() -> void:
	TerrainManager.reset()
	TerrainManager.set_land_polys([PackedVector2Array([
		Vector2(-LAND_HALF, -LAND_HALF), Vector2(LAND_HALF, -LAND_HALF),
		Vector2(LAND_HALF, LAND_HALF), Vector2(-LAND_HALF, LAND_HALF),
	])], true)
	WeatherManager.current_weather = WeatherManager.WeatherType.SEA_FOG
	WeatherManager.intensity = 1.0
	# CivBonusManager is an autoload and keeps state between tests: pin the enemy
	# to a civ without a fog bonus so only the Atlantes test sees the tighter range.
	CivBonusManager.init_player(1, "franks")

	_units = Node2D.new()
	add_child_autofree(_units)
	_fow = FogOfWar.new()
	add_child_autofree(_fow)
	_fow._units_node = _units

func after_each() -> void:
	WeatherManager.current_weather = WeatherManager.WeatherType.CLEAR
	WeatherManager.intensity = 0.0
	TerrainManager.reset()

func _add_unit(pos: Vector2, pid: int) -> UnitDouble:
	var u: UnitDouble = UnitDouble.new()
	u.player_id = pid
	_units.add_child(u)
	u.global_position = pos
	return u

## Runs one visibility pass over a fully-lit map, so the only thing that can hide
## the enemy is the fog cloak.
func _visibility_of(enemy: Node2D) -> bool:
	_fow.reveal_all()
	_fow._apply_visibility()
	return enemy.visible

# 1 — the mechanic itself: fog still hides an unescorted enemy
func test_enemy_alone_in_the_fog_stays_hidden() -> void:
	var enemy: UnitDouble = _add_unit(ENEMY_POS, 1)
	_add_unit(ENEMY_POS + Vector2(0.0, 900.0), 0)  # own unit, far away
	assert_false(_visibility_of(enemy), "an enemy deep in the fog bank is invisible")

# 2 — but never the one standing right in front of you
func test_enemy_next_to_an_own_unit_is_spotted() -> void:
	var enemy: UnitDouble = _add_unit(ENEMY_POS, 1)
	_add_unit(ENEMY_POS + Vector2(0.0, 100.0), 0)
	assert_true(_visibility_of(enemy), "100 px is inside the 180 px spot range")

# 3 — attacking gives the position away
func test_attacking_enemy_is_revealed() -> void:
	var enemy: UnitDouble = _add_unit(ENEMY_POS, 1)
	enemy.revealed = true
	_add_unit(ENEMY_POS + Vector2(0.0, 900.0), 0)
	assert_true(_visibility_of(enemy), "a unit that just struck cannot stay cloaked")

# 4 — Atlantes have to be found at closer quarters
func test_atlantes_hide_closer_in() -> void:
	CivBonusManager.init_player(1, "atlantes")
	CivBonusManager.init_player(2, "franks")
	var atlantes: UnitDouble = _add_unit(ENEMY_POS, 1)
	var franks: UnitDouble = _add_unit(ENEMY_POS + Vector2(60.0, 0.0), 2)
	# 140 px from both: inside the default spot range, outside the Atlantes' half.
	_add_unit(ENEMY_POS + Vector2(30.0, 140.0), 0)
	_fow.reveal_all()
	_fow._apply_visibility()
	assert_true(franks.visible, "any other civ is spotted at 140 px")
	assert_false(atlantes.visible, "the Atlantes are still hidden at 140 px")

func test_spot_range_is_civ_scaled() -> void:
	CivBonusManager.init_player(1, "atlantes")
	assert_eq(WeatherManager.fog_spot_range(1), WeatherManager.FOG_SPOT_RANGE * 0.5,
		"the Atlantes fog_stealth multiplier halves the spot range")
	assert_eq(WeatherManager.fog_spot_range(99), WeatherManager.FOG_SPOT_RANGE,
		"civs without the bonus use the default range")

# 5 — no fog, no cloak, whatever the distance
func test_clear_weather_hides_nobody() -> void:
	WeatherManager.current_weather = WeatherManager.WeatherType.CLEAR
	WeatherManager.intensity = 0.0
	var enemy: UnitDouble = _add_unit(ENEMY_POS, 1)
	assert_true(_visibility_of(enemy), "without sea fog the coastal band means nothing")

# 6 — own buildings watch too, not just units
func test_own_building_spots_the_fog() -> void:
	var buildings: Node2D = Node2D.new()
	add_child_autofree(buildings)
	_fow._buildings_node = buildings
	var tower: UnitDouble = UnitDouble.new()   # doubles as a building: player_id + position
	tower.player_id = 0
	buildings.add_child(tower)
	tower.global_position = ENEMY_POS + Vector2(0.0, 120.0)
	var enemy: UnitDouble = _add_unit(ENEMY_POS, 1)
	assert_true(_visibility_of(enemy), "a garrisoned shore is not blind in its own fog")

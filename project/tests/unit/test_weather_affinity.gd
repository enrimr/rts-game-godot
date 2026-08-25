extends GutTest

## Civ × weather affinity — penalties are scaled per-civ via
## CivBonusManager.get_weather_resistance + CivilizationResource.weather_affinity.
##
## What is covered:
##   1.  Unknown / unset player (incl. -1) returns full penalty (resistance 1.0).
##   2.  A civ with no weather_affinity returns 1.0 for any weather.
##   3.  An affinity of 0.0 means immune; 0.5 means half penalty.
##   4.  Affinity is per-weather: a key only affects its own weather id.
##   5.  Shipped civ data carries the designed affinities (guanches/atlantes…).
##   6.  CivilizationResource defaults weather_affinity to an empty dict.

const CIVRES := preload("res://resources/civilizations/civilization_resource.gd")

# A throwaway player id unlikely to collide with a running match.
const P := 9001

func after_each() -> void:
	# CivBonusManager is an autoload; clear our scratch player so tests don't leak.
	if CivBonusManager._weather_affinity.has(P):
		CivBonusManager._weather_affinity.erase(P)
	if CivBonusManager._multipliers.has(P):
		CivBonusManager._multipliers.erase(P)

func _set_affinity(aff: Dictionary) -> void:
	CivBonusManager._weather_affinity[P] = aff

# 1 — unknown/unset players take the full penalty
func test_unknown_player_full_penalty() -> void:
	assert_eq(CivBonusManager.get_weather_resistance(-1, "calima"), 1.0, "player -1 must be full penalty")
	assert_eq(CivBonusManager.get_weather_resistance(P, "calima"), 1.0, "unset player must be full penalty")

# 2 — a civ without affinity entries is unaffected
func test_no_affinity_is_full_penalty() -> void:
	_set_affinity({})
	assert_eq(CivBonusManager.get_weather_resistance(P, "calima"), 1.0)
	assert_eq(CivBonusManager.get_weather_resistance(P, "atlantic_storm"), 1.0)

# 3 — immunity and partial resistance
func test_immune_and_partial() -> void:
	_set_affinity({"calima": 0.0, "volcanic_ash": 0.5})
	assert_eq(CivBonusManager.get_weather_resistance(P, "calima"), 0.0, "0.0 = immune")
	assert_eq(CivBonusManager.get_weather_resistance(P, "volcanic_ash"), 0.5, "0.5 = half penalty")

# 4 — affinity is per-weather, not global
func test_affinity_is_per_weather() -> void:
	_set_affinity({"calima": 0.0})
	assert_eq(CivBonusManager.get_weather_resistance(P, "calima"), 0.0)
	assert_eq(CivBonusManager.get_weather_resistance(P, "sea_fog"), 1.0, "unlisted weather keeps full penalty")

# 5 — shipped data matches the design
func test_shipped_affinities() -> void:
	var guanches: CivilizationResource = load("res://resources/civilizations/guanches.tres") as CivilizationResource
	var atlantes: CivilizationResource = load("res://resources/civilizations/atlantes.tres") as CivilizationResource
	var britons: CivilizationResource  = load("res://resources/civilizations/britons.tres")  as CivilizationResource
	var canarii: CivilizationResource  = load("res://resources/civilizations/canarii.tres")  as CivilizationResource
	var castellanos: CivilizationResource = load("res://resources/civilizations/castellanos.tres") as CivilizationResource
	var franks: CivilizationResource   = load("res://resources/civilizations/franks.tres")   as CivilizationResource
	assert_eq(guanches.weather_affinity.get("calima", 1.0), 0.0, "Guanches immune to calima")
	assert_eq(guanches.weather_affinity.get("volcanic_ash", 1.0), 0.5, "Guanches half ash penalty")
	assert_eq(atlantes.weather_affinity.get("atlantic_storm", 1.0), 0.0, "Atlantes immune to storm at sea")
	assert_eq(britons.weather_affinity.get("atlantic_storm", 1.0), 0.5, "Britons half storm penalty")
	assert_eq(canarii.weather_affinity.get("sea_fog", 1.0), 0.5, "Canarii half sea-fog penalty")
	assert_eq(canarii.weather_affinity.get("trade_winds", 1.0), 0.5, "Canarii half headwind penalty")
	assert_eq(castellanos.weather_affinity.get("calima", 1.0), 0.5, "Castellanos half calima penalty")
	assert_eq(franks.weather_affinity.size(), 0, "Franks are the neutral continental baseline")

# 6 — resource default
func test_resource_default_empty() -> void:
	var c: CivilizationResource = CIVRES.new()
	assert_eq((c.weather_affinity as Dictionary).size(), 0, "weather_affinity defaults to empty")

extends GutTest

## Volcanic ash is spatial — tied to the map's CALDERA zones instead of
## covering the whole map (WeatherManager._in_volcanic_zone).
##
## What is covered:
##   1.  Points inside a caldera and within VOLCANIC_ZONE_RADIUS of its edge
##       are in the volcanic zone; farther points are not.
##   2.  Every caldera on the map projects its own ash zone.
##   3.  A map with no caldera keeps the legacy whole-map behaviour.
##   4.  VOLCANIC_ASH can only be rolled on Volcanic Coast maps.
##   5.  The spatial gate reaches the stat queries: same weather, same civ,
##       different position → different gather/vision/building-damage result.

var _saved_map_type: int

func before_each() -> void:
	_saved_map_type = MatchConfig.map_type
	TerrainManager.reset()

func after_each() -> void:
	MatchConfig.map_type = _saved_map_type
	TerrainManager.reset()
	WeatherManager.current_weather = WeatherManager.WeatherType.CLEAR
	WeatherManager.intensity = 0.0

func _add_caldera(center: Vector2, radius: float) -> void:
	TerrainManager.add_zone(center, radius, TerrainManager.TerrainType.CALDERA)

# 1 — zone boundary around a single caldera
func test_zone_bounded_by_caldera_radius() -> void:
	_add_caldera(Vector2.ZERO, 300.0)
	var reach: float = 300.0 + WeatherManager.VOLCANIC_ZONE_RADIUS
	assert_true(WeatherManager._in_volcanic_zone(Vector2.ZERO), "caldera centre is in the zone")
	assert_true(WeatherManager._in_volcanic_zone(Vector2(reach - 1.0, 0.0)), "just inside the edge reach")
	assert_false(WeatherManager._in_volcanic_zone(Vector2(reach + 1.0, 0.0)), "just outside the edge reach")
	assert_false(WeatherManager._in_volcanic_zone(Vector2(0.0, -reach - 500.0)), "far away is safe")

# 2 — multiple calderas each project ash
func test_every_caldera_projects_ash() -> void:
	_add_caldera(Vector2(-2000.0, 0.0), 200.0)
	_add_caldera(Vector2(2000.0, 0.0), 200.0)
	assert_true(WeatherManager._in_volcanic_zone(Vector2(-2000.0, 0.0)))
	assert_true(WeatherManager._in_volcanic_zone(Vector2(2000.0, 0.0)))
	assert_false(WeatherManager._in_volcanic_zone(Vector2.ZERO), "midpoint between distant calderas is safe")

# 3 — non-caldera zones don't count; no caldera at all = whole-map fallback
func test_no_caldera_falls_back_to_whole_map() -> void:
	TerrainManager.add_zone(Vector2.ZERO, 300.0, TerrainManager.TerrainType.MALPAIS)
	assert_true(WeatherManager._in_volcanic_zone(Vector2(9999.0, 9999.0)),
		"a calderaless map keeps the legacy whole-map ash so an active event is never a no-op")

# 4 — ash is only rolled on volcanic maps
func test_ash_restricted_to_volcanic_coast() -> void:
	MatchConfig.map_type = MatchConfig.MapType.VOLCANIC_COAST
	assert_true(WeatherManager._is_allowed_on_current_map(WeatherManager.WeatherType.VOLCANIC_ASH))
	MatchConfig.map_type = MatchConfig.MapType.PLAINS
	assert_false(WeatherManager._is_allowed_on_current_map(WeatherManager.WeatherType.VOLCANIC_ASH))
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	assert_false(WeatherManager._is_allowed_on_current_map(WeatherManager.WeatherType.VOLCANIC_ASH))

# 5 — the spatial gate is honoured by the stat query API
func test_stat_queries_respect_zone() -> void:
	_add_caldera(Vector2.ZERO, 300.0)
	WeatherManager.current_weather = WeatherManager.WeatherType.VOLCANIC_ASH
	WeatherManager.intensity = 1.0
	var inside: Vector2 = Vector2.ZERO
	var outside: Vector2 = Vector2(300.0 + WeatherManager.VOLCANIC_ZONE_RADIUS + 100.0, 0.0)
	assert_eq(WeatherManager.get_gather_rate_multiplier("food", inside), 0.7, "gather penalised inside")
	assert_eq(WeatherManager.get_gather_rate_multiplier("food", outside), 1.0, "gather untouched outside")
	assert_eq(WeatherManager.get_vision_multiplier(inside), 0.5, "vision penalised inside")
	assert_eq(WeatherManager.get_vision_multiplier(outside), 1.0, "vision untouched outside")
	assert_eq(WeatherManager.get_building_damage_rate(inside), 2.0, "buildings drain inside")
	assert_eq(WeatherManager.get_building_damage_rate(outside), 0.0, "buildings safe outside")

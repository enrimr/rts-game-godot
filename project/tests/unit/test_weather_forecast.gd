extends GutTest

## Weather forecast: a "forecast" phase now warns the player before a weather
## event ramps in (weather_incoming), and the weather stays inactive during the
## warning. Full timing is verified manually in-game (incoming → FORECAST_TIME →
## changed); here we pin the public contract so it can't regress silently.

func test_forecast_constant_exists() -> void:
	assert_true(WeatherManager.FORECAST_TIME > 0.0,
		"FORECAST_TIME must be a positive warning window")

func test_weather_incoming_signal_exists() -> void:
	assert_true(WeatherManager.has_signal("weather_incoming"),
		"WeatherManager must expose weather_incoming(weather_id, seconds_until)")

# weather_id_of maps every type to a stable string (used by the forecast emit,
# which must work even though current_weather is still CLEAR at that point).
func test_weather_id_mapping() -> void:
	assert_eq(WeatherManager._weather_id_of(WeatherManager.WeatherType.CALIMA), "calima")
	assert_eq(WeatherManager._weather_id_of(WeatherManager.WeatherType.ATLANTIC_STORM), "atlantic_storm")
	assert_eq(WeatherManager._weather_id_of(WeatherManager.WeatherType.CLEAR), "clear")

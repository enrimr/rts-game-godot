extends GutTest

## NetworkSession pure parts: the lobby config snapshot must round-trip so
## every machine simulates the identical match, and an offline session must
## leave the CommandBus executing locally (all other suites depend on it).

func after_each() -> void:
	MatchConfig.forced_seed = 0

func test_config_snapshot_round_trips() -> void:
	MatchConfig.forced_seed = 987654
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	MatchConfig.map_size = MatchConfig.MapSize.LARGE
	MatchConfig.player_civ_id = "atlantes"
	MatchConfig.rival_civ_ids = ["fenicios"] as Array[String]
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	MatchConfig.weather_enabled = false
	var cfg: Dictionary = NetworkSession.snapshot_config()

	MatchConfig.forced_seed = 0
	MatchConfig.map_type = MatchConfig.MapType.PLAINS
	MatchConfig.player_civ_id = "guanches"
	MatchConfig.weather_enabled = true
	NetworkSession.apply_config(cfg)

	assert_eq(MatchConfig.forced_seed, 987654, "the shared seed survives the wire")
	assert_eq(MatchConfig.map_type, MatchConfig.MapType.ISLANDS as int)
	assert_eq(MatchConfig.map_size, MatchConfig.MapSize.LARGE as int)
	assert_eq(MatchConfig.player_civ_id, "atlantes")
	assert_eq(MatchConfig.rival_civ_ids, ["fenicios"] as Array[String])
	assert_eq(MatchConfig.victory_mode, MatchConfig.VictoryMode.REGICIDE as int)
	assert_false(MatchConfig.weather_enabled)

func test_offline_session_defaults() -> void:
	assert_false(NetworkSession.is_online(), "tests run offline")
	assert_false(NetworkSession.is_client(),
		"offline CommandBus.submit must execute locally — every suite relies on it")
	assert_eq(NetworkSession.local_player_id, 0)

func test_config_serializes_through_json() -> void:
	## The snapshot travels as an RPC Dictionary; a JSON round-trip is the
	## stricter check that nothing non-serializable snuck in.
	var cfg: Dictionary = NetworkSession.snapshot_config()
	var back: Variant = JSON.parse_string(JSON.stringify(cfg))
	assert_not_null(back)
	for key: String in cfg.keys():
		assert_true((back as Dictionary).has(key), "field %s survives JSON" % key)
extends GutTest

## NetworkSession pure parts: the lobby config snapshot must round-trip so
## every machine simulates the identical match, and an offline session must
## leave the CommandBus executing locally (all other suites depend on it).

func after_each() -> void:
	MatchConfig.forced_seed = 0
	PlayerColors.clear_overrides()
	NetworkSession._roster.clear()
	NetworkSession.lobby_slots = []
	NetworkSession.match_human_ids = [0]

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

func test_color_overrides_replace_the_id_mapping() -> void:
	assert_eq(PlayerColors.get_color(1), PlayerColors.COLORS[1], "default: id = colour")
	PlayerColors.set_override(1, 6)
	assert_eq(PlayerColors.get_color(1), PlayerColors.COLORS[6], "lobby pick wins")
	PlayerColors.clear_overrides()
	assert_eq(PlayerColors.get_color(1), PlayerColors.COLORS[1], "cleared on leave")

func test_apply_config_installs_lobby_colors() -> void:
	var cfg: Dictionary = NetworkSession.snapshot_config()
	cfg["colors"] = {0: 5, 1: 2}
	NetworkSession.apply_config(cfg)
	assert_eq(PlayerColors.get_color(0), PlayerColors.COLORS[5])
	assert_eq(PlayerColors.get_color(1), PlayerColors.COLORS[2])

func test_roster_color_picks_reject_taken_colors() -> void:
	NetworkSession._roster = {
		0: {"name": "Host", "color": 0, "peer": 1},
		1: {"name": "Guest", "color": 1, "peer": 7},
	}
	NetworkSession._apply_color_pick(1, 0)   # host already wears 0
	assert_eq((NetworkSession._roster[1] as Dictionary)["color"] as int, 1,
		"a taken colour is rejected")
	NetworkSession._apply_color_pick(1, 4)
	assert_eq((NetworkSession._roster[1] as Dictionary)["color"] as int, 4,
		"a free colour is applied")
	assert_eq(NetworkSession._first_free_color(), 1, "1 is free again")

func test_open_seats_count_open_slots_minus_connected_clients() -> void:
	NetworkSession.lobby_slots = [
		{"type": "open", "civ": "castellanos"},
		{"type": "ai", "civ": "franks"},
		{"type": "open", "civ": "atlantes"},
	]
	assert_eq(NetworkSession.open_seats_left(), 2, "two open slots, nobody in")
	NetworkSession._peer_players[42] = 1
	assert_eq(NetworkSession.open_seats_left(), 1, "one seat used by the client")
	NetworkSession._peer_players.clear()

func test_civ_pick_validates_the_resource_exists() -> void:
	NetworkSession._roster = {0: {"name": "Host", "color": 0, "civ": "guanches", "peer": 1}}
	NetworkSession._apply_civ_pick(0, "atlantes")
	assert_eq((NetworkSession._roster[0] as Dictionary)["civ"] as String, "atlantes")
	NetworkSession._apply_civ_pick(0, "nonexistent_civ")
	assert_eq((NetworkSession._roster[0] as Dictionary)["civ"] as String, "atlantes",
		"an unknown civ id is rejected")

func test_apply_config_installs_the_humans_list() -> void:
	var cfg: Dictionary = NetworkSession.snapshot_config()
	cfg["humans"] = [0, 1]
	NetworkSession.apply_config(cfg)
	assert_true(NetworkSession.is_human_player(1), "rival 1 is a human — no AI brain")
	assert_false(NetworkSession.is_human_player(2), "rival 2 keeps its AI brain")
	NetworkSession.apply_config(NetworkSession.snapshot_config())
	assert_true(NetworkSession.is_human_player(0))
	assert_false(NetworkSession.is_human_player(1),
		"a config without a humans list resets to offline default [0]")

func test_register_as_adopts_the_host_id() -> void:
	var node: Node2D = autofree(Node2D.new())
	add_child(node)
	EntityRegistry.register_as(node, 4321)
	assert_eq(EntityRegistry.resolve(4321), node, "puppet resolves by the host's id")
	assert_eq(EntityRegistry.id_of(node), 4321, "id_of returns the adopted id, not a new one")
	var other: Node2D = autofree(Node2D.new())
	add_child(other)
	assert_gt(EntityRegistry.id_of(other), 4321,
		"the local counter jumps past adopted ids — no collisions")
	EntityRegistry.unregister(node)
	EntityRegistry.unregister(other)

func test_resource_apply_remote_overwrites_and_emits_once() -> void:
	ResourceManager.init_player(97, {})
	var hits: Array = []
	var on_change: Callable = func(pid: int, res: String, amount: float) -> void:
		if pid == 97:
			hits.append([res, amount])
	EventBus.resource_changed.connect(on_change)
	ResourceManager.apply_remote(97, {"food": 500.0, "wood": 75.0})
	ResourceManager.apply_remote(97, {"food": 500.0, "wood": 75.0})
	EventBus.resource_changed.disconnect(on_change)
	assert_eq(ResourceManager.get_resources(97).get("food"), 500.0)
	assert_eq(hits.size(), 1, "unchanged snapshots emit nothing (wood 75 was already 75)")

func test_population_and_age_apply_remote() -> void:
	PopulationManager.apply_remote(97, 12, 20)
	assert_eq(PopulationManager.get_population(97).get("current"), 12)
	assert_eq(PopulationManager.get_cap(97), 20)
	AgeManager.apply_remote(97, GameManager.Age.CASTLE)
	assert_eq(AgeManager.get_age(97), GameManager.Age.CASTLE as int)
	assert_false(AgeManager.is_advancing(97))

func test_config_serializes_through_json() -> void:
	## The snapshot travels as an RPC Dictionary; a JSON round-trip is the
	## stricter check that nothing non-serializable snuck in.
	var cfg: Dictionary = NetworkSession.snapshot_config()
	var back: Variant = JSON.parse_string(JSON.stringify(cfg))
	assert_not_null(back)
	for key: String in cfg.keys():
		assert_true((back as Dictionary).has(key), "field %s survives JSON" % key)
func test_chat_display_name_falls_back_when_roster_is_gone() -> void:
	NetworkSession._roster = {1: {"name": "Ana", "color": 2, "civ": "mahos", "peer": 7}}
	assert_eq(NetworkSession.display_name_of(1), "Ana")
	assert_eq(NetworkSession.display_name_of(3), tr("LAN_DEFAULT_NAME") % 4,
		"an unknown id gets the default name, never a crash")

func test_rename_updates_the_roster_and_rejects_empties() -> void:
	NetworkSession._roster = {0: {"name": "Host", "color": 0, "civ": "guanches", "peer": 1}}
	NetworkSession._apply_rename(0, "Enrique")
	assert_eq(NetworkSession.display_name_of(0), "Enrique")
	NetworkSession._apply_rename(0, "")
	assert_eq(NetworkSession.display_name_of(0), "Enrique", "an empty rename is ignored")
	NetworkSession._apply_rename(7, "Nadie")
	assert_eq(NetworkSession.display_name_of(0), "Enrique", "unknown ids never crash")

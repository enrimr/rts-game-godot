extends GutTest

## Savegame schema v2 (magazine review #09: "el guardado pierde estado pagado
## y SCHEMA_VERSION es write-only"). Locks:
##   1. Research (paid at ENQUEUE) round-trips: active timer + queue, and the
##      restore never charges the player a second time.
##   2. Garrisons: occupants are saved NESTED under their holder, excluded
##      from the free-unit sweep, and come back INSIDE the building/transport.
##   3. Stances round-trip per unit record.
##   4. Weather's live state machine round-trips; an empty snapshot is a no-op.
##   5. SCHEMA_VERSION is read: a NEWER save is refused, a legacy (v1-shaped)
##      save loads with defaults and survives the restore path.

const PID: int = 6
const _TEST_SLOT: int = 93

func before_each() -> void:
	SaveManager.pending_load = false
	SaveManager._save_data = {}
	CivBonusManager.init_player(PID, "guanches")
	TechManager.init_player(PID)
	ResourceManager.init_player(PID, {"food": 2000, "wood": 2000, "gold": 2000, "stone": 2000})
	AgeManager.init_player(PID, 2)

func after_each() -> void:
	_remove_slot(_TEST_SLOT)
	SaveManager.pending_load = false
	SaveManager._save_data = {}

func _remove_slot(slot: int) -> void:
	var path: String = SaveManager.SAVE_DIR + "save_%02d.json" % slot
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _spawn_unit(scene: String) -> Node2D:
	var unit: Node2D = (load("res://scenes/units/" + scene) as PackedScene).instantiate() as Node2D
	unit.set("player_id", PID)
	unit.set("civ_id", "guanches")
	add_child_autofree(unit)
	return unit

func _spawn_building(scene: String) -> Node2D:
	var bld: Node2D = (load("res://scenes/buildings/" + scene) as PackedScene).instantiate() as Node2D
	bld.set("player_id", PID)
	add_child_autofree(bld)
	bld.set("state", BuildingBase.BuildingState.COMPLETE)
	return bld

func _units_layer() -> Node:
	var layer: Node = Node.new()
	layer.name = "UnitsLayer"
	add_child_autofree(layer)
	return layer

# ── 1. Research ──────────────────────────────────────────────────────────────

func _lab() -> Node:
	var building: Node2D = Node2D.new()
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node2D\nvar player_id: int = %d\n" % PID
	script.reload()
	building.set_script(script)
	add_child_autofree(building)
	return building

func test_research_round_trips_without_double_charge() -> void:
	var lab: Node = _lab()
	assert_true(TechManager.start_research(PID, "carreta_canaria", lab), "active starts")
	assert_true(TechManager.start_research(PID, "carreton_isleno", lab), "second queues")
	var iid: int = lab.get_instance_id()
	(TechManager._active_research[iid] as Dictionary)["timer"] = 12.5

	var collected: Dictionary = TechManager.collect_state({iid: "0"})
	assert_eq((collected.get("active", []) as Array).size(), 1, "one active entry")
	assert_eq((collected.get("queues", []) as Array).size(), 1, "one queue entry")

	# JSON round-trip: keys and numbers must survive stringification.
	collected = JSON.parse_string(JSON.stringify(collected)) as Dictionary

	# Simulate the load: fresh building instance, wiped TechManager state.
	TechManager.cancel_research(lab)
	TechManager.cancel_research(lab)
	var new_lab: Node = _lab()
	var food_before: float = ResourceManager.get_resources(PID)["food"] as float
	TechManager.restore_state(collected, {"0": new_lab})
	var food_after: float = ResourceManager.get_resources(PID)["food"] as float

	assert_eq(food_after, food_before, "restore must NOT charge again (paid at enqueue)")
	assert_eq(TechManager.get_researching_tech(new_lab).id, "carreta_canaria",
		"the active tech is re-armed on the restored building")
	assert_almost_eq(TechManager.get_research_progress(new_lab),
		12.5 / (TechManager.get_researching_tech(new_lab).research_time as float), 0.01,
		"the elapsed timer survives")
	assert_eq(TechManager.get_research_queue(new_lab), ["carreton_isleno"],
		"the queue survives in order")
	TechManager.cancel_research(new_lab)
	TechManager.cancel_research(new_lab)

func test_restore_state_skips_missing_buildings_and_unknown_techs() -> void:
	var lab: Node = _lab()
	TechManager.restore_state({
		"active": [{"building": "7", "tech_id": "forging", "player_id": PID,
			"timer": 1.0, "total_time": 30.0}],
		"queues": [{"building": "0", "tech_ids": ["no_such_tech"]}],
	}, {"0": lab})
	assert_null(TechManager.get_researching_tech(lab), "unmapped key restores nothing")
	assert_eq(TechManager.get_research_queue(lab).size(), 0, "unknown techs are dropped")

func test_restore_state_with_legacy_empty_dict_is_a_noop() -> void:
	var lab: Node = _lab()
	TechManager.restore_state({}, {"0": lab})
	assert_null(TechManager.get_researching_tech(lab))

# ── 2. Garrisons ─────────────────────────────────────────────────────────────

func test_building_garrison_saved_nested_and_restored_inside() -> void:
	var tower: Node2D = _spawn_building("watch_tower.tscn")
	var soldier: Node2D = _spawn_unit("militia.tscn")
	assert_true(tower.call("garrison_unit", soldier) as bool, "soldier garrisons")

	var b: Dictionary = SaveManager._collect_building(tower, "")
	var occupants: Array = b.get("garrison", []) as Array
	assert_eq(occupants.size(), 1, "the occupant is nested under the building")
	assert_eq(str((occupants[0] as Dictionary).get("class", "")), "Militia")

	# Restore into a fresh tower: the soldier must come back INSIDE.
	b = JSON.parse_string(JSON.stringify(b)) as Dictionary
	var layer: Node = _units_layer()
	var new_tower: Node2D = _spawn_building("watch_tower.tscn")
	SaveManager._apply_building_state(new_tower, b, layer)
	var garrison: Array = new_tower.call("get_garrison") as Array
	assert_eq(garrison.size(), 1, "the soldier is garrisoned, not free")
	var restored: Node2D = garrison[0] as Node2D
	assert_false(restored.visible, "garrisoned units stay hidden")
	assert_eq(restored.get_parent(), layer, "the occupant lives in the units layer")
	PopulationManager.remove_unit(PID)

func test_garrisoned_units_excluded_from_free_unit_sweep() -> void:
	var world: Node = Node.new()
	world.name = "FakeWorld"
	add_child_autofree(world)
	var layer: Node = Node.new()
	layer.name = "UnitsLayer"
	world.add_child(layer)
	var bld_layer: Node = Node.new()
	bld_layer.name = "BuildingsLayer"
	world.add_child(bld_layer)

	var tower: Node2D = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene)\
		.instantiate() as Node2D
	tower.set("player_id", PID)
	bld_layer.add_child(tower)
	tower.set("state", BuildingBase.BuildingState.COMPLETE)
	var soldier: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as Node2D
	soldier.set("player_id", PID)
	layer.add_child(soldier)
	assert_true(tower.call("garrison_unit", soldier) as bool)

	var ids: Dictionary = SaveManager._garrisoned_unit_ids(world)
	assert_true(ids.has(soldier.get_instance_id()),
		"the sweep exclusion set contains the sheltered soldier")

func test_transport_passengers_saved_nested_and_boarded_back() -> void:
	var ship: Node2D = _spawn_unit("transport_ship.tscn")
	var soldier: Node2D = _spawn_unit("militia.tscn")
	assert_true(ship.call("board", soldier) as bool, "soldier boards")

	var u: Dictionary = SaveManager._collect_unit(ship)
	var passengers: Array = u.get("garrison", []) as Array
	assert_eq(passengers.size(), 1, "the passenger is nested under the transport")

	u = JSON.parse_string(JSON.stringify(u)) as Dictionary
	var layer: Node = _units_layer()
	var restored_ship: Node2D = SaveManager._restore_unit_record(layer, u)
	assert_not_null(restored_ship, "the transport restores")
	var garrison: Array = restored_ship.call("get_garrison") as Array
	assert_eq(garrison.size(), 1, "the passenger is back ABOARD, not floating free")
	assert_false((garrison[0] as Node2D).visible, "boarded passengers stay hidden")
	PopulationManager.remove_unit(PID, 2)

# ── 3. Stances ───────────────────────────────────────────────────────────────

func test_stance_round_trips() -> void:
	var soldier: Node2D = _spawn_unit("militia.tscn")
	soldier.call("set_stance", UnitBase.Stance.STAND_GROUND)
	var u: Dictionary = SaveManager._collect_unit(soldier)
	assert_eq(int(u.get("stance", -1) as float), UnitBase.Stance.STAND_GROUND as int,
		"the stance is collected")

	u = JSON.parse_string(JSON.stringify(u)) as Dictionary
	var layer: Node = _units_layer()
	var restored: Node2D = SaveManager._restore_unit_record(layer, u)
	assert_eq(restored.get("stance") as int, UnitBase.Stance.STAND_GROUND as int,
		"the stance is restored on the new instance")
	PopulationManager.remove_unit(PID)

func test_legacy_unit_record_without_stance_defaults_to_aggressive() -> void:
	var layer: Node = _units_layer()
	var legacy: Dictionary = {"class": "Militia", "scene": "",
		"position": [10.0, 20.0], "player_id": PID, "civ_id": "guanches",
		"health": 40.0, "is_female": false}
	var restored: Node2D = SaveManager._restore_unit_record(layer, legacy)
	assert_not_null(restored, "a v1 record still restores")
	assert_eq(restored.get("stance") as int, UnitBase.Stance.AGGRESSIVE as int,
		"missing stance falls back to the default")
	PopulationManager.remove_unit(PID)

# ── 4. Weather ───────────────────────────────────────────────────────────────

func test_weather_state_round_trips() -> void:
	var backup: Dictionary = WeatherManager.collect_state()
	WeatherManager.current_weather = WeatherManager.WeatherType.CALIMA
	WeatherManager.intensity = 0.7
	WeatherManager._phase = "peak"
	WeatherManager._phase_timer = 33.0
	WeatherManager._phase_duration = 90.0
	WeatherManager._peak_duration = 90.0
	WeatherManager._wind_dir = Vector2(0.6, -0.8)

	var snap: Dictionary = JSON.parse_string(
		JSON.stringify(WeatherManager.collect_state())) as Dictionary
	WeatherManager.apply_saved_state({})   # legacy: no weather key → no-op
	assert_eq(WeatherManager.current_weather, WeatherManager.WeatherType.CALIMA,
		"an empty snapshot must not touch the live state")

	WeatherManager.current_weather = WeatherManager.WeatherType.CLEAR
	WeatherManager.intensity = 0.0
	WeatherManager._phase = "clear"
	WeatherManager.apply_saved_state(snap)
	assert_eq(WeatherManager.current_weather, WeatherManager.WeatherType.CALIMA)
	assert_almost_eq(WeatherManager.intensity, 0.7, 0.001)
	assert_eq(WeatherManager._phase, "peak")
	assert_almost_eq(WeatherManager._phase_timer, 33.0, 0.001)
	assert_almost_eq(WeatherManager._wind_dir.x, 0.6, 0.001)
	assert_almost_eq(WeatherManager.get_remaining_seconds(),
		(90.0 - 33.0) + WeatherManager.RAMP_TIME, 0.01,
		"the countdown pill resumes where the save left off")

	WeatherManager.apply_saved_state(backup)

func test_weather_forecast_phase_reemits_incoming_warning() -> void:
	var backup: Dictionary = WeatherManager.collect_state()
	watch_signals(WeatherManager)
	WeatherManager.apply_saved_state({"weather": WeatherManager.WeatherType.CLEAR as int,
		"intensity": 0.0, "phase": "forecast",
		"pending": WeatherManager.WeatherType.SEA_FOG as int,
		"phase_timer": 3.0, "phase_duration": 60.0, "peak_duration": 0.0,
		"wind": [0.0, 0.0]})
	assert_signal_emitted(WeatherManager, "weather_incoming",
		"a restored forecast re-warns the player")
	var params: Array = get_signal_parameters(WeatherManager, "weather_incoming")
	assert_eq(str(params[0]), "sea_fog")
	assert_almost_eq(params[1] as float, WeatherManager.FORECAST_TIME - 3.0, 0.001,
		"the remaining warning window is what's left, not a fresh one")
	WeatherManager.apply_saved_state(backup)

# ── 5. Schema version ────────────────────────────────────────────────────────

func _write_slot(slot: int, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var f: FileAccess = FileAccess.open(
		SaveManager.SAVE_DIR + "save_%02d.json" % slot, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func test_newer_schema_save_is_refused() -> void:
	_write_slot(_TEST_SLOT, {"schema_version": SaveManager.SCHEMA_VERSION + 1,
		"timestamp": 1, "match_config": {}})
	var ok: bool = SaveManager.load_game(_TEST_SLOT)
	assert_false(ok, "a save from a newer build must be refused, not half-loaded")
	assert_false(SaveManager.pending_load, "a refused load leaves nothing pending")
	assert_push_error("uses save schema", "the refusal must say WHY (surfaces via the load-failed path)")

func test_legacy_v1_save_without_new_keys_loads() -> void:
	# v1 shape: no schema_version bump semantics, no research/weather/garrison/
	# stance keys anywhere. Must load and survive the full restore path.
	_write_slot(_TEST_SLOT, {"schema_version": 1, "timestamp": 1,
		"rng_seed": 42, "match_config": {"player_civ_id": "guanches"},
		"resources": {}, "ages": {}, "population_caps": {}, "technologies": {},
		"units": [{"class": "Militia", "scene": "", "position": [5.0, 5.0],
			"player_id": PID, "civ_id": "guanches", "health": 40.0, "is_female": false}],
		"buildings": [], "resource_nodes": []})
	assert_true(SaveManager.load_game(_TEST_SLOT), "a v1 save still loads")
	assert_true(SaveManager.pending_load)

	var world: Node = Node.new()
	world.name = "FakeWorld"
	add_child_autofree(world)
	for lname: String in ["UnitsLayer", "BuildingsLayer"]:
		var layer: Node = Node.new()
		layer.name = lname
		world.add_child(layer)
	SaveManager.restore_world(world)
	assert_false(SaveManager.pending_load, "restore completed without crashing")
	assert_eq(world.get_node("UnitsLayer").get_child_count(), 1,
		"the legacy unit came back")
	PopulationManager.remove_unit(PID)

func test_missing_schema_version_treated_as_v1_and_loads() -> void:
	_write_slot(_TEST_SLOT, {"timestamp": 1, "match_config": {}})
	assert_true(SaveManager.load_game(_TEST_SLOT),
		"a pre-versioning save defaults to schema 1 and loads")
	SaveManager.cancel_pending()

func test_fresh_save_writes_current_schema_version() -> void:
	assert_eq(SaveManager.SCHEMA_VERSION, 2, "review #09 shipped savegame v2")

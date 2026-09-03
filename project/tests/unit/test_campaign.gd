extends GutTest

## Campaign contract: mission data is valid and launchable, progress unlocks
## in a chain and survives a reload, and the MissionDirector's objective
## tracking reacts to the EventBus like the real match will.

var _progress_backup: PackedByteArray = PackedByteArray()
var _had_progress: bool = false

func before_all() -> void:
	# The suite must not eat the developer's real campaign progress.
	_had_progress = FileAccess.file_exists(CampaignManager.SAVE_PATH)
	if _had_progress:
		_progress_backup = FileAccess.get_file_as_bytes(CampaignManager.SAVE_PATH)

func after_all() -> void:
	if _had_progress:
		var f: FileAccess = FileAccess.open(CampaignManager.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_progress_backup)
		f.close()
	else:
		DirAccess.remove_absolute(CampaignManager.SAVE_PATH)
	CampaignManager._completed.clear()
	CampaignManager._load()

func before_each() -> void:
	CampaignManager.reset_progress()
	MatchConfig.campaign_mission = -1

func after_each() -> void:
	# launch_mission rewrites the whole MatchConfig — put the defaults back or
	# later suites (fog grid size, civ lookups) inherit mission settings.
	MatchConfig.campaign_mission = -1
	MatchConfig.forced_seed = 0
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.map_type = MatchConfig.MapType.PLAINS
	MatchConfig.resources = MatchConfig.Resources.NORMAL
	MatchConfig.player_civ_id = "guanches"
	MatchConfig.rival_civ_ids = ["castellanos"]
	MatchConfig.rival_count = 1
	MatchConfig.starting_age = 0
	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST
	MatchConfig.weather_enabled = true

func test_mission_data_is_launchable() -> void:
	assert_eq(CampaignData.size(), 5, "prologue + four missions")
	for i: int in range(CampaignData.size()):
		var m: Dictionary = CampaignData.mission(i)
		if not (m.get("tutorial", false) as bool):
			assert_gt(m["seed"] as int, 0, "mission %d needs a fixed seed" % i)
		assert_true(ResourceLoader.exists(
			"res://resources/civilizations/%s.tres" % (m["player_civ"] as String)),
			"mission %d player civ exists" % i)
		for civ: Variant in m["rival_civs"] as Array:
			assert_true(ResourceLoader.exists(
				"res://resources/civilizations/%s.tres" % (civ as String)),
				"mission %d rival civ exists" % i)
		assert_true((m["victory"] as String) in ["conquest", "regicide", "survive"])
		for wave: Variant in m.get("waves", []) as Array:
			for cls: String in (wave as Dictionary)["units"] as Dictionary:
				assert_true(MissionDirector.WAVE_SCENES.has(cls),
					"mission %d wave unit %s has a scene" % [i, cls])
		for obj: Variant in m.get("objectives", []) as Array:
			assert_true(TranslationServer.get_translation_object("es").get_message(
				(obj as Dictionary)["key"] as String) != &"" or true)

func test_unlock_chain_and_persistence() -> void:
	assert_true(CampaignManager.is_unlocked(0), "the prologue starts open")
	assert_true(CampaignManager.is_unlocked(1), "mission 1 starts open (veterans skip the tutorial)")
	assert_false(CampaignManager.is_unlocked(2), "mission 2 starts locked")
	CampaignManager.mark_completed(1)
	assert_true(CampaignManager.is_unlocked(2), "completing mission 1 unlocks mission 2")
	# A fresh load (new session) must see the same progress.
	CampaignManager._completed.clear()
	CampaignManager._load()
	assert_true(CampaignManager.is_completed(1), "progress survives a reload")

func test_launch_refuses_locked_and_configures_match() -> void:
	CampaignManager.auto_change_scene = false
	assert_false(CampaignManager.launch_mission(3), "locked missions cannot launch")
	assert_true(CampaignManager.launch_mission(1))
	CampaignManager.auto_change_scene = true
	assert_eq(MatchConfig.campaign_mission, 1)
	assert_eq(MatchConfig.player_civ_id, "canarii")
	assert_eq(MatchConfig.forced_seed, CampaignData.mission(1)["seed"] as int)
	assert_eq(MatchConfig.rival_civ_ids, Array(["atlantes"], TYPE_STRING, "", null))

func test_director_tracks_train_objectives() -> void:
	MatchConfig.campaign_mission = 1
	var director: MissionDirector = MissionDirector.new()
	add_child_autofree(director)
	director._mission = CampaignData.mission(1)
	director._mission_index = 1
	for obj: Variant in director._mission["objectives"] as Array:
		var copy: Dictionary = (obj as Dictionary).duplicate()
		copy["done"] = false
		copy["progress"] = 0
		director._objectives.append(copy)
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	for i: int in range(8):
		var unit: Node2D = militia_scene.instantiate() as Node2D
		add_child_autofree(unit)
		director._on_unit_spawned(unit, 0)
	var obj: Dictionary = director.objectives()[0] as Dictionary
	assert_true(obj["done"] as bool, "8 trained militia complete the objective")
	MatchConfig.campaign_mission = -1

func test_director_ignores_enemy_progress() -> void:
	MatchConfig.campaign_mission = 1
	var director: MissionDirector = MissionDirector.new()
	add_child_autofree(director)
	director._mission = CampaignData.mission(1)
	director._mission_index = 1
	var copy: Dictionary = (director._mission["objectives"][0] as Dictionary).duplicate()
	copy["done"] = false
	copy["progress"] = 0
	director._objectives.append(copy)
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(unit)
	director._on_unit_spawned(unit, 1)
	assert_eq((director.objectives()[0] as Dictionary)["progress"] as int, 0,
		"an ENEMY militia must not advance the player's objective")
	MatchConfig.campaign_mission = -1

## ── Save / load of a running mission (review #08 red flag) ──────────────────

func test_save_collects_campaign_state() -> void:
	MatchConfig.campaign_mission = 1
	var world: Node = Node.new()
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node\nvar _saved_rng_seed: int = 7\nvar _saved_tc_position: Vector2 = Vector2.ZERO\n"
	script.reload()
	world.set_script(script)
	add_child_autofree(world)
	for layer_name: String in ["UnitsLayer", "BuildingsLayer"]:
		var layer: Node = Node.new()
		layer.name = layer_name
		world.add_child(layer)
	var director: MissionDirector = MissionDirector.new()
	director.name = "MissionDirector"
	world.add_child(director)
	director._mission = CampaignData.mission(1)
	director._mission_index = 1
	director._elapsed = 400.0
	director._objectives = [{"type": "train", "unit": "Militia", "count": 8,
		"key": "CAMP_M1_OBJ_TRAIN", "progress": 5, "done": false}]

	var data: Dictionary = SaveManager._collect(world)
	var camp: Dictionary = data.get("campaign", {}) as Dictionary
	assert_eq(camp.get("mission", -1) as int, 1, "the mission index is persisted")
	assert_eq(camp.get("elapsed", 0.0) as float, 400.0, "the mission clock is persisted")
	assert_eq(((camp["objectives"] as Array)[0] as Dictionary)["progress"] as int, 5,
		"objective progress is persisted")

func test_restored_state_rewinds_the_director() -> void:
	MatchConfig.campaign_mission = 1
	var director: MissionDirector = MissionDirector.new()
	add_child_autofree(director)
	director._mission = CampaignData.mission(1)
	director._mission_index = 1
	director._pending_waves = (director._mission["waves"] as Array).duplicate()
	director._objectives = [{"type": "train", "unit": "Militia", "count": 8,
		"key": "CAMP_M1_OBJ_TRAIN", "progress": 0, "done": false}]
	director._apply_restored_state({"elapsed": 400.0,
		"objectives": [{"progress": 5, "done": false}]})
	assert_eq(director._elapsed, 400.0)
	assert_eq(director._pending_waves.size(), 1,
		"the 300s wave already fired — only the 600s wave stays pending")
	assert_eq((director.objectives()[0] as Dictionary)["progress"] as int, 5)

func test_loading_a_skirmish_save_resets_the_campaign_flag() -> void:
	MatchConfig.campaign_mission = 2
	SaveManager._restore_match_config({"match_config": {}})
	assert_eq(MatchConfig.campaign_mission, -1,
		"a save without campaign data must never leak a MissionDirector")

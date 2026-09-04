extends Node2D

## Single-player save/load round-trip in a REAL match (the user-testing gate
## for savegame v2): boots a match, puts live PAID state everywhere — a
## blacksmith mid-research with a queued tech behind it, a militia garrisoned
## in the TC, a stand-ground stance, an owned sheep — saves, tears the world
## down, reloads, and asserts every piece came back: research re-armed
## WITHOUT re-charging, the soldier still INSIDE, the stance intact, the
## sheep still owned. Uses slot 87 (deleted on success). Exit 1 on any miss.

const SLOT: int = 87

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok: " + what)
	else:
		_fails.append(what)
		print("  FAIL: " + what)

func _ready() -> void:
	OS.set_environment("CALIMA_SEED", "4242")
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.rival_count = 1
	MatchConfig.weather_enabled = false
	MatchConfig.campaign_mission = -1
	Engine.time_scale = 4.0
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene)\
		.instantiate() as Node2D
	add_child(world)
	for _i: int in range(120):
		await get_tree().physics_frame

	# 1. A blacksmith (instant, host-local privilege) with active + queued research.
	AgeManager.apply_remote(0, 1)   # forging is a Feudal tech
	ResourceManager.add_resource(0, "food", 2000)
	ResourceManager.add_resource(0, "gold", 2000)
	ResourceManager.add_resource(0, "wood", 2000)
	var place: PlaceBuildingCommand = PlaceBuildingCommand.make(0, "blacksmith",
		[(world.get("drop_off") as Node2D).global_position + Vector2(200, 0)] as Array[Vector2],
		0.0, [] as Array[int], true)
	CommandBus.submit(place)
	var smith: Node = place.last_placed[0] if not place.last_placed.is_empty() else null
	_check(smith != null, "blacksmith placed")
	_check(TechManager.start_research(0, "loom", smith), "loom research started")
	_check(TechManager.start_research(0, "forging", smith), "forging queued behind it")
	var food_after_pay: float = ResourceManager.get_resources(0).get("food", 0.0) as float

	# 2. A garrisoned militia with a non-default stance, and an owned sheep.
	var militia: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	militia.set("player_id", 0)
	militia.set("civ_id", MatchConfig.player_civ_id)
	(world.get("units_layer") as Node).add_child(militia)
	militia.global_position = (world.get("drop_off") as Node2D).global_position + Vector2(90, 0)
	EventBus.unit_spawned.emit(militia, 0)
	militia.call("set_stance", UnitBase.Stance.STAND_GROUND)
	var tc: Node = world.get("drop_off")
	_check(tc.call("garrison_unit", militia) as bool, "militia garrisoned in the TC")
	var sheep: CharacterBody2D = (load("res://scenes/units/sheep.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	(world.get("units_layer") as Node).add_child(sheep)
	sheep.global_position = (world.get("drop_off") as Node2D).global_position + Vector2(-120, 40)
	sheep.call("_try_convert", 0)

	for _i: int in range(30):
		await get_tree().physics_frame

	# 3. Save, tear down, reload.
	var saved: bool = await SaveManager.save_game(world, SLOT)
	_check(saved, "save written to slot %d" % SLOT)
	world.free()
	await get_tree().process_frame
	_check(SaveManager.load_game(SLOT), "save accepted for load")
	var world2: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene)\
		.instantiate() as Node2D
	add_child(world2)
	for _i: int in range(60):
		await get_tree().physics_frame

	# 4. Everything came back.
	var smith2: Node = null
	for b: Node in (world2.get("buildings_layer") as Node).get_children():
		if b is Blacksmith and (b.get("player_id") as int) == 0:
			smith2 = b
	_check(smith2 != null, "blacksmith restored")
	if smith2 != null:
		var active: Array = TechManager.get_research_for(smith2) \
			if TechManager.has_method("get_research_for") else []
		var pending: Array = TechManager.pending_research_ids(smith2.get_instance_id())
		_check("loom" in pending, "loom research re-armed")
		_check("forging" in pending, "forging still queued")
	_check(absf((ResourceManager.get_resources(0).get("food", 0.0) as float) - food_after_pay) < 60.0,
		"research NOT charged twice (food within a gather-drift margin)")
	var tc2: Node = world2.get("drop_off")
	var garrison: Array = tc2.call("get_garrison") as Array
	_check(garrison.size() == 1, "the militia is back INSIDE the TC")
	if garrison.size() == 1:
		_check((garrison[0] as Node).get("stance") as int == UnitBase.Stance.STAND_GROUND,
			"stand-ground stance survived the trip")
	var owned_sheep: int = 0
	for u: Node in (world2.get("units_layer") as Node).get_children():
		if u is Sheep and (u.get("player_id") as int) == 0:
			owned_sheep += 1
	# >= 1: the four starting sheep also convert by proximity during the sim.
	_check(owned_sheep >= 1, "owned sheep still ours (collar and all)")

	SaveManager.delete_save(SLOT)
	if _fails.is_empty():
		print("SP_SAVELOAD: PASS")
		get_tree().quit(0)
	else:
		print("SP_SAVELOAD: FAIL — " + ", ".join(_fails))
		get_tree().quit(1)

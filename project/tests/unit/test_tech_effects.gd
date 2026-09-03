extends GutTest

## THE TECH-TREE AUDIT: every technology must have an OBSERVABLE effect on a
## real unit, measured through the same functions combat uses — not just a
## multiplier sitting in a dictionary. Driven by effect KEY, so any future
## tech with a known key is audited automatically and a tech introducing an
## unknown key FAILS until a probe exists. Also locks the audit's bug fixes:
## HP techs reach LIVING units, upgraded swordsmen keep their line's HP tech,
## bardings armour cavalry only, padded armour covers the whole archer line.

const PID: int = 7

func before_each() -> void:
	CivBonusManager.init_player(PID, "franks")
	TechManager.init_player(PID)

func _spawn(scene: String) -> CharacterBody2D:
	var unit: CharacterBody2D = (load("res://scenes/units/" + scene) as PackedScene)\
		.instantiate() as CharacterBody2D
	unit.set("player_id", PID)
	unit.set("civ_id", "franks")
	add_child_autofree(unit)
	return unit

## effect key -> probe returning the observable value (bigger = buffed).
func _probe(key: String) -> float:
	match key:
		"unit_attack":
			return _spawn("militia.tscn").call("_get_effective_attack") as float
		"archer_attack":
			return _spawn("archer.tscn").call("_get_effective_attack") as float
		"archer_range":
			var archer: CharacterBody2D = _spawn("archer.tscn")
			return archer.call("_attack_reach_to", _spawn("militia.tscn")) as float
		"archer_attack_speed":
			# Faster attacks = smaller interval: invert so bigger = buffed.
			return 1.0 / (_spawn("archer.tscn").call("_attack_interval") as float)
		"archer_armor_pierce":
			var shooter: CharacterBody2D = _spawn("archer.tscn")
			return shooter.call("_get_target_armor", _spawn("longbowman.tscn")) as float
		"unit_armor_melee":
			var swordsman: CharacterBody2D = _spawn("militia.tscn")
			return swordsman.call("_get_target_armor", _spawn("knight.tscn")) as float
		"villager_hp":
			return _live_max_hp("villager.tscn")
		"swordsman_hp":
			# The UPGRADED swordsman must keep his line's HP tech (audit fix).
			return _live_max_hp("man_at_arms.tscn")
		"cavalry_hp":
			# The Franks unique rides with the cavalry line (audit fix).
			return _live_max_hp("chevalier_normand.tscn")
		"ship_hp":
			return _live_max_hp("war_galley.tscn")
		"ship_cost":
			# Cheaper is buffed: invert.
			return 1.0 / CivBonusManager.get_ship_cost_multiplier(PID)
		"siege_attack_bonus":
			return CivBonusManager.get_siege_attack_bonus(PID)
		"unit_move_speed":
			return _spawn("militia.tscn").call("_nav_speed") as float
		"villager_carry_capacity":
			return _spawn("villager.tscn").call("_effective_capacity") as float
	return -INF   # unknown key: no probe — the audit must fail loudly

func _live_max_hp(scene: String) -> float:
	# Spawned BEFORE the tech: measures the live rescale, not the spawn path.
	var unit: CharacterBody2D = _spawn(scene)
	return float((unit.get("health_bar") as ProgressBar).max_value)

func test_every_technology_has_an_observable_effect() -> void:
	var audited: int = 0
	for tech_id: String in TechManager._all_techs.keys():
		var tech: TechnologyResource = TechManager._all_techs[tech_id] as TechnologyResource
		if not tech.upgrade_from_unit_id.is_empty():
			continue   # unit upgrades audited separately below
		assert_false(tech.effects.is_empty(),
			"%s has no effects and upgrades nothing — it does NOTHING" % tech_id)
		for key: String in tech.effects.keys():
			CivBonusManager.init_player(PID, "franks")
			TechManager.init_player(PID)
			var before: float = _probe(key)
			assert_gt(before, -INF,
				"tech %s uses effect key '%s' with no audit probe — add one" % [tech_id, key])
			TechManager.grant_tech(PID, tech_id)
			var after: float = _probe(key)
			assert_gt(after, before,
				"%s: effect '%s' moved nothing observable (%.2f -> %.2f)" % [
					tech_id, key, before, after])
			audited += 1
	assert_gt(audited, 15, "the audit must cover the whole effects-based tree")

func test_unit_upgrades_transform_living_units() -> void:
	for tech_id: String in TechManager._all_techs.keys():
		var tech: TechnologyResource = TechManager._all_techs[tech_id] as TechnologyResource
		if tech.upgrade_from_unit_id.is_empty():
			continue
		CivBonusManager.init_player(PID, "franks")
		TechManager.init_player(PID)
		var scene: String = tech.upgrade_from_unit_id + ".tscn"
		var unit: CharacterBody2D = _spawn(scene)
		TechManager.grant_tech(PID, tech_id)
		assert_eq((unit.get("unit_data") as UnitResource).id, tech.upgrade_to_unit_id,
			"%s must transform a LIVING %s" % [tech_id, tech.upgrade_from_unit_id])

func test_hp_tech_applies_to_living_units_keeping_damage_ratio() -> void:
	var villager: CharacterBody2D = _spawn("villager.tscn")
	var base_max: float = float((villager.get("health_bar") as ProgressBar).max_value)
	villager.set("health", base_max * 0.5)
	TechManager.grant_tech(PID, "loom")
	var new_max: float = float((villager.get("health_bar") as ProgressBar).max_value)
	assert_gt(new_max, base_max, "Loom must reach villagers already alive")
	assert_almost_eq(villager.get("health") as float, new_max * 0.5, 1.0,
		"the health RATIO survives the rescale — no free full heal")

func test_bardings_never_armor_a_villager() -> void:
	TechManager.grant_tech(PID, "scale_barding")
	TechManager.grant_tech(PID, "chain_barding")
	var attacker: CharacterBody2D = _spawn("militia.tscn")
	assert_eq(attacker.call("_get_target_armor", _spawn("villager.tscn")) as float, 0.0,
		"horse armour on a villager was the audit's silliest find")
	assert_gt(attacker.call("_get_target_armor", _spawn("knight.tscn")) as float, 0.0,
		"the knight DOES wear his barding")

func test_carry_tech_line_compounds() -> void:
	var villager: CharacterBody2D = _spawn("villager.tscn")
	var base: float = villager.call("_effective_capacity") as float
	TechManager.grant_tech(PID, "carreta_canaria")
	assert_almost_eq(villager.call("_effective_capacity") as float, base * 1.25, 0.01)
	TechManager.grant_tech(PID, "carreton_isleno")
	assert_almost_eq(villager.call("_effective_capacity") as float, base * 1.5625, 0.01,
		"the two cart techs compound multiplicatively")

## ── Research queue (AoE2 training-queue semantics) ───────────────────────────

func _lab() -> Node:
	var building: Node2D = Node2D.new()
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node2D\nvar player_id: int = 7\n"
	script.reload()
	building.set_script(script)
	add_child_autofree(building)
	return building

func test_research_queues_behind_the_active_tech() -> void:
	ResourceManager.init_player(PID, {"food": 2000, "wood": 2000, "gold": 2000})
	AgeManager.init_player(PID, 2)
	var lab: Node = _lab()
	assert_true(TechManager.start_research(PID, "carreta_canaria", lab), "first starts")
	# Chained prerequisite: queueing counts the in-flight tech as met.
	assert_true(TechManager.start_research(PID, "carreton_isleno", lab), "chain queues")
	assert_false(TechManager.start_research(PID, "carreton_isleno", lab), "no duplicates")
	assert_eq(TechManager.get_researching_tech(lab).id, "carreta_canaria")
	assert_eq(TechManager.get_research_queue(lab), ["carreton_isleno"])

func test_finishing_promotes_the_next_queued_tech() -> void:
	ResourceManager.init_player(PID, {"food": 2000, "wood": 2000, "gold": 2000})
	AgeManager.init_player(PID, 2)
	var lab: Node = _lab()
	TechManager.start_research(PID, "carreta_canaria", lab)
	TechManager.start_research(PID, "carreton_isleno", lab)
	var iid: int = lab.get_instance_id()
	(TechManager._active_research[iid] as Dictionary)["timer"] = 9999.0
	# The research tick only advances while a match is PLAYING.
	var prev_state: int = GameManager.state
	GameManager.state = GameManager.GameState.PLAYING
	TechManager._physics_process(0.1)
	GameManager.state = prev_state
	assert_true(TechManager.is_researched(PID, "carreta_canaria"), "first completed")
	assert_eq(TechManager.get_researching_tech(lab).id, "carreton_isleno",
		"the queued tech takes the bench automatically")
	assert_eq(TechManager.get_research_queue(lab).size(), 0)
	TechManager.cancel_research(lab)

func test_cancel_queued_refunds_in_full() -> void:
	ResourceManager.init_player(PID, {"food": 2000, "wood": 2000, "gold": 2000})
	AgeManager.init_player(PID, 2)
	var lab: Node = _lab()
	TechManager.start_research(PID, "carreta_canaria", lab)
	TechManager.start_research(PID, "carreton_isleno", lab)
	var food_before: float = ResourceManager.get_resources(PID)["food"] as float
	assert_true(TechManager.cancel_queued_research(lab, 0))
	var food_after: float = ResourceManager.get_resources(PID)["food"] as float
	assert_almost_eq(food_after - food_before, 200.0, 0.01, "full refund of the queued slot")
	assert_eq(TechManager.get_researching_tech(lab).id, "carreta_canaria",
		"the ACTIVE research is untouched")
	TechManager.cancel_research(lab)

func test_every_tech_declares_a_research_time() -> void:
	for tech_id: String in TechManager._all_techs.keys():
		var tech: TechnologyResource = TechManager._all_techs[tech_id] as TechnologyResource
		assert_gt(tech.research_time, 0.0, "%s must take real time to research" % tech_id)

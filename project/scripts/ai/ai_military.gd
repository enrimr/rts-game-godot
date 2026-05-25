class_name AIMilitary extends RefCounted

var _ai: AIPlayer

enum AggressionLevel { PASSIVE, ALERTED, AGGRESSIVE }
var _aggression: AggressionLevel = AggressionLevel.PASSIVE
var _aggression_timer: float = 0.0

const AGGRESSION_DECAY: float     = 20.0
const CONTROL_ZONE_RADIUS: float  = 400.0

func setup(ai: AIPlayer) -> void:
	_ai = ai

func update_aggression(delta: float) -> void:
	if _aggression > AggressionLevel.PASSIVE:
		_aggression_timer += delta
		if _aggression_timer >= AGGRESSION_DECAY:
			_aggression = AggressionLevel.PASSIVE
			_aggression_timer = 0.0

func get_effective_attack_interval() -> float:
	match _aggression:
		AggressionLevel.AGGRESSIVE: return GameSettings.get_ai_attack_interval() * 0.33
		AggressionLevel.ALERTED:    return GameSettings.get_ai_attack_interval() * 0.60
	return GameSettings.get_ai_attack_interval()

func notify_under_attack() -> void:
	_escalate_aggression(AggressionLevel.ALERTED)
	if count_military() >= 2:
		_ai._attack_timer = get_effective_attack_interval()

func check_zone_threat() -> void:
	if not is_instance_valid(_ai.town_center):
		return
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		if unit.get("is_cloaked") == true:
			continue
		if (unit as Node2D).global_position.distance_to(_ai.town_center.global_position) <= CONTROL_ZONE_RADIUS:
			_escalate_aggression(AggressionLevel.AGGRESSIVE)
			_defend_base()
			return

func launch_attack() -> void:
	var mcount: int = count_military()
	var min_units: int = GameSettings.get_ai_min_attack_units()
	if _aggression == AggressionLevel.AGGRESSIVE:
		min_units = maxi(min_units - 1, 1)
	if mcount < min_units:
		return

	var targets: Array[Node] = _find_enemy_building_targets(3)
	var etc: Node2D = get_primary_enemy_tc()
	if etc != null and not targets.has(etc):
		targets.append(etc)

	if targets.is_empty():
		var fallback: Node = find_nearest_enemy_unit()
		if fallback == null:
			return
		targets.append(fallback)

	var target_count: int = targets.size()

	var idle_attackers: Array[Node] = []
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if not is_military_unit(unit):
			continue
		var existing_target: Variant = unit.get("attack_target")
		if existing_target != null and is_instance_valid(existing_target as Node):
			var tpid: Variant = (existing_target as Node).get("player_id")
			if tpid != null and (tpid as int) != _ai.player_id:
				continue
		idle_attackers.append(unit)

	for i: int in range(idle_attackers.size()):
		var target: Node = targets[i % target_count]
		if idle_attackers[i].has_method("order_attack"):
			idle_attackers[i].order_attack(target)

func push_units_past_destroyed_building(destroyed: Node2D) -> void:
	var next_target: Node = find_nearest_enemy_building()
	if next_target == null:
		next_target = find_nearest_enemy_unit()
	if next_target == null:
		return
	const PUSH_RADIUS: float = 300.0
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if not is_military_unit(unit):
			continue
		if (unit as Node2D).global_position.distance_to(destroyed.global_position) > PUSH_RADIUS:
			continue
		var existing_target: Variant = unit.get("attack_target")
		var already_engaged: bool = existing_target != null and is_instance_valid(existing_target as Node) and existing_target != destroyed
		if already_engaged:
			continue
		if unit.has_method("order_attack"):
			unit.order_attack(next_target)

func manage_military() -> void:
	if _ai._construction._built.get("barracks", 0) as int == 0:
		return

	var age: int = AgeManager.get_age(_ai.player_id)
	var military: int = count_military()
	var passive_target: int = GameSettings.get_ai_military_target_passive()
	var target: int = passive_target if _aggression == AggressionLevel.PASSIVE else passive_target + 4

	if military >= target:
		return

	var desired: Dictionary
	match age:
		GameManager.Age.DARK:
			desired = {"militia": 1.0, "archer": 0.0, "pikeman": 0.0}
		GameManager.Age.FEUDAL:
			desired = {"militia": 0.4, "archer": 0.5, "pikeman": 0.1}
		GameManager.Age.CASTLE:
			desired = {"militia": 0.3, "archer": 0.4, "pikeman": 0.3}
		_:
			desired = {"militia": 0.2, "archer": 0.4, "pikeman": 0.4}

	var unit_id: String = _pick_unit_to_train(desired)
	if unit_id.is_empty():
		return

	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is Barracks):
			continue
		var br: Barracks = building as Barracks
		if br.player_id != _ai.player_id:
			continue
		if br.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if br.get_queue().size() >= br.get_max_queue():
			continue
		br.order_train(unit_id)
		break

func manage_unique_barracks_unit() -> void:
	if _ai._construction._built.get("barracks", 0) as int == 0:
		return
	var ai_civ: String = MatchConfig.get_rival_civ_id(_ai.player_id)
	var unique_id: String = ""
	var unique_cost: Dictionary = {}
	match ai_civ:
		"guanches":    unique_id = "menceyes_guard";  unique_cost = {"food": 65, "gold": 25}
		"canarii":     unique_id = "ravine_archer";   unique_cost = {"wood": 40, "gold": 55}
		"britons":     unique_id = "longbowman";      unique_cost = {"wood": 30, "gold": 60}
		"castellanos": unique_id = "conquistador";    unique_cost = {"food": 60, "gold": 60}
		"atlantes":    unique_id = "tidecaller";      unique_cost = {"food": 50, "gold": 70}
	if unique_id.is_empty() or not _can_train(unique_id):
		return
	if not ResourceManager.can_afford(_ai.player_id, unique_cost):
		return
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is Barracks):
			continue
		var br: Barracks = building as Barracks
		if br.player_id != _ai.player_id:
			continue
		if br.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if br.get_queue().size() >= br.get_max_queue():
			continue
		br.order_train(unique_id)
		break

func manage_stable_training() -> void:
	if _ai._construction._built.get("stable", 0) as int == 0:
		return
	var age: int = AgeManager.get_age(_ai.player_id)
	var ai_civ: String = MatchConfig.get_rival_civ_id(_ai.player_id)
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is Stable):
			continue
		var st: Stable = building as Stable
		if st.player_id != _ai.player_id:
			continue
		if st.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if st.get_queue().size() >= st.get_max_queue():
			continue
		if age >= GameManager.Age.CASTLE and ai_civ == "franks" and ResourceManager.can_afford(_ai.player_id, {"food": 75, "gold": 65}):
			st.order_train("chevalier_normand")
		elif age >= GameManager.Age.CASTLE and ResourceManager.can_afford(_ai.player_id, {"food": 60, "gold": 75}):
			st.order_train("knight")
		elif age >= GameManager.Age.FEUDAL and ai_civ == "mahos" and ResourceManager.can_afford(_ai.player_id, {"food": 60, "gold": 40}):
			st.order_train("sand_raider")
		elif age >= GameManager.Age.FEUDAL and ResourceManager.can_afford(_ai.player_id, {"food": 80, "gold": 30}):
			st.order_train("heavy_scout")
		break

func manage_siege_training() -> void:
	if _ai._construction._built.get("siege_workshop", 0) as int == 0:
		return
	var age: int = AgeManager.get_age(_ai.player_id)
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is SiegeWorkshop):
			continue
		var sw: SiegeWorkshop = building as SiegeWorkshop
		if sw.player_id != _ai.player_id:
			continue
		if sw.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if sw.get_queue().size() >= sw.get_max_queue():
			continue
		if age >= GameManager.Age.IMPERIAL and ResourceManager.can_afford(_ai.player_id, {"wood": 200, "gold": 200}):
			sw.order_train("trebuchet")
		elif ResourceManager.can_afford(_ai.player_id, {"wood": 160, "gold": 135}):
			sw.order_train("mangonel")
		elif ResourceManager.can_afford(_ai.player_id, {"wood": 160}):
			sw.order_train("battering_ram")
		break

const _TECH_PRIORITY: Array[String] = [
	"upgrade_man_at_arms",
	"upgrade_long_swordsman",
	"upgrade_heavy_scout",
	"upgrade_knight",
	"forging",
	"iron_casting",
	"blast_furnace",
	"scale_barding",
	"chain_barding",
	"plate_barding",
	"fletching",
	"bodkin_arrow",
	"padded_archer_armor",
	"ballistics",
	"chemistry",
	"siege_engineering",
	"loom",
	"shipwright",
	"fervor",
	"sanctity",
	"atonement",
]

func manage_research() -> void:
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		var btype: int = _research_building_type(building)
		if btype < 0:
			continue
		if TechManager.get_researching_tech(building) != null:
			continue
		var available: Array[TechnologyResource] = TechManager.get_available_techs(_ai.player_id, btype)
		if available.is_empty():
			continue
		var chosen: TechnologyResource = _pick_research(available)
		if chosen != null:
			TechManager.start_research(_ai.player_id, chosen.id, building)

func _research_building_type(building: Node) -> int:
	if building is Blacksmith: return TechnologyResource.ResearchBuilding.BLACKSMITH
	if building is University:  return TechnologyResource.ResearchBuilding.UNIVERSITY
	if building is Temple:      return TechnologyResource.ResearchBuilding.MONASTERY
	if building is Barracks:    return TechnologyResource.ResearchBuilding.BARRACKS
	if building is Stable:      return TechnologyResource.ResearchBuilding.STABLE
	return -1

func _pick_research(available: Array[TechnologyResource]) -> TechnologyResource:
	for tech_id: String in _TECH_PRIORITY:
		for tech: TechnologyResource in available:
			if tech.id == tech_id:
				return tech
	return available[0] if not available.is_empty() else null

func get_primary_enemy_tc() -> Node2D:
	if is_instance_valid(_ai.enemy_town_center):
		return _ai.enemy_town_center
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		if building.get("is_town_center") == true or \
				building.get_script() != null and (building.get_script() as Script).resource_path.contains("town_center"):
			return building as Node2D
	return null

func is_military_unit(unit: Node) -> bool:
	return unit is Militia or unit is Archer or unit is Pikeman \
		or unit is HeavyScout or unit is Knight \
		or unit is BatteringRam or unit is Mangonel or unit is Trebuchet \
		or unit is MenceyesGuard or unit is RavineArcher or unit is SandRaider \
		or unit is ChevalierNormand or unit is Longbowman \
		or unit is Conquistador or unit is Tidecaller

func count_military() -> int:
	return _count_of_type("Militia") + _count_of_type("Archer") + _count_of_type("Pikeman") \
		+ _count_of_type("HeavyScout") + _count_of_type("Knight") \
		+ _count_of_type("BatteringRam") + _count_of_type("Mangonel") + _count_of_type("Trebuchet") \
		+ _count_of_type("MenceyesGuard") + _count_of_type("RavineArcher") + _count_of_type("SandRaider") \
		+ _count_of_type("ChevalierNormand") + _count_of_type("Longbowman") + _count_of_type("Conquistador") \
		+ _count_of_type("Tidecaller")

func _find_enemy_building_targets(max_count: int) -> Array[Node]:
	var origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else Vector2.ZERO
	var candidates: Array[Node] = []
	var etc: Node2D = get_primary_enemy_tc()
	if etc != null:
		candidates.append(etc)
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		var sv: Variant = building.get("state")
		if sv != null and (sv as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			continue
		if not candidates.has(building):
			candidates.append(building)
	candidates.sort_custom(func(a: Node, b: Node) -> bool:
		return origin.distance_to((a as Node2D).global_position) < \
			   origin.distance_to((b as Node2D).global_position)
	)
	return candidates.slice(0, max_count) as Array[Node]

func find_nearest_enemy_building() -> Node:
	var origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else Vector2.ZERO
	var best: Node = null
	var best_dist: float = INF
	var etc: Node2D = get_primary_enemy_tc()
	if etc != null:
		best = etc
		best_dist = origin.distance_to(etc.global_position)
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		var sv: Variant = building.get("state")
		if sv != null and (sv as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			continue
		var d: float = origin.distance_to((building as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = building
	return best

func find_nearest_enemy_unit() -> Node:
	var origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else Vector2.ZERO
	var best: Node = null
	var best_dist: float = INF
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		if unit.get("is_cloaked") == true:
			continue
		var d: float = origin.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

func _escalate_aggression(level: AggressionLevel) -> void:
	if level > _aggression:
		_aggression = level
	_aggression_timer = 0.0

func _defend_base() -> void:
	if not is_instance_valid(_ai.town_center):
		return
	var best_enemy: Node = null
	var best_dist: float = CONTROL_ZONE_RADIUS
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		if unit.get("is_cloaked") == true:
			continue
		var d: float = (unit as Node2D).global_position.distance_to(_ai.town_center.global_position)
		if d < best_dist:
			best_dist = d
			best_enemy = unit
	if best_enemy == null:
		return
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if is_military_unit(unit) and unit.has_method("order_attack"):
			unit.order_attack(best_enemy)

func _pick_unit_to_train(desired: Dictionary) -> String:
	var militia_c: int = _count_of_type("Militia")
	var archer_c: int  = _count_of_type("Archer")
	var pike_c: int    = _count_of_type("Pikeman")
	var total: int     = militia_c + archer_c + pike_c

	if total == 0:
		for unit_id: String in ["militia", "archer", "pikeman"]:
			if _can_train(unit_id):
				return unit_id
		return ""

	var best_id: String = ""
	var best_deficit: float = -1.0
	for unit_id: String in desired.keys():
		var want: float = desired[unit_id] as float
		if want <= 0.0:
			continue
		if not _can_train(unit_id):
			continue
		var current_ratio: float = 0.0
		match unit_id:
			"militia": current_ratio = float(militia_c) / float(total)
			"archer":  current_ratio = float(archer_c)  / float(total)
			"pikeman": current_ratio = float(pike_c)    / float(total)
		var deficit: float = want - current_ratio
		if deficit > best_deficit:
			best_deficit = deficit
			best_id = unit_id
	return best_id

func _can_train(unit_id: String) -> bool:
	var age: int = AgeManager.get_age(_ai.player_id)
	var ai_civ: String = MatchConfig.get_rival_civ_id(_ai.player_id)
	match unit_id:
		"militia":          return true
		"archer":           return age >= GameManager.Age.FEUDAL
		"pikeman":          return age >= GameManager.Age.CASTLE
		"menceyes_guard":   return age >= GameManager.Age.CASTLE and ai_civ == "guanches"
		"ravine_archer":    return age >= GameManager.Age.CASTLE and ai_civ == "canarii"
		"longbowman":       return age >= GameManager.Age.CASTLE and ai_civ == "britons"
		"conquistador":     return age >= GameManager.Age.CASTLE and ai_civ == "castellanos"
		"tidecaller":       return age >= GameManager.Age.CASTLE and ai_civ == "atlantes"
	return false

func _count_of_type(type_name: String) -> int:
	var count: int = 0
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		match type_name:
			"Villager":         if unit is Villager:         count += 1
			"Militia":          if unit is Militia:          count += 1
			"Archer":           if unit is Archer:           count += 1
			"Pikeman":          if unit is Pikeman:          count += 1
			"HeavyScout":       if unit is HeavyScout:       count += 1
			"Knight":           if unit is Knight:           count += 1
			"BatteringRam":     if unit is BatteringRam:     count += 1
			"Mangonel":         if unit is Mangonel:         count += 1
			"Trebuchet":        if unit is Trebuchet:        count += 1
			"MenceyesGuard":    if unit is MenceyesGuard:    count += 1
			"RavineArcher":     if unit is RavineArcher:     count += 1
			"SandRaider":       if unit is SandRaider:       count += 1
			"ChevalierNormand": if unit is ChevalierNormand: count += 1
			"Longbowman":       if unit is Longbowman:       count += 1
			"Conquistador":     if unit is Conquistador:     count += 1
			"Tidecaller":       if unit is Tidecaller:       count += 1
	return count

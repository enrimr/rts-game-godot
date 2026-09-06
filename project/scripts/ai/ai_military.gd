class_name AIMilitary extends RefCounted

var _ai  # AIPlayer — untyped Variant so dynamic property access works at runtime

enum AggressionLevel { PASSIVE, ALERTED, AGGRESSIVE }
var _aggression: AggressionLevel = AggressionLevel.PASSIVE
var _aggression_timer: float = 0.0

const CONTROL_ZONE_RADIUS: float  = 400.0

func setup(ai) -> void:
	_ai = ai

func update_aggression(delta: float) -> void:
	if _aggression > AggressionLevel.PASSIVE:
		_aggression_timer += delta
		if _aggression_timer >= GameSettings.get_ai_aggression_decay():
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
	var anchors: Array[Vector2] = []
	if is_instance_valid(_ai.town_center):
		anchors.append(_ai.town_center.global_position)
	for b: Node in _ai.world.own_buildings(_ai.player_id):
		anchors.append((b as Node2D).global_position)
	if anchors.is_empty():
		return
	for unit: Node in _ai.world.sighted_enemy_units(_ai.player_id):
		var upos: Vector2 = (unit as Node2D).global_position
		for anchor: Vector2 in anchors:
			if upos.distance_to(anchor) <= CONTROL_ZONE_RADIUS:
				_escalate_aggression(AggressionLevel.AGGRESSIVE)
				_defend_base()
				return

func launch_attack() -> void:
	var mcount: int = count_military()
	var min_units: int = GameSettings.get_ai_min_attack_units()
	if _aggression == AggressionLevel.AGGRESSIVE:
		min_units = maxi(min_units - 1, 1)

	var targets: Array[Node] = _find_enemy_building_targets(3)
	var etc: Node2D = get_primary_enemy_tc()
	if etc != null and not targets.has(etc):
		targets.append(etc)

	if targets.is_empty():
		var fallback: Node = find_nearest_enemy_unit()
		if fallback == null:
			return
		targets.append(fallback)
		# Mop-up: nothing left to siege — hunt the last sighted units with
		# whatever army stands, instead of waiting for a full wave that no
		# longer has a reason to exist.
		min_units = 1

	if mcount < min_units:
		return

	if _has_human_ally():
		NetworkSession.ai_ping(_ai.player_id, (targets[0] as Node2D).global_position)
		EventBus.ally_message.emit(_ai.player_id, "attack")

	var target_count: int = targets.size()

	var idle_attackers: Array[Node] = []
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if not is_military_unit(unit):
			continue
		var existing_target: Variant = unit.get("attack_target")
		if existing_target != null and is_instance_valid(existing_target as Node):
			var tpid: Variant = (existing_target as Node).get("player_id")
			if tpid != null and (tpid as int) != _ai.player_id:
				continue
		idle_attackers.append(unit)

	_ai.debug_log("ATTACK %d units → %d targets (aggr=%s)" % [idle_attackers.size(), target_count, AggressionLevel.keys()[_aggression]])
	# Round-robin target assignment, batched into one command per target.
	var by_target: Dictionary = {}   # target entity id → Array[int] of unit ids
	for i: int in range(idle_attackers.size()):
		var tid: int = EntityRegistry.id_of(targets[i % target_count])
		if not by_target.has(tid):
			by_target[tid] = [] as Array[int]
		(by_target[tid] as Array[int]).append(EntityRegistry.id_of(idle_attackers[i]))
	for tid: int in by_target:
		CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "attack",
			by_target[tid] as Array[int], tid))

func push_units_past_destroyed_building(destroyed: Node2D) -> void:
	var next_target: Node = find_nearest_enemy_building()
	if next_target == null:
		next_target = find_nearest_enemy_unit()
	if next_target == null:
		return
	const PUSH_RADIUS: float = 300.0
	var pushed: Array[int] = []
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if not is_military_unit(unit):
			continue
		if (unit as Node2D).global_position.distance_to(destroyed.global_position) > PUSH_RADIUS:
			continue
		var existing_target: Variant = unit.get("attack_target")
		var already_engaged: bool = existing_target != null and is_instance_valid(existing_target as Node) and existing_target != destroyed
		if already_engaged:
			continue
		pushed.append(EntityRegistry.id_of(unit))
	if not pushed.is_empty():
		CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "attack", pushed,
			EntityRegistry.id_of(next_target)))

func manage_military() -> void:
	if _ai._construction._built.get("barracks", 0) as int == 0:
		return

	var age: int = AgeManager.get_age(_ai.player_id)
	var military: int = count_military()
	var passive_target: int = GameSettings.get_ai_military_target_passive()
	var target: int = passive_target if _aggression == AggressionLevel.PASSIVE else passive_target + 4
	# Campaign ramp: early missions cap the standing army hard.
	if _ai.military_cap >= 0:
		target = mini(target, _ai.military_cap)

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

	var unit_id: String = _pick_unit_to_train(_counter_bias(desired))
	if unit_id.is_empty():
		return

	# Archers train at ArcheryRange; infantry at Barracks.
	if unit_id == "archer":
		for ar: ArcheryRange in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), ArcheryRange):
			if ar.state != BuildingBase.BuildingState.COMPLETE:
				continue
			if ar.get_queue().size() >= ar.get_max_queue():
				continue
			_ai.debug_log("TRAIN %s at archery_range" % unit_id)
			CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
				EntityRegistry.id_of(ar), unit_id))
			break
	else:
		for br: Barracks in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), Barracks):
			if br.state != BuildingBase.BuildingState.COMPLETE:
				continue
			if br.get_queue().size() >= br.get_max_queue():
				continue
			_ai.debug_log("TRAIN %s at barracks" % unit_id)
			CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
				EntityRegistry.id_of(br), unit_id))
			break

## Field medicine: once a Temple stands, keep a couple of Harimaguadas
## alive — their idle auto-triage mends the army between assaults.
const MAX_AI_HEALERS: int = 2

func manage_healers() -> void:
	if AgeManager.get_age(_ai.player_id) < 2:
		return
	if not ResourceManager.can_afford(_ai.player_id, {"food": 85, "gold": 25}):
		return
	var healers: int = 0
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if unit.has_method("order_heal"):
			healers += 1
	if healers >= MAX_AI_HEALERS:
		return
	for temple: Temple in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), Temple):
		if temple.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if temple.get_queue().size() >= temple.get_max_queue():
			continue
		CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
			EntityRegistry.id_of(temple), "harimaguada"))
		break

func manage_unique_barracks_unit() -> void:
	if _ai._construction._built.get("barracks", 0) as int == 0 \
			and _ai._construction._built.get("archery_range", 0) as int == 0:
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
	# Archer-class unique units train at ArcheryRange; others at Barracks.
	var use_archery_range: bool = unique_id == "ravine_archer" or unique_id == "longbowman"
	var prod_type: Variant = ArcheryRange if use_archery_range else Barracks
	for building: Node in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), prod_type):
		if building.get("state") as int != BuildingBase.BuildingState.COMPLETE:
			continue
		if (building.get_queue() as Array).size() >= building.get_max_queue() as int:
			continue
		CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
			EntityRegistry.id_of(building), unique_id))
		break

func manage_stable_training() -> void:
	if GameSettings.difficulty <= GameSettings.Difficulty.EASY:
		return
	if _ai._construction._built.get("stable", 0) as int == 0:
		return
	var age: int = AgeManager.get_age(_ai.player_id)
	var ai_civ: String = MatchConfig.get_rival_civ_id(_ai.player_id)
	for st: Stable in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), Stable):
		if st.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if st.get_queue().size() >= st.get_max_queue():
			continue
		var stable_unit: String = ""
		if age >= GameManager.Age.CASTLE and ai_civ == "franks" and ResourceManager.can_afford(_ai.player_id, {"food": 75, "gold": 65}):
			stable_unit = "chevalier_normand"
		elif age >= GameManager.Age.CASTLE and ResourceManager.can_afford(_ai.player_id, {"food": 60, "gold": 75}):
			stable_unit = "knight"
		elif age >= GameManager.Age.FEUDAL and ai_civ == "mahos" and ResourceManager.can_afford(_ai.player_id, {"food": 60, "gold": 40}):
			stable_unit = "sand_raider"
		elif age >= GameManager.Age.FEUDAL and ResourceManager.can_afford(_ai.player_id, {"food": 80, "gold": 30}):
			stable_unit = "heavy_scout"
		if not stable_unit.is_empty():
			CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
				EntityRegistry.id_of(st), stable_unit))
		break

func manage_siege_training() -> void:
	if GameSettings.difficulty <= GameSettings.Difficulty.EASY:
		return
	if _ai._construction._built.get("siege_workshop", 0) as int == 0:
		return
	var age: int = AgeManager.get_age(_ai.player_id)
	for sw: SiegeWorkshop in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), SiegeWorkshop):
		if sw.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if sw.get_queue().size() >= sw.get_max_queue():
			continue
		var siege_unit: String = ""
		if age >= GameManager.Age.IMPERIAL and ResourceManager.can_afford(_ai.player_id, {"wood": 200, "gold": 200}):
			siege_unit = "trebuchet"
		elif ResourceManager.can_afford(_ai.player_id, {"wood": 160, "gold": 135}):
			siege_unit = "mangonel"
		elif ResourceManager.can_afford(_ai.player_id, {"wood": 160}):
			siege_unit = "battering_ram"
		if not siege_unit.is_empty():
			CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
				EntityRegistry.id_of(sw), siege_unit))
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
	if GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL:
		return
	var research_cap: int = 2 if GameSettings.difficulty == GameSettings.Difficulty.EASY else 999
	for building: Node in _ai.world.own_buildings(_ai.player_id):
		var btype: int = _research_building_type(building)
		if btype < 0:
			continue
		if TechManager.get_researching_tech(building) != null:
			continue
		if GameSettings.difficulty == GameSettings.Difficulty.EASY:
			var done: int = TechManager.get_researched_count(_ai.player_id)
			if done >= research_cap:
				continue
		var available: Array[TechnologyResource] = TechManager.get_available_techs(_ai.player_id, btype)
		if available.is_empty():
			continue
		var chosen: TechnologyResource = _pick_research(available)
		if chosen != null:
			_ai.debug_log("RESEARCH %s" % chosen.id)
			CommandBus.submit(ProductionCommand.make(_ai.player_id, "research",
				EntityRegistry.id_of(building), chosen.id))

func _research_building_type(building: Node) -> int:
	if building is Blacksmith:    return TechnologyResource.ResearchBuilding.BLACKSMITH
	if building is University:    return TechnologyResource.ResearchBuilding.UNIVERSITY
	if building is Temple:        return TechnologyResource.ResearchBuilding.MONASTERY
	if building is Barracks:      return TechnologyResource.ResearchBuilding.BARRACKS
	if building is ArcheryRange:  return TechnologyResource.ResearchBuilding.BARRACKS
	if building is Stable:        return TechnologyResource.ResearchBuilding.STABLE
	if building is LumberCamp:    return TechnologyResource.ResearchBuilding.LUMBER_CAMP
	if building is MiningCamp:    return TechnologyResource.ResearchBuilding.MINING_CAMP
	if building is Mill:          return TechnologyResource.ResearchBuilding.MILL
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
	for building: Node in _ai.world.enemy_buildings(_ai.player_id):
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

## Fog-honest attack-target picks: only buildings the AI has actually scouted
## (sighted now, or remembered from an earlier sighting — they don't move) are
## candidates. The primary enemy TC stays known: starting positions are map
## knowledge, and without a destination the AI would never leave its base.
func _find_enemy_building_targets(max_count: int) -> Array[Node]:
	var origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else Vector2.ZERO
	var candidates: Array[Node] = []
	var etc: Node2D = get_primary_enemy_tc()
	if etc != null:
		candidates.append(etc)
	for building: Node in _ai.world.known_enemy_buildings(_ai.player_id):
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
	for building: Node in _ai.world.known_enemy_buildings(_ai.player_id):
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
	for unit: Node in _ai.world.sighted_enemy_units(_ai.player_id):
		var d: float = origin.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

func _escalate_aggression(level: AggressionLevel) -> void:
	if level > _aggression:
		_ai.debug_log("AGGRESSION → %s" % AggressionLevel.keys()[level])
		_aggression = level
	_aggression_timer = 0.0

# ── Allied-team behaviour ────────────────────────────────────────────────────

const ASSIST_COOLDOWN_SEC: float = 30.0
const ASSIST_MIN_ARMY: int = 4
const ASSIST_SQUAD_MAX: int = 8
var _last_assist_msec: int = -100000

## An ally is being attacked at `pos`: send a squad to help (attack-move, so
## they engage whatever they meet), ping the spot for the team and say so.
func assist_ally(pos: Vector2) -> void:
	if Time.get_ticks_msec() - _last_assist_msec < int(ASSIST_COOLDOWN_SEC * 1000.0):
		return
	if count_military() < ASSIST_MIN_ARMY:
		return
	var soldiers: Array[Node] = []
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if is_military_unit(unit):
			soldiers.append(unit)
	soldiers.sort_custom(func(a: Node, b: Node) -> bool:
		return (a as Node2D).global_position.distance_squared_to(pos) \
			< (b as Node2D).global_position.distance_squared_to(pos))
	var squad: Array[int] = []
	for i: int in range(mini(ASSIST_SQUAD_MAX, soldiers.size())):
		squad.append(EntityRegistry.id_of(soldiers[i]))
	if squad.is_empty():
		return
	_last_assist_msec = Time.get_ticks_msec()
	CommandBus.submit(UnitPointCommand.make(_ai.player_id, "attack_move", squad, pos))
	NetworkSession.ai_ping(_ai.player_id, pos)
	EventBus.ally_message.emit(_ai.player_id, "assist")

func _has_human_ally() -> bool:
	for pid: Variant in NetworkSession.match_human_ids:
		if (pid as int) != _ai.player_id \
				and GameManager.are_allied(_ai.player_id, pid as int):
			return true
	return false

func _defend_base() -> void:
	# Find the enemy unit closest to any AI building/TC.
	var best_enemy: Node = null
	var best_dist: float = CONTROL_ZONE_RADIUS
	for unit: Node in _ai.world.sighted_enemy_units(_ai.player_id):
		var upos: Vector2 = (unit as Node2D).global_position
		var min_d: float = INF
		if is_instance_valid(_ai.town_center):
			min_d = minf(min_d, upos.distance_to(_ai.town_center.global_position))
		for b: Node in _ai.world.own_buildings(_ai.player_id):
			min_d = minf(min_d, upos.distance_to((b as Node2D).global_position))
		if min_d < best_dist:
			best_dist = min_d
			best_enemy = unit
	if best_enemy == null:
		return
	var defenders: Array[int] = []
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if is_military_unit(unit):
			defenders.append(EntityRegistry.id_of(unit))
	if not defenders.is_empty():
		CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "attack", defenders,
			EntityRegistry.id_of(best_enemy)))

## Counter-intel: shift the desired barracks mix toward the counters of what
## the enemy actually FIELDS (fog-honest: sighted units only). Cavalry on the
## board raises the pike share, archer lines raise the sword fodder that
## closes on them, infantry masses raise archers — composition now answers
## composition instead of following the static per-age table blindly.
func _counter_bias(desired: Dictionary) -> Dictionary:
	var seen: Array = _ai.world.sighted_enemy_units(_ai.player_id)
	if seen.size() < 4:
		return desired
	var cav: int = 0
	var arch: int = 0
	var inf: int = 0
	for u: Node in seen:
		match UnitBase.combat_class_of(u):
			"cavalry":
				cav += 1
			"archer":
				arch += 1
			"infantry", "spearman":
				inf += 1
	var total: int = cav + arch + inf
	if total == 0:
		return desired
	var out: Dictionary = desired.duplicate()
	out["pikeman"] = (out.get("pikeman", 0.0) as float) + float(cav) / float(total) * 0.6
	out["militia"] = (out.get("militia", 0.0) as float) + float(arch) / float(total) * 0.4
	out["archer"] = (out.get("archer", 0.0) as float) + float(inf) / float(total) * 0.4
	return out

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
		"pikeman":          return age >= GameManager.Age.CASTLE \
			or CivBonusManager.has_bonus(_ai.player_id, "spear_available_dark_age")
		"menceyes_guard":   return age >= GameManager.Age.CASTLE and ai_civ == "guanches"
		"ravine_archer":    return age >= GameManager.Age.CASTLE and ai_civ == "canarii"
		"longbowman":       return age >= GameManager.Age.CASTLE and ai_civ == "britons"
		"conquistador":     return age >= GameManager.Age.CASTLE and ai_civ == "castellanos"
		"tidecaller":       return age >= GameManager.Age.CASTLE and ai_civ == "atlantes"
	return false

func _count_of_type(type_name: String) -> int:
	var count: int = 0
	for unit: Node in _ai.world.own_units(_ai.player_id):
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

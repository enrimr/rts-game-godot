extends Node

var _researched: Dictionary = {}        # {player_id: Array[String]}
var _all_techs: Dictionary = {}         # {tech_id: TechnologyResource}
var _active_research: Dictionary = {}   # {building_instance_id (int): {tech_id, player_id, timer, total_time}}

func _ready() -> void:
	_scan_techs()

func _scan_techs() -> void:
	var dir: DirAccess = DirAccess.open("res://resources/technologies/")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path: String = "res://resources/technologies/" + file_name
			var res: Resource = load(full_path)
			if res is TechnologyResource:
				var tech: TechnologyResource = res as TechnologyResource
				_all_techs[tech.id] = tech
		file_name = dir.get_next()
	dir.list_dir_end()

func init_player(player_id: int) -> void:
	_researched[player_id] = []

func is_researched(player_id: int, tech_id: String) -> bool:
	var list: Variant = _researched.get(player_id)
	if list == null:
		return false
	return (list as Array).has(tech_id)

func get_researched_count(player_id: int) -> int:
	var list: Variant = _researched.get(player_id)
	if list == null:
		return 0
	return (list as Array).size()

func can_research(player_id: int, tech_id: String) -> bool:
	if is_researched(player_id, tech_id):
		return false
	if not _all_techs.has(tech_id):
		return false
	var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
	if AgeManager.get_age(player_id) < tech.required_age:
		return false
	for prereq: String in tech.prerequisites:
		if not is_researched(player_id, prereq):
			return false
	var costs: Dictionary = {}
	if tech.cost_food > 0: costs["food"] = tech.cost_food
	if tech.cost_wood > 0: costs["wood"] = tech.cost_wood
	if tech.cost_gold > 0: costs["gold"] = tech.cost_gold
	return ResourceManager.can_afford(player_id, costs)

func start_research(player_id: int, tech_id: String, building: Node) -> bool:
	if not can_research(player_id, tech_id):
		return false
	if not is_instance_valid(building):
		return false
	var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
	var costs: Dictionary = {}
	if tech.cost_food > 0: costs["food"] = tech.cost_food
	if tech.cost_wood > 0: costs["wood"] = tech.cost_wood
	if tech.cost_gold > 0: costs["gold"] = tech.cost_gold
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	var iid: int = building.get_instance_id()
	_active_research[iid] = {
		"tech_id": tech_id,
		"player_id": player_id,
		"timer": 0.0,
		"total_time": tech.research_time,
	}
	return true

func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	var finished_keys: Array = []
	for iid: Variant in _active_research.keys():
		var entry: Dictionary = _active_research[iid] as Dictionary
		var instance_id: int = iid as int
		var obj: Object = instance_from_id(instance_id)
		if not is_instance_valid(obj as Node):
			finished_keys.append(iid)
			continue
		entry["timer"] = (entry["timer"] as float) + delta
		if (entry["timer"] as float) >= (entry["total_time"] as float):
			finished_keys.append(iid)
			_apply_tech(entry["player_id"] as int, entry["tech_id"] as String)
			EventBus.technology_researched.emit(entry["player_id"] as int, entry["tech_id"] as String)
	for key: Variant in finished_keys:
		_active_research.erase(key)

func _apply_tech(player_id: int, tech_id: String) -> void:
	if not _all_techs.has(tech_id):
		return
	var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
	var list: Variant = _researched.get(player_id)
	if list == null:
		_researched[player_id] = []
	(_researched[player_id] as Array).append(tech_id)
	for key: Variant in tech.effects.keys():
		CivBonusManager.apply_tech_effect(player_id, key as String, tech.effects[key] as float)
	if tech.upgrade_from_unit_id != "":
		var to_res: UnitResource = load("res://resources/units/" + tech.upgrade_to_unit_id + "_data.tres") as UnitResource
		if to_res != null:
			EventBus.unit_upgrade_applied.emit(player_id, tech.upgrade_from_unit_id, to_res)

func get_available_techs(player_id: int, research_building_type: int) -> Array[TechnologyResource]:
	var result: Array[TechnologyResource] = []
	for tech_id: String in _all_techs.keys():
		var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
		if tech.research_building != research_building_type:
			continue
		if is_researched(player_id, tech_id):
			continue
		if AgeManager.get_age(player_id) < tech.required_age:
			continue
		var prereqs_met: bool = true
		for prereq: String in tech.prerequisites:
			if not is_researched(player_id, prereq):
				prereqs_met = false
				break
		if prereqs_met:
			result.append(tech)
	return result

func get_research_progress(building: Node) -> float:
	if not is_instance_valid(building):
		return 0.0
	var iid: int = building.get_instance_id()
	if not _active_research.has(iid):
		return 0.0
	var entry: Dictionary = _active_research[iid] as Dictionary
	var total: float = entry["total_time"] as float
	if total <= 0.0:
		return 1.0
	return clampf((entry["timer"] as float) / total, 0.0, 1.0)

func get_researching_tech(building: Node) -> TechnologyResource:
	if not is_instance_valid(building):
		return null
	var iid: int = building.get_instance_id()
	if not _active_research.has(iid):
		return null
	var entry: Dictionary = _active_research[iid] as Dictionary
	var tech_id: String = entry["tech_id"] as String
	if not _all_techs.has(tech_id):
		return null
	return _all_techs[tech_id] as TechnologyResource

## Instantly applies a technology for a player without cost or build time.
## Used for civ bonuses like Castellanos free Blacksmith tech per age.
func grant_tech(player_id: int, tech_id: String) -> void:
	if not _all_techs.has(tech_id):
		return
	if is_researched(player_id, tech_id):
		return
	_apply_tech(player_id, tech_id)
	EventBus.technology_researched.emit(player_id, tech_id)

## Returns the first unresearched Blacksmith tech available at or below the
## given age, respecting prerequisites. Returns "" if none found.
func get_oldest_unresearched_blacksmith_tech(player_id: int, max_age: int) -> String:
	var candidates: Array[TechnologyResource] = []
	for tech_id: String in _all_techs.keys():
		var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
		if tech.research_building != 0:  # 0 = BLACKSMITH
			continue
		if is_researched(player_id, tech_id):
			continue
		if tech.required_age > max_age:
			continue
		var prereqs_met: bool = true
		for prereq: String in tech.prerequisites:
			if not is_researched(player_id, prereq):
				prereqs_met = false
				break
		if prereqs_met:
			candidates.append(tech)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: TechnologyResource, b: TechnologyResource) -> bool:
		return (a as TechnologyResource).required_age < (b as TechnologyResource).required_age)
	return (candidates[0] as TechnologyResource).id

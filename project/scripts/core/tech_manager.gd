extends Node

var _researched: Dictionary = {}        # {player_id: Array[String]}
var _all_techs: Dictionary = {}         # {tech_id: TechnologyResource}
var _active_research: Dictionary = {}   # {building_instance_id (int): {tech_id, player_id, timer, total_time}}
## Techs waiting behind the active one, AoE2-training-queue style: paid at
## enqueue time, refunded slot by slot on cancel, promoted automatically.
var _research_queue: Dictionary = {}    # {building_instance_id (int): Array[String]}
const MAX_RESEARCH_QUEUE: int = 5

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

## Entry point for the research verb: starts immediately when the building is
## idle, otherwise QUEUES behind the active tech (paid now, like unit
## training). Chains queue naturally — a queued prerequisite counts as met.
func start_research(player_id: int, tech_id: String, building: Node) -> bool:
	if not is_instance_valid(building):
		return false
	var iid: int = building.get_instance_id()
	if not _can_queue(player_id, tech_id, iid):
		return false
	var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
	if not ResourceManager.spend_resource(player_id, _costs_of(tech)):
		return false
	if _active_research.has(iid):
		var queue: Array = _research_queue.get(iid, []) as Array
		queue.append(tech_id)
		_research_queue[iid] = queue
	else:
		_activate(player_id, tech_id, iid)
	EventBus.research_state_changed.emit(building)
	return true

func _activate(player_id: int, tech_id: String, iid: int) -> void:
	var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
	_active_research[iid] = {
		"tech_id": tech_id,
		"player_id": player_id,
		"timer": 0.0,
		"total_time": tech.research_time,
	}

func _costs_of(tech: TechnologyResource) -> Dictionary:
	var costs: Dictionary = {}
	if tech.cost_food > 0: costs["food"] = tech.cost_food
	if tech.cost_wood > 0: costs["wood"] = tech.cost_wood
	if tech.cost_gold > 0: costs["gold"] = tech.cost_gold
	return costs

## can_research, but a tech already active or queued in THIS building counts
## as done for prerequisites and as a duplicate for itself.
func _can_queue(player_id: int, tech_id: String, iid: int) -> bool:
	if not _all_techs.has(tech_id) or is_researched(player_id, tech_id):
		return false
	var in_flight: Array = pending_research_ids(iid)
	if tech_id in in_flight:
		return false
	if in_flight.size() >= MAX_RESEARCH_QUEUE:
		return false
	var tech: TechnologyResource = _all_techs[tech_id] as TechnologyResource
	if AgeManager.get_age(player_id) < tech.required_age:
		return false
	for prereq: String in tech.prerequisites:
		if not is_researched(player_id, prereq) and not (prereq in in_flight):
			return false
	return ResourceManager.can_afford(player_id, _costs_of(tech))

## Active + queued tech ids for one building (HUD and validation).
func pending_research_ids(iid: int) -> Array:
	var out: Array = []
	if _active_research.has(iid):
		out.append((_active_research[iid] as Dictionary)["tech_id"])
	out.append_array(_research_queue.get(iid, []) as Array)
	return out

func get_research_queue(building: Node) -> Array:
	if not is_instance_valid(building):
		return []
	return (_research_queue.get(building.get_instance_id(), []) as Array).duplicate()

## Cancels ONE queued (not yet active) tech by queue index, with full refund.
func cancel_queued_research(building: Node, index: int) -> bool:
	if not is_instance_valid(building):
		return false
	var iid: int = building.get_instance_id()
	var queue: Array = _research_queue.get(iid, []) as Array
	if index < 0 or index >= queue.size():
		return false
	var tech: TechnologyResource = _all_techs.get(queue[index]) as TechnologyResource
	queue.remove_at(index)
	_research_queue[iid] = queue
	if tech != null:
		_refund(building.get("player_id") as int, tech)
	EventBus.research_state_changed.emit(building)
	return true

func _refund(player_id: int, tech: TechnologyResource) -> void:
	if tech.cost_food > 0: ResourceManager.add_resource(player_id, "food", float(tech.cost_food))
	if tech.cost_wood > 0: ResourceManager.add_resource(player_id, "wood", float(tech.cost_wood))
	if tech.cost_gold > 0: ResourceManager.add_resource(player_id, "gold", float(tech.cost_gold))

## The next queued tech takes the bench the moment the active slot frees up.
func _promote_next(iid: int, building: Node) -> void:
	var queue: Array = _research_queue.get(iid, []) as Array
	if queue.is_empty():
		return
	var pid: int = -1
	if is_instance_valid(building) and building.get("player_id") != null:
		pid = building.get("player_id") as int
	if pid < 0:
		return
	_activate(pid, queue.pop_front() as String, iid)
	_research_queue[iid] = queue

## Aborts a building's active research with a full refund (AoE2 rule).
func cancel_research(building: Node) -> bool:
	if not is_instance_valid(building):
		return false
	var iid: int = building.get_instance_id()
	if not _active_research.has(iid):
		return false
	var entry: Dictionary = _active_research[iid] as Dictionary
	var tech: TechnologyResource = _all_techs.get(entry["tech_id"]) as TechnologyResource
	var pid: int = entry["player_id"] as int
	if tech != null:
		_refund(pid, tech)
	_active_research.erase(iid)
	_promote_next(iid, building)
	EventBus.research_state_changed.emit(building)
	return true

func _physics_process(delta: float) -> void:
	# A LAN client mirrors research from replication; ticking locally would
	# apply techs twice and desync the HUD.
	if NetworkSession.is_client():
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	var finished_keys: Array = []
	for iid: Variant in _active_research.keys():
		var entry: Dictionary = _active_research[iid] as Dictionary
		var instance_id: int = iid as int
		var obj: Object = instance_from_id(instance_id)
		if not is_instance_valid(obj as Node):
			# The lab fell: refund whatever was still waiting in its queue.
			var pid: int = entry["player_id"] as int
			for queued: Variant in _research_queue.get(iid, []) as Array:
				var qtech: TechnologyResource = _all_techs.get(queued) as TechnologyResource
				if qtech != null:
					_refund(pid, qtech)
			_research_queue.erase(iid)
			finished_keys.append(iid)
			continue
		entry["timer"] = (entry["timer"] as float) + delta
		if (entry["timer"] as float) >= (entry["total_time"] as float):
			finished_keys.append(iid)
			_apply_tech(entry["player_id"] as int, entry["tech_id"] as String)
			EventBus.technology_researched.emit(entry["player_id"] as int, entry["tech_id"] as String)
			EventBus.research_state_changed.emit(obj as Node)
	for key: Variant in finished_keys:
		_active_research.erase(key)
		var obj: Object = instance_from_id(key as int)
		if is_instance_valid(obj as Node):
			_promote_next(key as int, obj as Node)
			if _active_research.has(key):
				EventBus.research_state_changed.emit(obj as Node)

## Replication: mirror a building's active research (client HUD slot).
func apply_remote_research(building: Node, tech_id: String, timer: float, total: float) -> void:
	if not is_instance_valid(building):
		return
	var iid: int = building.get_instance_id()
	var had: bool = _active_research.has(iid)
	var changed: bool = not had \
		or ((_active_research[iid] as Dictionary).get("tech_id", "") as String) != tech_id
	_active_research[iid] = {
		"tech_id": tech_id,
		"player_id": building.get("player_id") as int,
		"timer": timer,
		"total_time": total,
	}
	if changed:
		EventBus.research_state_changed.emit(building)

## Replication: mirror a building's research QUEUE (client HUD slots).
func apply_remote_research_queue(building: Node, tech_ids: Array) -> void:
	if not is_instance_valid(building):
		return
	var iid: int = building.get_instance_id()
	if (_research_queue.get(iid, []) as Array) == tech_ids:
		return
	_research_queue[iid] = tech_ids.duplicate()
	EventBus.research_state_changed.emit(building)

## Replication: the host reports no active research for this building.
func clear_remote_research(building: Node) -> void:
	if not is_instance_valid(building):
		return
	var iid: int = building.get_instance_id()
	if _active_research.has(iid):
		_active_research.erase(iid)
		EventBus.research_state_changed.emit(building)

## Replication: adopt the host's researched-tech list for a player. New techs
## get their effects applied locally too, so displayed stats stay consistent.
func apply_remote_researched(player_id: int, tech_ids: Array) -> void:
	for tid: Variant in tech_ids:
		if not is_researched(player_id, tid as String):
			_apply_tech(player_id, tid as String)
			EventBus.technology_researched.emit(player_id, tid as String)

func get_researched(player_id: int) -> Array:
	return (_researched.get(player_id, []) as Array).duplicate()

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

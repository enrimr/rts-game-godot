class_name AIEconomy extends RefCounted

var _ai: Node  # AIPlayer — untyped to avoid circular class reference

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")

func setup(ai: Node) -> void:
	_ai = ai

func manage_villagers() -> void:
	if not is_instance_valid(_ai.town_center):
		var counts: Dictionary = {}
		var assigned_total: int = 0
		for unit: Node in _ai.units_layer.get_children():
			if not is_instance_valid(unit) or not (unit is Villager):
				continue
			var vil: Villager = unit as Villager
			if vil.player_id != _ai.player_id or not is_instance_valid(vil.gather_target) or not (vil.gather_target is ResourceNode):
				continue
			var rt: ResourceNode.ResourceType = (vil.gather_target as ResourceNode).resource_type
			counts[rt] = (counts.get(rt, 0) as int) + 1
			assigned_total += 1
		for unit: Node in _ai.units_layer.get_children():
			if not is_instance_valid(unit) or not (unit is Villager):
				continue
			var v: Villager = unit as Villager
			if v.player_id != _ai.player_id or v.current_state != UnitBase.UnitState.IDLE:
				continue
			_assign_villager(v, counts, assigned_total)
		return
	var vcount: int = _count_of_type_villager()
	var target: int = GameSettings.get_ai_villager_target()
	if vcount < target and not PopulationManager.at_cap(_ai.player_id):
		spawn_villager()
	var counts: Dictionary = {}
	var assigned_total: int = 0
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var vil: Villager = unit as Villager
		if vil.player_id != _ai.player_id:
			continue
		if not is_instance_valid(vil.gather_target) or not (vil.gather_target is ResourceNode):
			continue
		var rt: ResourceNode.ResourceType = (vil.gather_target as ResourceNode).resource_type
		var n: int = counts.get(rt, 0) as int
		counts[rt] = n + 1
		assigned_total += 1
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != _ai.player_id:
			continue
		if v.current_state == UnitBase.UnitState.IDLE:
			_assign_villager(v, counts, assigned_total)

func manage_age_advance() -> void:
	if AgeManager.is_advancing(_ai.player_id):
		return
	if AgeManager.get_age(_ai.player_id) >= GameManager.Age.IMPERIAL:
		return
	var military: int = _ai._military.count_military()
	var _easy_mode: bool = GameSettings.difficulty == GameSettings.Difficulty.EASY or GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL
	var min_mil: int = 2 if _easy_mode else 3
	if military >= min_mil and AgeManager.can_advance(_ai.player_id):
		AgeManager.start_advance(_ai.player_id)

func find_nearest_resource(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for node: Node in _ai.get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.resource_type != rtype:
			continue
		var d: float = from.distance_to(rn.global_position)
		if d < best_dist:
			best_dist = d
			best = rn
	return best

func find_nearest_drop_off(rtype: ResourceNode.ResourceType) -> Node2D:
	var preferred_id: String
	match rtype:
		ResourceNode.ResourceType.WOOD:
			preferred_id = "lumber_camp"
		ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE:
			preferred_id = "mining_camp"
		_:
			return _ai.drop_off
	var best: Node2D = null
	var best_dist: float = INF
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		var bdata: Variant = building.get("building_data")
		if bdata == null:
			continue
		if (bdata as Resource).get("id") as String != preferred_id:
			continue
		if building.get("state") as int != BuildingBase.BuildingState.COMPLETE:
			continue
		var tc_pos: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else (building as Node2D).global_position
		var d: float = (building as Node2D).global_position.distance_to(tc_pos)
		if d < best_dist:
			best_dist = d
			best = building as Node2D
	return best if best != null else _ai.drop_off

func redirect_villagers_to_drop_off(new_drop: Node2D, rtype: ResourceNode.ResourceType) -> void:
	var reassigned: int = 0
	for unit: Node in _ai.units_layer.get_children():
		if reassigned >= 2:
			break
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != _ai.player_id:
			continue
		var carried: Variant = v.get("carried_resource")
		if carried != null and (carried as String) != "" and v.gather_target != null:
			v.drop_off_target = new_drop
			reassigned += 1

func spawn_villager() -> void:
	if not is_instance_valid(_ai.town_center):
		return
	if not ResourceManager.spend_resource(_ai.player_id, {"food": 50}):
		return
	var v: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	v.set("player_id", _ai.player_id)
	v.set("civ_id", MatchConfig.get_rival_civ_id(_ai.player_id))
	_ai.units_layer.add_child(v)
	v.global_position = _ai.town_center.global_position + Vector2(randf_range(-50.0, 50.0), 60.0)
	PopulationManager.add_unit(_ai.player_id)
	EventBus.unit_spawned.emit(v, _ai.player_id)

func _assign_villager(v: Villager, counts: Dictionary, assigned_total: int) -> void:
	var age: int = AgeManager.get_age(_ai.player_id)

	var target_fractions: Dictionary = {
		ResourceNode.ResourceType.FOOD_HUNT: 0.25,
		ResourceNode.ResourceType.WOOD:      0.20,
		ResourceNode.ResourceType.GOLD:      0.45,
		ResourceNode.ResourceType.STONE:     0.10,
	}
	match age:
		GameManager.Age.DARK:
			target_fractions = {
				ResourceNode.ResourceType.FOOD_HUNT: 0.60,
				ResourceNode.ResourceType.WOOD:      0.40,
				ResourceNode.ResourceType.GOLD:      0.00,
				ResourceNode.ResourceType.STONE:     0.00,
			}
		GameManager.Age.FEUDAL:
			target_fractions = {
				ResourceNode.ResourceType.FOOD_HUNT: 0.40,
				ResourceNode.ResourceType.WOOD:      0.30,
				ResourceNode.ResourceType.GOLD:      0.25,
				ResourceNode.ResourceType.STONE:     0.05,
			}
		GameManager.Age.CASTLE:
			target_fractions = {
				ResourceNode.ResourceType.FOOD_HUNT: 0.30,
				ResourceNode.ResourceType.WOOD:      0.25,
				ResourceNode.ResourceType.GOLD:      0.35,
				ResourceNode.ResourceType.STONE:     0.10,
			}

	var best_node: ResourceNode = null
	var best_deficit: float = -INF
	var total: float = float(assigned_total + 1)
	for rtype: ResourceNode.ResourceType in target_fractions.keys():
		var want: float = target_fractions[rtype] as float
		if want <= 0.0:
			continue
		var node: ResourceNode = find_nearest_resource(rtype, v.global_position)
		if node == null:
			continue
		var current_frac: float = float(counts.get(rtype, 0) as int) / total
		var deficit: float = want - current_frac
		if deficit > best_deficit:
			best_deficit = deficit
			best_node = node

	if best_node == null:
		return
	var nearest_drop: Node2D = find_nearest_drop_off(best_node.resource_type)
	v.order_gather(best_node, best_node.get_resource_name(), nearest_drop if nearest_drop != null else _ai.drop_off)

func _count_of_type_villager() -> int:
	var count: int = 0
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if unit is Villager:
			count += 1
	return count

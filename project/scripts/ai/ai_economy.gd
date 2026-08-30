class_name AIEconomy extends RefCounted

var _ai  # AIPlayer — untyped Variant so dynamic property access works at runtime

func setup(ai) -> void:
	_ai = ai

## Own villagers (typed), via WorldQuery — replaces the repeated
## "for child / is Villager / player_id == mine" scans in this module.
func _own_villagers() -> Array:
	return WorldQuery.of_type(_ai.world.own_units(_ai.player_id), Villager)

func manage_villagers() -> void:
	if not is_instance_valid(_ai.town_center):
		var counts: Dictionary = {}
		var assigned_total: int = 0
		for vil: Villager in _own_villagers():
			if not is_instance_valid(vil.gather_target) or not (vil.gather_target is ResourceNode):
				continue
			var rt: ResourceNode.ResourceType = _food_bucket((vil.gather_target as ResourceNode).resource_type)
			counts[rt] = (counts.get(rt, 0) as int) + 1
			assigned_total += 1
		for v: Villager in _own_villagers():
			if v.current_state != UnitBase.UnitState.IDLE:
				continue
			_assign_villager(v, counts, assigned_total)
		return
	var vcount: int = _count_of_type_villager()
	var target: int = GameSettings.get_ai_villager_target()
	if vcount < target and not PopulationManager.at_cap(_ai.player_id) \
			and not _ai.is_saving_for_age_up():
		spawn_villager()
	var counts: Dictionary = {}
	var assigned_total: int = 0
	for vil: Villager in _own_villagers():
		if not is_instance_valid(vil.gather_target) or not (vil.gather_target is ResourceNode):
			continue
		var rt: ResourceNode.ResourceType = _food_bucket((vil.gather_target as ResourceNode).resource_type)
		var n: int = counts.get(rt, 0) as int
		counts[rt] = n + 1
		assigned_total += 1
	for v: Villager in _own_villagers():
		if v.current_state == UnitBase.UnitState.IDLE:
			_assign_villager(v, counts, assigned_total)

## All food sources fill the same allocation bucket (keyed on FOOD_HUNT), so
## berry/fish gatherers count against the food target instead of leaking out.
func _food_bucket(rtype: ResourceNode.ResourceType) -> ResourceNode.ResourceType:
	if rtype == ResourceNode.ResourceType.FOOD_BERRY or rtype == ResourceNode.ResourceType.FOOD_FISH:
		return ResourceNode.ResourceType.FOOD_HUNT
	return rtype

func manage_age_advance() -> void:
	if AgeManager.is_advancing(_ai.player_id):
		return
	if AgeManager.get_age(_ai.player_id) >= GameManager.Age.IMPERIAL:
		return
	var military: int = _ai._military.count_military()
	if military >= GameSettings.get_ai_age_advance_min_military() and AgeManager.can_advance(_ai.player_id):
		_ai.debug_log("AGE ADVANCE started (mil=%d)" % military)
		CommandBus.submit(AdvanceAgeCommand.make(_ai.player_id))

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

# A valid drop-off node, or null. _ai.drop_off can point at a freed Town Center
# after the TC is destroyed (it is only reassigned on rebuild), so never hand it
# back without an is_instance_valid check.
func _base_drop_off() -> Node2D:
	return _ai.drop_off if is_instance_valid(_ai.drop_off) else null

func find_nearest_drop_off(rtype: ResourceNode.ResourceType) -> Node2D:
	var preferred_id: String
	match rtype:
		ResourceNode.ResourceType.WOOD:
			preferred_id = "lumber_camp"
		ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE:
			preferred_id = "mining_camp"
		_:
			return _base_drop_off()
	var best: Node2D = null
	var best_dist: float = INF
	for building: Node in _ai.world.own_buildings(_ai.player_id):
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
	return best if best != null else _base_drop_off()

func redirect_villagers_to_drop_off(new_drop: Node2D, _rtype: ResourceNode.ResourceType) -> void:
	var ids: Array[int] = []
	for v: Villager in _own_villagers():
		if ids.size() >= 2:
			break
		var carried: Variant = v.get("carried_resource")
		if carried != null and (carried as String) != "" and v.gather_target != null:
			ids.append(EntityRegistry.id_of(v))
	if not ids.is_empty():
		CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "set_drop_off", ids,
			EntityRegistry.id_of(new_drop)))

## Queues a villager at the AI's Town Center — the SAME queue, cost and train
## time the player pays. The old instant spawn skipped the wait entirely and
## unbalanced the early game. At most 2 queued at a time, so the food bank
## stays honest for the age-up logic.
const MAX_AI_TC_QUEUE: int = 2

func spawn_villager() -> void:
	if not is_instance_valid(_ai.town_center) or not _ai.town_center.has_method("order_train"):
		return
	if (_ai.town_center.get_queue() as Array).size() >= MAX_AI_TC_QUEUE:
		return
	if not ResourceManager.can_afford(_ai.player_id, {"food": 50}):
		return
	_ai.debug_log("QUEUE villager")
	CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
		EntityRegistry.id_of(_ai.town_center)))

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
		# The food bucket is keyed on hunt, but game maps run out of huntables
		# long before the food need does — fall back to berry patches so the AI
		# does not starve into an eternal Dark Age once the fauna is gone.
		if node == null and rtype == ResourceNode.ResourceType.FOOD_HUNT:
			node = find_nearest_resource(ResourceNode.ResourceType.FOOD_BERRY, v.global_position)
		if node == null:
			continue
		var current_frac: float = float(counts.get(rtype, 0) as int) / total
		var deficit: float = want - current_frac
		if deficit > best_deficit:
			best_deficit = deficit
			best_node = node

	if best_node == null:
		return
	# find_nearest_drop_off already returns null when there is no valid drop-off
	# (e.g. the Town Center was destroyed); order_gather tolerates a null target.
	var nearest_drop: Node2D = find_nearest_drop_off(best_node.resource_type)
	_ai.debug_log("GATHER villager → %s (deficit=%.2f)" % [best_node.get_resource_name(), best_deficit])
	CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "gather",
		[EntityRegistry.id_of(v)] as Array[int], EntityRegistry.id_of(best_node),
		EntityRegistry.id_of(nearest_drop) if nearest_drop != null else 0))

func _count_of_type_villager() -> int:
	return _own_villagers().size()

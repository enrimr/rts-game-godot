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
		ResourceNode.ResourceType.FOOD_HUNT, ResourceNode.ResourceType.FOOD_BERRY:
			preferred_id = "mill"
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

func _target_fractions_for_age(age: int) -> Dictionary:
	match age:
		GameManager.Age.DARK:
			return {
				ResourceNode.ResourceType.FOOD_HUNT: 0.60,
				ResourceNode.ResourceType.WOOD:      0.40,
				ResourceNode.ResourceType.GOLD:      0.00,
				ResourceNode.ResourceType.STONE:     0.00,
			}
		GameManager.Age.FEUDAL:
			return {
				ResourceNode.ResourceType.FOOD_HUNT: 0.40,
				ResourceNode.ResourceType.WOOD:      0.30,
				ResourceNode.ResourceType.GOLD:      0.25,
				ResourceNode.ResourceType.STONE:     0.05,
			}
		GameManager.Age.CASTLE:
			return {
				ResourceNode.ResourceType.FOOD_HUNT: 0.30,
				ResourceNode.ResourceType.WOOD:      0.25,
				ResourceNode.ResourceType.GOLD:      0.35,
				ResourceNode.ResourceType.STONE:     0.10,
			}
	return {
		ResourceNode.ResourceType.FOOD_HUNT: 0.25,
		ResourceNode.ResourceType.WOOD:      0.20,
		ResourceNode.ResourceType.GOLD:      0.45,
		ResourceNode.ResourceType.STONE:     0.10,
	}

func _assign_villager(v: Villager, counts: Dictionary, assigned_total: int) -> void:
	var target_fractions: Dictionary = _target_fractions_for_age(AgeManager.get_age(_ai.player_id))

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

# ── Pastoral economy: Presa Canario herding + eating the flock ────────────────

const MAX_AI_DOGS: int = 2
const DOG_COST: Dictionary = {"food": 30, "gold": 10}
const DOG_HERD_RADIUS: float = 2000.0
const SLAUGHTER_RADIUS: float = 350.0

## The one slaughter order allowed in flight: while this sheep still lives the
## next order waits — its carcass feeds the hunters for a while anyway.
var _slaughter_target: Animal = null

## Own dogs, by capability (the Presa Canario has no class_name — order_herd
## is its contract, mirroring how manage_healers finds Harimaguadas).
func _own_dogs() -> Array:
	var dogs: Array = []
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if unit.has_method("order_herd"):
			dogs.append(unit)
	return dogs

func manage_dogs() -> void:
	var dogs: Array = _own_dogs()
	if not _ai.is_saving_for_age_up():
		_train_dog_if_wanted(dogs)
	# A herding trip rides the ATTACKING state, so only truly idle dogs get a
	# new order — that is the whole anti-spam throttle.
	var claimed: Dictionary = {}
	for dog: Node in dogs:
		var target: Variant = dog.get("herd_target")
		if target != null and is_instance_valid(target as Node):
			claimed[(target as Node).get_instance_id()] = true
	for dog: Node in dogs:
		if dog.get("current_state") as int != UnitBase.UnitState.IDLE:
			continue
		var animal: Animal = find_herdable_animal((dog as Node2D).global_position, claimed)
		if animal == null:
			return
		claimed[animal.get_instance_id()] = true
		_ai.debug_log("HERD dog → animal at (%.0f,%.0f)" % [animal.global_position.x, animal.global_position.y])
		CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "herd",
			[EntityRegistry.id_of(dog)] as Array[int], EntityRegistry.id_of(animal)))

func _train_dog_if_wanted(dogs: Array) -> void:
	if dogs.size() >= MAX_AI_DOGS:
		return
	if not ResourceManager.can_afford(_ai.player_id, DOG_COST):
		return
	if PopulationManager.at_cap(_ai.player_id):
		return
	for mill: Mill in WorldQuery.of_type(_ai.world.own_buildings(_ai.player_id), Mill):
		if mill.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if dogs.size() + mill.get_queue().size() >= MAX_AI_DOGS:
			return
		_ai.debug_log("TRAIN presa_canario at mill")
		CommandBus.submit(ProductionCommand.make(_ai.player_id, "train",
			EntityRegistry.id_of(mill), "presa_canario"))
		return

## Nearest live animal worth fetching: wild game or an enemy's sheep — never
## the AI's own flock, never an ally's, never one already in tow.
func find_herdable_animal(from: Vector2, claimed: Dictionary = {}) -> Animal:
	var best: Animal = null
	var best_d: float = DOG_HERD_RADIUS
	for unit: Node in _ai.world.all_units():
		if not (unit is Animal):
			continue
		var a: Animal = unit as Animal
		if a.current_state == Animal.AnimalState.DEAD \
				or a.current_state == Animal.AnimalState.HERDED:
			continue
		if a.player_id == _ai.player_id:
			continue
		if a.player_id >= 0 and GameManager.are_allied(a.player_id, _ai.player_id):
			continue
		if claimed.has(a.get_instance_id()):
			continue
		var d: float = from.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best

## Eats the flock: one villager is sent to slaughter one own sheep near the TC
## when food income is wanted — the carcass becomes a FOOD_HUNT node the
## hunters already handle (the butcher auto-gathers it, villager hunt logic).
func manage_flock() -> void:
	if is_instance_valid(_slaughter_target) \
			and _slaughter_target.current_state != Animal.AnimalState.DEAD:
		return
	_slaughter_target = null
	if not is_instance_valid(_ai.town_center):
		return
	if not _wants_food():
		return
	var tc_pos: Vector2 = _ai.town_center.global_position
	var sheep: Animal = null
	var best_d: float = SLAUGHTER_RADIUS
	for unit: Node in _ai.world.own_units(_ai.player_id):
		if not (unit is Animal):
			continue
		var a: Animal = unit as Animal
		if a.current_state != Animal.AnimalState.OWNED:
			continue
		var d: float = tc_pos.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			sheep = a
	if sheep == null:
		return
	var butcher: Villager = _nearest_food_villager(sheep.global_position)
	if butcher == null:
		return
	_slaughter_target = sheep
	_ai.debug_log("SLAUGHTER sheep at (%.0f,%.0f)" % [sheep.global_position.x, sheep.global_position.y])
	CommandBus.submit(UnitTargetCommand.make(_ai.player_id, "attack",
		[EntityRegistry.id_of(butcher)] as Array[int], EntityRegistry.id_of(sheep)))

func _nearest_food_villager(from: Vector2) -> Villager:
	var best: Villager = null
	var best_d: float = INF
	for v: Villager in _own_villagers():
		if not is_instance_valid(v.gather_target) or not (v.gather_target is ResourceNode):
			continue
		if _food_bucket((v.gather_target as ResourceNode).resource_type) != ResourceNode.ResourceType.FOOD_HUNT:
			continue
		var d: float = from.distance_squared_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best

## Food income is wanted while the food-gatherer share has not overshot the
## age's target fraction — the same allocation signal _assign_villager uses.
func _wants_food() -> bool:
	var food_assigned: int = 0
	var assigned_total: int = 0
	for v: Villager in _own_villagers():
		if not is_instance_valid(v.gather_target) or not (v.gather_target is ResourceNode):
			continue
		assigned_total += 1
		if _food_bucket((v.gather_target as ResourceNode).resource_type) == ResourceNode.ResourceType.FOOD_HUNT:
			food_assigned += 1
	if food_assigned == 0:
		return false
	var want: float = _target_fractions_for_age(AgeManager.get_age(_ai.player_id)) \
		.get(ResourceNode.ResourceType.FOOD_HUNT, 0.25) as float
	return float(food_assigned) / float(assigned_total) <= want + 0.01

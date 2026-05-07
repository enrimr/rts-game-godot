extends Node

## AIPlayer — tick-based AI that collects resources, builds, trains, and attacks.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const MILITIA_SCENE: PackedScene  = preload("res://scenes/units/militia.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")

const ATTACK_INTERVAL: float   = 30.0
const TICK_INTERVAL: float     = 2.0
const CONTROL_ZONE_RADIUS: float = 400.0   # px around TC considered "home"
const THREAT_CHECK_INTERVAL: float = 3.0  # how often to scan for nearby enemies

@export var player_id: int = 1

var town_center: Node2D = null
var units_layer: Node2D = null
var buildings_layer: Node2D = null
var drop_off: Node2D = null
var enemy_town_center: Node2D = null

var _timer: float = 0.0
var _attack_timer: float = 0.0
var _threat_timer: float = 0.0
var _barracks_built: bool = false

func _ready() -> void:
	EventBus.ai_unit_under_attack.connect(_on_ai_unit_under_attack)

func _on_ai_unit_under_attack(attacked_player_id: int) -> void:
	if attacked_player_id != player_id:
		return
	notify_under_attack()

# Aggression state
enum AggressionLevel { PASSIVE, ALERTED, AGGRESSIVE }
var _aggression: AggressionLevel = AggressionLevel.PASSIVE
var _aggression_timer: float = 0.0
const AGGRESSION_DECAY: float = 20.0  # seconds before returning to PASSIVE

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	_timer += delta
	_attack_timer += delta
	_threat_timer += delta

	if _aggression > AggressionLevel.PASSIVE:
		_aggression_timer += delta
		if _aggression_timer >= AGGRESSION_DECAY:
			_aggression = AggressionLevel.PASSIVE
			_aggression_timer = 0.0

	if _timer >= TICK_INTERVAL:
		_timer = 0.0
		_run_tick()

	var effective_attack_interval: float = _effective_attack_interval()
	if _attack_timer >= effective_attack_interval:
		_attack_timer = 0.0
		_launch_attack()

	if _threat_timer >= THREAT_CHECK_INTERVAL:
		_threat_timer = 0.0
		_check_zone_threat()

func _effective_attack_interval() -> float:
	match _aggression:
		AggressionLevel.AGGRESSIVE: return GameSettings.get_ai_attack_interval() * 0.33
		AggressionLevel.ALERTED:    return GameSettings.get_ai_attack_interval() * 0.60
	return GameSettings.get_ai_attack_interval()

func _run_tick() -> void:
	_manage_villagers()
	_manage_buildings()
	_manage_military()
	_manage_age_advance()

# --- Threat detection ---

func _check_zone_threat() -> void:
	if not is_instance_valid(town_center):
		return
	var threat_found: bool = false
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if (unit as Node2D).global_position.distance_to(town_center.global_position) <= CONTROL_ZONE_RADIUS:
			threat_found = true
			break

	if threat_found:
		_escalate_aggression(AggressionLevel.AGGRESSIVE)
		_defend_base()

func _escalate_aggression(level: AggressionLevel) -> void:
	if level > _aggression:
		_aggression = level
	_aggression_timer = 0.0

# Called when an AI unit takes damage — wired up in _spawn_villager / militia spawn.
func notify_under_attack() -> void:
	_escalate_aggression(AggressionLevel.ALERTED)
	# Trigger an early counter-attack if we have enough units
	var mcount: int = _count_units_of_type("Militia")
	if mcount >= 2:
		_attack_timer = _effective_attack_interval()  # fires next frame

func _defend_base() -> void:
	if not is_instance_valid(town_center):
		return
	# Find the closest enemy unit in the zone and rally all militia toward it
	var best_enemy: Node = null
	var best_dist: float = CONTROL_ZONE_RADIUS
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var d: float = (unit as Node2D).global_position.distance_to(town_center.global_position)
		if d < best_dist:
			best_dist = d
			best_enemy = unit

	if best_enemy == null:
		return

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if not (unit is Militia or unit is Archer or unit is Pikeman):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if unit.has_method("order_attack"):
			unit.order_attack(best_enemy)

# --- Age advancement ---

func _manage_age_advance() -> void:
	if AgeManager.is_advancing(player_id):
		return
	var current_age: int = AgeManager.get_age(player_id)
	if current_age >= GameManager.Age.IMPERIAL:
		return
	# AI advances as soon as it can afford it and has a defensive force
	if _count_units_of_type_any(["Militia", "Archer", "Pikeman"]) >= 3 and AgeManager.can_advance(player_id):
		AgeManager.start_advance(player_id)

# --- Economy ---

func _manage_villagers() -> void:
	if not is_instance_valid(town_center):
		return
	var vcount: int = _count_units_of_type("Villager")
	if vcount < GameSettings.get_ai_villager_target() and not PopulationManager.at_cap(player_id):
		_spawn_villager()
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != player_id:
			continue
		if v.current_state == UnitBase.UnitState.IDLE:
			_assign_villager_to_resource(v)

func _assign_villager_to_resource(v: Villager) -> void:
	var preferred: Array[ResourceNode.ResourceType] = [
		ResourceNode.ResourceType.WOOD,
		ResourceNode.ResourceType.FOOD_HUNT,
		ResourceNode.ResourceType.GOLD,
		ResourceNode.ResourceType.STONE,
	]
	var wood: int = ResourceManager.get_resources(player_id).get("wood", 0) as int
	if wood > 300:
		preferred = [ResourceNode.ResourceType.FOOD_HUNT, ResourceNode.ResourceType.WOOD,
					 ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE]
	for rtype: ResourceNode.ResourceType in preferred:
		var node: ResourceNode = _find_nearest_resource(rtype, v.global_position)
		if node != null:
			v.order_gather(node, node.get_resource_name(), drop_off)
			return

func _find_nearest_resource(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
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

# --- Buildings ---

func _manage_buildings() -> void:
	if not is_instance_valid(town_center):
		return
	if _barracks_built:
		return
	if ResourceManager.can_afford(player_id, {"wood": 175}):
		_build_barracks()

func _build_barracks() -> void:
	var barracks: Node2D = BARRACKS_SCENE.instantiate() as Node2D
	var offset: Vector2 = Vector2(randf_range(-120.0, 120.0), randf_range(80.0, 160.0))
	barracks.global_position = town_center.global_position + offset
	barracks.set("player_id", player_id)
	buildings_layer.add_child(barracks)
	barracks.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	barracks.add_construction(100.0)
	EventBus.building_placed.emit(barracks, player_id)
	ResourceManager.spend_resource(player_id, {"wood": 175})
	_barracks_built = true

# --- Military ---

func _manage_military() -> void:
	if not _barracks_built:
		return
	var target_count: int = GameSettings.get_ai_military_target_passive() if _aggression == AggressionLevel.PASSIVE else GameSettings.get_ai_military_target_passive() + 3
	var mcount: int = _count_units_of_type_any(["Militia", "Archer", "Pikeman"])
	if mcount < target_count:
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building) or not (building is Barracks):
				continue
			var br: Barracks = building as Barracks
			if br.player_id != player_id:
				continue
			# Train best available unit (highest age = most powerful)
			var available: Array[Dictionary] = br.get_available_units()
			if available.is_empty():
				break
			var best_def: Dictionary = available[available.size() - 1] as Dictionary
			br.order_train(best_def["id"] as String)
			break

func _launch_attack() -> void:
	if not is_instance_valid(enemy_town_center):
		return
	var mcount: int = _count_units_of_type_any(["Militia", "Archer", "Pikeman"])
	var min_for_attack: int = GameSettings.get_ai_min_attack_units() - 1 if _aggression == AggressionLevel.AGGRESSIVE else GameSettings.get_ai_min_attack_units()
	if mcount < min_for_attack:
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if unit is Militia or unit is Archer or unit is Pikeman:
			if unit.has_method("order_attack"):
				unit.order_attack(enemy_town_center)

func _spawn_villager() -> void:
	if not ResourceManager.spend_resource(player_id, {"food": 50}):
		return
	var v: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	v.set("player_id", player_id)
	units_layer.add_child(v)
	v.global_position = town_center.global_position + Vector2(randf_range(-50.0, 50.0), 60.0)
	PopulationManager.add_unit(player_id)
	EventBus.unit_spawned.emit(v, player_id)

# --- Helpers ---

func _count_units_of_type(type_name: String) -> int:
	return _count_units_of_type_any([type_name])

func _count_units_of_type_any(type_names: Array) -> int:
	var count: int = 0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		for type_name: Variant in type_names:
			match type_name as String:
				"Villager":
					if unit is Villager: count += 1
				"Militia":
					if unit is Militia: count += 1
				"Archer":
					if unit is Archer: count += 1
				"Pikeman":
					if unit is Pikeman: count += 1
	return count

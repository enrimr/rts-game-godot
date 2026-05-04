extends Node

## AIPlayer — tick-based AI that collects resources, builds, trains, and attacks.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const MILITIA_SCENE: PackedScene  = preload("res://scenes/units/militia.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")

const ATTACK_INTERVAL: float = 30.0   # seconds between attack waves
const TICK_INTERVAL: float   = 2.0

@export var player_id: int = 1

var town_center: Node2D = null        # set by game_world on setup
var units_layer: Node2D = null
var buildings_layer: Node2D = null
var drop_off: Node2D = null           # AI's own town center (drop-off)
var enemy_town_center: Node2D = null  # player 0's town center

var _timer: float = 0.0
var _attack_timer: float = 0.0
var _barracks_built: bool = false

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	_timer += delta
	_attack_timer += delta
	if _timer >= TICK_INTERVAL:
		_timer = 0.0
		_run_tick()
	if _attack_timer >= ATTACK_INTERVAL:
		_attack_timer = 0.0
		_launch_attack()

func _run_tick() -> void:
	_manage_villagers()
	_manage_buildings()
	_manage_military()

# --- Economy ---

func _manage_villagers() -> void:
	if not is_instance_valid(town_center):
		return
	var vcount: int = _count_units_of_type("Villager")
	if vcount < 8 and not PopulationManager.at_cap(player_id):
		_spawn_villager()
	# Assign idle villagers to nearest resource
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != player_id:
			continue
		if v.current_state == UnitBase.UnitState.IDLE:
			_assign_villager_to_resource(v)

func _assign_villager_to_resource(v: Villager) -> void:
	# Prioritize wood then food then gold then stone
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
	var scene: PackedScene = BARRACKS_SCENE
	var barracks: Node2D = scene.instantiate() as Node2D
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
	# Train militia from AI's barracks until we have 5
	var mcount: int = _count_units_of_type("Militia")
	if mcount < 5:
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building) or not (building is Barracks):
				continue
			var br: Barracks = building as Barracks
			if br.player_id != player_id:
				continue
			br.order_train()
			break

func _launch_attack() -> void:
	if not is_instance_valid(enemy_town_center):
		return
	var target: Node2D = enemy_town_center
	var mcount: int = _count_units_of_type("Militia")
	if mcount < 2:
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Militia):
			continue
		var m: Militia = unit as Militia
		if m.player_id != player_id:
			continue
		m.order_attack(target)

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
	var count: int = 0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		match type_name:
			"Villager":
				if unit is Villager:
					count += 1
			"Militia":
				if unit is Militia:
					count += 1
	return count

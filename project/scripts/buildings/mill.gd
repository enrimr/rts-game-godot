extends BuildingBase

class_name Mill

## The Mill closes the drop-off set: food finally has a camp of its own next
## to the Lumber and Mining Camps. It also keeps the island's oldest farmhand
## — it breeds the Presa Canario, the herding dog that fetches animals home.

const MAX_QUEUE: int = 5

const UNIT_DEFS: Array[Dictionary] = [
	{
		"id": "presa_canario",
		"scene": "res://scenes/units/presa_canario.tscn",
		"data": "res://resources/units/presa_canario_data.tres",
		"label": "PC",
		"color": Color(0.62, 0.46, 0.28),
		"age": 0,
	},
]

var _train_queue: Array = []
var _train_timer: float = 0.0

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)
	if state == BuildingState.COMPLETE:
		_register_drop_off()

func _on_construction_complete() -> void:
	_register_drop_off()

func _register_drop_off() -> void:
	var drop_off := DropOffBuilding.new()
	drop_off.player_id = player_id
	add_child(drop_off)

func _process(delta: float) -> void:
	super._process(delta)
	if state != BuildingState.COMPLETE:
		return
	_tick_training(delta)

func order_train(unit_id: String = "presa_canario") -> bool:
	if _train_queue.size() >= MAX_QUEUE:
		return false
	var def: Dictionary = _find_def(unit_id)
	if def.is_empty():
		return false
	if AgeManager.get_age(player_id) < (def.get("age", 0) as int):
		return false
	var unit_data: UnitResource = load(def["data"] as String) as UnitResource
	var costs: Dictionary = {}
	if unit_data.cost_food > 0: costs["food"] = unit_data.cost_food
	if unit_data.cost_wood > 0: costs["wood"] = unit_data.cost_wood
	if unit_data.cost_gold > 0: costs["gold"] = unit_data.cost_gold
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	_train_queue.append({
		"unit_id": unit_id,
		"label": def["label"] as String,
		"color": def["color"] as Color,
		"costs": costs,
		"scene": def["scene"] as String,
		"train_time": unit_data.train_time,
	})
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)
	return true

func order_cancel_train(index: int) -> void:
	if index < 0 or index >= _train_queue.size():
		return
	var entry: Dictionary = _train_queue[index] as Dictionary
	var costs: Dictionary = entry.get("costs", {}) as Dictionary
	ResourceManager.add_resource(player_id, "food", costs.get("food", 0))
	ResourceManager.add_resource(player_id, "wood", costs.get("wood", 0))
	ResourceManager.add_resource(player_id, "gold", costs.get("gold", 0))
	_train_queue.remove_at(index)
	if index == 0:
		_train_timer = 0.0
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func get_available_units() -> Array[Dictionary]:
	var current_age: int = AgeManager.get_age(player_id)
	var result: Array[Dictionary] = []
	for def: Dictionary in UNIT_DEFS:
		if (def["age"] as int) <= current_age:
			result.append(def)
	return result

func get_queue() -> Array:
	return _train_queue.duplicate()

func get_max_queue() -> int:
	return MAX_QUEUE

func _find_def(unit_id: String) -> Dictionary:
	for def: Dictionary in UNIT_DEFS:
		if (def["id"] as String) == unit_id:
			return def
	return {}

func _tick_training(delta: float) -> void:
	if _train_queue.is_empty() or get_meta(&"rep_puppet", false):
		return
	var entry: Dictionary = _train_queue[0] as Dictionary
	if PopulationManager.at_cap(player_id):
		return
	_train_timer += delta
	if _train_timer < (entry.get("train_time", 18.0) as float):
		return
	_train_timer = 0.0
	var scene_path: String = entry.get("scene", "") as String
	_train_queue.pop_front()
	_spawn_trained(scene_path)
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func _spawn_trained(scene_path: String) -> void:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var unit: Node2D = packed.instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	get_parent().add_child(unit)
	unit.global_position = BuildingBase.find_spawn_pos(global_position, get_world_2d().direct_space_state)
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.call("order_move", rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

extends Node2D

class_name TownCenter

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const VILLAGER_DATA: UnitResource = preload("res://resources/units/villager_data.tres")
const VILLAGER_COSTS: Dictionary = {"food": 50}
const MAX_QUEUE: int = 5

@export var player_id: int = 0

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _process(delta: float) -> void:
	if _train_queue.is_empty():
		return
	_train_timer += delta
	var train_time: float = VILLAGER_DATA.train_time
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time:
		_train_timer = 0.0
		_train_queue.pop_front()
		if is_instance_valid(_train_bar) and _train_queue.is_empty():
			_train_bar.value = 0.0
		_spawn_villager()
		EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func order_train() -> bool:
	if _train_queue.size() >= MAX_QUEUE:
		return false
	if PopulationManager.at_cap(player_id):
		return false
	if not ResourceManager.spend_resource(player_id, VILLAGER_COSTS):
		return false
	_train_queue.append({"unit_id": "villager", "label": "V", "color": Color(0.6, 0.45, 0.2), "costs": VILLAGER_COSTS})
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)
	return true

func order_cancel_train(index: int) -> void:
	if index < 0 or index >= _train_queue.size():
		return
	var entry: Dictionary = _train_queue[index]
	ResourceManager.add_resource(player_id, "food", (entry["costs"] as Dictionary).get("food", 0))
	ResourceManager.add_resource(player_id, "wood", (entry["costs"] as Dictionary).get("wood", 0))
	_train_queue.remove_at(index)
	if index == 0:
		_train_timer = 0.0
		if is_instance_valid(_train_bar):
			_train_bar.value = 0.0
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func get_queue() -> Array:
	return _train_queue.duplicate()

func get_max_queue() -> int:
	return MAX_QUEUE

func _spawn_villager() -> void:
	var unit: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	unit.set("player_id", player_id)
	get_parent().add_child(unit)
	unit.global_position = global_position + Vector2(80.0, 0.0)
	PopulationManager.add_unit(player_id)
	EventBus.unit_spawned.emit(unit, player_id)

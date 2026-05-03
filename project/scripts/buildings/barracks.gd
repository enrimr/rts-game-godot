extends BuildingBase

class_name Barracks

const MILITIA_SCENE: PackedScene = preload("res://scenes/units/militia.tscn")
const MILITIA_DATA: UnitResource = preload("res://resources/units/militia_data.tres")
const MILITIA_COSTS: Dictionary = {"food": 60, "wood": 20}
const SPAWN_OFFSET: Vector2 = Vector2(60.0, 0.0)
const MAX_QUEUE: int = 5

# Each entry: {"unit_id": String, "label": String, "color": Color, "costs": Dictionary}
var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if state != BuildingState.COMPLETE or _train_queue.is_empty():
		return
	_train_timer += delta
	var train_time: float = MILITIA_DATA.train_time
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time:
		_train_timer = 0.0
		_train_queue.pop_front()
		if is_instance_valid(_train_bar) and _train_queue.is_empty():
			_train_bar.value = 0.0
		_spawn_unit()
		EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func order_train() -> bool:
	if _train_queue.size() >= MAX_QUEUE:
		return false
	if PopulationManager.at_cap(player_id):
		return false
	if not ResourceManager.spend_resource(player_id, MILITIA_COSTS):
		return false
	_train_queue.append({"unit_id": "militia", "label": "M", "color": Color(0.7, 0.15, 0.10), "costs": MILITIA_COSTS})
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

func _spawn_unit() -> void:
	var unit: Node2D = MILITIA_SCENE.instantiate() as Node2D
	unit.set("player_id", player_id)
	get_parent().add_child(unit)
	unit.global_position = global_position + SPAWN_OFFSET
	PopulationManager.add_unit(player_id)
	EventBus.unit_spawned.emit(unit, player_id)

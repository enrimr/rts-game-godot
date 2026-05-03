extends BuildingBase

class_name Barracks

const MILITIA_SCENE: PackedScene = preload("res://scenes/units/militia.tscn")
const MILITIA_DATA: UnitResource = preload("res://resources/units/militia_data.tres")
const MILITIA_COSTS: Dictionary = {"food": 60, "wood": 20}
const SPAWN_OFFSET: Vector2 = Vector2(60.0, 0.0)
const MAX_QUEUE: int = 5

var _train_queue: int = 0
var _train_timer: float = 0.0

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if state != BuildingState.COMPLETE or _train_queue == 0:
		return
	_train_timer += delta
	var train_time: float = MILITIA_DATA.train_time
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time:
		_train_timer = 0.0
		_train_queue -= 1
		if is_instance_valid(_train_bar) and _train_queue == 0:
			_train_bar.value = 0.0
		_spawn_unit()
		EventBus.train_queue_changed.emit(self, _train_queue, MAX_QUEUE)

func order_train() -> bool:
	if _train_queue >= MAX_QUEUE:
		return false
	if PopulationManager.at_cap(player_id):
		return false
	if not ResourceManager.spend_resource(player_id, MILITIA_COSTS):
		return false
	_train_queue += 1
	EventBus.train_queue_changed.emit(self, _train_queue, MAX_QUEUE)
	return true

func get_queue_size() -> int:
	return _train_queue

func get_max_queue() -> int:
	return MAX_QUEUE

func _spawn_unit() -> void:
	var unit: Node2D = MILITIA_SCENE.instantiate() as Node2D
	unit.set("player_id", player_id)
	get_parent().add_child(unit)
	unit.global_position = global_position + SPAWN_OFFSET
	PopulationManager.add_unit(player_id)
	EventBus.unit_spawned.emit(unit, player_id)

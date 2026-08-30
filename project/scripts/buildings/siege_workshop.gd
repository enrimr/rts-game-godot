extends BuildingBase

class_name SiegeWorkshop

const SPAWN_OFFSET: Vector2 = Vector2(70.0, 0.0)
const MAX_QUEUE: int = 5

const UNIT_DEFS: Array[Dictionary] = [
	{
		"id": "battering_ram",
		"scene": "res://scenes/units/battering_ram.tscn",
		"data": "res://resources/units/battering_ram_data.tres",
		"label": "BR",
		"color": Color(0.55, 0.38, 0.18),
		"age": 2,
	},
	{
		"id": "mangonel",
		"scene": "res://scenes/units/mangonel.tscn",
		"data": "res://resources/units/mangonel_data.tres",
		"label": "MG",
		"color": Color(0.55, 0.42, 0.18),
		"age": 2,
	},
	{
		"id": "trebuchet",
		"scene": "res://scenes/units/trebuchet.tscn",
		"data": "res://resources/units/trebuchet_data.tres",
		"label": "TB",
		"color": Color(0.50, 0.35, 0.15),
		"age": 3,
	},
]

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if is_instance_valid(_train_bar):
		_train_bar.visible = not _train_queue.is_empty()
	if state != BuildingState.COMPLETE or _train_queue.is_empty():
		return
	var entry: Dictionary = _train_queue[0] as Dictionary
	var train_time: float = entry.get("train_time", 60.0) as float
	if get_meta(&"rep_puppet", false):
		# Mirror building: the queue/timer are replicated; never spawn locally.
		if is_instance_valid(_train_bar):
			_train_bar.value = (_train_timer / train_time) * 100.0
		return
	if not PopulationManager.at_cap(player_id):
		_train_timer += delta
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time and not PopulationManager.at_cap(player_id):
		_train_timer = 0.0
		var scene_path: String = entry.get("scene", "") as String
		_train_queue.pop_front()
		if is_instance_valid(_train_bar) and _train_queue.is_empty():
			_train_bar.value = 0.0
		_do_spawn(scene_path)
		EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func order_train(unit_id: String = "battering_ram") -> bool:
	if _train_queue.size() >= MAX_QUEUE:
		return false
	var def: Dictionary = _find_def(unit_id)
	if def.is_empty():
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
		if is_instance_valid(_train_bar):
			_train_bar.value = 0.0
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func get_queue() -> Array:
	return _train_queue.duplicate()

func get_max_queue() -> int:
	return MAX_QUEUE

func get_train_progress() -> float:
	if _train_queue.is_empty():
		return 0.0
	var t: float = (_train_queue[0] as Dictionary).get("train_time", 60.0) as float
	return _train_timer / t if t > 0.0 else 0.0

func get_available_units() -> Array[Dictionary]:
	var current_age: int = AgeManager.get_age(player_id)
	var result: Array[Dictionary] = []
	for def: Dictionary in UNIT_DEFS:
		if (def["age"] as int) <= current_age:
			result.append(def)
	return result

func _find_def(unit_id: String) -> Dictionary:
	for def: Dictionary in UNIT_DEFS:
		if (def["id"] as String) == unit_id:
			return def
	return {}

func _do_spawn(scene_path: String) -> void:
	if scene_path.is_empty():
		return
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
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

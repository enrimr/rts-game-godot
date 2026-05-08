extends BuildingBase

class_name Barracks

const SPAWN_OFFSET: Vector2 = Vector2(60.0, 0.0)
const MAX_QUEUE: int = 5

# All trainable units, unlocked by age_required
const UNIT_DEFS: Array[Dictionary] = [
	{
		"id": "militia",
		"scene": "res://scenes/units/militia.tscn",
		"data": "res://resources/units/militia_data.tres",
		"label": "M",
		"color": Color(0.7, 0.15, 0.10),
		"age": 0,
	},
	{
		"id": "archer",
		"scene": "res://scenes/units/archer.tscn",
		"data": "res://resources/units/archer_data.tres",
		"label": "A",
		"color": Color(0.25, 0.45, 0.20),
		"age": 1,
	},
	{
		"id": "pikeman",
		"scene": "res://scenes/units/pikeman.tscn",
		"data": "res://resources/units/pikeman_data.tres",
		"label": "P",
		"color": Color(0.50, 0.45, 0.65),
		"age": 2,
	},
]

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if state != BuildingState.COMPLETE or _train_queue.is_empty():
		return
	_train_timer += delta
	var entry: Dictionary = _train_queue[0] as Dictionary
	var train_time: float = entry.get("train_time", 30.0) as float
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time:
		_train_timer = 0.0
		var scene_path: String = entry.get("scene", "") as String
		_train_queue.pop_front()
		if is_instance_valid(_train_bar) and _train_queue.is_empty():
			_train_bar.value = 0.0
		_do_spawn(scene_path)
		EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func order_train(unit_id: String = "militia") -> bool:
	if _train_queue.size() >= MAX_QUEUE:
		return false
	if PopulationManager.at_cap(player_id):
		return false
	var def: Dictionary = _find_def(unit_id)
	if def.is_empty():
		return false
	var unit_data: UnitResource = load(def["data"] as String) as UnitResource
	var costs: Dictionary = {}
	if unit_data.cost_food > 0: costs["food"] = unit_data.cost_food
	if unit_data.cost_wood > 0: costs["wood"] = unit_data.cost_wood
	if unit_data.cost_gold > 0: costs["gold"] = unit_data.cost_gold
	var cost_mult: Dictionary = CivBonusManager.get_unit_cost_multiplier(player_id, unit_id)
	if cost_mult.has("food"): costs["food"] = int(costs.get("food", 0) * (cost_mult["food"] as float))
	if cost_mult.has("wood"): costs["wood"] = int(costs.get("wood", 0) * (cost_mult["wood"] as float))
	if cost_mult.has("gold"): costs["gold"] = int(costs.get("gold", 0) * (cost_mult["gold"] as float))
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
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.rival_civ_id)
	get_parent().add_child(unit)
	unit.global_position = global_position + SPAWN_OFFSET
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

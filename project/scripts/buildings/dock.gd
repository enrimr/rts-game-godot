extends BuildingBase

class_name Dock

## Dock — coastal building that trains naval units.
## Must be placed straddling land and water — at least one edge in ocean,
## at least one edge on land.

const MAX_QUEUE: int = 5

const UNIT_DEFS: Array[Dictionary] = [
	{
		"id": "fishing_boat",
		"scene": "res://scenes/units/fishing_boat.tscn",
		"data": "res://resources/units/fishing_boat_data.tres",
		"label": "F",
		"color": Color(0.20, 0.50, 0.65),
		"age": 0,
	},
	{
		"id": "transport_ship",
		"scene": "res://scenes/units/transport_ship.tscn",
		"data": "res://resources/units/transport_ship_data.tres",
		"label": "T",
		"color": Color(0.55, 0.45, 0.20),
		"age": 1,
	},
	{
		"id": "war_galley",
		"scene": "res://scenes/units/war_galley.tscn",
		"data": "res://resources/units/war_galley_data.tres",
		"label": "G",
		"color": Color(0.65, 0.18, 0.18),
		"age": 1,
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

func order_train(unit_id: String) -> bool:
	if _train_queue.size() >= MAX_QUEUE:
		return false
	var def: Dictionary = _find_def(unit_id)
	if def.is_empty():
		return false
	var unit_data: UnitResource = load(def["data"] as String) as UnitResource
	var ship_mult: float = CivBonusManager.get_ship_cost_multiplier(player_id)
	var costs: Dictionary = {}
	if unit_data.cost_food > 0: costs["food"] = unit_data.cost_food * ship_mult
	if unit_data.cost_wood > 0: costs["wood"] = unit_data.cost_wood * ship_mult
	if unit_data.cost_gold > 0: costs["gold"] = unit_data.cost_gold * ship_mult
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
	# civ_id set to "atlantes" by ShipBase._ready() — ocean passable
	get_parent().add_child(unit)
	unit.global_position = _water_spawn_pos()
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

# Returns the world position where ships should spawn — the nearest ocean tile
# to the dock, guaranteed to be water regardless of dock placement.
func _water_spawn_pos() -> Vector2:
	var ocean_pos: Vector2 = TerrainManager.nearest_ocean(global_position)
	if ocean_pos != Vector2.ZERO:
		return ocean_pos
	return global_position + Vector2(0.0, 60.0)  # absolute last resort

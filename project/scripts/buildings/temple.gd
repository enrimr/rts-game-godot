extends BuildingBase

class_name Temple

## The Temple earns its keep: besides its three research lines it is now the
## field HOSPITAL — wounded units garrison inside (capacity from the .tres)
## and the BUILDING channels the healing (occupants have processing off) —
## and it trains the Harimaguada, the Canarii priestess-healer.
## Heroes heal at HALF rate: an immortal king parked inside a temple must
## never turn Regicide into a waiting game.

const HEAL_RATE: float = 4.0
const HERO_HEAL_MULT: float = 0.5
const MAX_QUEUE: int = 5

const UNIT_DEFS: Array[Dictionary] = [
	{
		"id": "harimaguada",
		"scene": "res://scenes/units/harimaguada.tscn",
		"data": "res://resources/units/harimaguada_data.tres",
		"label": "HA",
		"color": Color(0.88, 0.85, 0.76),
		"age": 2,
	},
]

var _train_queue: Array = []
var _train_timer: float = 0.0

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	super._process(delta)
	if state != BuildingState.COMPLETE:
		return
	_heal_ward(delta)
	_tick_training(delta)

## The ward: every garrisoned patient mends while sheltered.
func _heal_ward(delta: float) -> void:
	if get_meta(&"rep_puppet", false):
		return
	for unit: Node in _garrison:
		if not is_instance_valid(unit) or not unit.has_method("heal"):
			continue
		var rate: float = HEAL_RATE
		if unit is HeroUnit:
			rate *= HERO_HEAL_MULT
		unit.call("heal", rate * delta)

# ── Training (same contract as every producer: order_train / get_queue) ──────

func order_train(unit_id: String = "harimaguada") -> bool:
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
	if _train_timer < (entry.get("train_time", 24.0) as float):
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

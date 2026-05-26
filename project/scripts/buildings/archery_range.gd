extends BuildingBase

class_name ArcheryRange

const SPAWN_OFFSET: Vector2 = Vector2(60.0, 0.0)
const MAX_QUEUE: int = 5

const UNIT_DEFS: Array[Dictionary] = [
	{
		"id": "archer",
		"scene": "res://scenes/units/archer.tscn",
		"data": "res://resources/units/archer_data.tres",
		"label": "A",
		"color": Color(0.25, 0.45, 0.20),
		"age": 1,
	},
	{
		"id": "ravine_archer",
		"scene": "res://scenes/units/ravine_archer.tscn",
		"data": "res://resources/units/ravine_archer_data.tres",
		"label": "RA",
		"color": Color(0.30, 0.55, 0.15),
		"age": 2,
		"civ_required": "canarii",
	},
	{
		"id": "longbowman",
		"scene": "res://scenes/units/longbowman.tscn",
		"data": "res://resources/units/longbowman_data.tres",
		"label": "LB",
		"color": Color(0.25, 0.45, 0.65),
		"age": 2,
		"civ_required": "britons",
	},
]

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0
var _unit_upgrades: Dictionary = {}  # from_unit_id -> to_unit_id

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()
	EventBus.unit_upgrade_applied.connect(_on_unit_upgrade_applied)

func _on_unit_upgrade_applied(pid: int, from_id: String, to_res: UnitResource) -> void:
	if pid != player_id:
		return
	_unit_upgrades[from_id] = to_res.id

func _process(delta: float) -> void:
	if state != BuildingState.COMPLETE or _train_queue.is_empty():
		return
	var entry: Dictionary = _train_queue[0] as Dictionary
	var train_time: float = entry.get("train_time", 30.0) as float
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

func order_train(unit_id: String = "archer") -> bool:
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

func get_train_progress() -> float:
	if _train_queue.is_empty():
		return 0.0
	var t: float = (_train_queue[0] as Dictionary).get("train_time", 30.0) as float
	return _train_timer / t if t > 0.0 else 0.0

func get_available_units() -> Array[Dictionary]:
	var current_age: int = AgeManager.get_age(player_id)
	var player_civ: String = MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id)
	var result: Array[Dictionary] = []
	for def: Dictionary in UNIT_DEFS:
		if (def["age"] as int) > current_age:
			continue
		if def.get("upgrade_only", false) as bool:
			continue
		var civ_req: String = def.get("civ_required", "") as String
		if civ_req != "" and civ_req != player_civ:
			continue
		result.append(def)
	return result

func _find_def(unit_id: String) -> Dictionary:
	for def: Dictionary in UNIT_DEFS:
		if (def["id"] as String) == unit_id:
			return def
	return {}

func _resolve_upgraded_scene(scene_path: String) -> String:
	# Walk the upgrade chain to find the highest-tier unit scene for this path.
	for def: Dictionary in UNIT_DEFS:
		if (def["scene"] as String) == scene_path:
			var effective_id: String = def["id"] as String
			while _unit_upgrades.has(effective_id):
				effective_id = _unit_upgrades[effective_id] as String
			if effective_id != (def["id"] as String):
				for upgraded_def: Dictionary in UNIT_DEFS:
					if (upgraded_def["id"] as String) == effective_id:
						return upgraded_def["scene"] as String
	return scene_path

func _do_spawn(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	scene_path = _resolve_upgraded_scene(scene_path)
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var unit: Node2D = packed.instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	get_parent().add_child(unit)
	unit.global_position = global_position + SPAWN_OFFSET
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

extends BuildingBase

class_name Dock

## Dock — coastal building that trains naval units.
## Must be placed straddling land and water — at least one edge in ocean,
## at least one edge on land.

const MAX_QUEUE: int = 5

## How far offshore a new ship is placed. TerrainManager.nearest_ocean() returns
## the first ocean pixel around the dock, which is the shoreline itself: ships
## spawned there sit half on the pier, and the whole training queue lands on the
## exact same point.
const WATER_CLEARANCE: float = 56.0
## Half-width of a ship hull, for the open-water and free-spot probes.
const SHIP_RADIUS: float = 16.0

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
	{
		"id": "trireme",
		"scene": "res://scenes/units/trireme.tscn",
		"data": "res://resources/units/trireme_data.tres",
		"label": "TR",
		"color": Color(0.20, 0.30, 0.60),
		"age": 1,
		"civ_required": "fenicios",
	},
]

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0
var _access_point: Vector2 = Vector2.ZERO
var _access_point_valid: bool = false

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if is_instance_valid(_train_bar):
		_train_bar.visible = not _train_queue.is_empty()
	if state != BuildingState.COMPLETE or _train_queue.is_empty():
		return
	var entry: Dictionary = _train_queue[0] as Dictionary
	var train_time: float = entry.get("train_time", 30.0) as float
	if get_meta(&"rep_puppet", false):
		# Mirror building: the queue/timer are replicated; never spawn locally.
		if is_instance_valid(_train_bar):
			_train_bar.value = (_train_timer / train_time) * 100.0
		return
	_train_timer += delta
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

func _do_spawn(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var unit: Node2D = packed.instantiate() as Node2D
	unit.set("player_id", player_id)
	# civ_id is derived from player_id by ShipBase._ready() (it drives ShipDress)
	get_parent().add_child(unit)
	unit.global_position = _water_spawn_pos()
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

## Open water off the dock's seaward side: where ships appear, and where a
## returning fishing boat has to sail to unload. The dock's own origin sits on
## the shoreline, often on land — a ship can never reach it, so anything that
## navigates to this dock must aim here instead.
## Resolved once: neither the dock nor the coastline moves, and returning boats
## ask for it every physics frame.
func water_access_point() -> Vector2:
	if _access_point_valid:
		return _access_point
	_access_point_valid = true
	_access_point = _resolve_water_access()
	return _access_point

func _resolve_water_access() -> Vector2:
	var seaward: Vector2 = _seaward_dir()
	for i: int in range(1, 7):
		var candidate: Vector2 = global_position + seaward * (WATER_CLEARANCE * 0.5 * float(i))
		if _is_open_water(candidate):
			return candidate
	var fallback: Vector2 = TerrainManager.nearest_ocean(global_position)
	if fallback != Vector2.ZERO:
		return fallback
	return global_position + Vector2(0.0, 60.0)  # absolute last resort

## Returns the world position where a freshly trained ship is put down: the
## access point, nudged aside when another ship already sits there.
func _water_spawn_pos() -> Vector2:
	return _free_water_near(water_access_point())

## Average direction of the water around the dock, i.e. away from its own shore.
func _seaward_dir() -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for i: int in range(16):
		var dir: Vector2 = Vector2.from_angle(TAU * float(i) / 16.0)
		if TerrainManager.is_ocean(global_position + dir * WATER_CLEARANCE):
			sum += dir
	return sum.normalized() if sum.length() > 0.01 else Vector2.DOWN

## True when a whole hull fits in the water at `p`, not just its centre point.
func _is_open_water(p: Vector2) -> bool:
	if not TerrainManager.is_ocean(p):
		return false
	for i: int in range(4):
		if not TerrainManager.is_ocean(p + Vector2.from_angle(TAU * float(i) / 4.0) * SHIP_RADIUS):
			return false
	return true

## Outward spiral like BuildingBase.find_spawn_pos, restricted to water, so a
## training queue does not pile every ship on one pixel.
func _free_water_near(base: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = SHIP_RADIUS
	query.shape = shape
	query.collision_mask = 2  # units only — the dock itself is world geometry
	query.transform = Transform2D(0.0, base)
	if space.intersect_shape(query, 1).is_empty():
		return base
	for ring: int in range(1, 6):
		var radius: float = SHIP_RADIUS * 2.0 * float(ring)
		var steps: int = maxi(6, ring * 6)
		for s: int in range(steps):
			var candidate: Vector2 = base \
				+ Vector2.from_angle(TAU * float(s) / float(steps)) * radius
			if not _is_open_water(candidate):
				continue
			query.transform = Transform2D(0.0, candidate)
			if space.intersect_shape(query, 1).is_empty():
				return candidate
	return base

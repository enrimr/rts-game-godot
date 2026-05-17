extends StaticBody2D

class_name TownCenterBuilding

## Town Center for buildings placed via scene (player 0 and AI).
## Handles health, damage, villager training queue, and drop-off.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const VILLAGER_DATA: UnitResource = preload("res://resources/units/villager_data.tres")
const VILLAGER_COSTS: Dictionary = {"food": 50}
const MAX_QUEUE: int = 5

var player_id: int = 0
var health: float = 2000.0
var max_health: float = 2000.0

var _selection_line: Line2D = null
var rally_point: Vector2 = Vector2.ZERO
var _rally_marker: Node2D = null

func set_rally_point(world_pos: Vector2) -> void:
	rally_point = world_pos
	if not is_instance_valid(_rally_marker):
		_rally_marker = BuildingBase._make_rally_marker()
		add_child(_rally_marker)
	_rally_marker.global_position = world_pos
	_rally_marker.visible = true

func set_selected(value: bool) -> void:
	if value:
		if not is_instance_valid(_selection_line):
			const PAD: float = 4.0
			var r: Rect2 = Rect2(-40.0 - PAD, -40.0 - PAD, 80.0 + PAD * 2.0, 80.0 + PAD * 2.0)
			var line: Line2D = Line2D.new()
			line.width = 1.5
			line.default_color = Color(1.0, 0.92, 0.2, 0.95)
			line.z_index = 6
			line.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
				r.end, Vector2(r.position.x, r.end.y), r.position])
			_selection_line = line
			add_child(_selection_line)
		_selection_line.visible = true
	else:
		if is_instance_valid(_selection_line):
			_selection_line.visible = false
	if is_instance_valid(_rally_marker):
		_rally_marker.visible = value and rally_point != Vector2.ZERO

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")
@onready var _drop_off: Node = get_node_or_null("DropOff")

func _ready() -> void:
	add_to_group("buildings")
	call_deferred("_add_player_color_stripe")

func _add_player_color_stripe() -> void:
	PlayerColors.apply_color_stripe(self, player_id, 80.0, 40.0)

func _process(delta: float) -> void:
	if _train_queue.is_empty():
		return
	var train_time: float = VILLAGER_DATA.train_time
	if not PopulationManager.at_cap(player_id):
		_train_timer += delta
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time and not PopulationManager.at_cap(player_id):
		_train_timer = 0.0
		_train_queue.pop_front()
		if is_instance_valid(_train_bar) and _train_queue.is_empty():
			_train_bar.value = 0.0
		_spawn_villager()
		EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func order_train() -> bool:
	if _train_queue.size() >= MAX_QUEUE:
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

var _hit_tween: Tween = null

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)
	if source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and (src_pid as int) != player_id and player_id != 0:
			EventBus.ai_unit_under_attack.emit(player_id)
	if is_instance_valid(_health_bar):
		_health_bar.value = (health / max_health) * 100.0
	if health <= 0.0:
		EventBus.building_destroyed.emit(self, player_id)
		queue_free()

func get_drop_off_node() -> Node:
	return _drop_off

func _spawn_villager() -> void:
	var unit: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	get_parent().add_child(unit)
	unit.global_position = global_position + Vector2(90.0, 0.0)
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	EventBus.unit_spawned.emit(unit, player_id)

extends Node2D

class_name TownCenter

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const VILLAGER_DATA: UnitResource = preload("res://resources/units/villager_data.tres")
const VILLAGER_COSTS: Dictionary = {"food": 50}
const MAX_QUEUE: int = 5
const HERO_RESPAWN_TIME: float = 120.0

@export var player_id: int = 0

var health: float = 2000.0
var max_health: float = 2000.0

var _hero_respawn_timer: float = 0.0
var _pending_hero_data: UnitResource = null

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

var _hit_tween: Tween = null

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)
	if health <= 0.0:
		EventBus.building_destroyed.emit(self, player_id)
		queue_free()

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	call_deferred("_add_player_color_stripe")
	EventBus.hero_died.connect(_on_hero_died)

func _add_player_color_stripe() -> void:
	PlayerColors.apply_color_stripe(self, player_id, 80.0, 40.0)

func get_hero_respawn_fraction() -> float:
	if _pending_hero_data == null or HERO_RESPAWN_TIME <= 0.0:
		return 0.0
	return clampf(1.0 - _hero_respawn_timer / HERO_RESPAWN_TIME, 0.0, 1.0)

func get_hero_respawn_remaining() -> int:
	return int(ceil(_hero_respawn_timer))

func is_respawning_hero() -> bool:
	return _pending_hero_data != null

func _on_hero_died(died_player_id: int, hero_data: UnitResource) -> void:
	if died_player_id != player_id:
		return
	_pending_hero_data = hero_data
	_hero_respawn_timer = HERO_RESPAWN_TIME

func _process(delta: float) -> void:
	if _pending_hero_data != null:
		_hero_respawn_timer -= delta
		if _hero_respawn_timer <= 0.0:
			_hero_respawn_timer = 0.0
			var data: UnitResource = _pending_hero_data
			_pending_hero_data = null
			_do_respawn_hero(data)
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

func get_train_progress() -> float:
	if _train_queue.is_empty():
		return 0.0
	var t: float = VILLAGER_DATA.train_time
	return _train_timer / t if t > 0.0 else 0.0

func _spawn_villager() -> void:
	var unit: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	get_parent().add_child(unit)
	unit.global_position = global_position + Vector2(80.0, 0.0)
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

func _do_respawn_hero(hero_data: UnitResource) -> void:
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var hero: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", hero_data)
	hero.set("player_id", player_id)
	hero.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	hero.global_position = global_position + Vector2(-80.0, -60.0)
	get_parent().add_child(hero)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(hero, player_id)
	EventBus.hero_respawned.emit(player_id)

extends StaticBody2D

class_name TownCenterBuilding

## Town Center for buildings placed via scene (player 0 and AI).
## Handles health, damage, villager training queue, and drop-off.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const VILLAGER_DATA: UnitResource = preload("res://resources/units/villager_data.tres")
const VILLAGER_COSTS: Dictionary = {"food": 50}
const MAX_QUEUE: int = 5
const HERO_RESPAWN_TIME: float = 120.0

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
	VisualFx.set_nameplate_visible(self, value)
	if is_instance_valid(_rally_marker):
		_rally_marker.visible = value and rally_point != Vector2.ZERO

var _hero_respawn_timer: float = 0.0
var _pending_hero_data: UnitResource = null

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0

@onready var _health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")
@onready var _drop_off: Node = get_node_or_null("DropOff")

func _ready() -> void:
	add_to_group("buildings")
	IsoBuildingMassing.apply(self)
	VisualFx.set_nameplate_visible(self, false)
	call_deferred("_add_player_color_stripe")
	call_deferred("_apply_team_accents")
	call_deferred("_setup_iso_billboard")
	EventBus.hero_died.connect(_on_hero_died)

func _add_player_color_stripe() -> void:
	if has_meta("massing_bot_y"):
		# Ground trim along the near footprint edges — a screen-space bar
		# would cut through the lower wall corner under the projection.
		PlayerColors.apply_iso_ownership_trim(self, player_id,
			IsoBuildingMassing._half_extents(self))
		return
	PlayerColors.apply_color_stripe(self, player_id, 80.0, 40.0)

func _apply_team_accents() -> void:
	var body: Node = get_node_or_null("Body")
	if body == null:
		return
	var col: Color = PlayerColors.get_color(player_id)
	var dark: Color = Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 1.0)
	for node: Node in body.get_children():
		if not node.name.begins_with("Team"):
			continue
		var tint: Color = dark if node.name.contains("Dark") else col
		if node is Polygon2D:
			(node as Polygon2D).color = tint
		elif node is Line2D:
			(node as Line2D).default_color = tint

func _setup_iso_billboard() -> void:
	# The massing pass already seats the volume with a footprint contact
	# shadow; only non-massed fallbacks need the detached ellipse.
	if not has_meta("massing_bot_y"):
		VisualFx.add_ground_shadow(self, 42.0, 22.0, 15.0)
	IsoBillboard.setup_entity(self, ["Body", "NameLabel", "HealthBar",
		"TrainingBar", "PlayerColorStripe"])

func _on_hero_died(died_player_id: int, hero_data: UnitResource) -> void:
	if died_player_id != player_id:
		return
	_pending_hero_data = hero_data
	_hero_respawn_timer = HERO_RESPAWN_TIME

func is_respawning_hero() -> bool:
	return _pending_hero_data != null

func get_hero_respawn_fraction() -> float:
	if _pending_hero_data == null or HERO_RESPAWN_TIME <= 0.0:
		return 0.0
	return clampf(1.0 - _hero_respawn_timer / HERO_RESPAWN_TIME, 0.0, 1.0)

func get_hero_respawn_remaining() -> int:
	return int(ceil(_hero_respawn_timer))

func _do_respawn_hero(hero_data: UnitResource) -> void:
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var hero: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", hero_data)
	hero.set("player_id", player_id)
	hero.set("civ_id", MatchConfig.get_rival_civ_id(player_id))
	hero.global_position = global_position + Vector2(-80.0, -60.0)
	get_parent().add_child(hero)
	EventBus.unit_spawned.emit(hero, player_id)
	EventBus.hero_respawned.emit(player_id)

func _process(delta: float) -> void:
	if _pending_hero_data != null:
		_hero_respawn_timer -= delta
		if _hero_respawn_timer <= 0.0:
			_hero_respawn_timer = 0.0
			var data: UnitResource = _pending_hero_data
			_pending_hero_data = null
			_do_respawn_hero(data)
	if is_instance_valid(_train_bar):
		_train_bar.visible = not _train_queue.is_empty()
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
	_train_queue.append({"unit_id": "villager", "scene": "res://scenes/units/villager.tscn", "label": "V", "color": Color(0.6, 0.45, 0.2), "costs": VILLAGER_COSTS})
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

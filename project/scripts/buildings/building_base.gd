extends StaticBody2D

class_name BuildingBase

enum BuildingState { BLUEPRINT, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

@export var building_data: BuildingResource

const MAX_BUILD_SPEED_MULTIPLIER: float = 3.0

var player_id: int = 0
var state: BuildingState = BuildingState.BLUEPRINT
var health: float = 0.0
var max_health: float = 0.0
var construction_progress: float = 0.0
var _active_builders: int = 0

signal construction_complete
signal building_destroyed(building: Node)

@onready var _progress_bar: ProgressBar = get_node_or_null("ConstructionBar")
@onready var _body_rect: ColorRect   = get_node_or_null("Body")

var _selection_line: Line2D = null
var rally_point: Vector2 = Vector2.ZERO
var _rally_marker: Node2D = null
var _hit_tween: Tween = null
var _under_attack_timer: float = 0.0
var _blink_phase: float = 0.0

func set_rally_point(world_pos: Vector2) -> void:
	rally_point = world_pos
	if not is_instance_valid(_rally_marker):
		_rally_marker = _make_rally_marker()
		add_child(_rally_marker)
	_rally_marker.global_position = world_pos
	_rally_marker.visible = true

func _show_rally_marker(show: bool) -> void:
	if is_instance_valid(_rally_marker):
		_rally_marker.visible = show and rally_point != Vector2.ZERO

static func _make_rally_marker() -> Node2D:
	var root: Node2D = Node2D.new()
	root.z_index = 5
	var line: Line2D = Line2D.new()
	line.width = 1.0
	line.default_color = Color(1.0, 0.92, 0.2, 0.7)
	line.points = PackedVector2Array([
		Vector2(-6.0, 0.0), Vector2(6.0, 0.0),
		Vector2(0.0, 0.0), Vector2(0.0, -12.0),
	])
	root.add_child(line)
	var circle: Line2D = Line2D.new()
	circle.width = 1.0
	circle.default_color = Color(1.0, 0.92, 0.2, 0.7)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(17):
		var a: float = i * TAU / 16.0
		pts.append(Vector2(cos(a), sin(a)) * 5.0)
	circle.points = pts
	root.add_child(circle)
	return root

func set_selected(value: bool) -> void:
	if value:
		if not is_instance_valid(_selection_line):
			_selection_line = _make_selection_line(_footprint_rect())
			add_child(_selection_line)
		_selection_line.visible = true
	else:
		if is_instance_valid(_selection_line):
			_selection_line.visible = false
	_show_rally_marker(value)

func _footprint_rect() -> Rect2:
	const PAD: float = 4.0
	if is_instance_valid(_body_rect):
		return Rect2(
			_body_rect.offset_left  - PAD, _body_rect.offset_top    - PAD,
			_body_rect.offset_right - _body_rect.offset_left + PAD * 2.0,
			_body_rect.offset_bottom - _body_rect.offset_top + PAD * 2.0)
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var h: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		return Rect2(-h.x - PAD, -h.y - PAD, (h.x + PAD) * 2.0, (h.y + PAD) * 2.0)
	return Rect2(-28.0, -28.0, 56.0, 56.0)

static func _make_selection_line(r: Rect2) -> Line2D:
	var line: Line2D = Line2D.new()
	line.width = 1.5
	line.default_color = Color(1.0, 0.92, 0.2, 0.95)
	line.z_index = 6
	line.points = PackedVector2Array([
		r.position,
		Vector2(r.end.x,    r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
		r.position,
	])
	return line

func _ready() -> void:
	add_to_group("buildings")
	if building_data:
		var hp_mult: float = CivBonusManager.get_building_hp_multiplier(player_id, building_data.id)
		max_health = building_data.max_health * hp_mult
		health = max_health
	_refresh_visuals()
	call_deferred("_apply_player_color_stripe")
	_setup_nav_obstacle()

func register_builder() -> void:
	_active_builders += 1

func unregister_builder() -> void:
	_active_builders = maxi(0, _active_builders - 1)

func add_construction(base_amount: float) -> void:
	var multiplier: float = minf(float(_active_builders), MAX_BUILD_SPEED_MULTIPLIER)
	if multiplier < 1.0:
		multiplier = 1.0
	construction_progress = minf(construction_progress + base_amount * multiplier, 100.0)
	_refresh_visuals()
	if construction_progress >= 100.0:
		_complete_construction()

func _complete_construction() -> void:
	state = BuildingState.COMPLETE
	if is_instance_valid(_progress_bar):
		_progress_bar.visible = false
	if is_instance_valid(_body_rect):
		_body_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if player_id == 0:
		AudioManager.play("build_complete")
	construction_complete.emit()
	EventBus.building_construction_complete.emit(self)

func _refresh_visuals() -> void:
	if is_instance_valid(_progress_bar):
		_progress_bar.value = construction_progress
		_progress_bar.visible = state == BuildingState.UNDER_CONSTRUCTION or construction_progress < 100.0
	# Blueprint/under-construction tint: semi-transparent
	if is_instance_valid(_body_rect):
		var alpha: float = 0.4 + construction_progress / 100.0 * 0.6
		_body_rect.modulate = Color(1.0, 1.0, 1.0, alpha)

func _apply_player_color_stripe() -> void:
	if not is_instance_valid(_body_rect):
		PlayerColors.apply_color_stripe(self, player_id, 48.0, 36.0)
		return
	var w: float = _body_rect.offset_right - _body_rect.offset_left
	var b: float = _body_rect.offset_bottom
	PlayerColors.apply_color_stripe(self, player_id, w, b)

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	_flash_hit()
	if source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and (src_pid as int) != player_id:
			if player_id != 0:
				EventBus.ai_unit_under_attack.emit(player_id)
			else:
				EventBus.player_entity_under_attack.emit(global_position, source)
	if health <= 0.0:
		_destroy()

func _flash_hit() -> void:
	_under_attack_timer = 3.0
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _process(delta: float) -> void:
	# Volcanic ash: slow HP drain for any standing building (including pre-placed
	# Town Centers whose state never transitions through add_construction).
	if state != BuildingState.UNDER_CONSTRUCTION and state != BuildingState.DESTROYED:
		var ash_dmg: float = WeatherManager.get_building_damage_rate(global_position) * delta
		if ash_dmg > 0.0:
			take_damage(ash_dmg)
	if _under_attack_timer <= 0.0:
		return
	_under_attack_timer -= delta
	# Let the sharp hit-flash finish before the slow pulse takes over
	if is_instance_valid(_hit_tween) and _hit_tween.is_running():
		return
	_blink_phase += delta * 4.0
	var t: float = (sin(_blink_phase) * 0.5 + 0.5)  # 0..1
	var r: float = lerpf(1.0, 1.0, t)
	var g: float = lerpf(0.35, 1.0, t)
	var b: float = lerpf(0.35, 1.0, t)
	modulate = Color(r, g, b, 1.0)
	if _under_attack_timer <= 0.0:
		modulate = Color(1.0, 1.0, 1.0, 1.0)

func _setup_nav_obstacle() -> void:
	var obs: NavigationObstacle2D = get_node_or_null("NavigationObstacle2D") as NavigationObstacle2D
	if obs == null:
		obs = NavigationObstacle2D.new()
		obs.name = "NavigationObstacle2D"
		add_child(obs)
	var half: Vector2 = _nav_half_extents()
	obs.vertices = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2( half.x, -half.y),
		Vector2( half.x,  half.y),
		Vector2(-half.x,  half.y),
	])
	obs.avoidance_enabled = true
	obs.affect_navigation_mesh = false

func _nav_half_extents() -> Vector2:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		# 16 px extra so RVO steering starts before the unit touches the building
		return (cs.shape as RectangleShape2D).size * 0.5 + Vector2(16.0, 16.0)
	return Vector2(46.0, 46.0)

func _nav_bake_half_extents() -> Vector2:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		# 4 px — just enough to carve a clean gap in the nav mesh without blocking adjacent work spots
		return (cs.shape as RectangleShape2D).size * 0.5 + Vector2(4.0, 4.0)
	return Vector2(34.0, 34.0)

# Returns the world-space obstacle polygon (4 corners) used by the nav bake.
func get_nav_obstacle_polygon() -> PackedVector2Array:
	var half: Vector2 = _nav_bake_half_extents()
	return PackedVector2Array([
		global_position + Vector2(-half.x, -half.y),
		global_position + Vector2( half.x, -half.y),
		global_position + Vector2( half.x,  half.y),
		global_position + Vector2(-half.x,  half.y),
	])

func _destroy() -> void:
	state = BuildingState.DESTROYED
	AudioManager.play("build_destroy", -2.0)
	EventBus.building_destroyed.emit(self, player_id)
	building_destroyed.emit(self)
	queue_free()

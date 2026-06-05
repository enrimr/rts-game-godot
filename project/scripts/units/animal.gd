extends CharacterBody2D

class_name Animal

enum AnimalState { WILD, OWNED, FLEEING, DEAD }

const FOOD_AMOUNT: float = 150.0
const WANDER_SPEED: float = 40.0
const FLEE_SPEED: float   = 110.0
const WANDER_RADIUS: float = 220.0
const FLEE_DURATION: float = 3.0

@export var max_health: float = 40.0
@export var animal_name: String = "Deer"
@export var convertible: bool = false
@export var line_of_sight: float = 1.0

var player_id: int = -1
var health: float = 0.0
var current_state: AnimalState = AnimalState.WILD

var _wander_timer: float = 0.0
var _flee_timer: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _hit_tween: Tween = null

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _selection_indicator: Node2D = $SelectionIndicator
@onready var _body_torso: Polygon2D = $Body/Torso
@onready var _nav: NavigationAgent2D = $NavigationAgent2D
@onready var _convert_area: Area2D = $ConvertArea

func _ready() -> void:
	health = max_health
	_origin = global_position
	_pick_wander_target()
	add_to_group("animals")
	_nav.velocity_computed.connect(_on_velocity_computed)
	_convert_area.body_entered.connect(_on_body_entered_range)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if current_state == AnimalState.DEAD:
		return
	velocity = safe_velocity
	move_and_slide()

func set_selected(value: bool) -> void:
	_selection_indicator.visible = value

func take_damage(amount: float, source: Node = null) -> void:
	if current_state == AnimalState.DEAD:
		return
	health -= amount
	_health_bar.value = (health / max_health) * 100.0
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)
	if health <= 0.0:
		_die()
		return
	if current_state == AnimalState.WILD and source != null:
		_start_flee(source)

func _physics_process(delta: float) -> void:
	# Teleport back to nearest passable ground if the nav mesh walked us into
	# impassable terrain (ocean, risco, caldera).
	if TerrainManager.is_impassable_for(global_position, ""):
		global_position = TerrainManager.nearest_passable(global_position, "")
		_nav.target_position = global_position
		velocity = Vector2.ZERO
		return
	match current_state:
		AnimalState.WILD:
			_handle_wander(delta)
		AnimalState.OWNED:
			_handle_owned_move()
		AnimalState.FLEEING:
			_handle_flee(delta)

func _handle_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_target()
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	_nav.set_velocity(_direction_to_target() * WANDER_SPEED)

func _handle_owned_move() -> void:
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	_nav.set_velocity(_direction_to_target() * WANDER_SPEED)

func order_move(destination: Vector2) -> void:
	if current_state != AnimalState.OWNED:
		return
	var target: Vector2 = destination if not TerrainManager.is_impassable_for(destination, "") \
		else TerrainManager.nearest_passable(destination, "")
	_nav.target_position = target

func _handle_flee(delta: float) -> void:
	_flee_timer -= delta
	if _flee_timer <= 0.0 or _nav.is_navigation_finished():
		current_state = AnimalState.WILD
		_pick_wander_target()
		return
	_nav.set_velocity(_direction_to_target() * FLEE_SPEED)

func _on_body_entered_range(body: Node) -> void:
	if not convertible:
		return
	if current_state == AnimalState.DEAD:
		return
	var pid: Variant = body.get("player_id")
	if pid == null:
		return
	var owner_id: int = pid as int
	if owner_id < 0:
		return
	_try_convert(owner_id)

func _try_convert(owner_id: int) -> void:
	if current_state == AnimalState.DEAD:
		return
	if player_id == owner_id:
		return
	_convert_to(owner_id)

func _convert_to(owner_id: int) -> void:
	player_id = owner_id
	current_state = AnimalState.OWNED
	_on_converted()
	_origin = global_position
	_nav.target_position = global_position
	velocity = Vector2.ZERO

func _on_converted() -> void:
	_body_torso.color = Color(0.78, 0.55, 0.18, 1.0)

func _start_flee(from_source: Node) -> void:
	current_state = AnimalState.FLEEING
	_flee_timer = FLEE_DURATION
	var flee_dir: Vector2 = (global_position - (from_source as Node2D).global_position).normalized()
	# Try to flee directly away; if that lands on impassable terrain, rotate
	# the direction in steps until a passable spot is found.
	for step: int in range(8):
		var rot: float = step * (PI / 4.0) * (1 if step % 2 == 0 else -1)
		var rotated: Vector2 = flee_dir.rotated(rot)
		var away: Vector2 = global_position + rotated * 300.0
		if not TerrainManager.is_impassable_for(away, ""):
			_nav.target_position = away
			return
	_nav.target_position = global_position

func _pick_wander_target() -> void:
	_wander_timer = randf_range(3.0, 8.0)
	# Try up to 10 candidates; skip any that land on impassable terrain (ocean,
	# risco, caldera) so the animal stays on its home terrain type.
	for _i: int in range(10):
		var angle: float = randf() * TAU
		var dist: float  = randf_range(60.0, WANDER_RADIUS)
		var candidate: Vector2 = _origin + Vector2(cos(angle), sin(angle)) * dist
		if not TerrainManager.is_impassable_for(candidate, ""):
			_nav.target_position = candidate
			return
	# All candidates were impassable — stay put
	_nav.target_position = global_position

func _direction_to_target() -> Vector2:
	if _nav.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = _nav.get_next_path_position()
	var dir: Vector2  = next - global_position
	if dir.length_squared() < 1.0:
		return Vector2.ZERO
	return dir.normalized()

func _die() -> void:
	current_state = AnimalState.DEAD
	_health_bar.visible = false
	_selection_indicator.visible = false
	var food_node: Node2D = Node2D.new()
	food_node.set_script(load("res://scripts/economy/resource_node.gd"))
	food_node.set("resource_type", ResourceNode.ResourceType.FOOD_HUNT)
	food_node.set("initial_amount", FOOD_AMOUNT)
	get_parent().get_parent().add_child(food_node)
	food_node.global_position = global_position
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(0.65, 0.18, 0.10, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.offset_left = -10.0
	rect.offset_top = -10.0
	rect.offset_right = 10.0
	rect.offset_bottom = 10.0
	food_node.add_child(rect)
	var lbl: Label = Label.new()
	lbl.text = "Food"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.offset_left = -20.0
	lbl.offset_top = -24.0
	lbl.offset_right = 20.0
	lbl.offset_bottom = -12.0
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	food_node.add_child(lbl)
	queue_free()

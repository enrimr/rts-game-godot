extends CharacterBody2D

class_name Animal

enum AnimalState { WILD, LURED, FLEEING, DEAD }

const FOOD_AMOUNT: float = 150.0
const WANDER_SPEED: float = 40.0
const LURED_SPEED: float = 70.0
const FLEE_SPEED: float  = 110.0
const WANDER_RADIUS: float = 200.0
const LURE_RANGE: float   = 240.0
const FLEE_DURATION: float = 3.0

@export var max_health: float = 40.0
@export var animal_name: String = "Deer"

var player_id: int = -1   # -1 = neutral wild animal; set when lured
var health: float = 0.0
var current_state: AnimalState = AnimalState.WILD

var _lurer: Node = null
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _flee_timer: float = 0.0
var _origin: Vector2 = Vector2.ZERO

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _selection_indicator: Node2D = $SelectionIndicator
@onready var _body_rect: ColorRect = $Body
@onready var _nav: NavigationAgent2D = $NavigationAgent2D

func _ready() -> void:
	health = max_health
	_origin = global_position
	_pick_wander_target()
	add_to_group("animals")
	_nav.velocity_computed.connect(_on_velocity_computed)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func set_selected(value: bool) -> void:
	_selection_indicator.visible = value

func take_damage(amount: float, source: Node = null) -> void:
	if current_state == AnimalState.DEAD:
		return
	health -= amount
	_health_bar.value = (health / max_health) * 100.0
	if health <= 0.0:
		_die()
		return
	# Wild animal flees when hit
	if current_state == AnimalState.WILD and source != null:
		_start_flee(source)

func lure(by_unit: Node) -> void:
	if current_state == AnimalState.DEAD:
		return
	_lurer = by_unit
	player_id = by_unit.get("player_id") as int if by_unit.get("player_id") != null else 0
	current_state = AnimalState.LURED
	_body_rect.color = Color(0.75, 0.55, 0.20, 1.0)  # slightly warmer to show tamed

func _physics_process(delta: float) -> void:
	match current_state:
		AnimalState.WILD:    _handle_wild(delta)
		AnimalState.LURED:   _handle_lured(delta)
		AnimalState.FLEEING: _handle_flee(delta)

func _handle_wild(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_target()
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	_nav.set_velocity(_direction_to_target() * WANDER_SPEED)

func _handle_lured(delta: float) -> void:
	if not is_instance_valid(_lurer):
		current_state = AnimalState.WILD
		_lurer = null
		return
	var dist: float = global_position.distance_to((_lurer as Node2D).global_position)
	if dist > LURE_RANGE:
		# Too far — go back to wild
		current_state = AnimalState.WILD
		_lurer = null
		return
	_nav.target_position = (_lurer as Node2D).global_position
	if _nav.is_navigation_finished() or dist < 48.0:
		velocity = Vector2.ZERO
		return
	_nav.set_velocity(_direction_to_target() * LURED_SPEED)

func _handle_flee(delta: float) -> void:
	_flee_timer -= delta
	if _flee_timer <= 0.0 or _nav.is_navigation_finished():
		current_state = AnimalState.WILD
		_pick_wander_target()
		return
	_nav.set_velocity(_direction_to_target() * FLEE_SPEED)

func _start_flee(from_source: Node) -> void:
	current_state = AnimalState.FLEEING
	_flee_timer = FLEE_DURATION
	var away: Vector2 = global_position + (global_position - (from_source as Node2D).global_position).normalized() * 300.0
	_nav.target_position = away

func _pick_wander_target() -> void:
	_wander_timer = randf_range(3.0, 8.0)
	var angle: float = randf() * TAU
	var dist: float = randf_range(60.0, WANDER_RADIUS)
	var target: Vector2 = _origin + Vector2(cos(angle), sin(angle)) * dist
	_nav.target_position = target
	_wander_target = target

func _direction_to_target() -> Vector2:
	if _nav.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = _nav.get_next_path_position()
	var dir: Vector2 = next - global_position
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
	var world: Node = get_parent().get_parent()
	world.add_child(food_node)
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

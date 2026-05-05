extends CharacterBody2D

class_name UnitBase

enum UnitState { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, DEAD }

@export var unit_data: UnitResource

var player_id: int = 0
var current_state: UnitState = UnitState.IDLE
var health: float = 0.0
var is_selected: bool = false

var _stuck_timer: float = 0.0
var _stuck_retries: int = 0
var _last_position: Vector2 = Vector2.ZERO

const STUCK_TIMEOUT: float = 1.5
const STUCK_THRESHOLD: float = 8.0
const MAX_STUCK_RETRIES: int = 1

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var selection_indicator: Node2D = $SelectionIndicator
@onready var attack_range_area: Area2D = get_node_or_null("AttackRange")

func _ready() -> void:
	if unit_data:
		health = unit_data.max_health
	_last_position = global_position
	if is_instance_valid(attack_range_area):
		attack_range_area.monitoring = true
		attack_range_area.body_entered.connect(_on_enemy_entered_range)
	call_deferred("_add_player_color_stripe")

func _add_player_color_stripe() -> void:
	PlayerColors.apply_color_stripe(self, player_id, 20.0, 4.0)

func set_selected(value: bool) -> void:
	is_selected = value
	selection_indicator.visible = value

func move_to(target_position: Vector2) -> void:
	nav_agent.target_position = target_position
	current_state = UnitState.MOVING

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	health_bar.value = health / unit_data.max_health * 100.0
	if health <= 0.0:
		die()
		return
	if current_state == UnitState.IDLE and source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and (src_pid as int) != player_id:
			_on_auto_attack_target(source)

func die() -> void:
	current_state = UnitState.DEAD
	if is_instance_valid(attack_range_area):
		attack_range_area.monitoring = false
	EventBus.unit_died.emit(self, player_id)
	queue_free()

func _on_enemy_entered_range(body: Node) -> void:
	if current_state != UnitState.IDLE:
		return
	var body_pid: Variant = body.get("player_id")
	if body_pid == null or (body_pid as int) == player_id:
		return
	_on_auto_attack_target(body)

# Override in subclasses to trigger attack logic.
func _on_auto_attack_target(_target: Node) -> void:
	pass

# Returns the desired velocity toward the next nav path point.
# Returns ZERO when already at the point or navigation is finished.
func _nav_velocity() -> Vector2:
	if nav_agent.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = nav_agent.get_next_path_position()
	var dir: Vector2 = next - global_position
	if dir.length_squared() < 1.0:
		return Vector2.ZERO
	return dir.normalized() * unit_data.move_speed

# Tracks movement over time. Returns true once per stuck period so the
# caller can take corrective action (re-path with jitter or force-finish).
func _advance_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_position) >= STUCK_THRESHOLD:
		_stuck_timer = 0.0
		_stuck_retries = 0
		_last_position = global_position
		return false
	_stuck_timer += delta
	if _stuck_timer >= STUCK_TIMEOUT:
		_stuck_timer = 0.0
		_last_position = global_position
		return true
	return false

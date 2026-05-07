extends CharacterBody2D

class_name UnitBase

enum UnitState { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, DEAD }

@export var unit_data: UnitResource

var player_id: int = 0
var current_state: UnitState = UnitState.IDLE
var health: float = 0.0
var is_selected: bool = false
var civ_id: String = ""   # set at spawn time from MatchConfig for player units

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
	if player_id == 0:
		AudioManager.play("hit_melee", -8.0)
	if source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and (src_pid as int) != player_id:
			if player_id != 0:
				EventBus.ai_unit_under_attack.emit(player_id)
			if current_state == UnitState.IDLE:
				_on_auto_attack_target(source)

func die() -> void:
	current_state = UnitState.DEAD
	if player_id == 0:
		AudioManager.play("unit_die", -6.0)
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
	# Only auto-attack units, not buildings (buildings don't have unit_data)
	if body.get("unit_data") == null and not (body is Animal):
		return
	_on_auto_attack_target(body)

# Override in subclasses to trigger attack logic.
func _on_auto_attack_target(_target: Node) -> void:
	pass

# Reads armor_melee from a target node, handling both unit (via unit_data) and
# building (via building_data or direct property) targets.
func _get_target_armor(target: Node) -> float:
	if not is_instance_valid(target):
		return 0.0
	var udata: Variant = target.get("unit_data")
	if udata is UnitResource:
		return (udata as UnitResource).armor_melee
	var bdata: Variant = target.get("building_data")
	if bdata is BuildingResource:
		return (bdata as BuildingResource).get("armor_melee") if (bdata as BuildingResource).get("armor_melee") != null else 0.0
	return 0.0

# Effective attack reach toward a target, extended by half the target's
# footprint so units stop and fight at the edge rather than trying to reach center.
func _attack_reach_to(target: Node) -> float:
	var base: float = unit_data.attack_range * 32.0
	if not is_instance_valid(target):
		return base
	# Prefer CollisionShape2D rectangle (buildings with StaticBody2D)
	var cs: CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var rect: RectangleShape2D = cs.shape as RectangleShape2D
		return base + maxf(rect.size.x, rect.size.y) * 0.5
	# Fallback: use the Body ColorRect dimensions (e.g. Town Center Node2D)
	var body_rect: ColorRect = target.get_node_or_null("Body") as ColorRect
	if body_rect == null:
		body_rect = target.get_node_or_null("DropOffVisual") as ColorRect
	if body_rect != null:
		var w: float = body_rect.offset_right - body_rect.offset_left
		var h: float = body_rect.offset_bottom - body_rect.offset_top
		return base + maxf(w, h) * 0.5
	return base

# Returns the best navigation target position toward a node.
# For buildings (StaticBody2D), approaches to the edge of their footprint
# instead of the center, which is inside their collision shape.
func _nav_target_for(target: Node) -> Vector2:
	var target_pos: Vector2 = (target as Node2D).global_position
	if not (target is StaticBody2D):
		return target_pos
	# Find footprint half-extents from CollisionShape2D
	var cs: CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		var to_self: Vector2 = global_position - target_pos
		# Clamp the approach point to just outside the bounding box
		var clamped: Vector2 = Vector2(
			clampf(to_self.x, -half.x, half.x),
			clampf(to_self.y, -half.y, half.y)
		)
		return target_pos + clamped + to_self.normalized() * 8.0
	return target_pos

# Clamps a movement destination to the nearest passable tile for this unit.
# Call this before setting nav_agent.target_position.
func _safe_destination(destination: Vector2) -> Vector2:
	return TerrainManager.nearest_passable(destination, civ_id)

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

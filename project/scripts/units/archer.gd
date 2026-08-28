extends UnitBase

class_name Archer

const ARROW_SCENE: PackedScene = preload("res://scenes/combat/arrow.tscn")

## How close (fraction of reach) an enemy may get before the archer backs away.
const KITE_RATIO: float = 0.4
const KITE_STEP: float = 80.0

var _cover_fire_pos: Vector2 = Vector2.ZERO
var _cover_fire_pending: bool = false

func get_selection_sound() -> String:
	return "select_archer"

func _ready() -> void:
	super._ready()
	UnitDress.apply.call_deferred(self, player_id)

# Narrower stripe at the feet so the team colour doesn't cover the archer body.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 6.6, 10.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func order_attack_ground(world_pos: Vector2) -> void:
	attack_target = null
	_attack_move_active = false
	_cover_fire_pending = false
	var reach: float = unit_data.attack_range * 32.0
	if global_position.distance_to(world_pos) <= reach:
		_destination_state = UnitState.IDLE
		current_state = UnitState.IDLE
		nav_agent.set_velocity(Vector2.ZERO)
		_launch_arrow_to(world_pos)
	else:
		# Move to the edge of attack range toward the target, then fire
		var dir: Vector2 = (world_pos - global_position).normalized()
		var stop_pos: Vector2 = world_pos - dir * reach * 0.85
		_cover_fire_pos = world_pos
		_cover_fire_pending = true
		_destination_state = UnitState.IDLE
		_navigate_to(stop_pos)
		current_state = UnitState.MOVING

# ── Combat machine hooks ──

func _on_move_ordered() -> void:
	_cover_fire_pending = false

func _on_destination_reached() -> void:
	_release_cover_fire()

func _on_movement_stuck() -> void:
	_release_cover_fire()

func _release_cover_fire() -> void:
	if _cover_fire_pending:
		_cover_fire_pending = false
		_launch_arrow_to(_cover_fire_pos)

# Archers keep distance — back away if the target gets too close.
func _combat_reposition(dist: float, reach: float) -> bool:
	if dist >= reach * KITE_RATIO:
		return false
	var away: Vector2 = global_position \
		+ (global_position - (attack_target as Node2D).global_position).normalized() * KITE_STEP
	nav_agent.target_position = _safe_destination(away)
	nav_agent.set_velocity(_nav_velocity())
	return true

# The arrow deals the damage and emits unit_attacked on impact.
func _execute_strike(target: Node) -> void:
	_launch_arrow(target)

func _launch_arrow(target: Node) -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	arrow.damage = _strike_damage(target)
	arrow.shooter = self
	arrow.target_pos = (target as Node2D).global_position
	arrow._original_target = target
	get_parent().add_child(arrow)
	arrow.global_position = global_position

func _launch_arrow_to(world_pos: Vector2) -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	arrow.damage = 0.0
	arrow.shooter = self
	arrow.target_pos = world_pos
	arrow._original_target = null
	get_parent().add_child(arrow)
	arrow.global_position = global_position

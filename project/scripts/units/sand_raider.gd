extends UnitBase

class_name SandRaider

var _retreating: bool = false
var _retreat_destination: Vector2 = Vector2.ZERO

const RETREAT_DISTANCE: float = 90.0

func get_selection_sound() -> String:
	return "select_cavalry"

# Stripe + shadow sized for the horse footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 9.9, 12.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 15.0, 4.5, 11.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

# ── Combat machine hooks ──

func _on_move_ordered() -> void:
	_retreating = false

func _on_attack_ordered() -> void:
	_retreating = false

func _on_target_lost() -> void:
	_retreating = false
	_scan_area_for_target()

## Hit & Run: after each strike, gallop away before re-engaging.
func _after_strike(_target: Node) -> void:
	_begin_retreat()

func _handle_movement_override(delta: float) -> bool:
	if not _retreating:
		return false
	if nav_agent.is_navigation_finished() \
			or global_position.distance_to(_retreat_destination) < 16.0:
		_retreating = false
		if is_instance_valid(attack_target):
			_destination_state = UnitState.ATTACKING
			_repath_to(_nav_target_for(attack_target))
		else:
			current_state = UnitState.IDLE
			_destination_state = UnitState.IDLE
			return true
	if _advance_stuck(delta):
		_retreating = false
		return true
	_drive_agent(_nav_velocity())
	return true

func _begin_retreat() -> void:
	if not is_instance_valid(attack_target):
		return
	var away_dir: Vector2 = (global_position - (attack_target as Node2D).global_position).normalized()
	_retreat_destination = global_position + away_dir * RETREAT_DISTANCE
	_retreating = true
	_navigate_to(_retreat_destination)
	current_state = UnitState.MOVING

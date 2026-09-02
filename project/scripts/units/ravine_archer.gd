extends UnitBase

class_name RavineArcher

## Ravine Archer — Canarii unique ranged unit. Strikes directly (no arrow
## projectile). Ambush Shot: after standing still for a while the next hit
## deals double damage, once per stationary period.

var _stationary_timer: float = 0.0
var _ambush_ready: bool = false
var _ambush_used: bool = false

const AMBUSH_STATIONARY_THRESHOLD: float = 1.5
const AMBUSH_DAMAGE_MULTIPLIER: float = 2.0
const STATIONARY_VELOCITY_THRESHOLD: float = 5.0

func get_selection_sound() -> String:
	return "select_archer"

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 6.6, 10.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

# ── Combat machine hooks ──

# Any frame spent MOVING (including the arrival frame) discards the ambush arm.
func _on_movement_tick(_delta: float) -> void:
	_reset_ambush()

func _combat_side_tick(delta: float) -> void:
	if current_state == UnitState.IDLE \
			or (current_state == UnitState.ATTACKING and velocity.length() < STATIONARY_VELOCITY_THRESHOLD):
		_stationary_timer += delta
		if _stationary_timer >= AMBUSH_STATIONARY_THRESHOLD and not _ambush_used:
			_ambush_ready = true
	elif current_state == UnitState.MOVING:
		_reset_ambush()

# Kiting: back away if the target gets too close, resetting the ambush charge.
func _combat_reposition(dist: float, reach: float) -> bool:
	if dist >= reach * 0.4:
		return false
	var away: Vector2 = global_position \
		+ (global_position - (attack_target as Node2D).global_position).normalized() * 80.0
	nav_agent.target_position = _safe_destination(away)
	_drive_agent(_nav_velocity())
	_reset_ambush()
	return true

func _strike_damage(target: Node) -> float:
	var dmg: float = super._strike_damage(target)
	if _ambush_ready and not _ambush_used:
		dmg *= AMBUSH_DAMAGE_MULTIPLIER
		_ambush_ready = false
		_ambush_used = true
		_stationary_timer = 0.0
	return dmg

func _strike_sound() -> String:
	return "hit_ranged"

func _reset_ambush() -> void:
	_stationary_timer = 0.0
	_ambush_ready = false
	_ambush_used = false

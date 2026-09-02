extends UnitBase

class_name Conquistador

var _salvo_cooldown: float = 0.0
var _salvo_active: bool = false
var _salvo_shots_remaining: int = 0
var _salvo_shot_timer: float = 0.0

const SALVO_COOLDOWN_MAX: float = 12.0
const SALVO_SHOT_COUNT: int = 3
const SALVO_SHOT_INTERVAL: float = 0.3
const SALVO_SHOT_DAMAGE: float = 6.0

func get_selection_sound() -> String:
	return "select_infantry"

# Stripe + shadow sized for the warhorse footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 11.0, 13.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 16.0, 5.0, 12.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

# ── Combat machine hooks ──

func _combat_side_tick(delta: float) -> void:
	if _salvo_cooldown > 0.0:
		_salvo_cooldown -= delta
	if _salvo_active:
		_tick_salvo(delta)

## A running salvo holds position and suspends the regular attack timer.
func _attack_paused() -> bool:
	return _salvo_active

# Back away if enemy closes past 50% of attack range.
func _combat_reposition(dist: float, reach: float) -> bool:
	if dist >= reach * 0.5:
		return false
	var away: Vector2 = global_position \
		+ (global_position - (attack_target as Node2D).global_position).normalized() * 64.0
	_repath_to(away)
	_drive_agent(_nav_velocity())
	return true

# A ready salvo replaces the regular shot; _tick_salvo delivers the burst.
func _execute_strike(target: Node) -> void:
	if _salvo_cooldown <= 0.0:
		_salvo_active = true
		_salvo_shots_remaining = SALVO_SHOT_COUNT
		_salvo_shot_timer = 0.0
		return
	super._execute_strike(target)

func _strike_sound() -> String:
	return "hit_ranged"

func _tick_salvo(delta: float) -> void:
	if not is_instance_valid(attack_target):
		_salvo_active = false
		_salvo_shots_remaining = 0
		return
	_salvo_shot_timer -= delta
	if _salvo_shot_timer <= 0.0:
		_salvo_shot_timer = SALVO_SHOT_INTERVAL
		if attack_target.has_method("take_damage"):
			var dmg: float = SALVO_SHOT_DAMAGE * CivBonusManager.get_unit_attack_multiplier(player_id, unit_data.id) \
				- _get_target_armor(attack_target)
			attack_target.take_damage(maxf(dmg, 0.0), self)
			AudioManager.play_if_visible("hit_ranged", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)
		_salvo_shots_remaining -= 1
		if _salvo_shots_remaining <= 0:
			_salvo_active = false
			_salvo_cooldown = SALVO_COOLDOWN_MAX

extends UnitBase

class_name MenceyesGuard

const RAGE_HP_THRESHOLD: float = 0.5
const RAGE_PULSE_INTERVAL: float = 2.0
const RAGE_RADIUS: float = 80.0
const RAGE_BONUS: float = 3.0
const RAGE_DURATION: float = 3.0

var _rage_timer: float = 0.0
# Incoming rage bonus from a nearby MenceyesGuard — consumed each attack tick.
var _rage_bonus: float = 0.0
var _rage_timer_remaining: float = 0.0

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 6.6, 10.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _combat_side_tick(delta: float) -> void:
	_tick_rage_aura(delta)
	if _rage_timer_remaining > 0.0:
		_rage_timer_remaining -= delta
		if _rage_timer_remaining <= 0.0:
			_rage_bonus = 0.0

func _tick_rage_aura(delta: float) -> void:
	if unit_data == null:
		return
	var max_hp: float = unit_data.max_health * CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
	if health / max_hp >= RAGE_HP_THRESHOLD:
		_rage_timer = 0.0
		return
	_rage_timer += delta
	if _rage_timer < RAGE_PULSE_INTERVAL:
		return
	_rage_timer = 0.0
	for body: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(body):
			continue
		var pid: Variant = body.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if (body as Node2D).global_position.distance_to(global_position) > RAGE_RADIUS:
			continue
		body.set("_rage_bonus", RAGE_BONUS)
		body.set("_rage_timer_remaining", RAGE_DURATION)

func _get_effective_attack_vs(target: Node) -> float:
	var base: float = super._get_effective_attack_vs(target)
	if _rage_bonus > 0.0:
		base += _rage_bonus
	return base

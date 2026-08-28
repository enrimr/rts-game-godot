extends UnitBase

class_name ChevalierNormand

var _distance_moved: float = 0.0
var _charge_ready: bool = false

const CHARGE_DISTANCE_THRESHOLD: float = 80.0
const CHARGE_DAMAGE_MULTIPLIER: float = 2.5

# Stripe + shadow sized for the warhorse footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 11.0, 13.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 16.0, 5.0, 12.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

# ── Combat machine hooks ──

## Lance Charge: arm after covering enough ground in one run.
func _on_movement_tick(delta: float) -> void:
	_distance_moved += velocity.length() * delta
	if _distance_moved >= CHARGE_DISTANCE_THRESHOLD:
		_charge_ready = true

func _strike_damage(target: Node) -> float:
	var dmg: float = super._strike_damage(target)
	if _charge_ready:
		dmg *= CHARGE_DAMAGE_MULTIPLIER
		_charge_ready = false
		_distance_moved = 0.0
	return dmg

# Every strike resets the charge, spent or not: standing and swinging must not
# keep accumulated approach distance banked for a later hit.
func _after_strike(_target: Node) -> void:
	_distance_moved = 0.0
	_charge_ready = false

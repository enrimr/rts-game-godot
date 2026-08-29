extends ShipBase

class_name Trireme

## Fenicios unique warship. The move/chase/strike cycle comes from UnitBase;
## this class adds the ram (double damage + knockback vs ships) and a passive
## gold trickle from the Fenicios merchant-fleet heritage.

const RAM_PUSH_DISTANCE: float = 40.0
const RAM_DAMAGE_MULTIPLIER: float = 2.0
## Passive gold trickle: 5 gold every 30 s, scaled by merchant_ship_gold_rate.
const GOLD_TICK_AMOUNT: float = 5.0
const GOLD_TICK_INTERVAL: float = 30.0

var _gold_timer: float = 0.0

func _ready() -> void:
	# Civ-unique hull: it is already painted in Fenicios colours (purple sail
	# stripe, painted eye), so it opts out of the shared naval dress pass.
	set_meta(ShipDress.META_APPLIED, true)
	super._ready()

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _combat_side_tick(delta: float) -> void:
	_tick_passive_gold(delta)

func _tick_passive_gold(delta: float) -> void:
	_gold_timer += delta
	if _gold_timer >= GOLD_TICK_INTERVAL:
		_gold_timer = 0.0
		var rate: float = CivBonusManager.get_multiplier(player_id, "merchant_ship_gold_rate")
		if rate > 0.0:
			ResourceManager.add_resource(player_id, "gold", int(GOLD_TICK_AMOUNT * rate))

func _strike_damage(target: Node) -> float:
	var dmg: float = super._strike_damage(target)
	if _is_ship_target(target):
		dmg *= RAM_DAMAGE_MULTIPLIER
	return dmg

func _after_strike(target: Node) -> void:
	if _is_ship_target(target):
		_push_target(target)

func _is_ship_target(target: Node) -> bool:
	return target is ShipBase

func _push_target(target: Node) -> void:
	var push_dir: Vector2 = ((target as Node2D).global_position - global_position).normalized()
	(target as Node2D).global_position += push_dir * RAM_PUSH_DISTANCE

extends Archer

class_name Longbowman

# The anti-cavalry Armour Piercing bonus moved to DATA: it is now
# attack_bonuses {"cavalry": 4.0} in longbowman_data.tres, applied by the
# shared counter-triangle path in UnitBase._strike_damage.

# Unique unit carries its own identity (hood + quiver rig): block the civ
# dress pass Archer._ready schedules, which would stack headgear on the hood.
func _ready() -> void:
	set_meta(UnitDress.META_APPLIED, true)
	super._ready()

# Kiting: back away when enemy closes in, exploiting the Longbowman's superior
# range — wider trigger (half reach) and longer step than the base archer.
func _combat_reposition(dist: float, reach: float) -> bool:
	if dist >= reach * 0.5:
		return false
	var away: Vector2 = global_position \
		+ (global_position - (attack_target as Node2D).global_position).normalized() * 96.0
	_repath_to(away)
	_drive_agent(_nav_velocity())
	return true

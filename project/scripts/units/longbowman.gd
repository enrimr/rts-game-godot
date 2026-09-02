extends Archer

class_name Longbowman

const CAVALRY_IDS: Array[String] = ["scout", "heavy_scout", "knight", "chevalier_normand", "sand_raider"]
const CAVALRY_BONUS_DAMAGE: float = 4.0

# Unique unit carries its own identity (hood + quiver rig): block the civ
# dress pass Archer._ready schedules, which would stack headgear on the hood.
func _ready() -> void:
	set_meta(UnitDress.META_APPLIED, true)
	super._ready()

# The arrow carries the anti-cavalry bonus on top of the base archer damage.
func _strike_damage(target: Node) -> float:
	return super._strike_damage(target) + _get_cavalry_bonus(target)

# Kiting: back away when enemy closes in, exploiting the Longbowman's superior
# range — wider trigger (half reach) and longer step than the base archer.
func _combat_reposition(dist: float, reach: float) -> bool:
	if dist >= reach * 0.5:
		return false
	var away: Vector2 = global_position \
		+ (global_position - (attack_target as Node2D).global_position).normalized() * 96.0
	nav_agent.target_position = _safe_destination(away)
	_drive_agent(_nav_velocity())
	return true

func _get_cavalry_bonus(target: Node) -> float:
	var udata: Variant = target.get("unit_data")
	if not (udata is UnitResource):
		return 0.0
	var uid: String = (udata as UnitResource).id
	for cavalry_id: String in CAVALRY_IDS:
		if uid == cavalry_id:
			return CAVALRY_BONUS_DAMAGE
	return 0.0

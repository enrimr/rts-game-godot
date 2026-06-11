extends GutTest

## Damage-type vs armour-type resolution in UnitBase._get_target_armor.
##
## Regression guard for the bug where every attacker subtracted the target's
## armor_melee regardless of attack type, so archers ignored armor_pierce
## entirely (an archer dealt the same damage to a heavily-armoured knight as
## to an unarmoured target). _get_target_armor must now pick the armour value
## matching the ATTACKER's unit_data.damage_type:
##   1.  A PIERCE attacker reads the target's armor_pierce.
##   2.  A MELEE attacker reads the target's armor_melee.
##   3.  The two values are genuinely independent (the bug returned melee for both).
##   4.  Resource defaults to MELEE so existing melee units are unaffected.
##   5.  The shipped archer_data.tres / militia_data.tres carry the right types.

const UNRES := preload("res://resources/units/unit_resource.gd")

# Minimal target stand-in: exposes unit_data + player_id via get(), which is all
# _get_target_armor reads from a target. Avoids the full UnitBase _ready rig.
class TargetDouble:
	extends Node
	var unit_data: UnitResource
	var player_id: int = 1

func _make_data(dmg_type: int, melee: float, pierce: float) -> UnitResource:
	var d: UnitResource = UNRES.new()
	d.id = "dummy"
	d.damage_type = dmg_type
	d.armor_melee = melee
	d.armor_pierce = pierce
	return d

func _attacker(dmg_type: int) -> UnitBase:
	var u: UnitBase = UnitBase.new()
	# _get_target_armor only needs unit_data on the attacker; do not add to tree.
	u.unit_data = _make_data(dmg_type, 0.0, 0.0)
	u.player_id = 0
	return u

func _target(melee: float, pierce: float) -> TargetDouble:
	var t: TargetDouble = TargetDouble.new()
	t.unit_data = _make_data(UNRES.DamageType.MELEE, melee, pierce)
	return t

func after_each() -> void:
	# Free the loose (non-tree) nodes we new()'d.
	pass

# 1 — PIERCE attacker reads armor_pierce
func test_pierce_attacker_uses_pierce_armor() -> void:
	var atk: UnitBase = _attacker(UNRES.DamageType.PIERCE)
	var tgt: TargetDouble = _target(8.0, 2.0)   # melee 8, pierce 2
	assert_eq(atk._get_target_armor(tgt), 2.0, "PIERCE attack must subtract armor_pierce, not armor_melee")
	atk.free(); tgt.free()

# 2 — MELEE attacker reads armor_melee
func test_melee_attacker_uses_melee_armor() -> void:
	var atk: UnitBase = _attacker(UNRES.DamageType.MELEE)
	var tgt: TargetDouble = _target(8.0, 2.0)
	assert_eq(atk._get_target_armor(tgt), 8.0, "MELEE attack must subtract armor_melee")
	atk.free(); tgt.free()

# 3 — the two armour channels are independent (the old bug collapsed them)
func test_armor_channels_are_independent() -> void:
	var archer: UnitBase = _attacker(UNRES.DamageType.PIERCE)
	var swordsman: UnitBase = _attacker(UNRES.DamageType.MELEE)
	var tgt: TargetDouble = _target(10.0, 0.0)   # armoured vs melee, naked vs pierce
	assert_eq(archer._get_target_armor(tgt), 0.0, "Archer should bypass pure melee armour")
	assert_eq(swordsman._get_target_armor(tgt), 10.0, "Swordsman should be fully blocked by melee armour")
	archer.free(); swordsman.free(); tgt.free()

# 4 — UnitResource defaults to MELEE
func test_resource_defaults_to_melee() -> void:
	var d: UnitResource = UNRES.new()
	assert_eq(d.damage_type, UNRES.DamageType.MELEE, "New UnitResource must default to MELEE")

# 5 — shipped data carries the right damage types
func test_shipped_data_damage_types() -> void:
	var archer: UnitResource = load("res://resources/units/archer_data.tres") as UnitResource
	var militia: UnitResource = load("res://resources/units/militia_data.tres") as UnitResource
	assert_eq(archer.damage_type, UNRES.DamageType.PIERCE, "archer_data must be PIERCE")
	assert_eq(militia.damage_type, UNRES.DamageType.MELEE, "militia_data must be MELEE")

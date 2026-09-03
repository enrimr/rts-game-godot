extends GutTest

## Combat numbers must not depend on the developer's persisted settings:
## a TUTORIAL difficulty left in user://settings.cfg halved every non-zero
## player's HP and broke the volley arithmetic below.
var _saved_difficulty: int = GameSettings.Difficulty.NORMAL

func before_all() -> void:
	_saved_difficulty = GameSettings.difficulty
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL

func after_all() -> void:
	GameSettings.difficulty = _saved_difficulty

## End-to-end combat damage flow, complementing the isolated
## test_pierce_armor.gd unit test.
##
## test_pierce_armor.gd checks _get_target_armor in isolation (attacker's
## damage_type selects which armour channel is read). This suite drives the
## FULL attack pipeline used by every attacker subclass:
##
##     dmg = attacker._get_effective_attack_vs(target) - attacker._get_target_armor(target)
##     target.take_damage(maxf(dmg, 0.0), attacker)   # -> health drops
##
## on real UnitBase nodes carrying the SHIPPED .tres stats, and asserts the
## resulting HP. The point is the tactical decision the armour split creates:
##   - The same archer volley melts the pierce-naked pikeman but is blunted by
##     the armoured knight (pierce armour absorbs part of each shot).
##   - A melee swordsman is reduced by the knight's melee armour instead, on a
##     separate channel — pierce and melee armour are genuinely independent when
##     resolved through take_damage(), not just in _get_target_armor().
##   - Overkill damage never heals: maxf(dmg, 0.0) floors it at zero.
##
## Setup notes:
##   - Units are real UnitBase nodes; required @onready children
##     (NavigationAgent2D, HealthBar, SelectionIndicator) are injected before
##     add_child_autofree so _ready() resolves them and initialises `health`.
##   - All units use player_id != 0 so take_damage() skips the player-only audio
##     and the player_entity_under_attack EventBus wiring, keeping teardown clean.
##   - Attackers and targets sit on different player_ids so damage is hostile.

const UNRES := preload("res://resources/units/unit_resource.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _inject_children(unit: UnitBase) -> void:
	var nav: NavigationAgent2D = NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	unit.add_child(nav)

	var hbar: ProgressBar = ProgressBar.new()
	hbar.name = "HealthBar"
	unit.add_child(hbar)

	var sel: Node2D = Node2D.new()
	sel.name = "SelectionIndicator"
	var circle: Polygon2D = Polygon2D.new()
	circle.name = "SelectionCircle"
	sel.add_child(circle)
	unit.add_child(sel)


# Builds a real UnitBase node from a shipped resource file, in the tree with
# its health initialised by _ready(). pid must be non-zero (see setup notes).
func _make_unit(res_path: String, pid: int) -> UnitBase:
	var u: UnitBase = UnitBase.new()
	_inject_children(u)
	u.unit_data = load(res_path) as UnitResource
	u.player_id = pid
	add_child_autofree(u)
	return u


# The exact one-liner every attacker subclass runs (militia.gd:97, knight.gd:94,
# pikeman.gd:87, archer arrow damage, ...). Returns the raw HP removed.
func _resolve_hit(attacker: UnitBase, target: UnitBase) -> float:
	var dmg: float = maxf(attacker._get_effective_attack_vs(target) - attacker._get_target_armor(target), 0.0)
	target.take_damage(dmg, attacker)
	return dmg


# ---------------------------------------------------------------------------
# Tactical scenario: one archer volley, two different targets
# ---------------------------------------------------------------------------

# Archer (attack 5, PIERCE) vs pikeman (armor_pierce 0): full 5 dmg lands.
func test_archer_full_damage_vs_pierce_naked_pikeman() -> void:
	var archer: UnitBase = _make_unit("res://resources/units/archer_data.tres", 1)
	var pikeman: UnitBase = _make_unit("res://resources/units/pikeman_data.tres", 2)
	var hp0: float = pikeman.health

	var dmg: float = _resolve_hit(archer, pikeman)

	assert_eq(dmg, 5.0, "Archer should deal its full 5 attack to a pierce-naked target")
	assert_eq(pikeman.health, hp0 - 5.0, "Pikeman HP must drop by the full 5")


# Same archer vs knight (armor_pierce 1): the armour blunts one point.
func test_archer_reduced_damage_vs_armoured_knight() -> void:
	var archer: UnitBase = _make_unit("res://resources/units/archer_data.tres", 1)
	var knight: UnitBase = _make_unit("res://resources/units/knight_data.tres", 2)
	var hp0: float = knight.health

	var dmg: float = _resolve_hit(archer, knight)

	assert_eq(dmg, 4.0, "Knight's armor_pierce (1) must absorb one point of the archer's 5")
	assert_eq(knight.health, hp0 - 4.0, "Knight HP must drop by 4, not 5")


# The whole reason the armour split exists: the identical archer volley is more
# effective against the unarmoured target than the armoured one, END TO END.
func test_archer_volley_favours_unarmoured_target() -> void:
	var archer: UnitBase = _make_unit("res://resources/units/archer_data.tres", 1)
	var pikeman: UnitBase = _make_unit("res://resources/units/pikeman_data.tres", 2)
	var knight: UnitBase = _make_unit("res://resources/units/knight_data.tres", 2)

	var dmg_vs_pikeman: float = _resolve_hit(archer, pikeman)
	var dmg_vs_knight: float = _resolve_hit(archer, knight)

	assert_gt(dmg_vs_pikeman, dmg_vs_knight,
		"Same archer must hurt the pierce-naked pikeman more than the armoured knight")


# ---------------------------------------------------------------------------
# The two armour channels are independent through the full take_damage() flow
# ---------------------------------------------------------------------------

# A melee attacker (militia, attack 4, MELEE) is reduced by the knight's
# armor_melee (2), NOT its armor_pierce (1) — the channels don't cross.
func test_melee_attacker_reduced_by_melee_armour() -> void:
	var militia: UnitBase = _make_unit("res://resources/units/militia_data.tres", 1)
	var knight: UnitBase = _make_unit("res://resources/units/knight_data.tres", 2)
	var hp0: float = knight.health

	var dmg: float = _resolve_hit(militia, knight)

	assert_eq(dmg, 2.0, "Militia (attack 4) minus knight armor_melee (2) = 2")
	assert_eq(knight.health, hp0 - 2.0, "Knight HP must drop by 2 from the melee hit")


# Against the SAME knight, archer and militia read different armour channels,
# so their effective damage differs even though it flows through one code path.
func test_pierce_and_melee_channels_differ_on_same_target() -> void:
	var archer: UnitBase = _make_unit("res://resources/units/archer_data.tres", 1)
	var militia: UnitBase = _make_unit("res://resources/units/militia_data.tres", 1)
	var knight_a: UnitBase = _make_unit("res://resources/units/knight_data.tres", 2)
	var knight_b: UnitBase = _make_unit("res://resources/units/knight_data.tres", 2)

	var pierce_dmg: float = _resolve_hit(archer, knight_a)   # 5 - pierce 1 = 4
	var melee_dmg: float = _resolve_hit(militia, knight_b)   # 4 - melee 2  = 2

	assert_eq(pierce_dmg, 4.0, "Pierce channel: 5 - armor_pierce 1")
	assert_eq(melee_dmg, 2.0, "Melee channel: 4 - armor_melee 2")
	assert_ne(pierce_dmg, melee_dmg, "The two armour channels must resolve independently")


# ---------------------------------------------------------------------------
# Edge cases through the real flow
# ---------------------------------------------------------------------------

# Cumulative volleys reduce HP monotonically and eventually kill.
func test_repeated_volleys_kill_target() -> void:
	var archer: UnitBase = _make_unit("res://resources/units/archer_data.tres", 1)
	var pikeman: UnitBase = _make_unit("res://resources/units/pikeman_data.tres", 2)
	# Pikeman 65 HP, 5 dmg/shot -> 13 shots to reach 0.
	for i in range(12):
		_resolve_hit(archer, pikeman)
	assert_gt(pikeman.health, 0.0, "Pikeman should survive 12 volleys (60 dmg vs 65 HP)")
	assert_eq(pikeman.current_state, UnitBase.UnitState.IDLE, "Still alive, not DEAD")

	_resolve_hit(archer, pikeman)   # 13th shot -> 65 dmg
	assert_true(pikeman.health <= 0.0, "13th volley must bring HP to 0 or below")
	assert_eq(pikeman.current_state, UnitBase.UnitState.DEAD, "die() must set DEAD state")


# maxf(dmg, 0.0) floor: an attack weaker than armour never heals the target.
func test_overkill_armour_never_heals() -> void:
	# Militia (attack 4) vs a target whose melee armour exceeds the attack.
	var militia: UnitBase = _make_unit("res://resources/units/militia_data.tres", 1)
	var tank: UnitBase = _make_unit("res://resources/units/knight_data.tres", 2)
	tank.unit_data = tank.unit_data.duplicate()
	tank.unit_data.armor_melee = 10.0   # far above militia's 4 attack
	var hp0: float = tank.health

	var dmg: float = _resolve_hit(militia, tank)

	assert_eq(dmg, 0.0, "Damage must floor at 0 when armour exceeds attack")
	assert_eq(tank.health, hp0, "HP must not increase from a fully-absorbed hit")

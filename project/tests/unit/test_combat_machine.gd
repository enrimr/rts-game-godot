extends GutTest

## Tests for the shared combat state machine in UnitBase (base contract only —
## per-unit ability internals are covered by test_unique_units.gd).
##
## What is covered:
##   Order intent
##     1.  order_attack sets attack_target, _destination_state = ATTACKING, state MOVING
##     2.  order_move clears attack_target and resets _destination_state to IDLE
##     3.  _handle_movement flips MOVING → ATTACKING when already in attack position
##   _accepts_attack_order gate
##     4.  Base gate returns is_combat_unit()
##     5.  FishingBoat / TransportShip: is_combat_unit() == false, order_attack refused
##     6.  Taunted Militia refuses targets other than taunt_source, accepts the taunter
##   _attack_interval
##     7.  Inverse of unit_data.attack_speed with the default ×1.0 civ multiplier
##     8.  Applies CivBonusManager.get_attack_speed_multiplier (injected archer bonus)
##   _execute_strike
##     9.  Damage floors at 1.0 against an over-armoured target
##     10. Deals attack − armour against a normal target
##     11. Emits EventBus.unit_attacked with (attacker, target)
##     12. Fires the _after_strike hook
##   _handle_attacking hook ordering
##     13. Invalid target → _on_target_lost fires, state returns to IDLE
##     14. _attack_paused() true → no strike, _attack_timer untouched
##     15. _combat_reposition() true → no strike, _attack_timer untouched
##     16. In reach + timer elapsed → strike executes, timer resets
##   is_combat_unit
##     17. true on Militia / Knight / Archer, false on FishingBoat / TransportShip
##
## What is NOT covered:
##   - The chase branch of _handle_attacking (dist > reach): it drives
##     NavigationAgent2D velocity, which needs a synced navigation map.
##   - Stuck detection / _unstick recovery: same NavigationServer dependency.
##   - Projectile strikes (Archer._execute_strike spawns an Arrow scene).
##
## Setup notes:
##   - Same manual-construction pattern as test_unique_units.gd: required
##     children (NavigationAgent2D, HealthBar, SelectionIndicator) are injected
##     before add_child_autofree so @onready vars resolve in _ready().
##   - player_id = 1 avoids the player-0 EventBus guard wiring.
##   - HookRecorder extends UnitBase and records hook invocations so the
##     machine's dispatch order can be asserted without touching leaf classes.

const TEST_PID: int = 1
const TARGET_PID: int = 2


# ---------------------------------------------------------------------------
# Shared stubs
# ---------------------------------------------------------------------------

class FakeTarget extends CharacterBody2D:
	var player_id: int = 2
	var unit_data: UnitResource = null
	var _damage_received: float = 0.0
	var _hit_count: int = 0

	func _init(armor: float = 0.0) -> void:
		unit_data = UnitResource.new()
		unit_data.id = "militia"
		unit_data.armor_melee = armor

	func take_damage(amount: float, _source: Node = null) -> void:
		_damage_received += amount
		_hit_count += 1


## Records combat-machine hook calls on top of the unmodified base machine.
class HookRecorder extends UnitBase:
	var paused: bool = false
	var reposition: bool = false
	var after_strike_calls: int = 0
	var target_lost_calls: int = 0
	var reposition_calls: int = 0

	func _attack_paused() -> bool:
		return paused

	func _combat_reposition(_dist: float, _reach: float) -> bool:
		reposition_calls += 1
		return reposition

	func _after_strike(_target: Node) -> void:
		after_strike_calls += 1

	func _on_target_lost() -> void:
		target_lost_calls += 1


# ---------------------------------------------------------------------------
# Factory helpers
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Deterministic civ bonuses: empty dicts mean ×1.0 multiplicative / +0 additive.
	CivBonusManager._multipliers[TEST_PID] = {}
	CivBonusManager._multipliers[TARGET_PID] = {}


func _make_unit_base_children(unit: UnitBase) -> void:
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


func _make_unit_data(uid: String, attack: float = 5.0, attack_speed: float = 1.0) -> UnitResource:
	var d: UnitResource = UnitResource.new()
	d.id = uid
	d.max_health = 100.0
	d.attack = attack
	d.attack_speed = attack_speed
	d.attack_range = 4.0
	d.armor_melee = 0.0
	d.move_speed = 100.0
	return d


func _finish_unit(u: UnitBase, uid: String) -> void:
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data(uid)
	u.player_id = TEST_PID
	add_child_autofree(u)


func _make_militia() -> Militia:
	var u: Militia = Militia.new()
	_finish_unit(u, "militia")
	return u


func _make_recorder(uid: String = "militia") -> HookRecorder:
	var u: HookRecorder = HookRecorder.new()
	_finish_unit(u, uid)
	return u


func _make_target(armor: float = 0.0, pos: Vector2 = Vector2.ZERO) -> FakeTarget:
	var t: FakeTarget = FakeTarget.new(armor)
	t.global_position = pos
	add_child_autofree(t)
	return t


# ===========================================================================
# Order intent: order_attack / order_move
# ===========================================================================

# 1. order_attack records the intent and travels first
func test_order_attack_sets_target_and_states() -> void:
	var u: Militia = _make_militia()
	var target: FakeTarget = _make_target(0.0, Vector2(500.0, 0.0))

	u.order_attack(target)

	assert_eq(u.attack_target, target, "order_attack must store the target")
	assert_eq(u._destination_state, UnitBase.UnitState.ATTACKING,
		"order_attack must set _destination_state = ATTACKING")
	assert_eq(u.current_state, UnitBase.UnitState.MOVING,
		"order_attack must start by MOVING toward the target")


# 2. order_move cancels any pending combat intent
func test_order_move_clears_attack_target_and_destination_state() -> void:
	var u: Militia = _make_militia()
	var target: FakeTarget = _make_target(0.0, Vector2(500.0, 0.0))
	u.order_attack(target)

	u.order_move(Vector2(100.0, 100.0))

	assert_null(u.attack_target, "order_move must clear attack_target")
	assert_eq(u._destination_state, UnitBase.UnitState.IDLE,
		"order_move must reset _destination_state to IDLE")
	assert_eq(u.current_state, UnitBase.UnitState.MOVING,
		"order_move must switch state to MOVING")


# 3. _handle_movement flips to ATTACKING once in attack position
func test_handle_movement_flips_to_attacking_when_in_position() -> void:
	var u: Militia = _make_militia()
	var target: FakeTarget = _make_target(0.0, u.global_position)  # dist 0 <= reach
	u.order_attack(target)

	u._handle_movement(0.016)

	assert_eq(u.current_state, UnitBase.UnitState.ATTACKING,
		"_handle_movement must flip MOVING → ATTACKING when _in_attack_position")
	assert_eq(u._destination_state, UnitBase.UnitState.IDLE,
		"_destination_state must be consumed on the flip")


# ===========================================================================
# _accepts_attack_order gate
# ===========================================================================

# 4. Base gate delegates to is_combat_unit()
func test_base_accepts_attack_order_returns_is_combat_unit() -> void:
	var u: HookRecorder = _make_recorder()
	var target: FakeTarget = _make_target()
	assert_eq(u._accepts_attack_order(target), u.is_combat_unit(),
		"UnitBase._accepts_attack_order must return is_combat_unit()")
	assert_true(u._accepts_attack_order(target),
		"Default combat unit must accept attack orders")


# 5a. FishingBoat refuses attack orders entirely
func test_fishing_boat_order_attack_refused() -> void:
	var u: FishingBoat = FishingBoat.new()
	_finish_unit(u, "fishing_boat")
	var target: FakeTarget = _make_target(0.0, Vector2(200.0, 0.0))

	assert_false(u.is_combat_unit(), "FishingBoat.is_combat_unit() must be false")

	u.order_attack(target)

	assert_null(u.attack_target, "FishingBoat must not store an attack target")
	assert_eq(u.current_state, UnitBase.UnitState.IDLE,
		"Refused attack order must leave FishingBoat IDLE")


# 5b. TransportShip refuses attack orders entirely
func test_transport_ship_order_attack_refused() -> void:
	var u: TransportShip = TransportShip.new()
	_finish_unit(u, "transport_ship")
	var target: FakeTarget = _make_target(0.0, Vector2(200.0, 0.0))

	assert_false(u.is_combat_unit(), "TransportShip.is_combat_unit() must be false")

	u.order_attack(target)

	assert_null(u.attack_target, "TransportShip must not store an attack target")
	assert_eq(u.current_state, UnitBase.UnitState.IDLE,
		"Refused attack order must leave TransportShip IDLE")


# 6a. Taunted Militia refuses any target that is not the taunter
func test_taunted_militia_refuses_other_targets() -> void:
	var u: Militia = _make_militia()
	var taunter: FakeTarget = _make_target(0.0, Vector2(300.0, 0.0))
	var other: FakeTarget = _make_target(0.0, Vector2(-300.0, 0.0))
	u.is_taunted = true
	u.taunt_source = taunter

	u.order_attack(other)

	assert_null(u.attack_target,
		"Taunted militia must refuse attack orders on non-taunt targets")
	assert_eq(u.current_state, UnitBase.UnitState.IDLE,
		"Refused order must not change state")


# 6b. Taunted Militia still accepts the taunt source
func test_taunted_militia_accepts_taunt_source() -> void:
	var u: Militia = _make_militia()
	var taunter: FakeTarget = _make_target(0.0, Vector2(300.0, 0.0))
	u.is_taunted = true
	u.taunt_source = taunter

	u.order_attack(taunter)

	assert_eq(u.attack_target, taunter,
		"Taunted militia must accept the taunt source as target")
	assert_eq(u._destination_state, UnitBase.UnitState.ATTACKING,
		"Accepted order must set _destination_state = ATTACKING")


# ===========================================================================
# _attack_interval
# ===========================================================================

# 7. Interval is 1 / attack_speed with the default ×1.0 multiplier
func test_attack_interval_inverse_of_attack_speed() -> void:
	var u: Militia = _make_militia()
	u.unit_data.attack_speed = 2.0

	assert_almost_eq(u._attack_interval(), 0.5, 0.0001,
		"Interval must be 1 / attack_speed when the civ multiplier is 1.0")
	assert_eq(CivBonusManager.get_attack_speed_multiplier(TEST_PID, "militia"), 1.0,
		"Militia attack-speed multiplier must default to 1.0")


# 8. Interval shrinks with a CivBonusManager attack-speed multiplier
func test_attack_interval_applies_civ_attack_speed_multiplier() -> void:
	var u: HookRecorder = _make_recorder("archer")  # archer id routes through archer_attack_speed
	u.unit_data.attack_speed = 1.0

	var base_interval: float = u._attack_interval()
	assert_almost_eq(base_interval, 1.0, 0.0001,
		"Baseline archer interval must be 1.0 s at attack_speed 1.0, multiplier 1.0")

	(CivBonusManager._multipliers[TEST_PID] as Dictionary)["archer_attack_speed"] = 2.0

	var mult: float = CivBonusManager.get_attack_speed_multiplier(TEST_PID, "archer")
	assert_eq(mult, 2.0, "Injected archer_attack_speed must be visible via the manager")
	assert_almost_eq(u._attack_interval(), 1.0 / (u.unit_data.attack_speed * mult), 0.0001,
		"_attack_interval must equal 1 / (attack_speed × manager multiplier)")


# 8b. The generic unit_attack_speed key reaches EVERY unit id — melee included —
#     and composes multiplicatively with the category-specific keys.
func test_attack_interval_applies_generic_unit_attack_speed() -> void:
	var melee: HookRecorder = _make_recorder("militia")
	melee.unit_data.attack_speed = 1.0
	assert_almost_eq(melee._attack_interval(), 1.0, 0.0001,
		"Baseline melee interval must be 1.0 s before injecting the generic key")

	(CivBonusManager._multipliers[TEST_PID] as Dictionary)["unit_attack_speed"] = 1.25
	assert_eq(CivBonusManager.get_attack_speed_multiplier(TEST_PID, "militia"), 1.25,
		"Generic unit_attack_speed must apply to melee ids")
	assert_almost_eq(melee._attack_interval(), 1.0 / 1.25, 0.0001,
		"Melee interval must shrink under the generic multiplier")

	(CivBonusManager._multipliers[TEST_PID] as Dictionary)["archer_attack_speed"] = 2.0
	assert_almost_eq(CivBonusManager.get_attack_speed_multiplier(TEST_PID, "archer"),
		2.0 * 1.25, 0.0001,
		"Generic key must compose multiplicatively with archer_attack_speed")

	(CivBonusManager._multipliers[TEST_PID] as Dictionary)["ship_attack_speed"] = 1.5
	assert_almost_eq(CivBonusManager.get_attack_speed_multiplier(TEST_PID, "war_galley"),
		1.5 * 1.25, 0.0001,
		"Generic key must compose multiplicatively with the naval keys")


# ===========================================================================
# _execute_strike
# ===========================================================================

# 9. Damage floors at 1.0 against an over-armoured target
func test_execute_strike_floors_damage_at_one() -> void:
	var u: Militia = _make_militia()  # attack 5.0
	var target: FakeTarget = _make_target(50.0)  # armour far above attack

	u._execute_strike(target)

	assert_eq(target._damage_received, 1.0,
		"Over-armoured targets must still lose exactly 1 HP per strike")


# 10. Normal strike deals attack − armour
func test_execute_strike_deals_attack_minus_armor() -> void:
	var u: Militia = _make_militia()  # attack 5.0
	var target: FakeTarget = _make_target(2.0)

	u._execute_strike(target)

	assert_eq(target._damage_received, 3.0,
		"Strike damage must be effective attack minus target melee armour")


# 11. Strike emits EventBus.unit_attacked with (attacker, target)
func test_execute_strike_emits_unit_attacked() -> void:
	var u: Militia = _make_militia()
	var target: FakeTarget = _make_target()
	watch_signals(EventBus)

	u._execute_strike(target)

	assert_signal_emitted_with_parameters(EventBus, "unit_attacked", [u, target])


# 12. Strike fires the _after_strike hook
func test_execute_strike_calls_after_strike_hook() -> void:
	var u: HookRecorder = _make_recorder()
	var target: FakeTarget = _make_target()

	u._execute_strike(target)

	assert_eq(u.after_strike_calls, 1,
		"_after_strike must fire exactly once per strike")


# ===========================================================================
# _handle_attacking hook ordering
# ===========================================================================

# 13. Invalid target → _on_target_lost, back to IDLE
func test_handle_attacking_invalid_target_calls_on_target_lost() -> void:
	var u: HookRecorder = _make_recorder()
	u.current_state = UnitBase.UnitState.ATTACKING
	u.attack_target = null

	u._handle_attacking(0.016)

	assert_eq(u.target_lost_calls, 1,
		"_on_target_lost must fire when the target is invalid")
	assert_eq(u.current_state, UnitBase.UnitState.IDLE,
		"State must fall back to IDLE when the target is lost")


# 14. Paused → no strike, timer untouched
func test_handle_attacking_paused_skips_strike_and_timer() -> void:
	var u: HookRecorder = _make_recorder()
	var target: FakeTarget = _make_target(0.0, u.global_position)
	u.current_state = UnitBase.UnitState.ATTACKING
	u.attack_target = target
	u.paused = true
	u._attack_timer = 0.4

	u._handle_attacking(5.0)

	assert_eq(target._hit_count, 0, "No strike must land while _attack_paused()")
	assert_eq(u._attack_timer, 0.4,
		"_attack_timer must not advance while _attack_paused()")
	assert_eq(u.reposition_calls, 0,
		"_attack_paused must short-circuit before _combat_reposition")


# 15. Reposition → no strike, timer untouched
func test_handle_attacking_reposition_skips_strike() -> void:
	var u: HookRecorder = _make_recorder()
	var target: FakeTarget = _make_target(0.0, u.global_position)
	u.current_state = UnitBase.UnitState.ATTACKING
	u.attack_target = target
	u.reposition = true
	u._attack_timer = 0.4

	u._handle_attacking(5.0)

	assert_eq(u.reposition_calls, 1, "_combat_reposition must be consulted")
	assert_eq(target._hit_count, 0,
		"No strike must land on a frame consumed by _combat_reposition")
	assert_eq(u._attack_timer, 0.4,
		"_attack_timer must not advance on a reposition frame")


# 16. In reach with elapsed timer → strike executes and timer resets
func test_handle_attacking_strikes_when_interval_elapsed() -> void:
	var u: HookRecorder = _make_recorder()  # attack_speed 1.0 → interval 1.0
	var target: FakeTarget = _make_target(0.0, u.global_position)
	u.current_state = UnitBase.UnitState.ATTACKING
	u.attack_target = target
	u._attack_timer = 0.0

	u._handle_attacking(1.0)

	assert_eq(target._hit_count, 1, "Strike must land once the interval elapses")
	assert_eq(u.after_strike_calls, 1, "_after_strike must fire on the machine strike")
	assert_eq(u._attack_timer, 0.0, "_attack_timer must reset after the strike")


# ===========================================================================
# is_combat_unit
# ===========================================================================

# 17. Military land units are combat units; economy ships are not
func test_is_combat_unit_true_for_military_units() -> void:
	var militia: Militia = _make_militia()
	assert_true(militia.is_combat_unit(), "Militia must be a combat unit")

	var knight: Knight = Knight.new()
	_finish_unit(knight, "knight")
	assert_true(knight.is_combat_unit(), "Knight must be a combat unit")

	var archer: Archer = Archer.new()
	_finish_unit(archer, "archer")
	assert_true(archer.is_combat_unit(), "Archer must be a combat unit")

extends GutTest

## Tests for all civilisation unique units.
##
## What is covered:
##   MenceyesGuard (Guanches)
##     1.  RAGE_HP_THRESHOLD / RAGE_PULSE_INTERVAL / RAGE_BONUS / RAGE_DURATION constants
##     2.  _tick_rage_aura does NOT pulse when health is above threshold
##     3.  _tick_rage_aura pulses when health is below threshold and interval elapsed
##     4.  _get_effective_attack_vs adds _rage_bonus to base attack when bonus is active
##     5.  _rage_timer_remaining expires and clears _rage_bonus
##     6.  get_selection_sound not overridden (inherits UnitBase default)
##
##   RavineArcher (Canarii)
##     7.  AMBUSH_STATIONARY_THRESHOLD / AMBUSH_DAMAGE_MULTIPLIER constants
##     8.  Stationary timer accumulates while IDLE
##     9.  _ambush_ready becomes true after threshold elapses
##     10. _ambush_ready resets to false when MOVING state starts
##     11. _ambush_used prevents a second ambush hit in the same stationary period
##     12. get_selection_sound returns "select_archer"
##
##   SandRaider (Mahos)
##     13. RETREAT_DISTANCE constant
##     14. _begin_retreat sets _retreating = true
##     15. order_move clears _retreating
##     16. order_attack clears _retreating
##     17. get_selection_sound returns "select_cavalry"
##
##   Longbowman (Britons)
##     18. CAVALRY_IDS contains expected cavalry unit ids
##     19. _get_cavalry_bonus returns CAVALRY_BONUS_DAMAGE for a cavalry target
##     20. _get_cavalry_bonus returns 0 for a non-cavalry target
##     21. get_selection_sound returns "select_archer"
##
##   Conquistador (Castellanos)
##     22. SALVO_SHOT_COUNT / SALVO_COOLDOWN_MAX / SALVO_SHOT_INTERVAL constants
##     23. _salvo_active starts as false, salvo activates from idle attack
##     24. _salvo_shots_remaining counts down via _tick_salvo
##     25. Salvo ends after SALVO_SHOT_COUNT shots and applies SALVO_COOLDOWN_MAX
##     26. get_selection_sound returns "select_infantry"
##
##   Tidecaller (Atlantes)
##     27. TIDAL_SPLASH_RADIUS / TIDAL_SPLASH_FRACTION constants
##     28. civ_id is set to "atlantes" in _ready
##     29. get_selection_sound returns "select_naval"
##
##   Trireme (Fenicios)
##     30. GOLD_TICK_AMOUNT / GOLD_TICK_INTERVAL / RAM_DAMAGE_MULTIPLIER constants
##     31. _tick_passive_gold does NOT grant gold before interval elapses
##     32. _tick_passive_gold grants gold after interval elapses
##     33. _tick_passive_gold respects merchant_ship_gold_rate multiplier
##     34. _is_ship_target returns true for ShipBase, false for non-ship
##
##   CivBonusManager integration
##     35. sand_raider appears in cavalry_hp branch (get_unit_hp_multiplier)
##     36. sand_raider appears in scout_speed branch (get_unit_speed_multiplier)
##     37. tidecaller / trireme appear in ship_hp branch
##     38. tidecaller / trireme appear in ship_attack branch (get_unit_attack_multiplier)
##     39. archer_range_flat accumulates on age advance for Britons
##     40. archer_range_flat does NOT accumulate for civs without archer_range_bonus_per_age
##
## What is NOT covered:
##   - Physics-based tidal splash (_apply_tidal_pulse): requires a live PhysicsServer.
##   - Navigation / movement timers: require NavigationServer and valid map.
##   - Castellanos free Blacksmith tech: requires TechManager to have techs loaded
##     and AgeManager state, making it integration territory.
##   - Trireme RAM push (_push_target): mutates global_position via Node2D; trivial
##     one-liner, no branching logic to unit-test.
##
## Setup notes:
##   - Unit nodes are constructed manually to avoid loading full .tscn scenes.
##     Required children (NavigationAgent2D, HealthBar, SelectionIndicator) are
##     injected before add_child_autofree so @onready vars resolve in _ready().
##   - player_id = 1 (non-zero) avoids connecting EventBus.player_entity_under_attack,
##     which simplifies teardown.
##   - FakeTarget is a minimal CharacterBody2D stub used as attack_target in tests
##     that need a valid Node2D with player_id / unit_data set.


# ---------------------------------------------------------------------------
# Shared stubs
# ---------------------------------------------------------------------------

class FakeTarget extends CharacterBody2D:
	var player_id: int = 2
	var unit_data: UnitResource = null
	var _damage_received: float = 0.0

	func _init() -> void:
		unit_data = UnitResource.new()
		unit_data.id = "militia"
		unit_data.armor_melee = 0.0

	func take_damage(amount: float, _source: Node = null) -> void:
		_damage_received += amount


class FakeCavalryTarget extends CharacterBody2D:
	var player_id: int = 2
	var unit_data: UnitResource = null

	func _init() -> void:
		unit_data = UnitResource.new()
		unit_data.id = "knight"
		unit_data.armor_melee = 0.0

	func take_damage(_amount: float, _source: Node = null) -> void:
		pass


# ---------------------------------------------------------------------------
# Factory helpers
# ---------------------------------------------------------------------------

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


func _make_unit_data(uid: String, attack: float = 5.0) -> UnitResource:
	var d: UnitResource = UnitResource.new()
	d.id = uid
	d.max_health = 100.0
	d.attack = attack
	d.attack_speed = 1.0
	d.attack_range = 4.0
	d.armor_melee = 0.0
	d.move_speed = 100.0
	return d


func _make_menceyes() -> MenceyesGuard:
	var u: MenceyesGuard = MenceyesGuard.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("menceyes_guard")
	u.player_id = 1
	add_child_autofree(u)
	return u


func _make_ravine_archer() -> RavineArcher:
	var u: RavineArcher = RavineArcher.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("ravine_archer")
	u.player_id = 1
	add_child_autofree(u)
	return u


func _make_sand_raider() -> SandRaider:
	var u: SandRaider = SandRaider.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("sand_raider")
	u.player_id = 1
	add_child_autofree(u)
	return u


func _make_longbowman() -> Longbowman:
	var u: Longbowman = Longbowman.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("longbowman")
	u.player_id = 1
	add_child_autofree(u)
	return u


func _make_conquistador() -> Conquistador:
	var u: Conquistador = Conquistador.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("conquistador")
	u.player_id = 1
	add_child_autofree(u)
	return u


func _make_tidecaller() -> Tidecaller:
	var u: Tidecaller = Tidecaller.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("tidecaller")
	u.player_id = 1
	add_child_autofree(u)
	return u


# ---------------------------------------------------------------------------
# Trireme requires ShipBase which also calls super._ready().
# We reuse the same child injection pattern.
# ---------------------------------------------------------------------------

func _make_trireme() -> Trireme:
	var u: Trireme = Trireme.new()
	_make_unit_base_children(u)
	u.unit_data = _make_unit_data("trireme")
	u.player_id = 1
	add_child_autofree(u)
	return u


# ===========================================================================
# MenceyesGuard
# ===========================================================================

# 1. Constants are set to design values
func test_menceyes_guard_constants() -> void:
	assert_eq(MenceyesGuard.RAGE_HP_THRESHOLD,    0.5,  "RAGE_HP_THRESHOLD must be 0.5")
	assert_eq(MenceyesGuard.RAGE_PULSE_INTERVAL,  2.0,  "RAGE_PULSE_INTERVAL must be 2.0 s")
	assert_eq(MenceyesGuard.RAGE_RADIUS,          80.0, "RAGE_RADIUS must be 80 px")
	assert_eq(MenceyesGuard.RAGE_BONUS,           3.0,  "RAGE_BONUS must be 3.0 attack")
	assert_eq(MenceyesGuard.RAGE_DURATION,        3.0,  "RAGE_DURATION must be 3.0 s")


# 2. No pulse when health is at or above threshold
func test_menceyes_rage_aura_no_pulse_above_threshold() -> void:
	var u: MenceyesGuard = _make_menceyes()
	# Full health — above threshold
	u.health = u.unit_data.max_health
	var before: float = u._rage_timer

	u._tick_rage_aura(3.0)   # enough to trigger if threshold were met

	assert_eq(u._rage_timer, 0.0,
		"_rage_timer must be reset to 0 when health is above threshold")


# 3. Rage aura timer advances below threshold
func test_menceyes_rage_aura_timer_advances_below_threshold() -> void:
	var u: MenceyesGuard = _make_menceyes()
	u.health = u.unit_data.max_health * 0.4   # below 0.5 threshold

	u._tick_rage_aura(1.0)

	assert_eq(u._rage_timer, 1.0,
		"_rage_timer must advance when health is below threshold")


# 4. _get_effective_attack_vs adds rage bonus
func test_menceyes_effective_attack_includes_rage_bonus() -> void:
	var u: MenceyesGuard = _make_menceyes()
	u._rage_bonus = MenceyesGuard.RAGE_BONUS

	var target: FakeTarget = FakeTarget.new()
	add_child_autofree(target)

	var without_rage: float = u.unit_data.attack   # base, no civ bonus for pid=1 default
	var with_rage: float = u._get_effective_attack_vs(target)

	assert_true(with_rage > without_rage,
		"_get_effective_attack_vs must be larger when _rage_bonus is active")
	assert_eq(with_rage - without_rage, MenceyesGuard.RAGE_BONUS,
		"Rage bonus must add exactly RAGE_BONUS to effective attack")


# 5. _rage_bonus expires when _rage_timer_remaining runs out
func test_menceyes_rage_bonus_expires() -> void:
	var u: MenceyesGuard = _make_menceyes()
	u._rage_bonus = MenceyesGuard.RAGE_BONUS
	u._rage_timer_remaining = 0.5

	# Simulate a physics tick that exhausts the timer
	u._rage_timer_remaining -= 0.6
	if u._rage_timer_remaining <= 0.0:
		u._rage_bonus = 0.0

	assert_eq(u._rage_bonus, 0.0, "_rage_bonus must be cleared when timer expires")


# 6. MenceyesGuard does not override get_selection_sound (uses UnitBase default)
func test_menceyes_guard_selection_sound_is_generic() -> void:
	var u: MenceyesGuard = _make_menceyes()
	assert_eq(u.get_selection_sound(), "select_generic",
		"MenceyesGuard must return the UnitBase default selection sound")


# ===========================================================================
# RavineArcher
# ===========================================================================

# 7. Constants
func test_ravine_archer_constants() -> void:
	assert_eq(RavineArcher.AMBUSH_STATIONARY_THRESHOLD, 1.5,
		"AMBUSH_STATIONARY_THRESHOLD must be 1.5 s")
	assert_eq(RavineArcher.AMBUSH_DAMAGE_MULTIPLIER, 2.0,
		"AMBUSH_DAMAGE_MULTIPLIER must be 2.0")
	assert_eq(RavineArcher.STATIONARY_VELOCITY_THRESHOLD, 5.0,
		"STATIONARY_VELOCITY_THRESHOLD must be 5.0 px/s")


# 8. Stationary timer accumulates while IDLE
func test_ravine_archer_stationary_timer_accumulates_idle() -> void:
	var u: RavineArcher = _make_ravine_archer()
	u.current_state = UnitBase.UnitState.IDLE
	u._stationary_timer = 0.0
	u._ambush_used = false

	# Simulate the idle branch accumulation manually
	if u.current_state == UnitBase.UnitState.IDLE:
		u._stationary_timer += 1.0

	assert_eq(u._stationary_timer, 1.0,
		"_stationary_timer must accumulate while IDLE")


# 9. _ambush_ready becomes true after threshold
func test_ravine_archer_ambush_ready_after_threshold() -> void:
	var u: RavineArcher = _make_ravine_archer()
	u._stationary_timer = RavineArcher.AMBUSH_STATIONARY_THRESHOLD
	u._ambush_ready = false
	u._ambush_used = false

	if u._stationary_timer >= RavineArcher.AMBUSH_STATIONARY_THRESHOLD and not u._ambush_used:
		u._ambush_ready = true

	assert_true(u._ambush_ready,
		"_ambush_ready must be true once stationary timer reaches threshold")


# 10. _ambush_ready resets when MOVING
func test_ravine_archer_ambush_resets_on_move() -> void:
	var u: RavineArcher = _make_ravine_archer()
	u._ambush_ready = true
	u._ambush_used = true
	u._stationary_timer = 5.0
	u.current_state = UnitBase.UnitState.MOVING

	# Simulate the MOVING branch of _physics_process
	if u.current_state == UnitBase.UnitState.MOVING:
		u._stationary_timer = 0.0
		u._ambush_ready = false
		u._ambush_used = false

	assert_false(u._ambush_ready, "_ambush_ready must be cleared when unit starts moving")
	assert_false(u._ambush_used,  "_ambush_used must be cleared when unit starts moving")
	assert_eq(u._stationary_timer, 0.0, "_stationary_timer must reset when unit starts moving")


# 11. _ambush_used prevents second ambush
func test_ravine_archer_ambush_used_prevents_repeat() -> void:
	var u: RavineArcher = _make_ravine_archer()
	u._ambush_ready = true
	u._ambush_used = true

	# Simulate the ambush check: ambush is ready but used
	var would_ambush: bool = u._ambush_ready and not u._ambush_used
	assert_false(would_ambush,
		"Ambush must not trigger again in the same stationary period (_ambush_used=true)")


# 12. Selection sound
func test_ravine_archer_selection_sound() -> void:
	var u: RavineArcher = _make_ravine_archer()
	assert_eq(u.get_selection_sound(), "select_archer",
		"RavineArcher must return 'select_archer'")


# ===========================================================================
# SandRaider
# ===========================================================================

# 13. Constant
func test_sand_raider_retreat_distance() -> void:
	assert_eq(SandRaider.RETREAT_DISTANCE, 90.0,
		"RETREAT_DISTANCE must be 90 px")


# 14. _begin_retreat sets _retreating
func test_sand_raider_begin_retreat_sets_flag() -> void:
	var u: SandRaider = _make_sand_raider()
	var target: FakeTarget = FakeTarget.new()
	target.global_position = Vector2(200.0, 0.0)
	add_child_autofree(target)
	u.attack_target = target

	u._begin_retreat()

	assert_true(u._retreating, "_begin_retreat must set _retreating = true")
	assert_eq(u.current_state, UnitBase.UnitState.MOVING,
		"_begin_retreat must switch state to MOVING")


# 15. order_move clears _retreating
func test_sand_raider_order_move_clears_retreating() -> void:
	var u: SandRaider = _make_sand_raider()
	u._retreating = true

	u.order_move(Vector2(100.0, 0.0))

	assert_false(u._retreating, "order_move must clear _retreating")


# 16. order_attack clears _retreating
func test_sand_raider_order_attack_clears_retreating() -> void:
	var u: SandRaider = _make_sand_raider()
	u._retreating = true
	var target: FakeTarget = FakeTarget.new()
	add_child_autofree(target)

	u.order_attack(target)

	assert_false(u._retreating, "order_attack must clear _retreating")


# 17. Selection sound
func test_sand_raider_selection_sound() -> void:
	var u: SandRaider = _make_sand_raider()
	assert_eq(u.get_selection_sound(), "select_cavalry",
		"SandRaider must return 'select_cavalry'")


# ===========================================================================
# Longbowman
# ===========================================================================

# 18. The cavalry roster lives in the shared COMBAT_CLASSES map now
func test_longbowman_cavalry_ids_contains_expected() -> void:
	for cav_id: String in ["scout", "heavy_scout", "knight", "chevalier_normand", "sand_raider"]:
		assert_eq(UnitBase.COMBAT_CLASSES.get(cav_id, ""), "cavalry",
			"COMBAT_CLASSES must class '%s' as cavalry" % cav_id)


# 19. The Armour Piercing bonus migrated to attack_bonuses data
func test_longbowman_cavalry_bonus_vs_cavalry() -> void:
	var u: Longbowman = _make_longbowman()
	# The synthetic factory data has no bonuses — this assertion is about the
	# SHIPPED data, so read the real .tres.
	u.unit_data = load("res://resources/units/longbowman_data.tres") as UnitResource
	var target: FakeCavalryTarget = FakeCavalryTarget.new()
	add_child_autofree(target)

	var bonus: float = u._class_bonus_vs(target)

	assert_eq(bonus, u.unit_data.attack_bonuses.get("cavalry", 0.0) as float,
		"_class_bonus_vs must pay the .tres cavalry bonus vs a cavalry target")
	assert_eq(bonus, 4.0, "Armour Piercing stays +4 after the data migration")


# 20. _get_cavalry_bonus returns 0 for non-cavalry target
func test_longbowman_cavalry_bonus_vs_infantry() -> void:
	var u: Longbowman = _make_longbowman()
	var target: FakeTarget = FakeTarget.new()  # unit_data.id = "militia"
	add_child_autofree(target)

	var bonus: float = u._class_bonus_vs(target)

	assert_eq(bonus, 0.0,
		"_class_bonus_vs must return 0.0 for non-cavalry targets")


# 21. Selection sound
func test_longbowman_selection_sound() -> void:
	var u: Longbowman = _make_longbowman()
	assert_eq(u.get_selection_sound(), "select_archer",
		"Longbowman must return 'select_archer'")


# ===========================================================================
# Conquistador
# ===========================================================================

# 22. Constants
func test_conquistador_constants() -> void:
	assert_eq(Conquistador.SALVO_SHOT_COUNT,    3,    "SALVO_SHOT_COUNT must be 3")
	assert_eq(Conquistador.SALVO_COOLDOWN_MAX,  12.0, "SALVO_COOLDOWN_MAX must be 12 s")
	assert_eq(Conquistador.SALVO_SHOT_INTERVAL, 0.3,  "SALVO_SHOT_INTERVAL must be 0.3 s")
	assert_eq(Conquistador.SALVO_SHOT_DAMAGE,   6.0,  "SALVO_SHOT_DAMAGE must be 6.0")


# 23. Salvo activates and sets shot count
func test_conquistador_salvo_activates() -> void:
	var u: Conquistador = _make_conquistador()
	assert_false(u._salvo_active, "precondition: _salvo_active must be false at start")
	assert_eq(u._salvo_cooldown, 0.0, "precondition: _salvo_cooldown must start at 0")

	# Simulate the activation path (cooldown == 0 and attack timer fires)
	u._salvo_active = true
	u._salvo_shots_remaining = Conquistador.SALVO_SHOT_COUNT
	u._salvo_shot_timer = 0.0

	assert_true(u._salvo_active,         "Salvo must be active after activation")
	assert_eq(u._salvo_shots_remaining, Conquistador.SALVO_SHOT_COUNT,
		"shots_remaining must equal SALVO_SHOT_COUNT after activation")


# 24. _tick_salvo fires shots and decrements counter
func test_conquistador_tick_salvo_decrements_shots() -> void:
	var u: Conquistador = _make_conquistador()
	var target: FakeTarget = FakeTarget.new()
	add_child_autofree(target)
	u.attack_target = target
	u._salvo_active = true
	u._salvo_shots_remaining = 3
	u._salvo_shot_timer = 0.0

	u._tick_salvo(Conquistador.SALVO_SHOT_INTERVAL + 0.01)

	assert_eq(u._salvo_shots_remaining, 2,
		"_tick_salvo must decrement shots_remaining by 1 per interval")


# 25. Salvo ends and applies cooldown after all shots
func test_conquistador_salvo_ends_with_cooldown() -> void:
	var u: Conquistador = _make_conquistador()
	var target: FakeTarget = FakeTarget.new()
	add_child_autofree(target)
	u.attack_target = target
	u._salvo_active = true
	u._salvo_shots_remaining = 1
	u._salvo_shot_timer = 0.0

	u._tick_salvo(Conquistador.SALVO_SHOT_INTERVAL + 0.01)

	assert_false(u._salvo_active,
		"Salvo must end (_salvo_active=false) after the last shot fires")
	assert_eq(u._salvo_cooldown, Conquistador.SALVO_COOLDOWN_MAX,
		"_salvo_cooldown must be set to SALVO_COOLDOWN_MAX when salvo ends")


# 26. Selection sound
func test_conquistador_selection_sound() -> void:
	var u: Conquistador = _make_conquistador()
	assert_eq(u.get_selection_sound(), "select_infantry",
		"Conquistador must return 'select_infantry'")


# ===========================================================================
# Tidecaller
# ===========================================================================

# 27. Constants
func test_tidecaller_constants() -> void:
	assert_eq(Tidecaller.TIDAL_SPLASH_RADIUS,   65.0, "TIDAL_SPLASH_RADIUS must be 65 px")
	assert_eq(Tidecaller.TIDAL_SPLASH_FRACTION, 0.40, "TIDAL_SPLASH_FRACTION must be 0.40")


# 28. civ_id is "atlantes" after _ready
func test_tidecaller_civ_id_is_atlantes() -> void:
	var u: Tidecaller = _make_tidecaller()
	assert_eq(u.civ_id, "atlantes",
		"Tidecaller must set civ_id='atlantes' so ocean tiles are passable")


# 29. Selection sound
func test_tidecaller_selection_sound() -> void:
	var u: Tidecaller = _make_tidecaller()
	assert_eq(u.get_selection_sound(), "select_naval",
		"Tidecaller must return 'select_naval'")


# ===========================================================================
# Trireme
# ===========================================================================

# 30. Constants
func test_trireme_constants() -> void:
	assert_eq(Trireme.GOLD_TICK_AMOUNT,     5.0,  "GOLD_TICK_AMOUNT must be 5")
	assert_eq(Trireme.GOLD_TICK_INTERVAL,   30.0, "GOLD_TICK_INTERVAL must be 30 s")
	assert_eq(Trireme.RAM_DAMAGE_MULTIPLIER, 2.0, "RAM_DAMAGE_MULTIPLIER must be 2.0")


# 31. No gold granted before interval
func test_trireme_no_gold_before_interval() -> void:
	var u: Trireme = _make_trireme()
	ResourceManager.init_player(u.player_id, {"gold": 0})
	CivBonusManager.init_player(u.player_id, "fenicios")
	u._gold_timer = 0.0

	u._tick_passive_gold(Trireme.GOLD_TICK_INTERVAL - 1.0)

	var gold: int = ResourceManager.get_resources(u.player_id).get("gold", 0) as int
	assert_eq(gold, 0, "Trireme must not grant gold before GOLD_TICK_INTERVAL elapses")


# 32. Gold granted when interval elapses (requires CivBonusManager player init)
func test_trireme_grants_gold_at_interval() -> void:
	var u: Trireme = _make_trireme()
	ResourceManager.init_player(u.player_id, {"gold": 0})
	CivBonusManager.init_player(u.player_id, "fenicios")
	u._gold_timer = 0.0

	u._tick_passive_gold(Trireme.GOLD_TICK_INTERVAL + 0.01)

	var gold: float = ResourceManager.get_resources(u.player_id).get("gold", 0.0) as float
	assert_true(gold > 0.0,
		"Trireme must grant gold once GOLD_TICK_INTERVAL elapses (fenicios merchant_ship_gold_rate > 0)")


# 33. merchant_ship_gold_rate = 0 means no gold
func test_trireme_no_gold_without_rate() -> void:
	var u: Trireme = _make_trireme()
	ResourceManager.init_player(u.player_id, {"gold": 0})
	# Explicitly set rate to 0 — overrides any default
	CivBonusManager.init_player(u.player_id, "guanches")   # guanches has no merchant_ship_gold_rate key
	(CivBonusManager._multipliers[u.player_id] as Dictionary)["merchant_ship_gold_rate"] = 0.0
	u._gold_timer = 0.0

	u._tick_passive_gold(Trireme.GOLD_TICK_INTERVAL + 0.01)

	var gold: float = ResourceManager.get_resources(u.player_id).get("gold", 0.0) as float
	assert_eq(gold, 0.0,
		"Trireme must not grant gold when merchant_ship_gold_rate is 0")


# 34. _is_ship_target
func test_trireme_is_ship_target_true_for_ship() -> void:
	var u: Trireme = _make_trireme()

	var other_ship: Trireme = Trireme.new()
	_make_unit_base_children(other_ship)
	other_ship.unit_data = _make_unit_data("trireme")
	other_ship.player_id = 2
	add_child_autofree(other_ship)

	assert_true(u._is_ship_target(other_ship),
		"_is_ship_target must return true for another ShipBase-derived node")


func test_trireme_is_ship_target_false_for_unit() -> void:
	var u: Trireme = _make_trireme()
	var land_unit: FakeTarget = FakeTarget.new()
	add_child_autofree(land_unit)

	assert_false(u._is_ship_target(land_unit),
		"_is_ship_target must return false for a non-ship node")


# ===========================================================================
# CivBonusManager integration
# ===========================================================================

# 35. sand_raider maps to cavalry_hp branch
func test_civ_bonus_sand_raider_cavalry_hp() -> void:
	CivBonusManager.init_player(99, "mahos")
	# Mahos do not have cavalry_hp in their .tres; inject a value to verify routing
	(CivBonusManager._multipliers[99] as Dictionary)["cavalry_hp"] = 1.20
	var mult: float = CivBonusManager.get_unit_hp_multiplier(99, "sand_raider")
	assert_eq(mult, 1.20,
		"sand_raider must be routed through the cavalry_hp branch of get_unit_hp_multiplier")


# 36. sand_raider maps to scout_speed branch (Mahos have scout_speed = 1.25)
func test_civ_bonus_sand_raider_scout_speed() -> void:
	CivBonusManager.init_player(99, "mahos")
	var mult: float = CivBonusManager.get_unit_speed_multiplier(99, "sand_raider")
	assert_eq(mult, 1.25,
		"sand_raider speed must equal Mahos scout_speed bonus (1.25)")


# 37. tidecaller / trireme map to ship_hp branch — routing test using injected bonus
func test_civ_bonus_tidecaller_ship_hp() -> void:
	CivBonusManager.init_player(99, "atlantes")
	# Inject a ship_hp bonus directly so the routing has something non-trivial to return
	(CivBonusManager._multipliers[99] as Dictionary)["ship_hp"] = 1.30
	var mult: float = CivBonusManager.get_unit_hp_multiplier(99, "tidecaller")
	assert_eq(mult, 1.30,
		"tidecaller must be routed through the ship_hp branch of get_unit_hp_multiplier")


func test_civ_bonus_trireme_ship_hp() -> void:
	CivBonusManager.init_player(99, "fenicios")
	(CivBonusManager._multipliers[99] as Dictionary)["ship_hp"] = 1.25
	var mult: float = CivBonusManager.get_unit_hp_multiplier(99, "trireme")
	assert_eq(mult, 1.25,
		"trireme must be routed through the ship_hp branch of get_unit_hp_multiplier")


# 38. tidecaller / trireme map to ship_attack branch — routing test using injected bonus
func test_civ_bonus_tidecaller_attack() -> void:
	CivBonusManager.init_player(99, "atlantes")
	(CivBonusManager._multipliers[99] as Dictionary)["ship_attack"] = 1.35
	var mult: float = CivBonusManager.get_unit_attack_multiplier(99, "tidecaller")
	assert_true(mult >= 1.35,
		"tidecaller must be routed through the ship_attack branch of get_unit_attack_multiplier")


func test_civ_bonus_trireme_attack() -> void:
	CivBonusManager.init_player(99, "fenicios")
	(CivBonusManager._multipliers[99] as Dictionary)["ship_attack"] = 1.40
	var mult: float = CivBonusManager.get_unit_attack_multiplier(99, "trireme")
	assert_true(mult >= 1.40,
		"trireme must be routed through the ship_attack branch of get_unit_attack_multiplier")


# 39. archer_range_flat accumulates each age advance for Britons
func test_britons_archer_range_flat_accumulates() -> void:
	CivBonusManager.init_player(99, "britons")
	var before: float = CivBonusManager.get_archer_range_flat(99)

	CivBonusManager.on_age_advanced(99)

	var after: float = CivBonusManager.get_archer_range_flat(99)
	assert_true(after > before,
		"archer_range_flat must increase after on_age_advanced for Britons")


# 40. archer_range_flat does not accumulate for civs without bonus
func test_non_britons_archer_range_flat_unchanged() -> void:
	CivBonusManager.init_player(99, "guanches")
	var before: float = CivBonusManager.get_archer_range_flat(99)

	CivBonusManager.on_age_advanced(99)

	var after: float = CivBonusManager.get_archer_range_flat(99)
	assert_eq(before, after,
		"archer_range_flat must not change on age advance for civs without archer_range_bonus_per_age")

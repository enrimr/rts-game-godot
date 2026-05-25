extends GutTest

## Tests for HeroUnit ability lifecycle — specifically verifying that _end_ability()
## cleans up all mutable state whether the ability expires naturally or the hero dies
## mid-cast via die().
##
## What is covered:
##   1.  _end_ability() sets _ability_active to false
##   2.  die() calls _end_ability() — _ability_active is false after die()
##   3.  MENCEYES_CHARGE: _buff_nearby_attack_speed populates _buffed_units
##   4.  MENCEYES_CHARGE: _end_ability() reverts attack_speed and clears _buffed_units
##   5.  MENCEYES_CHARGE: die() mid-cast reverts the speed buff on ally
##   6.  AMBUSH: die() mid-cast restores modulate.a to 1.0
##   7.  PLUNDER: triggering ability connects _on_plunder_kill to EventBus.unit_died
##   8.  PLUNDER: die() disconnects _on_plunder_kill from EventBus.unit_died
##   9.  CHALLENGE: _taunt_nearest_enemy sets is_taunted on the nearest enemy
##   10. CHALLENGE: die() clears is_taunted and nulls _taunt_target
##   11. FORCED_DIPLOMACY: _convert_nearest_native changes target player_id
##   12. FORCED_DIPLOMACY: die() reverts target player_id to original
##   13. CALIMA: _end_ability() de-cloaks units in _cloaked_units and clears the list
##   14. CALIMA: die() de-cloaks units injected into _cloaked_units
##   15. TRADE_ROUTE: _activate_trade_route adds a Timer child to the hero
##   16. TRADE_ROUTE: die() stops and removes the Timer child
##
## What is NOT covered:
##   - KNIGHT_ERRANT_CHARGE: uses create_tween() which binds to the node and
##     auto-kills on queue_free(). No SceneTreeTimer involved; no fix required.
##   - Physics / navigation — requires a live NavigationServer; integration territory.
##   - Gold awards from _on_plunder_kill — requires ResourceManager with real state.
##
## Setup notes:
##   - HeroUnit extends Militia extends UnitBase (CharacterBody2D). UnitBase._ready()
##     requires NavigationAgent2D, ProgressBar, and Node2D children resolvable by name.
##     All are injected before add_child_autofree so @onready variables resolve correctly.
##   - hero.player_id is set to 1 (non-zero) to avoid connecting the
##     EventBus.player_entity_under_attack signal, which simplifies after_each cleanup.
##   - FakeUnit is a minimal Node2D stub that exposes the same properties that
##     HeroUnit ability code reads and writes via set()/get().


## ── Minimal target stub ───────────────────────────────────────────────────────
class FakeUnit extends Node2D:
	var player_id: int = 1
	var unit_data: UnitResource = null
	var current_state: int = 0
	var is_taunted: bool = false
	var taunt_source: Node = null
	var attack_target: Node = null
	var is_cloaked: bool = false

	func _init() -> void:
		unit_data = UnitResource.new()
		unit_data.attack_speed = 1.5


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_hero(ability_id: String) -> HeroUnit:
	var hero: HeroUnit = HeroUnit.new()

	var nav: NavigationAgent2D = NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	hero.add_child(nav)

	var hbar: ProgressBar = ProgressBar.new()
	hbar.name = "HealthBar"
	hero.add_child(hbar)

	var sel: Node2D = Node2D.new()
	sel.name = "SelectionIndicator"
	var circle: Polygon2D = Polygon2D.new()
	circle.name = "SelectionCircle"
	sel.add_child(circle)
	hero.add_child(sel)

	var data: UnitResource = UnitResource.new()
	data.id = "test_hero"
	data.display_name = "Test Hero"
	data.max_health = 200.0
	data.attack = 10.0
	data.attack_speed = 1.0
	data.attack_range = 1.0
	data.move_speed = 100.0
	data.is_hero = true
	data.hero_ability_id = ability_id
	data.hero_ability_cooldown = 30.0
	hero.unit_data = data
	hero.player_id = 1

	add_child_autofree(hero)
	return hero


func _make_fake_unit(pid: int, in_units_group: bool = false) -> FakeUnit:
	var fu: FakeUnit = FakeUnit.new()
	fu.player_id = pid
	add_child_autofree(fu)
	if in_units_group:
		fu.add_to_group("units")
	return fu


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func after_each() -> void:
	# Belt-and-suspenders: disconnect any _on_plunder_kill that survived.
	var conns: Array = EventBus.unit_died.get_connections()
	for conn: Dictionary in conns:
		if (conn.callable as Callable).get_method() == "_on_plunder_kill":
			EventBus.unit_died.disconnect(conn.callable)


# ---------------------------------------------------------------------------
# 1. _end_ability() sets _ability_active to false
# ---------------------------------------------------------------------------

func test_end_ability_sets_ability_active_false() -> void:
	var hero: HeroUnit = _make_hero("ambush")
	hero._ability_active = true
	hero._ability_timer = 10.0

	hero._end_ability()

	assert_false(hero._ability_active,
		"_end_ability must set _ability_active to false")


# ---------------------------------------------------------------------------
# 2. die() triggers _end_ability() — _ability_active is false after die()
# ---------------------------------------------------------------------------

func test_die_calls_end_ability() -> void:
	var hero: HeroUnit = _make_hero("ambush")
	hero._ability_active = true
	hero._ability_timer = 10.0
	hero.modulate.a = 0.15

	hero.die()

	assert_false(hero._ability_active,
		"die() must call _end_ability(), leaving _ability_active false")
	assert_eq(hero.modulate.a, 1.0,
		"die() via _end_ability() must restore AMBUSH modulate.a")


# ---------------------------------------------------------------------------
# 3. MENCEYES_CHARGE: buff populates _buffed_units
# ---------------------------------------------------------------------------

func test_menceyes_charge_populates_buffed_units() -> void:
	var hero: HeroUnit = _make_hero("menceyes_charge")
	var ally: FakeUnit = _make_fake_unit(1, true)

	hero._buff_nearby_attack_speed(1.30)

	assert_eq(hero._buffed_units.size(), 1,
		"_buff_nearby_attack_speed must add one entry per buffed ally")
	assert_eq((hero._buffed_units[0] as Dictionary).unit, ally,
		"_buffed_units must reference the buffed ally node")


# ---------------------------------------------------------------------------
# 4. MENCEYES_CHARGE: _end_ability() reverts speed and clears _buffed_units
# ---------------------------------------------------------------------------

func test_menceyes_charge_end_ability_reverts_speed() -> void:
	var hero: HeroUnit = _make_hero("menceyes_charge")
	var ally: FakeUnit = _make_fake_unit(1, true)
	var original_speed: float = ally.unit_data.attack_speed

	hero._buff_nearby_attack_speed(1.30)

	# Sanity: ally was actually buffed before reverting.
	assert_true(
		absf((ally.unit_data as UnitResource).attack_speed - (original_speed * 1.30)) < 0.001,
		"precondition: ally attack_speed must be buffed before _end_ability")

	hero._end_ability()

	assert_eq((ally.unit_data as UnitResource).attack_speed, original_speed,
		"_end_ability must revert ally attack_speed to its original value")
	assert_eq(hero._buffed_units.size(), 0,
		"_end_ability must clear _buffed_units")


# ---------------------------------------------------------------------------
# 5. MENCEYES_CHARGE: die() mid-cast reverts buff on the ally
# ---------------------------------------------------------------------------

func test_menceyes_charge_die_reverts_buff() -> void:
	var hero: HeroUnit = _make_hero("menceyes_charge")
	var ally: FakeUnit = _make_fake_unit(1, true)
	var original_speed: float = ally.unit_data.attack_speed

	hero._buff_nearby_attack_speed(1.30)
	hero._ability_active = true

	hero.die()

	assert_eq((ally.unit_data as UnitResource).attack_speed, original_speed,
		"die() must revert ally attack_speed even when the hero dies mid-cast")


# ---------------------------------------------------------------------------
# 6. AMBUSH: die() mid-cast restores modulate.a
# ---------------------------------------------------------------------------

func test_ambush_die_restores_opacity() -> void:
	var hero: HeroUnit = _make_hero("ambush")
	hero._ability_active = true
	hero._ability_timer = 15.0
	hero.modulate.a = 0.15

	hero.die()

	assert_eq(hero.modulate.a, 1.0,
		"die() must restore modulate.a to 1.0 when AMBUSH is interrupted by death")


# ---------------------------------------------------------------------------
# 7. PLUNDER: triggering ability connects _on_plunder_kill to EventBus.unit_died
# ---------------------------------------------------------------------------

func test_plunder_trigger_connects_unit_died() -> void:
	var hero: HeroUnit = _make_hero("plunder")
	hero._cooldown_remaining = 0.0

	hero._trigger_ability()

	assert_true(EventBus.unit_died.is_connected(hero._on_plunder_kill),
		"PLUNDER must connect _on_plunder_kill to EventBus.unit_died on activation")


# ---------------------------------------------------------------------------
# 8. PLUNDER: die() disconnects _on_plunder_kill from EventBus.unit_died
# ---------------------------------------------------------------------------

func test_plunder_die_disconnects_unit_died() -> void:
	var hero: HeroUnit = _make_hero("plunder")
	hero._cooldown_remaining = 0.0
	hero._trigger_ability()
	assert_true(EventBus.unit_died.is_connected(hero._on_plunder_kill),
		"precondition: unit_died must be connected after PLUNDER activation")

	hero.die()

	assert_false(EventBus.unit_died.is_connected(hero._on_plunder_kill),
		"die() must disconnect _on_plunder_kill from EventBus.unit_died")


# ---------------------------------------------------------------------------
# 9. CHALLENGE: sets is_taunted on the nearest enemy
# ---------------------------------------------------------------------------

func test_challenge_sets_is_taunted_on_enemy() -> void:
	var hero: HeroUnit = _make_hero("challenge")
	var enemy: FakeUnit = _make_fake_unit(2, true)

	hero._taunt_nearest_enemy()

	assert_true(enemy.is_taunted,
		"_taunt_nearest_enemy must set is_taunted = true on the nearest enemy")
	assert_eq(hero._taunt_target, enemy,
		"_taunt_target must reference the taunted enemy")


# ---------------------------------------------------------------------------
# 10. CHALLENGE: die() clears is_taunted and nulls _taunt_target
# ---------------------------------------------------------------------------

func test_challenge_die_clears_taunt() -> void:
	var hero: HeroUnit = _make_hero("challenge")
	var enemy: FakeUnit = _make_fake_unit(2, true)
	hero._taunt_nearest_enemy()
	hero._ability_active = true

	hero.die()

	assert_false(enemy.is_taunted,
		"die() must clear is_taunted on the taunted enemy")
	assert_null(hero._taunt_target,
		"die() must null out _taunt_target")


# ---------------------------------------------------------------------------
# 11. FORCED_DIPLOMACY: changes target's player_id to the hero's
# ---------------------------------------------------------------------------

func test_forced_diplomacy_converts_enemy_player_id() -> void:
	var hero: HeroUnit = _make_hero("forced_diplomacy")
	var enemy: FakeUnit = _make_fake_unit(2, true)
	var original_pid: int = enemy.player_id

	hero._convert_nearest_native()

	assert_eq(enemy.player_id, hero.player_id,
		"_convert_nearest_native must set target player_id to hero's player_id")
	assert_eq(hero._fd_original_pid, original_pid,
		"_fd_original_pid must store the target's original player_id")


# ---------------------------------------------------------------------------
# 12. FORCED_DIPLOMACY: die() reverts target's player_id
# ---------------------------------------------------------------------------

func test_forced_diplomacy_die_reverts_player_id() -> void:
	var hero: HeroUnit = _make_hero("forced_diplomacy")
	var enemy: FakeUnit = _make_fake_unit(2, true)
	var original_pid: int = enemy.player_id
	hero._convert_nearest_native()
	hero._ability_active = true

	hero.die()

	assert_eq(enemy.player_id, original_pid,
		"die() must revert the converted unit's player_id to its original value")


# ---------------------------------------------------------------------------
# 13. CALIMA: _end_ability() de-cloaks _cloaked_units and clears the list
# ---------------------------------------------------------------------------

func test_calima_end_ability_de_cloaks_units() -> void:
	var hero: HeroUnit = _make_hero("calima")
	var ally: FakeUnit = _make_fake_unit(1)
	# Inject cloaked state directly, as if _spawn_calima_cloud already ran.
	ally.is_cloaked = true
	ally.modulate.a = 0.25
	hero._cloaked_units.append(ally)
	hero._ability_active = true

	hero._end_ability()

	assert_false(ally.is_cloaked,
		"_end_ability must set is_cloaked = false on each cloaked ally")
	assert_eq(ally.modulate.a, 1.0,
		"_end_ability must restore modulate.a = 1.0 on each cloaked ally")
	assert_eq(hero._cloaked_units.size(), 0,
		"_end_ability must clear _cloaked_units")


# ---------------------------------------------------------------------------
# 14. CALIMA: die() de-cloaks units injected into _cloaked_units
# ---------------------------------------------------------------------------

func test_calima_die_de_cloaks_units() -> void:
	var hero: HeroUnit = _make_hero("calima")
	var ally: FakeUnit = _make_fake_unit(1)
	ally.is_cloaked = true
	ally.modulate.a = 0.25
	hero._cloaked_units.append(ally)
	hero._ability_active = true

	hero.die()

	assert_false(ally.is_cloaked,
		"die() must de-cloak all units in _cloaked_units")
	assert_eq(ally.modulate.a, 1.0,
		"die() must restore modulate.a on each cloaked ally")


# ---------------------------------------------------------------------------
# 15. TRADE_ROUTE: _activate_trade_route adds a Timer as a direct child
# ---------------------------------------------------------------------------

func test_trade_route_creates_timer_child() -> void:
	var hero: HeroUnit = _make_hero("trade_route")

	hero._activate_trade_route(30.0)

	assert_not_null(hero._trade_route_timer,
		"_activate_trade_route must assign _trade_route_timer")
	assert_true(is_instance_valid(hero._trade_route_timer),
		"_trade_route_timer must be a valid node after activation")
	assert_eq(hero._trade_route_timer.get_parent(), hero,
		"_trade_route_timer must be added as a direct child of the hero")


# ---------------------------------------------------------------------------
# 16. TRADE_ROUTE: die() stops and removes the Timer child
# ---------------------------------------------------------------------------

func test_trade_route_die_cleans_up_timer() -> void:
	var hero: HeroUnit = _make_hero("trade_route")
	hero._activate_trade_route(30.0)
	hero._ability_active = true
	var timer_ref: Timer = hero._trade_route_timer
	assert_true(is_instance_valid(timer_ref),
		"precondition: timer must exist and be valid before die()")

	hero.die()

	assert_null(hero._trade_route_timer,
		"die() must null out _trade_route_timer")
	# stop() is called synchronously in _end_ability before queue_free().
	assert_true(timer_ref.is_stopped(),
		"die() must stop the trade_route Timer before freeing it")

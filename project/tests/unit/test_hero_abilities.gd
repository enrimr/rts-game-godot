extends GutTest

## Audit of all 16 hero abilities: every cast must succeed, charge a
## cooldown (the instant abilities used to skip it — free spam), emit
## hero_ability_used (the tutorial step listens), and block a second cast.
## Ability-specific effects are asserted where they are cheap to observe.

const HERO_TRES: Dictionary = {
	"menceyes_charge":      "hero_bencomo",
	"challenge":            "hero_doramas",
	"ambush":               "hero_guadarfia",
	"forced_diplomacy":     "hero_bethencourt",
	"plunder":              "hero_drake",
	"knight_errant_charge": "hero_quijote",
	"calima":               "hero_artaxerax",
	"trade_route":          "hero_hanno",
	"mountain_voice":       "hero_dacil",
	"fates_arrow":          "hero_guayarmina",
	"sandstorm":            "hero_tibiabin",
	"honor_duel":           "hero_catalina",
	"boarding_action":      "hero_grace",
	"call_to_arms":         "hero_dulcinea",
	"rising_tide":          "hero_cleito",
	"mercenary_pact":       "hero_elissa",
}

var _ability_signal_pid: int = -1

func before_each() -> void:
	_ability_signal_pid = -1
	EventBus.hero_ability_used.connect(_on_used)
	ResourceManager.init_player(0, {"gold": 1000})
	MatchConfig.player_teams.clear()

func after_each() -> void:
	EventBus.hero_ability_used.disconnect(_on_used)

func _on_used(pid: int) -> void:
	_ability_signal_pid = pid

func _spawn_hero(ability_id: String) -> Node2D:
	var hero: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", load("res://resources/units/%s.tres" % HERO_TRES[ability_id]))
	hero.set("player_id", 0)
	hero.set("civ_id", "guanches")
	add_child_autofree(hero)
	hero.global_position = Vector2(400.0, 400.0)
	return hero

func _spawn_enemy(pos: Vector2, hero_tres: String = "") -> Node2D:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	if not hero_tres.is_empty():
		unit.set_script(load("res://scripts/units/hero_unit.gd"))
		unit.set("unit_data", load("res://resources/units/%s.tres" % hero_tres))
	unit.set("player_id", 1)
	unit.set("civ_id", "franks")
	add_child_autofree(unit)
	unit.global_position = pos
	return unit

func _cast_and_check(ability_id: String, hero: Node2D) -> void:
	assert_true(hero.call("use_ability") as bool, "%s: cast succeeds" % ability_id)
	assert_gt(hero.get("_cooldown_remaining") as float, 0.0,
		"%s: a successful cast charges its cooldown" % ability_id)
	assert_eq(_ability_signal_pid, 0, "%s: hero_ability_used reached the bus" % ability_id)
	assert_false(hero.call("use_ability") as bool, "%s: blocked while cooling down" % ability_id)

func test_every_ability_casts_cools_down_and_signals() -> void:
	for ability_id: String in HERO_TRES:
		_ability_signal_pid = -1
		var hero: Node2D = _spawn_hero(ability_id)
		# Generic context: one enemy in range (duel needs an enemy HERO).
		var enemy: Node2D = _spawn_enemy(Vector2(480.0, 400.0),
			"hero_bethencourt" if ability_id == "honor_duel" else "")
		_cast_and_check(ability_id, hero)
		enemy.queue_free()
		hero.queue_free()

func test_challenge_taunts_the_nearest_enemy() -> void:
	var hero: Node2D = _spawn_hero("challenge")
	var enemy: Node2D = _spawn_enemy(Vector2(470.0, 400.0))
	hero.call("use_ability")
	assert_true(enemy.get("is_taunted") as bool)

func test_ambush_cloaks_the_hero() -> void:
	var hero: Node2D = _spawn_hero("ambush")
	hero.call("use_ability")
	assert_lt(hero.modulate.a, 0.5, "the hero fades while ambushing")

func test_fates_arrow_damages_but_never_allies() -> void:
	var hero: Node2D = _spawn_hero("fates_arrow")
	MatchConfig.player_teams = {0: 1, 1: 1}
	var ally: Node2D = _spawn_enemy(Vector2(460.0, 400.0))
	var hp0: float = ally.get("health") as float
	assert_true(hero.call("use_ability") as bool)
	assert_eq(hero.get("_cooldown_remaining") as float, 0.0,
		"no hostile in range with an allied-only field: the cast fizzles free")
	assert_eq(ally.get("health") as float, hp0, "an ALLY is never sniped")
	MatchConfig.player_teams.clear()
	assert_true(hero.call("use_ability") as bool)
	assert_lt(ally.get("health") as float, hp0, "the same unit takes 80 when hostile")

func test_call_to_arms_summons_three() -> void:
	var hero: Node2D = _spawn_hero("call_to_arms")
	var before: int = get_tree().get_nodes_in_group("units").size()
	hero.call("use_ability")
	await wait_frames(2)
	assert_eq(get_tree().get_nodes_in_group("units").size(), before + 3,
		"three temporary militia joined")

func test_mercenary_pact_converts_and_charges_gold() -> void:
	var hero: Node2D = _spawn_hero("mercenary_pact")
	var enemy: Node2D = _spawn_enemy(Vector2(480.0, 400.0))
	assert_true(hero.call("use_ability") as bool)
	assert_eq(enemy.get("player_id") as int, 0, "the enemy switched sides")
	assert_almost_eq(ResourceManager.get_resources(0).get("gold", 0.0) as float, 600.0, 1.0,
		"400 gold spent")

func test_ambush_sets_the_real_cloak_flag_and_breaks_on_strike() -> void:
	var hero: Node2D = _spawn_hero("ambush")
	hero.call("use_ability")
	assert_true(hero.get("is_cloaked") as bool, "targeting consults is_cloaked, not alpha")
	hero.call("_after_strike", null)
	assert_false(hero.get("is_cloaked") as bool, "striking breaks the ambush")
	assert_eq(hero.modulate.a, 1.0)

func test_honor_duel_compels_and_scales_damage() -> void:
	var hero: Node2D = _spawn_hero("honor_duel")
	var rival: Node2D = _spawn_enemy(Vector2(480.0, 400.0), "hero_bethencourt")
	var outsider: Node2D = _spawn_enemy(Vector2(520.0, 400.0))
	hero.call("use_ability")
	assert_eq(hero.get("_duel_target"), rival, "the duel found its champion")
	assert_true(rival.get("is_taunted") as bool, "the rival is compelled to fight")
	var hp0: float = hero.get("health") as float
	hero.call("take_damage", 10.0, rival)
	assert_almost_eq(hp0 - (hero.get("health") as float), 20.0, 0.01,
		"the rival hits the duelist twice as hard")
	hp0 = hero.get("health") as float
	hero.call("take_damage", 10.0, outsider)
	assert_almost_eq(hp0 - (hero.get("health") as float), 5.0, 0.01,
		"outsiders barely scratch the duel bubble")

func test_slow_and_stun_status_effects() -> void:
	var unit: Node2D = _spawn_enemy(Vector2(600.0, 400.0))
	var base_speed: float = unit.call("_nav_speed") as float
	unit.call("apply_slow", 0.6, 1300)
	assert_almost_eq((unit.call("_nav_speed") as float) / base_speed, 0.6, 0.01,
		"sandstorm slow reaches the nav speed")
	assert_false(unit.call("is_stunned") as bool)
	unit.call("apply_stun", 2000)
	assert_true(unit.call("is_stunned") as bool, "boarding stun holds the unit")

func test_mountain_voice_heals_the_buffed_allies() -> void:
	var hero: Node2D = _spawn_hero("mountain_voice")
	var ally: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	ally.set("player_id", 0)
	add_child_autofree(ally)
	ally.global_position = Vector2(450.0, 400.0)
	hero.call("use_ability")
	ally.set("health", 10.0)
	hero.call("_tick_mountain_voice_healing", 1.05)
	assert_almost_eq(ally.get("health") as float, 14.0, 0.01,
		"the chant heals 4 HP per second")

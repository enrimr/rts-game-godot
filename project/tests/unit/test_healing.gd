extends GutTest

## The healing contract (community requests #3 and #4):
## UnitBase.heal() is THE canonical heal (clamped, bar-refreshing), the
## Temple ward mends its garrison (heroes at half rate — no degenerate
## Regicide stalling), and the Harimaguada follows-and-mends without ever
## fighting. Also pins the Rising Tide fix (its old ad-hoc heal no-opped).

const PID: int = 7

func _spawn(scene: String) -> CharacterBody2D:
	var unit: CharacterBody2D = (load("res://scenes/units/" + scene) as PackedScene)\
		.instantiate() as CharacterBody2D
	unit.set("player_id", PID)
	unit.set("civ_id", "canarii")
	add_child_autofree(unit)
	return unit

func test_heal_is_clamped_and_refreshes_the_bar() -> void:
	var unit: CharacterBody2D = _spawn("militia.tscn")
	var bar: ProgressBar = unit.get("health_bar") as ProgressBar
	var max_hp: float = float(bar.max_value)
	unit.set("health", max_hp * 0.4)
	unit.call("heal", 10.0)
	assert_almost_eq(unit.get("health") as float, max_hp * 0.4 + 10.0, 0.01)
	assert_almost_eq(float(bar.value), unit.get("health") as float, 0.01,
		"the bar follows the canonical heal")
	unit.call("heal", 99999.0)
	assert_almost_eq(unit.get("health") as float, max_hp, 0.01, "never past max")
	assert_true(unit.call("is_fully_healed") as bool)

func test_temple_ward_heals_garrison_heroes_at_half_rate() -> void:
	var temple: Temple = (load("res://scenes/buildings/temple.tscn") as PackedScene)\
		.instantiate() as Temple
	temple.set("player_id", PID)
	add_child_autofree(temple)
	temple.state = BuildingBase.BuildingState.COMPLETE
	assert_eq(temple.garrison_capacity(), 5, "capacity now read from the .tres")

	var soldier: CharacterBody2D = _spawn("militia.tscn")
	soldier.set("health", 1.0)
	assert_true(temple.garrison_unit(soldier), "wounded soldier checks in")
	# Built like production: script BEFORE entering the tree, or @onready
	# fields of the swapped script never resolve.
	var hero: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", load("res://resources/units/hero_doramas.tres"))
	hero.set("player_id", PID)
	add_child_autofree(hero)
	hero.set("health", 1.0)
	assert_true(temple.garrison_unit(hero), "the hero fits too")

	temple.call("_heal_ward", 2.0)
	var soldier_gain: float = (soldier.get("health") as float) - 1.0
	var hero_gain: float = (hero.get("health") as float) - 1.0
	assert_almost_eq(soldier_gain, Temple.HEAL_RATE * 2.0, 0.01)
	assert_almost_eq(hero_gain, soldier_gain * Temple.HERO_HEAL_MULT, 0.01,
		"heroes mend at half pace — Regicide stays honest")
	temple.ungarrison_all()

func test_harimaguada_heals_and_never_fights() -> void:
	var healer: CharacterBody2D = _spawn("harimaguada.tscn")
	assert_false(healer.call("is_combat_unit") as bool)
	assert_eq(healer.get("stance") as int, UnitBase.Stance.PASSIVE,
		"she never auto-acquires enemies")
	var patient: CharacterBody2D = _spawn("militia.tscn")
	patient.set("health", 5.0)
	patient.global_position = healer.global_position + Vector2(20.0, 0.0)
	healer.call("order_heal", patient)
	assert_eq(healer.get("heal_target"), patient)
	healer.call("_handle_healing", 2.0)
	assert_almost_eq(patient.get("health") as float, 5.0 + 10.0, 0.01,
		"in touch range she channels HEAL_RATE hp/s")

func test_harimaguada_refuses_enemies_and_the_healthy() -> void:
	var healer: CharacterBody2D = _spawn("harimaguada.tscn")
	var enemy: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	enemy.set("player_id", PID + 1)
	add_child_autofree(enemy)
	enemy.set("health", 5.0)
	healer.call("order_heal", enemy)
	assert_eq(healer.get("heal_target"), null, "enemies are not patients")
	var healthy: CharacterBody2D = _spawn("militia.tscn")
	healer.call("order_heal", healthy)
	assert_eq(healer.get("heal_target"), null, "the healthy need no tending")

func test_rising_tide_actually_heals_now() -> void:
	var ally: CharacterBody2D = _spawn("militia.tscn")
	var bar: ProgressBar = ally.get("health_bar") as ProgressBar
	ally.set("health", 1.0)
	ally.call("heal", 60.0)
	assert_almost_eq(float(bar.value), ally.get("health") as float, 0.01,
		"the canonical path updates the bar the old ad-hoc write missed")

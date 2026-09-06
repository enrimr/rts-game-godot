extends GutTest

## The counter triangle: data-driven class bonuses (UnitResource.attack_bonuses,
## applied in UnitBase._strike_damage) so composition beats raw numbers —
## pikes punish cavalry, cavalry eats archers, archers pick off spearmen.
## Also audits that every bonus key in every .tres maps to a real combat class,
## and locks the two freshly wired civ bonuses (Franks farm build speed,
## Castellanos tower range).

const PID: int = 7

func before_each() -> void:
	CivBonusManager.init_player(PID, "franks")
	TechManager.init_player(PID)

func _spawn(scene: String, pid: int = PID) -> CharacterBody2D:
	var unit: CharacterBody2D = (load("res://scenes/units/" + scene) as PackedScene)\
		.instantiate() as CharacterBody2D
	unit.set("player_id", pid)
	unit.set("civ_id", "franks")
	add_child_autofree(unit)
	return unit

func _dmg(attacker: Node, target: Node) -> float:
	return attacker.call("_strike_damage", target) as float

# ── The triangle itself ──────────────────────────────────────────────────────

func test_pikeman_punishes_cavalry() -> void:
	var pike: CharacterBody2D = _spawn("pikeman.tscn")
	var knight: CharacterBody2D = _spawn("knight.tscn", 8)
	var militia: CharacterBody2D = _spawn("militia.tscn", 8)
	assert_almost_eq(pike.call("_class_bonus_vs", knight) as float, 12.0, 0.01,
		"+12 vs cavalry: the banot finds the horse")
	assert_almost_eq(pike.call("_class_bonus_vs", militia) as float, 0.0, 0.01)
	# The duel that used to be hopeless: pike now drops the knight FIRST.
	var pike_hits_to_kill: int = ceili(120.0 / _dmg(pike, knight))
	var knight_hits_to_kill: int = ceili(65.0 / _dmg(knight, pike))
	assert_lt(pike_hits_to_kill, knight_hits_to_kill,
		"cost-for-cost the spearman wins his matchup")

func test_cavalry_eats_archers() -> void:
	var knight: CharacterBody2D = _spawn("knight.tscn")
	var archer: CharacterBody2D = _spawn("archer.tscn", 8)
	assert_almost_eq(knight.call("_class_bonus_vs", archer) as float, 4.0, 0.01)
	var scout: CharacterBody2D = _spawn("scout.tscn")
	assert_almost_eq(scout.call("_class_bonus_vs", archer) as float, 3.0, 0.01,
		"even the light scout raids the archer line now")

func test_archers_pick_off_spearmen() -> void:
	var archer: CharacterBody2D = _spawn("archer.tscn")
	var pike: CharacterBody2D = _spawn("pikeman.tscn", 8)
	assert_almost_eq(archer.call("_class_bonus_vs", pike) as float, 3.0, 0.01,
		"the loop closes: pike > cav > archer > pike")

func test_longbowman_bonus_lives_in_data_now() -> void:
	var lb: CharacterBody2D = _spawn("longbowman.tscn")
	var knight: CharacterBody2D = _spawn("knight.tscn", 8)
	assert_almost_eq(lb.call("_class_bonus_vs", knight) as float, 4.0, 0.01,
		"Armour Piercing migrated to attack_bonuses without changing numbers")
	assert_false(lb.has_method("_get_cavalry_bonus"),
		"the hardcoded override is gone")

func test_bonuses_never_apply_to_buildings_or_animals() -> void:
	var pike: CharacterBody2D = _spawn("pikeman.tscn")
	var tower: Node2D = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene)\
		.instantiate() as Node2D
	tower.set("player_id", 8)
	add_child_autofree(tower)
	assert_eq(pike.call("_class_bonus_vs", tower) as float, 0.0,
		"a wall is not a horse")

## Every attack_bonuses key in every shipped unit .tres must name a REAL
## combat class — a typo would silently do nothing forever.
func test_every_bonus_key_is_a_known_class() -> void:
	var valid: Array = ["cavalry", "archer", "spearman", "infantry", "siege",
		"ship", "villager"]
	var audited: int = 0
	var dir: DirAccess = DirAccess.open("res://resources/units")
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var res: UnitResource = load("res://resources/units/" + file) as UnitResource
		if res == null:
			continue
		for key: Variant in res.attack_bonuses.keys():
			assert_has(valid, key as String,
				"%s: attack_bonuses key '%s' is not a combat class" % [file, key])
			audited += 1
	assert_gt(audited, 9, "the whole triangle roster was audited")

# ── The two freshly wired civ bonuses ────────────────────────────────────────

func test_franks_build_farms_faster() -> void:
	CivBonusManager.init_player(PID, "franks")
	assert_almost_eq(CivBonusManager.get_multiplier(PID, "farm_build_speed"), 1.20, 0.001)
	CivBonusManager.init_player(8, "britons")
	assert_almost_eq(CivBonusManager.get_multiplier(8, "farm_build_speed"), 1.0, 0.001)

func test_castellanos_towers_reach_further() -> void:
	var tower: Node2D = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene)\
		.instantiate() as Node2D
	tower.set("player_id", PID)
	add_child_autofree(tower)
	CivBonusManager.init_player(PID, "castellanos")
	assert_almost_eq(tower.call("_attack_range") as float, 242.0, 0.01,
		"220 px × 1.10 — the declared tower_range finally reads")
	CivBonusManager.init_player(PID, "franks")
	assert_almost_eq(tower.call("_attack_range") as float, 220.0, 0.01)

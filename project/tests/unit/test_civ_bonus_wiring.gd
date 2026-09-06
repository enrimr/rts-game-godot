extends GutTest

## The four civ bonuses that were advertised in the .tres descriptions with no
## code reading them (game-review + docs-audit finding), now wired for real:
##   - Fenicios: market from the Dark Age + real ship discount (ship_cost 0.85)
##   - Guanches: pikeman (banot spearman) trainable from the Dark Age
##   - Canarii: houses double as drop-off points
##   - Mahos: buildings cost less wood (button, AI sheet and command charge all
##     go through CivBonusManager.get_building_costs)
## Plus the caldera claim: a Mining Camp near a CALDERA zone trickles stone.

const PID: int = 7
const RIVAL: int = 8

func before_each() -> void:
	TechManager.init_player(PID)
	AgeManager.init_player(PID, GameManager.Age.DARK)

func after_each() -> void:
	TerrainManager.reset()

func _building(scene: String, pid: int, civ: String) -> Node2D:
	CivBonusManager.init_player(pid, civ)
	var b: Node2D = (load(scene) as PackedScene).instantiate() as Node2D
	b.set("player_id", pid)
	add_child_autofree(b)
	return b

# ── has_bonus: presence, not value ───────────────────────────────────────────

func test_has_bonus_reads_key_presence() -> void:
	CivBonusManager.init_player(PID, "fenicios")
	assert_true(CivBonusManager.has_bonus(PID, "market_available_dark_age"))
	assert_false(CivBonusManager.has_bonus(PID, "spear_available_dark_age"))
	CivBonusManager.init_player(PID, "franks")
	assert_false(CivBonusManager.has_bonus(PID, "market_available_dark_age"))

# ── Fenicios ─────────────────────────────────────────────────────────────────

func test_fenicios_market_unlocks_in_dark_age() -> void:
	CivBonusManager.init_player(PID, "fenicios")
	var market_def: Dictionary = {"id": "build:market", "min_age": 1}
	assert_eq(HudActionDefs.build_min_age(market_def, PID), 0,
		"the Fenicios build menu offers the market from the start")
	CivBonusManager.init_player(RIVAL, "franks")
	assert_eq(HudActionDefs.build_min_age(market_def, RIVAL), 1,
		"everyone else waits for Feudal")

func test_fenicios_ships_cost_less() -> void:
	CivBonusManager.init_player(PID, "fenicios")
	assert_almost_eq(CivBonusManager.get_ship_cost_multiplier(PID), 0.85, 0.001,
		"the .tres now DECLARES the discount the description promised")

# ── Guanches ─────────────────────────────────────────────────────────────────

func test_guanches_train_pikeman_from_dark_age() -> void:
	var barracks: Node2D = _building("res://scenes/buildings/barracks.tscn", PID, "guanches")
	var ids: Array = barracks.call("get_available_units").map(
		func(d: Dictionary) -> String: return d["id"] as String)
	assert_has(ids, "pikeman", "banot spearmen from the start for Guanches")

func test_other_civs_still_wait_for_castle_pikes() -> void:
	AgeManager.init_player(RIVAL, GameManager.Age.DARK)
	var barracks: Node2D = _building("res://scenes/buildings/barracks.tscn", RIVAL, "franks")
	var ids: Array = barracks.call("get_available_units").map(
		func(d: Dictionary) -> String: return d["id"] as String)
	assert_does_not_have(ids, "pikeman")

# ── Canarii ──────────────────────────────────────────────────────────────────

func test_canarii_house_registers_as_drop_off() -> void:
	var house: Node2D = _building("res://scenes/buildings/house.tscn", PID, "canarii")
	house.call("force_complete")
	house.call("_maybe_register_drop_off")
	var drop: Node = house.get_node_or_null("DropOffBuilding")
	assert_not_null(drop, "a Canarii house IS a drop-off point")
	assert_true(drop.is_in_group("drop_off_buildings"),
		"villagers find it through the same group as the camps")
	assert_eq(drop.get("player_id") as int, PID)

func test_other_civ_houses_are_just_houses() -> void:
	var house: Node2D = _building("res://scenes/buildings/house.tscn", RIVAL, "franks")
	house.call("force_complete")
	house.call("_maybe_register_drop_off")
	assert_null(house.get_node_or_null("DropOffBuilding"))

# ── Mahos ────────────────────────────────────────────────────────────────────

func test_mahos_buildings_cost_less_wood() -> void:
	CivBonusManager.init_player(PID, "mahos")
	var base: Dictionary = {"wood": 100, "stone": 50}
	var discounted: Dictionary = CivBonusManager.get_building_costs(PID, base)
	assert_eq(discounted["wood"], 70, "building_wood_cost 0.70 finally has a reader")
	assert_eq(discounted["stone"], 50, "only the timber is cheaper")
	CivBonusManager.init_player(RIVAL, "franks")
	assert_eq(CivBonusManager.get_building_costs(RIVAL, base), base)

# ── Mahos dune vision ────────────────────────────────────────────────────────

func test_mahos_see_farther_from_the_dunes() -> void:
	TerrainManager.reset()
	TerrainManager.add_zone(Vector2.ZERO, 300.0, TerrainManager.TerrainType.DUNE)
	var fog: FogOfWar = FogOfWar.new()
	autofree(fog)
	CivBonusManager.init_player(0, "mahos")
	assert_almost_eq(fog._dune_vision_mult(Vector2.ZERO) as float, 1.40, 0.001,
		"standing ON the dune, the Mahos watcher sees 40% farther")
	assert_almost_eq(fog._dune_vision_mult(Vector2(900.0, 0.0)) as float, 1.0, 0.001,
		"off the dune the bonus is gone")
	CivBonusManager.init_player(0, "franks")
	assert_almost_eq(fog._dune_vision_mult(Vector2.ZERO) as float, 1.0, 0.001,
		"other civs read the dunes like everyone else")

# ── Caldera claim ────────────────────────────────────────────────────────────

func test_mining_camp_near_caldera_trickles_stone() -> void:
	TerrainManager.reset()
	TerrainManager.add_zone(Vector2(500, 0), 200.0, TerrainManager.TerrainType.CALDERA)
	ResourceManager.init_player(PID, {"food": 0, "wood": 0, "gold": 0, "stone": 0})
	var camp: Node2D = _building("res://scenes/buildings/mining_camp.tscn", PID, "franks")
	camp.global_position = Vector2.ZERO   # 300 px from the rim: inside the claim
	camp.call("_on_construction_complete")
	assert_true(camp.get("_caldera_claim") as bool)
	camp.call("_physics_process", MiningCamp.CALDERA_STONE_INTERVAL + 0.1)
	assert_eq(ResourceManager.get_resources(PID).get("stone", 0) as int,
		MiningCamp.CALDERA_STONE_AMOUNT, "the claim pays its first stone")

func test_mining_camp_far_from_caldera_gets_nothing() -> void:
	TerrainManager.reset()
	TerrainManager.add_zone(Vector2(5000, 0), 200.0, TerrainManager.TerrainType.CALDERA)
	ResourceManager.init_player(PID, {"food": 0, "wood": 0, "gold": 0, "stone": 0})
	var camp: Node2D = _building("res://scenes/buildings/mining_camp.tscn", PID, "franks")
	camp.global_position = Vector2.ZERO
	camp.call("_on_construction_complete")
	assert_false(camp.get("_caldera_claim") as bool)
	camp.call("_physics_process", MiningCamp.CALDERA_STONE_INTERVAL + 0.1)
	assert_eq(ResourceManager.get_resources(PID).get("stone", 0) as int, 0)

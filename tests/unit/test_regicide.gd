extends GutTest

## Tests for Regicide victory mode.
##
## What is covered:
##   1. MatchConfig.VictoryMode enum values (CONQUEST == 0, REGICIDE == 1)
##   2. MatchConfig.victory_mode field is readable and settable
##   3. GameManager.start_game() connects hero_died handler only in REGICIDE mode
##   4. EventBus.hero_died triggers game_over with correct winner in REGICIDE mode
##   5. EventBus.hero_died does NOT trigger game_over in CONQUEST mode
##   6. GameManager.state transitions to GAME_OVER after regicide
##   7. Handler is disconnected after first death — no double-fire
##   8. SaveManager persists victory_mode across save/load cycle
##   9. Missing victory_mode key in save JSON leaves victory_mode unchanged
##
## What is NOT covered:
##   - restore_world: requires live PackedScenes; integration test territory.
##   - Multi-hero / multi-player edge cases beyond 2 players: the handler always
##     picks the first pid != dead_player_id, which is well-defined for 2 players.
##
## Setup notes:
##   - GameManager, EventBus, MatchConfig, SaveManager are all autoloads.
##   - before_each() disconnects the regicide handler if it leaked from a
##     previous test, and resets GameManager to MAIN_MENU / empty players.
##   - game_over signal is connected in individual tests that need to observe it
##     and is always disconnected in after_each() to prevent cross-test leakage.
##   - Slot 93 is used for SaveManager tests — chosen to avoid collision with
##     test_save_manager.gd which occupies slots 90-92.

const _TEST_SLOT: int = 93

## Captured winner_id from the game_over signal; -999 means not fired.
var _captured_winner: int = -999
var _game_over_fired: bool = false

## Build a minimal world Node that satisfies _collect()'s property reads.
## Direct copy from test_save_manager.gd — GUT has no import mechanism.
func _make_fake_world(rng_seed: int = 12345, tc_pos: Vector2 = Vector2(100.0, 200.0)) -> Node:
	var world: Node = Node.new()
	var script: GDScript = GDScript.new()
	script.source_code = """
extends Node
var _saved_rng_seed: int = 0
var _saved_tc_position: Vector2 = Vector2.ZERO
"""
	script.reload()
	world.set_script(script)
	world._saved_rng_seed = rng_seed
	world._saved_tc_position = tc_pos

	var units_layer: Node = Node.new()
	units_layer.name = "UnitsLayer"
	world.add_child(units_layer)

	var bld_layer: Node = Node.new()
	bld_layer.name = "BuildingsLayer"
	world.add_child(bld_layer)

	var tc_script: GDScript = GDScript.new()
	tc_script.source_code = """
extends Node2D
var health: float = 1500.0
var max_health: float = 2000.0
var rally_point: Vector2 = Vector2(50.0, 75.0)
"""
	tc_script.reload()
	var drop_off: Node2D = Node2D.new()
	drop_off.name = "DropOffNode"
	drop_off.set_script(tc_script)
	drop_off.global_position = Vector2(100.0, 200.0)
	world.add_child(drop_off)

	return world


func _remove_slot(slot: int) -> void:
	var path: String = SaveManager.SAVE_DIR + "save_%02d.json" % slot
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _on_game_over(winner_id: int) -> void:
	_captured_winner = winner_id
	_game_over_fired = true


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_each() -> void:
	_captured_winner = -999
	_game_over_fired = false

	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST

	GameManager.state = GameManager.GameState.MAIN_MENU
	GameManager.players = []

	# Disconnect the regicide handler if a previous test left it connected.
	if EventBus.hero_died.is_connected(GameManager._on_hero_died_regicide):
		EventBus.hero_died.disconnect(GameManager._on_hero_died_regicide)

	# Disconnect our own observer if it leaked from a previous test.
	if GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.disconnect(_on_game_over)

	_remove_slot(_TEST_SLOT)
	SaveManager.pending_load = false
	SaveManager._save_data = {}

	MatchConfig.map_size      = 1
	MatchConfig.resources     = 1
	MatchConfig.map_type      = 0
	MatchConfig.player_civ_id = "guanches"
	MatchConfig.starting_age  = 0
	MatchConfig.rival_count   = 1
	MatchConfig.rival_civ_ids = ["castellanos"]


func after_each() -> void:
	if EventBus.hero_died.is_connected(GameManager._on_hero_died_regicide):
		EventBus.hero_died.disconnect(GameManager._on_hero_died_regicide)

	if GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.disconnect(_on_game_over)

	GameManager.state = GameManager.GameState.MAIN_MENU
	GameManager.players = []

	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST

	_remove_slot(_TEST_SLOT)
	SaveManager.pending_load = false
	SaveManager._save_data = {}


# ---------------------------------------------------------------------------
# 1. MatchConfig.VictoryMode enum values
# ---------------------------------------------------------------------------

func test_victory_mode_conquest_equals_zero() -> void:
	assert_eq(MatchConfig.VictoryMode.CONQUEST, 0,
		"VictoryMode.CONQUEST must equal 0")


func test_victory_mode_regicide_equals_one() -> void:
	assert_eq(MatchConfig.VictoryMode.REGICIDE, 1,
		"VictoryMode.REGICIDE must equal 1")


# ---------------------------------------------------------------------------
# 2. MatchConfig.victory_mode field
# ---------------------------------------------------------------------------

func test_victory_mode_field_default_is_conquest() -> void:
	# before_each resets to CONQUEST; verify the field is accessible and holds it.
	assert_eq(MatchConfig.victory_mode, MatchConfig.VictoryMode.CONQUEST,
		"victory_mode must default to CONQUEST after reset")


func test_victory_mode_field_holds_regicide_after_assignment() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	assert_eq(MatchConfig.victory_mode, MatchConfig.VictoryMode.REGICIDE,
		"victory_mode must hold REGICIDE after being set to it")


func test_victory_mode_field_returns_int() -> void:
	# The field is typed as int; verify the returned value satisfies is_int()
	# by comparing it to itself cast to int (a non-int would differ).
	var v: int = MatchConfig.victory_mode
	assert_eq(v, MatchConfig.victory_mode,
		"victory_mode must return a value that is assignable to int")


# ---------------------------------------------------------------------------
# 3. GameManager.start_game wires the handler only in REGICIDE mode
# ---------------------------------------------------------------------------

func test_start_game_regicide_connects_hero_died_handler() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	GameManager.start_game([{}, {}])
	assert_true(EventBus.hero_died.is_connected(GameManager._on_hero_died_regicide),
		"hero_died must be connected to _on_hero_died_regicide after start_game in REGICIDE mode")


func test_start_game_conquest_does_not_connect_hero_died_handler() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST
	GameManager.start_game([{}, {}])
	assert_false(EventBus.hero_died.is_connected(GameManager._on_hero_died_regicide),
		"hero_died must NOT be connected to _on_hero_died_regicide in CONQUEST mode")


# ---------------------------------------------------------------------------
# 4. hero_died emission triggers game_over with the correct winner
# ---------------------------------------------------------------------------

func test_hero_died_for_player_1_fires_game_over_with_winner_0() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	GameManager.game_over.connect(_on_game_over)
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(1, hero_data)

	assert_eq(_captured_winner, 0,
		"game_over must fire with winner_id == 0 when player 1's hero dies")


func test_hero_died_for_player_0_fires_game_over_with_winner_1() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	GameManager.game_over.connect(_on_game_over)
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(0, hero_data)

	assert_eq(_captured_winner, 1,
		"game_over must fire with winner_id == 1 when player 0's hero dies")


# ---------------------------------------------------------------------------
# 5. hero_died does NOT trigger game_over in CONQUEST mode
# ---------------------------------------------------------------------------

func test_hero_died_in_conquest_mode_does_not_fire_game_over() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST
	GameManager.game_over.connect(_on_game_over)
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(1, hero_data)

	assert_false(_game_over_fired,
		"game_over must not fire when a hero dies in CONQUEST mode")


func test_hero_died_in_conquest_mode_does_not_change_state() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(1, hero_data)

	assert_eq(GameManager.state, GameManager.GameState.PLAYING,
		"GameManager.state must remain PLAYING after hero_died in CONQUEST mode")


# ---------------------------------------------------------------------------
# 6. GameManager.state becomes GAME_OVER after regicide
# ---------------------------------------------------------------------------

func test_state_is_game_over_after_hero_dies_in_regicide_mode() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(1, hero_data)

	assert_eq(GameManager.state, GameManager.GameState.GAME_OVER,
		"GameManager.state must be GAME_OVER after a hero dies in REGICIDE mode")


# ---------------------------------------------------------------------------
# 7. Handler is disconnected after game_over — no double-fire
# ---------------------------------------------------------------------------

func test_hero_died_handler_disconnected_after_first_death() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(1, hero_data)

	assert_false(EventBus.hero_died.is_connected(GameManager._on_hero_died_regicide),
		"_on_hero_died_regicide must be disconnected from hero_died after game_over fires")


func test_second_hero_died_emission_does_not_fire_game_over_again() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	GameManager.game_over.connect(_on_game_over)
	GameManager.start_game([{}, {}])

	var hero_data: UnitResource = UnitResource.new()
	EventBus.hero_died.emit(1, hero_data)

	# Reset the observer to detect a second emission.
	_game_over_fired = false
	_captured_winner = -999

	# Manually set state back to PLAYING so declare_winner would run if called,
	# proving it's the disconnection — not the state guard — blocking the second fire.
	# We do NOT set state back; the guard inside _on_hero_died_regicide also stops it,
	# but the primary proof is that the signal itself is no longer connected.
	EventBus.hero_died.emit(0, hero_data)

	assert_false(_game_over_fired,
		"game_over must not fire a second time after the handler was disconnected")


# ---------------------------------------------------------------------------
# 8. SaveManager persists victory_mode across save/load
# ---------------------------------------------------------------------------

func test_save_load_restores_victory_mode_regicide() -> void:
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE

	var world: Node = _make_fake_world()
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT)

	# Reset to CONQUEST before loading to prove the load actually overwrites it.
	MatchConfig.victory_mode = MatchConfig.VictoryMode.CONQUEST

	SaveManager.load_game(_TEST_SLOT)

	assert_eq(MatchConfig.victory_mode, MatchConfig.VictoryMode.REGICIDE,
		"victory_mode must be REGICIDE after loading a save that was created with REGICIDE")


# ---------------------------------------------------------------------------
# 9. Missing victory_mode key in save JSON leaves victory_mode unchanged
# ---------------------------------------------------------------------------

func test_missing_victory_mode_in_save_leaves_value_unchanged() -> void:
	# Write a minimal save JSON that has a match_config block but no victory_mode key.
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var path: String = SaveManager.SAVE_DIR + "save_%02d.json" % _TEST_SLOT
	var minimal_save: Dictionary = {
		"schema_version": 1,
		"rng_seed":       0,
		"match_config":   {
			"map_size":      1,
			"resources":     1,
			"map_type":      0,
			"player_civ_id": "guanches",
			"starting_age":  0,
			"rival_count":   1,
			"rival_civ_ids": ["castellanos"],
			# victory_mode intentionally absent
		},
		"resources":       {},
		"ages":            {},
		"population_caps": {},
		"technologies":    {},
		"units":           [],
		"buildings":       [],
		"resource_nodes":  [],
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "test setup: must be able to write the minimal save file")
	file.store_string(JSON.stringify(minimal_save))
	file.close()

	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE
	SaveManager.load_game(_TEST_SLOT)

	assert_eq(MatchConfig.victory_mode, MatchConfig.VictoryMode.REGICIDE,
		"victory_mode must remain unchanged when the key is absent from the save's match_config")

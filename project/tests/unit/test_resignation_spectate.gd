extends GutTest

## Tests for the resignation → spectate flow (WorldVictory.handle_resignation).
##
## What is covered:
##   1. Local player (pid 0) resigning while two mutually hostile rivals still
##      stand: the match does NOT end (no game_over), the player is eliminated
##      (player_eliminated fires once) — spectate mode.
##   2. Resigning in a 1v1 ends the match: the remaining rival wins after
##      RESIGN_END_DELAY.
##   3. handle_resignation is idempotent — a second call never re-emits.
##   4. _check_defeat_for skips already-resigned players (no re-announcement
##      when their leftover buildings fall later).
##
## What is NOT covered:
##   - The HUD defeat panel and order lockout (scene territory: HudMatchStats /
##     GameWorld input routing).
##   - Multiplayer resignations (NetworkSession paths).
##
## Setup notes:
##   - WorldVictory is a RefCounted that reads the world dynamically; a stub
##     Node with units_layer/buildings_layer children satisfies every property
##     touched by the resignation paths. The stub must live in the tree because
##     handle_resignation awaits a SceneTreeTimer through _world.get_tree().

class StubUnit extends Node2D:
	var player_id: int = 0

var _victory: WorldVictory = null
var _world: Node = null
var _units_layer: Node2D = null

var _eliminated_pids: Array[int] = []
var _captured_winner: int = -999
var _game_over_fired: bool = false

func _on_player_eliminated(pid: int) -> void:
	_eliminated_pids.append(pid)

func _on_game_over(winner_id: int) -> void:
	_captured_winner = winner_id
	_game_over_fired = true

func _spawn_unit(pid: int) -> void:
	var unit: StubUnit = StubUnit.new()
	unit.player_id = pid
	_units_layer.add_child(unit)

func before_each() -> void:
	_eliminated_pids.clear()
	_captured_winner = -999
	_game_over_fired = false

	MatchConfig.victory_mode  = MatchConfig.VictoryMode.CONQUEST
	MatchConfig.player_civ_id = "guanches"
	MatchConfig.player_teams  = {}
	GameManager.state = GameManager.GameState.PLAYING

	_world = Node.new()
	_units_layer = Node2D.new()
	_units_layer.name = "UnitsLayer"
	_world.add_child(_units_layer)
	var buildings: Node2D = Node2D.new()
	buildings.name = "BuildingsLayer"
	_world.add_child(buildings)
	var world_script: GDScript = GDScript.new()
	world_script.source_code = """
extends Node
@onready var units_layer: Node2D = $UnitsLayer
@onready var buildings_layer: Node2D = $BuildingsLayer
var _ai_town_centers: Dictionary = {}
var _ai_town_center: Node2D = null
var drop_off: Node2D = null
"""
	world_script.reload()
	_world.set_script(world_script)
	add_child_autofree(_world)

	_victory = WorldVictory.new()
	_victory.setup(_world)

	EventBus.player_eliminated.connect(_on_player_eliminated)
	GameManager.game_over.connect(_on_game_over)

func after_each() -> void:
	if EventBus.player_eliminated.is_connected(_on_player_eliminated):
		EventBus.player_eliminated.disconnect(_on_player_eliminated)
	if GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.disconnect(_on_game_over)
	GameManager.state = GameManager.GameState.MAIN_MENU
	GameManager.players = []
	MatchConfig.rival_count   = 1
	MatchConfig.rival_civ_ids = ["castellanos"]

func test_resign_with_hostile_rivals_left_keeps_match_running() -> void:
	MatchConfig.rival_count   = 2
	MatchConfig.rival_civ_ids = ["castellanos", "franks"]
	_spawn_unit(1)
	_spawn_unit(2)

	_victory.handle_resignation(0)
	await wait_seconds(WorldVictory.RESIGN_END_DELAY + 0.5)

	assert_eq(_eliminated_pids, [0], "the resigned player is eliminated")
	assert_false(_game_over_fired, "hostile sides remain — no game over")
	assert_eq(GameManager.state, GameManager.GameState.PLAYING,
		"the match keeps simulating for the spectator")

func test_resign_in_1v1_ends_match_with_rival_victory() -> void:
	MatchConfig.rival_count   = 1
	MatchConfig.rival_civ_ids = ["castellanos"]
	_spawn_unit(1)

	_victory.handle_resignation(0)
	await wait_seconds(WorldVictory.RESIGN_END_DELAY + 0.5)

	assert_eq(_eliminated_pids, [0], "the resigned player is eliminated")
	assert_true(_game_over_fired, "nobody left to fight — the match ends")
	assert_eq(_captured_winner, 1, "the remaining rival wins")

func test_resignation_is_idempotent() -> void:
	MatchConfig.rival_count   = 2
	MatchConfig.rival_civ_ids = ["castellanos", "franks"]
	_spawn_unit(1)
	_spawn_unit(2)

	_victory.handle_resignation(0)
	_victory.handle_resignation(0)
	await wait_seconds(WorldVictory.RESIGN_END_DELAY + 0.5)

	assert_eq(_eliminated_pids, [0], "a second resignation never re-emits")
	assert_false(_game_over_fired)

func test_check_defeat_skips_resigned_player() -> void:
	MatchConfig.rival_count   = 2
	MatchConfig.rival_civ_ids = ["castellanos", "franks"]
	_spawn_unit(1)
	_spawn_unit(2)

	_victory.handle_resignation(0)
	_eliminated_pids.clear()
	# A leftover building of the resigned player falls later: no re-announcement.
	_victory._check_defeat_for(0)
	await wait_seconds(WorldVictory.RESIGN_END_DELAY + 0.5)

	assert_eq(_eliminated_pids, [], "resigned players are never re-eliminated")
	assert_false(_game_over_fired)

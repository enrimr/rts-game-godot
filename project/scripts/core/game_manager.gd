extends Node

## GameManager — singleton that owns global game state.
## Access via GameManager autoload.

signal game_started
signal game_paused(is_paused: bool)
signal game_over(winner_player_id: int)

enum GameState { MAIN_MENU, LOADING, PLAYING, PAUSED, GAME_OVER }
enum Age { DARK = 0, FEUDAL = 1, CASTLE = 2, IMPERIAL = 3 }

const RESOURCE_STARTING: Dictionary = {
	"food": 200,
	"wood": 200,
	"gold": 100,
	"stone": 200,
}

var state: GameState = GameState.MAIN_MENU
var players: Array = []
var current_tick: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_game(player_configs: Array) -> void:
	players = player_configs
	state = GameState.PLAYING
	game_started.emit()

func toggle_pause() -> void:
	if state == GameState.PLAYING:
		state = GameState.PAUSED
		get_tree().paused = true
		game_paused.emit(true)
	elif state == GameState.PAUSED:
		state = GameState.PLAYING
		get_tree().paused = false
		game_paused.emit(false)

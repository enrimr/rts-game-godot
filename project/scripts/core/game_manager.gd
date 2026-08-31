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
var game_speed: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_game(player_configs: Array) -> void:
	players = player_configs
	_dead_heroes.clear()
	state = GameState.PLAYING
	game_started.emit()
	if MatchConfig.victory_mode == MatchConfig.VictoryMode.REGICIDE:
		EventBus.hero_died.connect(_on_hero_died_regicide)

## Single source of truth for diplomacy: same player, or both on the same
## non-zero team. Everything that decides hostility must go through this.
func are_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	var team_a: int = MatchConfig.team_of(a)
	return team_a > 0 and team_a == MatchConfig.team_of(b)

func set_game_speed(speed: float) -> void:
	game_speed = speed
	Engine.time_scale = speed

func toggle_pause() -> void:
	if state == GameState.PLAYING:
		state = GameState.PAUSED
		get_tree().paused = true
		Engine.time_scale = 0.0
		game_paused.emit(true)
	elif state == GameState.PAUSED:
		state = GameState.PLAYING
		get_tree().paused = false
		Engine.time_scale = game_speed
		game_paused.emit(false)

func declare_winner(winner_id: int) -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.GAME_OVER
	Engine.time_scale = 1.0
	if EventBus.hero_died.is_connected(_on_hero_died_regicide):
		EventBus.hero_died.disconnect(_on_hero_died_regicide)
	game_over.emit(winner_id)

var _dead_heroes: Dictionary = {}

func _on_hero_died_regicide(dead_player_id: int, _hero_data: UnitResource) -> void:
	if state != GameState.PLAYING:
		return
	# In regicide the player who loses their hero is eliminated. The match
	# ends when every remaining hero belongs to ONE side (team-aware).
	_dead_heroes[dead_player_id] = true
	var alive: Array[int] = []
	for cfg: Variant in players:
		var pid: int = (cfg as Dictionary).get("id", 0) as int
		if not _dead_heroes.has(pid):
			alive.append(pid)
	if not alive.is_empty():
		for pid: int in alive:
			if not are_allied(alive[0], pid):
				return
		declare_winner(alive[0])
		return
	if dead_player_id == 0:
		# Human lost their hero → first surviving rival wins.
		for i: int in range(1, players.size()):
			declare_winner(i)
			return
		declare_winner(1)
	else:
		# A rival lost their hero — check if all rivals are gone.
		# We treat "rival hero dead" as that rival being eliminated;
		# game_world will also call player_eliminated via EventBus if needed.
		# If the human hero is still alive and all rivals' heroes are dead → player 0 wins.
		var all_rivals_dead: bool = true
		for i: int in range(1, players.size()):
			if i != dead_player_id:
				# Can't easily check hero alive here — declare_winner only when
				# this is the last rival (single-rival common case).
				all_rivals_dead = false
				break
		if all_rivals_dead:
			declare_winner(0)

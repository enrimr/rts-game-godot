extends Node

## AgeManager — tracks each player's current Age and handles advancement.

# Costs to advance to each Age (indexed by target Age value)
const ADVANCE_COSTS: Array[Dictionary] = [
	{},                        # DARK (no cost, starting age)
	{"food": 500},             # FEUDAL
	{"food": 800, "gold": 200},   # CASTLE
	{"food": 1000, "gold": 800},  # IMPERIAL
]

# Time in seconds to finish advancing
const ADVANCE_TIMES: Array[float] = [0.0, 130.0, 160.0, 190.0]

var _player_age: Dictionary = {}           # player_id -> Age int
var _advancing: Dictionary = {}            # player_id -> bool
var _advance_timer: Dictionary = {}        # player_id -> float elapsed
var _advance_target: Dictionary = {}       # player_id -> target Age int

func init_player(player_id: int, starting_age: int = GameManager.Age.DARK) -> void:
	_player_age[player_id] = starting_age
	_advancing[player_id] = false
	_advance_timer[player_id] = 0.0
	_advance_target[player_id] = starting_age

func get_age(player_id: int) -> int:
	return _player_age.get(player_id, GameManager.Age.DARK) as int

func is_advancing(player_id: int) -> bool:
	return _advancing.get(player_id, false) as bool

func get_advance_progress(player_id: int) -> float:
	if not is_advancing(player_id):
		return 0.0
	var target: int = _advance_target.get(player_id, 1) as int
	var total: float = ADVANCE_TIMES[target]
	if total <= 0.0:
		return 1.0
	return clampf((_advance_timer.get(player_id, 0.0) as float) / total, 0.0, 1.0)

## Replication: adopt the host's age for a player (client HUD/tech gates).
func apply_remote(player_id: int, age: int) -> void:
	if get_age(player_id) == age:
		return
	_player_age[player_id] = age
	_advancing[player_id] = false
	EventBus.age_advance_complete.emit(player_id, age)

func can_advance(player_id: int) -> bool:
	var current: int = get_age(player_id)
	if current >= GameManager.Age.IMPERIAL:
		return false
	if is_advancing(player_id):
		return false
	var target: int = current + 1
	var mult: float = CivBonusManager.get_age_advance_cost_multiplier(player_id)
	var adjusted_costs: Dictionary = {}
	for k: String in ADVANCE_COSTS[target]:
		adjusted_costs[k] = maxi(1, roundi(ADVANCE_COSTS[target][k] * mult))
	return ResourceManager.can_afford(player_id, adjusted_costs)

func start_advance(player_id: int) -> bool:
	if not can_advance(player_id):
		return false
	var target: int = get_age(player_id) + 1
	var mult: float = CivBonusManager.get_age_advance_cost_multiplier(player_id)
	var adjusted_costs: Dictionary = {}
	for k: String in ADVANCE_COSTS[target]:
		adjusted_costs[k] = maxi(1, roundi(ADVANCE_COSTS[target][k] * mult))
	if not ResourceManager.spend_resource(player_id, adjusted_costs):
		return false
	_advancing[player_id] = true
	_advance_timer[player_id] = 0.0
	_advance_target[player_id] = target
	EventBus.age_advance_started.emit(player_id, target)
	return true

func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	for pid: Variant in _advancing.keys():
		if not (_advancing[pid] as bool):
			continue
		_advance_timer[pid] = (_advance_timer[pid] as float) + delta
		var target: int = _advance_target[pid] as int
		if (_advance_timer[pid] as float) >= ADVANCE_TIMES[target]:
			_finish_advance(pid as int)

func _finish_advance(player_id: int) -> void:
	var target: int = _advance_target.get(player_id, 1) as int
	_player_age[player_id] = target
	_advancing[player_id] = false
	_advance_timer[player_id] = 0.0
	_advance_target[player_id] = target
	EventBus.age_advance_complete.emit(player_id, target)

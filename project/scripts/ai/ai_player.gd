extends Node

## AIPlayer — simple state-machine AI controller.
## Runs on a tick timer rather than every frame.

enum AIStrategy { PASSIVE, ECONOMIC, RUSH, BOOM, TURTLE }

@export var strategy: AIStrategy = AIStrategy.ECONOMIC
@export var difficulty: float = 1.0  # 0.0 easy .. 1.0 hard

var player_id: int = -1
var _tick_interval: float = 1.0  # seconds between AI decisions
var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _tick_interval:
		_timer = 0.0
		_run_tick()

func _run_tick() -> void:
	_manage_economy()
	_manage_military()
	_manage_research()

func _manage_economy() -> void:
	pass  # TODO: assign idle villagers to resources

func _manage_military() -> void:
	pass  # TODO: produce units, manage attacks

func _manage_research() -> void:
	pass  # TODO: queue technologies

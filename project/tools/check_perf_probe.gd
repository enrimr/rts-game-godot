extends Node2D

## Frame-time probe: boots a real match (fixed seed), warms up, then samples
## the per-frame main-loop and physics times for a few seconds and prints the
## averages. Run twice (two builds) and diff the numbers.

var _world: Node2D = null
var _samples_process: Array[float] = []
var _samples_physics: Array[float] = []
var _t: float = 0.0

func _ready() -> void:
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	MatchConfig.rival_count = 2
	MatchConfig.rival_civ_ids = ["castellanos", "britons"]
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)

func _process(delta: float) -> void:
	_t += delta
	if _t < 4.0:
		return
	_samples_process.append(Performance.get_monitor(Performance.TIME_PROCESS))
	_samples_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	if _t >= 14.0:
		var ap: float = 0.0
		var af: float = 0.0
		for v: float in _samples_process: ap += v
		for v: float in _samples_physics: af += v
		ap = ap * 1000.0 / _samples_process.size()
		af = af * 1000.0 / _samples_physics.size()
		print("PERF process %.3f ms  physics %.3f ms  frames %d  fps %.0f" % [
			ap, af, _samples_process.size(), Performance.get_monitor(Performance.TIME_FPS)])
		print("PERF: done")
		get_tree().quit(0)

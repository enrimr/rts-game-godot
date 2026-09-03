extends Node2D

## Headless simulation-budget gate: boots a real match, spawns a 100v100
## battle, and measures how fast the simulation actually advances against
## wall-clock time. Fails when the sim can no longer hold at least
## MIN_TICK_RATE physics ticks per wall second — the symptom every past
## regression shared (per-resource RVO obstacles, per-tick chase repaths).
## Thresholds carry a wide margin so a slower machine doesn't flake; a real
## regression (2-10x) blows straight through them.

const ARMY_PER_SIDE: int = 100
const MEASURE_WALL_SEC: float = 8.0
const WARMUP_WALL_SEC: float = 4.0
## Healthy today: ~60 ticks/s headless on dev hardware. Gate at half of
## that; CI runners are far weaker, so they override the floor via
## CALIMA_PERF_MIN_TICKS — the gate still catches order-of-magnitude
## regressions there (the RVO bug ran at a small fraction of healthy).
const MIN_TICK_RATE: float = 30.0

static func _min_tick_rate() -> float:
	var env: String = OS.get_environment("CALIMA_PERF_MIN_TICKS")
	return float(env) if env.is_valid_float() else MIN_TICK_RATE

const ARMY_SCENES: Array[String] = [
	"res://scenes/units/militia.tscn",
	"res://scenes/units/archer.tscn",
	"res://scenes/units/knight.tscn",
]

var _world: Node2D = null
var _ticks: int = 0
var _measuring: bool = false

func _ready() -> void:
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	MatchConfig.rival_count = 1
	MatchConfig.rival_civ_ids = ["castellanos"]
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("PERF_GATE: TIMEOUT")
		get_tree().quit(1))
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	_spawn_armies.call_deferred()
	_run()

func _spawn_armies() -> void:
	var own_tc: Vector2 = (_world.get("drop_off") as Node2D).global_position
	var rival_tc: Vector2 = ((_world.get("_ai_town_centers") as Dictionary)[1] as Node2D).global_position
	var mid: Vector2 = (own_tc + rival_tc) * 0.5
	var dir: Vector2 = (rival_tc - own_tc).normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var ids_a: Array[int] = []
	var ids_b: Array[int] = []
	for i: int in range(ARMY_PER_SIDE):
		var scene: PackedScene = load(ARMY_SCENES[i % ARMY_SCENES.size()]) as PackedScene
		var row: float = float(i / 12) * 30.0
		var col: float = float(i % 12 - 6) * 26.0
		for pid: int in [0, 1]:
			var unit: CharacterBody2D = scene.instantiate() as CharacterBody2D
			unit.set("player_id", pid)
			unit.set("civ_id", "guanches" if pid == 0 else "castellanos")
			(_world.get("units_layer") as Node).add_child(unit)
			unit.global_position = mid + dir * (-1.0 if pid == 0 else 1.0) * (220.0 + row) + side * col
			PopulationManager.add_unit(pid)
			EventBus.unit_spawned.emit(unit, pid)
			if pid == 0:
				ids_a.append(EntityRegistry.id_of(unit))
			else:
				ids_b.append(EntityRegistry.id_of(unit))
	CommandBus.submit(UnitPointCommand.make(0, "attack_move", ids_a, mid + dir * 300.0))
	CommandBus.submit(UnitPointCommand.make(1, "attack_move", ids_b, mid - dir * 300.0))

func _physics_process(_delta: float) -> void:
	if _measuring:
		_ticks += 1

func _run() -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(WARMUP_WALL_SEC * 1000.0):
		await get_tree().process_frame
	_measuring = true
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(MEASURE_WALL_SEC * 1000.0):
		await get_tree().process_frame
	_measuring = false
	var wall: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var tick_rate: float = float(_ticks) / wall
	var alive: int = 0
	for unit: Node in (_world.get("units_layer") as Node).get_children():
		if is_instance_valid(unit):
			alive += 1
	print("PERF_GATE: %d units, %.1f ticks/s over %.1f s (gate: >= %.0f)" % [
		alive, tick_rate, wall, _min_tick_rate()])
	if tick_rate < _min_tick_rate():
		print("PERF_GATE: FAIL — the simulation lost more than half its speed under a 100v100 battle")
		get_tree().quit(1)
		return
	print("PERF_GATE: done")
	get_tree().quit(0)

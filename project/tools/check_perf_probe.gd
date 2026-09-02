extends Node2D

## Frame-time probe: boots a real match (fixed seed), optionally fast-forwards
## it so the AIs develop, optionally spawns two synthetic armies and sends them
## at each other, then samples per-frame main-loop and physics times and prints
## one summary row. Parameters via env:
##   CALIMA_PERF_LABEL      row label (default "probe")
##   CALIMA_PERF_RIVALS     rival count 1..3 (default 2)
##   CALIMA_PERF_MAP_SIZE   0 small / 1 medium / 2 large (default 1)
##   CALIMA_PERF_MAP        MatchConfig.MapType index (default 1 standard)
##   CALIMA_PERF_RESOURCES  MatchConfig.Resources index (default 1 normal)
##   CALIMA_PERF_ARMY       extra military units PER SIDE, clashing (default 0)
##   CALIMA_PERF_DEVELOP    game-seconds to run at 4x before measuring (default 0)
##   CALIMA_PERF_WINDOW     seconds of measurement (default 8)
## Run on two builds (git worktree) and diff the rows for an A/B.

const WARMUP_SEC: float = 4.0
const SETTLE_SEC: float = 2.0
const DEVELOP_SPEED: float = 4.0

const ARMY_SCENES: Array[String] = [
	"res://scenes/units/militia.tscn",
	"res://scenes/units/archer.tscn",
	"res://scenes/units/knight.tscn",
]

var _world: Node2D = null
var _label: String = "probe"
var _army: int = 0
var _develop: float = 0.0
var _window: float = 8.0

enum Phase { WARMUP, DEVELOP, SETTLE, MEASURE }
var _phase: Phase = Phase.WARMUP
var _t: float = 0.0
var _proc_sum: float = 0.0
var _phys_sum: float = 0.0
var _worst: float = 0.0
var _frames: int = 0
var _real_start_msec: int = 0

func _env_int(key: String, fallback: int) -> int:
	var v: String = OS.get_environment(key)
	return int(v) if v.is_valid_int() else fallback

func _ready() -> void:
	# Vsync waits leak into the frame-time monitors and cap fps at the display
	# rate — a perf probe must measure real headroom, never the compositor.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_label = OS.get_environment("CALIMA_PERF_LABEL")
	if _label.is_empty():
		_label = "probe"
	_army = _env_int("CALIMA_PERF_ARMY", 0)
	_develop = float(_env_int("CALIMA_PERF_DEVELOP", 0))
	_window = float(_env_int("CALIMA_PERF_WINDOW", 8))
	var rivals: int = clampi(_env_int("CALIMA_PERF_RIVALS", 2), 1, 3)
	MatchConfig.map_type = _env_int("CALIMA_PERF_MAP", MatchConfig.MapType.STANDARD)
	MatchConfig.map_size = clampi(_env_int("CALIMA_PERF_MAP_SIZE", 1), 0, 2)
	MatchConfig.resources = clampi(_env_int("CALIMA_PERF_RESOURCES", 1), 0, 3)
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	MatchConfig.rival_count = rivals
	var civs: Array[String] = ["castellanos", "britons", "mahos"]
	MatchConfig.rival_civ_ids = civs.slice(0, rivals)
	get_tree().create_timer(570.0).timeout.connect(func() -> void:
		print("PERF %s: TIMEOUT" % _label)
		get_tree().quit(1))
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	if _army > 0:
		_spawn_armies.call_deferred()
	_apply_disables.call_deferred(OS.get_environment("CALIMA_PERF_DISABLE").split(",", false))
	_real_start_msec = Time.get_ticks_msec()

## Cost attribution: switch whole systems off and diff against the baseline.
## CALIMA_PERF_DISABLE=fog,minimap,hud,weather,units,world,interp
func _apply_disables(disables: PackedStringArray) -> void:
	for what: String in disables:
		match what:
			"fog":
				(_world.get("_fog") as Node).set_process(false)
			"minimap":
				var mm: Node = (_world.get("hud") as Node).get_node_or_null("%Minimap")
				if mm != null:
					mm.set_process(false)
					mm.propagate_call("set_process", [false])
			"hud":
				(_world.get("hud") as Node).propagate_call("set_process", [false])
			"weather":
				var wo: Node = _world.get_node_or_null("WeatherOverlay")
				if wo != null:
					wo.propagate_call("set_process", [false])
					(wo as Node2D).visible = false
			"units":
				(_world.get("units_layer") as Node).propagate_call("set_process", [false])
			"hide_units":
				(_world.get("units_layer") as Node2D).visible = false
			"hide_world":
				_world.visible = false
			"world":
				_world.set_process(false)
			"interp":
				get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

## Two mirrored blocks between the player TC and the first rival TC, ordered
## into each other with attack-move — a worst-case melee/pathfinding pile-up.
func _spawn_armies() -> void:
	var own_tc: Vector2 = (_world.get("drop_off") as Node2D).global_position
	var rival_tc: Vector2 = ((_world.get("_ai_town_centers") as Dictionary)[1] as Node2D).global_position
	var mid: Vector2 = (own_tc + rival_tc) * 0.5
	var dir: Vector2 = (rival_tc - own_tc).normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var ids_a: Array[int] = []
	var ids_b: Array[int] = []
	for i: int in range(_army):
		var scene: PackedScene = load(ARMY_SCENES[i % ARMY_SCENES.size()]) as PackedScene
		var row: float = float(i / 12) * 30.0
		var col: float = float(i % 12 - 6) * 26.0
		for pid: int in [0, 1]:
			var unit: CharacterBody2D = scene.instantiate() as CharacterBody2D
			unit.set("player_id", pid)
			unit.set("civ_id", MatchConfig.player_civ_id if pid == 0 else MatchConfig.get_rival_civ_id(1))
			(_world.get("units_layer") as Node).add_child(unit)
			var facing: float = -1.0 if pid == 0 else 1.0
			unit.global_position = mid + dir * facing * (220.0 + row) + side * col
			PopulationManager.add_unit(pid)
			EventBus.unit_spawned.emit(unit, pid)
			if pid == 0:
				ids_a.append(EntityRegistry.id_of(unit))
			else:
				ids_b.append(EntityRegistry.id_of(unit))
	CommandBus.submit(UnitPointCommand.make(0, "attack_move", ids_a, mid + dir * 300.0))
	CommandBus.submit(UnitPointCommand.make(1, "attack_move", ids_b, mid - dir * 300.0))

## Physics-side attribution, applied when measuring starts (armies exist by
## then): CALIMA_PERF_DISABLE=areas (attack-range Area2Ds), rvo (agent
## avoidance), unit_physics (freeze every unit's _physics_process).
func _apply_combat_disables(disables: PackedStringArray) -> void:
	if disables.is_empty():
		return
	for unit: Node in (_world.get("units_layer") as Node).get_children():
		if not is_instance_valid(unit):
			continue
		for what: String in disables:
			match what:
				"areas":
					var area: Variant = unit.get("attack_range_area")
					if area is Area2D:
						(area as Area2D).monitoring = false
						(area as Area2D).monitorable = false
				"rvo":
					var agent: Variant = unit.get("nav_agent")
					if agent is NavigationAgent2D:
						(agent as NavigationAgent2D).avoidance_enabled = false
				"unit_physics":
					unit.set_physics_process(false)
				"no_velcb":
					var nav: Variant = unit.get("nav_agent")
					if nav is NavigationAgent2D and unit.has_method("_on_velocity_computed") \
							and (nav as NavigationAgent2D).velocity_computed.is_connected(
								Callable(unit, "_on_velocity_computed")):
						(nav as NavigationAgent2D).velocity_computed.disconnect(
							Callable(unit, "_on_velocity_computed"))
				"rvo_lite":
					var ag: Variant = unit.get("nav_agent")
					if ag is NavigationAgent2D:
						(ag as NavigationAgent2D).max_neighbors = 4
						(ag as NavigationAgent2D).neighbor_distance = 48.0
				"phys30":
					Engine.physics_ticks_per_second = 30
				"steps4":
					Engine.max_physics_steps_per_frame = 4
				"steps2":
					Engine.max_physics_steps_per_frame = 2

func _count_units() -> int:
	var n: int = 0
	for unit: Node in (_world.get("units_layer") as Node).get_children():
		if is_instance_valid(unit):
			n += 1
	return n

func _process(delta: float) -> void:
	_t += delta
	match _phase:
		Phase.WARMUP:
			if _t >= WARMUP_SEC:
				_t = 0.0
				if _develop > 0.0:
					_phase = Phase.DEVELOP
					GameManager.set_game_speed(DEVELOP_SPEED)
				else:
					_phase = Phase.SETTLE
		Phase.DEVELOP:
			# delta is already time-scaled, so _t accumulates GAME seconds.
			if _t >= _develop:
				_t = 0.0
				GameManager.set_game_speed(1.0)
				_phase = Phase.SETTLE
		Phase.SETTLE:
			if _t >= SETTLE_SEC:
				_t = 0.0
				_apply_combat_disables(OS.get_environment("CALIMA_PERF_DISABLE").split(",", false))
				_phase = Phase.MEASURE
		Phase.MEASURE:
			var p: float = Performance.get_monitor(Performance.TIME_PROCESS)
			var f: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			_proc_sum += p
			_phys_sum += f
			_worst = maxf(_worst, p + f)
			_frames += 1
			if _t >= _window:
				_report()

func _report() -> void:
	var n: float = float(maxi(_frames, 1))
	print("PERF %-14s | rivals=%d size=%d map=%d res=%d army=%d dev=%ds | process %6.2f ms  physics %6.2f ms  worst %6.1f ms  fps %5.1f  units %4d  real %ds" % [
		_label, MatchConfig.rival_count, MatchConfig.map_size, MatchConfig.map_type,
		MatchConfig.resources, _army, int(_develop),
		_proc_sum * 1000.0 / n, _phys_sum * 1000.0 / n, _worst * 1000.0,
		n / _window, _count_units(),
		(Time.get_ticks_msec() - _real_start_msec) / 1000])
	print("PERF %-14s | nav_agents %d  nav_obstacles %d  nav_polys %d  phys_objects %d  phys_pairs %d  phys_islands %d  nodes %d" % [
		_label,
		int(Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT)),
		int(Performance.get_monitor(Performance.NAVIGATION_OBSTACLE_COUNT)),
		int(Performance.get_monitor(Performance.NAVIGATION_POLYGON_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	print("PERF: done")
	get_tree().quit(0)

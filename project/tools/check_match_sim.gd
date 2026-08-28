extends Node2D

## Headed match simulator: boots a full game like screenshot_runner, fast-
## forwards CALIMA_WARMUP seconds of gameplay at CALIMA_TIMESCALE, then prints
## per-player development stats (age, population, unit/building census,
## stockpiles) at regular intervals so AI stalls and combat anomalies show up
## as numbers instead of needing pixel review.
## Run: CALIMA_WARMUP=900 CALIMA_TIMESCALE=12 CALIMA_RIVALS=3 $GODOT --path project res://tools/check_match_sim.tscn

var _world: Node2D = null

func _ready() -> void:
	if OS.get_environment("CALIMA_SEED").is_empty():
		OS.set_environment("CALIMA_SEED", "42")
	MatchConfig.weather_enabled = false
	GameSettings.ai_debug = true
	MatchConfig.rival_count = 1
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.STANDARD
	var civ_env: String = OS.get_environment("CALIMA_CIV")
	if not civ_env.is_empty():
		MatchConfig.player_civ_id = civ_env
	var rival_env: String = OS.get_environment("CALIMA_RIVAL_CIV")
	if not rival_env.is_empty():
		var civ_list: PackedStringArray = rival_env.split(",", false)
		MatchConfig.rival_civ_ids.clear()
		for c: String in civ_list:
			MatchConfig.rival_civ_ids.append(c.strip_edges())
		MatchConfig.rival_count = MatchConfig.rival_civ_ids.size()
	var rivals_env: String = OS.get_environment("CALIMA_RIVALS")
	if not rivals_env.is_empty():
		MatchConfig.rival_count = int(rivals_env)
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var warmup: float = float(OS.get_environment("CALIMA_WARMUP")) if not OS.get_environment("CALIMA_WARMUP").is_empty() else 300.0
	var tscale: float = float(OS.get_environment("CALIMA_TIMESCALE")) if not OS.get_environment("CALIMA_TIMESCALE").is_empty() else 10.0
	Engine.time_scale = tscale
	var elapsed: float = 0.0
	var step: float = warmup / 6.0
	while elapsed < warmup:
		await get_tree().create_timer(step).timeout
		elapsed += step
		_print_census(elapsed)
	Engine.time_scale = 1.0
	_dump_villager_detail()
	_dump_ai_logs()
	print("MATCH_SIM: done")
	get_tree().quit(0)

func _dump_villager_detail() -> void:
	print("MATCH_SIM drop_off_buildings group:")
	for n: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		var parent: Node = n.get_parent()
		print("    node=%s pid=%s parent=%s parent_pid=%s pos=%s" % [
			n.name, str(n.get("player_id")), parent.name if parent != null else "-",
			str(parent.get("player_id")) if parent != null else "-",
			str((n as Node2D).global_position.round()) if n is Node2D else "-"])
	var units_layer: Node = _world.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return
	var shown: Dictionary = {}
	for u: Node in units_layer.get_children():
		if not (u is Villager):
			continue
		var pid: int = u.get("player_id") as int
		if pid == 0:
			continue
		shown[pid] = (shown.get(pid, 0) as int) + 1
		if (shown[pid] as int) > 3:
			continue
		var v: Villager = u as Villager
		var tgt: String = "-"
		if is_instance_valid(v.gather_target):
			tgt = "%s d=%.0f" % [v.gather_target.name,
				v.global_position.distance_to((v.gather_target as Node2D).global_position)]
		var drop: Node = v._resolve_drop_off()
		print("    P%d villager state=%d carried=%s %.1f/%.1f target=%s drop=%s" % [
			pid, v.current_state, str(v.carried_resource), v.carried_amount,
			v.carry_capacity, tgt, drop.name if is_instance_valid(drop) else "NULL"])

func _dump_ai_logs() -> void:
	for child: Node in _world.get_children():
		if child.get_script() == null:
			continue
		if not (child.get_script() as Script).resource_path.contains("ai_player"):
			continue
		var pid: int = child.get("player_id") as int
		print("MATCH_SIM ai_log P%d:" % pid)
		var lines: Array = child.call("get_debug_log") as Array
		for i: int in range(maxi(0, lines.size() - 12), lines.size()):
			print("    ", lines[i])

func _print_census(t: float) -> void:
	var units_layer: Node = _world.get_node_or_null("UnitsLayer")
	var buildings_layer: Node = _world.get_node_or_null("BuildingsLayer")
	var per_player: Dictionary = {}
	if units_layer != null:
		for u: Node in units_layer.get_children():
			var pid: Variant = u.get("player_id")
			if pid == null:
				continue
			var d: Dictionary = per_player.get(pid as int, {"units": {}, "buildings": {}}) as Dictionary
			var cls: String = u.get_class() if u.get_script() == null else (u.get_script() as Script).get_global_name()
			var units: Dictionary = d["units"] as Dictionary
			units[cls] = (units.get(cls, 0) as int) + 1
			if u is Villager:
				var st: int = u.get("current_state") as int
				var states: Dictionary = d.get("vstates", {}) as Dictionary
				states[st] = (states.get(st, 0) as int) + 1
				d["vstates"] = states
			per_player[pid as int] = d
	if buildings_layer != null:
		for b: Node in buildings_layer.get_children():
			var pid_b: Variant = b.get("player_id")
			if pid_b == null:
				continue
			var d2: Dictionary = per_player.get(pid_b as int, {"units": {}, "buildings": {}}) as Dictionary
			var cls_b: String = b.get_class() if b.get_script() == null else (b.get_script() as Script).get_global_name()
			var bl: Dictionary = d2["buildings"] as Dictionary
			bl[cls_b] = (bl.get(cls_b, 0) as int) + 1
			per_player[pid_b as int] = d2
	# SceneTreeTimers run on scaled time, so t already counts GAME seconds.
	print("MATCH_SIM t=%dm%02ds" % [int(t) / 60, int(t) % 60])
	var pids: Array = per_player.keys()
	pids.sort()
	for pid_i: Variant in pids:
		var pd: Dictionary = per_player[pid_i] as Dictionary
		var age: int = AgeManager.get_age(pid_i as int)
		var pop_d: Dictionary = PopulationManager.get_population(pid_i as int)
		var pop: int = pop_d["current"] as int
		var cap: int = pop_d["cap"] as int
		var res_raw: Dictionary = ResourceManager.get_resources(pid_i as int)
		var res: Dictionary = {}
		for r: Variant in res_raw:
			res[r] = int(res_raw[r] as float)
		print("  P%d age=%d pop=%d/%d res=%s units=%s buildings=%s vstates=%s" % [
			pid_i as int, age, pop, cap, JSON.stringify(res),
			JSON.stringify(pd["units"]), JSON.stringify(pd["buildings"]),
			JSON.stringify(pd.get("vstates", {}))])

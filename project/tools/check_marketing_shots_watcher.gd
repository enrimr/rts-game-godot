extends Node

func _ready() -> void:
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-marketing"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(2.5).timeout
	var world: Node = get_tree().get_first_node_in_group("world")
	var rep: Node = world.get_node_or_null("StateReplicator")
	if rep == null:
		print("MARKETING_SHOTS: no replicator — abort")
		get_tree().quit(1)
		return
	var total: float = rep.call("replay_duration") as float
	print("MARKETING_SHOTS: duration %.0f s" % total)
	var times: Array = []
	var env_t: String = OS.get_environment("CALIMA_MKT_TIMES")
	if not env_t.is_empty():
		for tok: String in env_t.split(","):
			times.append(float(tok))
	else:
		for frac: float in [0.12, 0.25, 0.40, 0.55, 0.70, 0.85, 0.95]:
			times.append(total * frac)
	if OS.get_environment("CALIMA_MKT_SCAN") == "1":
		var step: float = OS.get_environment("CALIMA_MKT_STEP").to_float() if not OS.get_environment("CALIMA_MKT_STEP").is_empty() else 120.0
		var t_scan: float = 60.0
		while t_scan < total:
			rep.call("seek", t_scan)
			var g: float = 0.0
			while (rep.call("replay_time") as float) < t_scan - 0.5 and g < 30.0:
				await get_tree().create_timer(0.25).timeout
				g += 0.25
			await get_tree().create_timer(0.6).timeout
			_scan_report(world, t_scan)
			t_scan += step
		print("MARKETING_SHOTS: scan done")
		get_tree().quit(0)
		return
	var shot_idx: int = 0
	var zoom_env: String = OS.get_environment("CALIMA_MKT_ZOOM")
	if not zoom_env.is_empty():
		world.call("set_zoom", float(zoom_env))
	for t: Variant in times:
		rep.call("seek", t as float)
		var guard: float = 0.0
		while (rep.call("replay_time") as float) < (t as float) - 0.5 and guard < 30.0:
			await get_tree().create_timer(0.25).timeout
			guard += 0.25
		await get_tree().create_timer(1.5).timeout   # let the snapshot stream settle
		# Point the camera at the ACTION: the closest enemy-vs-enemy pair
		# (a battle), else the densest crowd.
		var spot: Vector2 = _hotspot(world, shot_idx)
		shot_idx += 1
		if spot != Vector2.INF:
			world.call("jump_camera_to", spot)
		await get_tree().create_timer(0.8).timeout
		var out: String = "%s/shot_%03d.png" % [dir, int(t as float)]
		get_viewport().get_texture().get_image().save_png(out)
		print("MARKETING_SHOTS: saved %s (spot %s)" % [out, str(spot)])
	print("MARKETING_SHOTS: done")
	get_tree().quit(0)

## Battle finder: midpoint of the closest hostile unit pair; fallback to the
## centroid of the biggest 400 px unit crowd.
func _hotspot(world: Node, idx: int) -> Vector2:
	var units: Array = []
	for u: Variant in (world.get("units_layer") as Node).get_children():
		if is_instance_valid(u) and (u as Node).get("player_id") != null \
				and (u as Node).get("unit_data") != null:
			units.append(u)
	if units.is_empty():
		return Vector2.INF
	var best_d: float = 700.0 * 700.0
	var best_mid: Vector2 = Vector2.INF
	for i: int in range(units.size()):
		var a: Node2D = units[i] as Node2D
		var pid_a: int = a.get("player_id") as int
		for j: int in range(i + 1, units.size()):
			var b: Node2D = units[j] as Node2D
			if (b.get("player_id") as int) == pid_a:
				continue
			var d: float = a.global_position.distance_squared_to(b.global_position)
			if d < best_d:
				best_d = d
				best_mid = (a.global_position + b.global_position) * 0.5
	if best_mid != Vector2.INF:
		return best_mid
	# No contact anywhere: cycle through each player's densest crowd so the
	# shot series tours every town instead of parking on one base.
	var pids: Array = []
	for u: Variant in units:
		var pid: int = (u as Node).get("player_id") as int
		if not pids.has(pid):
			pids.append(pid)
	pids.sort()
	var want: int = pids[idx % pids.size()] as int
	var best_count: int = 0
	var best_pos: Vector2 = (units[0] as Node2D).global_position
	for u: Variant in units:
		if ((u as Node).get("player_id") as int) != want:
			continue
		var count: int = 0
		for v: Variant in units:
			if ((v as Node).get("player_id") as int) == want \
					and (u as Node2D).global_position.distance_to((v as Node2D).global_position) < 400.0:
				count += 1
		if count > best_count:
			best_count = count
			best_pos = (u as Node2D).global_position
	return best_pos

## One line per sample: how close the armies are and how many units each side fields.
func _scan_report(world: Node, t: float) -> void:
	var per_pid: Dictionary = {}
	var units: Array = []
	for u: Variant in (world.get("units_layer") as Node).get_children():
		if is_instance_valid(u) and (u as Node).get("player_id") != null \
				and (u as Node).get("unit_data") != null:
			units.append(u)
			var pid: int = (u as Node).get("player_id") as int
			per_pid[pid] = (per_pid.get(pid, 0) as int) + 1
	var best: float = 1e12
	var mid: Vector2 = Vector2.ZERO
	for i: int in range(units.size()):
		var a: Node2D = units[i] as Node2D
		for j: int in range(i + 1, units.size()):
			var b: Node2D = units[j] as Node2D
			if (b.get("player_id") as int) == (a.get("player_id") as int):
				continue
			var d: float = a.global_position.distance_squared_to(b.global_position)
			if d < best:
				best = d
				mid = (a.global_position + b.global_position) * 0.5
	print("MARKETING_SCAN: t=%d contact=%.0f mid=%s counts=%s" % [
		int(t), sqrt(best) if best < 1e12 else -1.0, str(mid), str(per_pid)])

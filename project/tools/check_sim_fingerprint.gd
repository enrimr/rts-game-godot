extends Node2D

## Determinism probe: boots a match at a fixed seed, runs an exact number of
## PHYSICS TICKS (never wall-clock time) and prints a canonical fingerprint —
## every entity's class/owner/position/health, the per-player stockpiles and
## the full CommandBus log. Run it twice and diff the output: identical means
## the simulation replayed deterministically for that window; the first
## differing line points at the subsystem that still diverges.
##
##   $GODOT --headless --path project res://tools/check_sim_fingerprint.tscn > /tmp/a.txt
##   $GODOT --headless --path project res://tools/check_sim_fingerprint.tscn > /tmp/b.txt
##   diff /tmp/a.txt /tmp/b.txt
##
## Env: CALIMA_SEED (default 4242), CALIMA_MAP (default 1 = STANDARD),
##      CALIMA_TICKS (default 3600 = 60 sim-seconds at 60 Hz)

var _world: Node2D = null

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.STANDARD
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1
	var ticks_env: String = OS.get_environment("CALIMA_TICKS")
	var ticks: int = int(ticks_env) if not ticks_env.is_empty() else 3600

	Engine.time_scale = 8.0
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)

	for _i: int in range(ticks):
		await get_tree().physics_frame

	print("SIM_FINGERPRINT seed=%s map=%d ticks=%d" % [
		OS.get_environment("CALIMA_SEED"), MatchConfig.map_type, ticks])
	_print_census()
	_print_resources()
	_print_log()
	print("SIM_FINGERPRINT: done")
	get_tree().quit(0)

func _print_census() -> void:
	var lines: Array[String] = []
	for unit: Node in (_world.units_layer as Node).get_children():
		if not is_instance_valid(unit):
			continue
		lines.append(_entity_line("unit", unit))
	for building: Node in (_world.buildings_layer as Node).get_children():
		if not is_instance_valid(building):
			continue
		lines.append(_entity_line("bldg", building))
	if is_instance_valid(_world.drop_off):
		lines.append(_entity_line("bldg", _world.drop_off))
	lines.sort()
	for line: String in lines:
		print("  " + line)

func _entity_line(tag: String, node: Node) -> String:
	var pid: Variant = node.get("player_id")
	var hp: Variant = node.get("health")
	var pos: Vector2 = (node as Node2D).global_position
	return "%s %-18s p%s (%.1f, %.1f) hp=%s" % [tag,
		(node.get_script() as Script).resource_path.get_file().get_basename(),
		str(pid) if pid != null else "-", pos.x, pos.y,
		("%.1f" % (hp as float)) if hp != null else "-"]

func _print_resources() -> void:
	for pid: int in [0, 1]:
		print("  res p%d %s" % [pid, JSON.stringify(ResourceManager.get_resources(pid), "", false)])
	print("  rng_state=%d" % MatchRng.get_state())

func _print_log() -> void:
	print("  command log (%d entries):" % CommandBus.log_entries().size())
	for entry: Dictionary in CommandBus.log_entries():
		print("  cmd " + JSON.stringify(entry, "", false))

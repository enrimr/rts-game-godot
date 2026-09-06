extends Node2D

## AI-vs-AI hostility gate: with the human player GONE (all their entities
## removed at match start — the spectator scenario), two mutually hostile AIs
## must find each other and fight. PASS requires, within the tick window:
##   1. an AI "attack" command whose TARGET belongs to the other AI, and
##   2. at least one unit/building casualty on either AI side.
##
##   $GODOT --headless --path project res://tools/check_ai_vs_ai.tscn
##
## Env: CALIMA_SEED (default 4242), CALIMA_TICKS (default 36000 = 10 sim-min).

var _world: Node2D = null
var _ai_losses: Dictionary = {1: 0, 2: 0}
var _first_cross_cmd_tick: int = -1
var _first_casualty_tick: int = -1
var _tick: int = 0
var _wipe_tick: int = 0
var _scan_index: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.STANDARD
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 2
	MatchConfig.player_teams = {}   # FFA: everyone hostile
	var ticks_env: String = OS.get_environment("CALIMA_TICKS")
	var ticks: int = int(ticks_env) if not ticks_env.is_empty() else 36000
	# CALIMA_WIPE_AT delays the player wipe so both AIs develop armies first
	# (the reported scenario is the ENDGAME: the player falls mid-match).
	var wipe_env: String = OS.get_environment("CALIMA_WIPE_AT")
	_wipe_tick = int(wipe_env) if not wipe_env.is_empty() else 1

	Engine.time_scale = 8.0
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.building_destroyed.connect(_on_building_destroyed)

	var report_every: int = maxi(ticks / 6, 1)
	for i: int in range(ticks):
		_tick = i
		await get_tree().physics_frame
		if i == _wipe_tick:
			_wipe_player_zero()
		if i > _wipe_tick and _first_cross_cmd_tick < 0:
			_scan_cross_commands()
		if (i + 1) % report_every == 0:
			print("CHECK_AI_VS_AI tick %d/%d: cross_cmd=%s casualty=%s losses=%s %s" % [
				i + 1, ticks, str(_first_cross_cmd_tick), str(_first_casualty_tick),
				JSON.stringify(_ai_losses, "", false), _ai_status()])
		if _first_cross_cmd_tick >= 0 and _first_casualty_tick >= 0:
			break

	var ok: bool = _first_cross_cmd_tick >= 0 and _first_casualty_tick >= 0
	print("CHECK_AI_VS_AI: after the wipe (tick %d) — first cross-AI attack cmd %+d ticks, first casualty %+d ticks (%s / %s sim-min after)" % [
		_wipe_tick,
		(_first_cross_cmd_tick - _wipe_tick) if _first_cross_cmd_tick >= 0 else -1,
		(_first_casualty_tick - _wipe_tick) if _first_casualty_tick >= 0 else -1,
		("%.1f" % (float(_first_cross_cmd_tick - _wipe_tick) / 3600.0)) if _first_cross_cmd_tick >= 0 else "never",
		("%.1f" % (float(_first_casualty_tick - _wipe_tick) / 3600.0)) if _first_casualty_tick >= 0 else "never"])
	print("CHECK_AI_VS_AI: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _ai_status() -> String:
	var parts: Array[String] = []
	# Untyped loop var: the freed player TC is still in the children array the
	# frame after the wipe, and a typed `child: Node` raises before any guard.
	for child: Variant in _world.get_children():
		if not is_instance_valid(child):
			continue
		var script: Script = (child as Node).get_script() as Script
		if script == null or not script.resource_path.contains("ai_player"):
			continue
		var mil: Variant = child.get("_military")
		parts.append("P%d[mil=%d atk_t=%.0f/%.0f tc=%s etc=%s]" % [
			child.get("player_id") as int,
			mil.call("count_military") as int,
			child.get("_attack_timer") as float,
			mil.call("get_effective_attack_interval") as float,
			str(is_instance_valid(child.get("town_center") as Node)),
			str(is_instance_valid(child.get("enemy_town_center") as Node))])
	return " ".join(parts)

func _wipe_player_zero() -> void:
	# CALIMA_SURVIVORS leaves that many player villagers alive (the reported
	# scenario: the player wiped out except two villagers in the AI's zone).
	var survivors: int = int(OS.get_environment("CALIMA_SURVIVORS")) \
		if not OS.get_environment("CALIMA_SURVIVORS").is_empty() else 0
	for u: Node in (_world.units_layer as Node).get_children():
		if u.get("player_id") != null and (u.get("player_id") as int) == 0:
			if survivors > 0 and u.has_method("order_gather"):
				survivors -= 1
				continue
			u.free()
	var bld: Array = (_world.buildings_layer as Node).get_children()
	var drop: Variant = _world.get("drop_off")
	if drop is Node and is_instance_valid(drop as Node):
		bld.append(drop)
	for b: Variant in bld:
		if (b as Node).get("player_id") != null and ((b as Node).get("player_id") as int) == 0:
			(b as Node).free()
	print("CHECK_AI_VS_AI: player 0 wiped — AIs are alone now")

## An AI "attack"/point command aimed at the OTHER AI's entity.
func _scan_cross_commands() -> void:
	var log: Array = CommandBus.log_entries()
	var fresh: Array = log.slice(_scan_index)
	_scan_index = log.size()
	for entry: Dictionary in fresh:
		var pid: int = entry.get("player", -1) as int
		if pid != 1 and pid != 2:
			continue
		if entry.get("kind", "") as String != "unit_target":
			continue
		if entry.get("verb", "") as String != "attack":
			continue
		var target: Node = EntityRegistry.resolve(entry.get("target", 0) as int)
		if target == null:
			continue
		var tpid: Variant = target.get("player_id")
		# Strictly the OTHER AI: own-flock slaughters and wild animals don't count.
		if tpid != null and (tpid as int) in [1, 2] and (tpid as int) != pid:
			_first_cross_cmd_tick = _tick
			return

func _on_unit_died(unit: Node, owner_id: int) -> void:
	if _tick <= _wipe_tick:
		return   # pre-wipe losses belong to the war against the player
	if owner_id == 1 or owner_id == 2:
		# Animal slaughter is economy, not war.
		if unit is Animal:
			return
		_ai_losses[owner_id] = (_ai_losses[owner_id] as int) + 1
		if _first_casualty_tick < 0:
			_first_casualty_tick = _tick

func _on_building_destroyed(_building: Node, owner_id: int) -> void:
	if _tick <= _wipe_tick:
		return
	if owner_id == 1 or owner_id == 2:
		if _first_casualty_tick < 0:
			_first_casualty_tick = _tick

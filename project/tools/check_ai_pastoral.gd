extends Node2D

## AI pastoral-economy gate: boots a fixed-seed skirmish and verifies the AI
## actually LIVES the new pastoral loop end-to-end —
##   1. builds a Mill,
##   2. trains a Presa Canario at it,
##   3. sends the dog herding (a "herd" UnitTargetCommand in the match log).
## Also reports (informational, not gating) watch towers built and slaughter
## orders issued. Prints one PASS/FAIL line and exits 0/1.
##
##   $GODOT --headless --path project res://tools/check_ai_pastoral.tscn
##
## Env: CALIMA_SEED (default 4242), CALIMA_TICKS (default 24000 = 6.7 sim-min:
## one awaited physics frame is always 1/60 sim-s — time_scale only compresses
## the WALL clock, ~50 s at 8x). The run early-exits once all three gates pass.

const AI_PID: int = 1

var _world: Node2D = null

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1
	var ticks_env: String = OS.get_environment("CALIMA_TICKS")
	var ticks: int = int(ticks_env) if not ticks_env.is_empty() else 24000

	Engine.time_scale = 8.0
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)

	var report_every: int = maxi(ticks / 4, 1)
	for i: int in range(ticks):
		await get_tree().physics_frame
		if (i + 1) % report_every == 0:
			print("CHECK_AI_PASTORAL tick %d/%d: mill=%s dog=%s herd=%s" % [
				i + 1, ticks, str(_ai_mill_count() > 0), str(_ai_dog_count() > 0),
				str(_herd_commands() > 0)])
		# CALIMA_FULL=1 rides out the whole window (e.g. to watch Feudal towers
		# go up) instead of exiting at the first all-green tick.
		if OS.get_environment("CALIMA_FULL").is_empty() \
				and _ai_mill_count() > 0 and _ai_dog_count() > 0 and _herd_commands() > 0:
			break

	var mills: int = _ai_mill_count()
	var dogs: int = _ai_dog_count()
	var herds: int = _herd_commands()
	var towers: int = _ai_tower_count()
	var slaughters: int = _slaughter_commands()
	print("CHECK_AI_PASTORAL: AI mills=%d dogs=%d herd_cmds=%d towers=%d slaughter_cmds=%d" % [
		mills, dogs, herds, towers, slaughters])

	_print_ai_census()
	var ok: bool = mills > 0 and dogs > 0 and herds > 0
	print("CHECK_AI_PASTORAL: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Diagnostic footprint: what the AI actually built/holds when the gate ends.
func _print_ai_census() -> void:
	var buildings: Dictionary = {}
	for b: Node in (_world.buildings_layer as Node).get_children():
		if not is_instance_valid(b) or b.get("player_id") == null \
				or (b.get("player_id") as int) != AI_PID:
			continue
		var bid: String = "?"
		var bdata: Variant = b.get("building_data")
		if bdata != null:
			bid = (bdata as Resource).get("id") as String
		buildings[bid] = (buildings.get(bid, 0) as int) + 1
	print("CHECK_AI_PASTORAL: AI buildings=%s res=%s" % [
		JSON.stringify(buildings, "", false),
		JSON.stringify(ResourceManager.get_resources(AI_PID), "", false)])

func _ai_mill_count() -> int:
	var count: int = 0
	for b: Node in (_world.buildings_layer as Node).get_children():
		if is_instance_valid(b) and b is Mill and (b.get("player_id") as int) == AI_PID:
			count += 1
	return count

func _ai_tower_count() -> int:
	var count: int = 0
	for b: Node in (_world.buildings_layer as Node).get_children():
		if is_instance_valid(b) and b is WatchTower and (b.get("player_id") as int) == AI_PID:
			count += 1
	return count

func _ai_dog_count() -> int:
	var count: int = 0
	for u: Node in (_world.units_layer as Node).get_children():
		if is_instance_valid(u) and u.has_method("order_herd") \
				and u.get("player_id") != null and (u.get("player_id") as int) == AI_PID:
			count += 1
	return count

func _herd_commands() -> int:
	return _count_commands("herd")

func _slaughter_commands() -> int:
	# The flock slaughter is an AI-issued villager attack on an own Animal —
	# in the log that is an "attack" UnitTargetCommand from the AI's player_id.
	return _count_commands("attack")

func _count_commands(verb: String) -> int:
	var count: int = 0
	for entry: Dictionary in CommandBus.log_entries():
		if entry.get("kind", "") as String != "unit_target":
			continue
		if entry.get("player", -1) as int != AI_PID:
			continue
		if entry.get("verb", "") as String == verb:
			count += 1
	return count

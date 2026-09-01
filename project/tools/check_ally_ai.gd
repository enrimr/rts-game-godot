extends Node2D

## Gate: an AI allied with the player must send an assist squad (attack-move
## + team ping + "assist" ally_message) when the player is raided at home.

var _assist_from: int = -1

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("ALLY_AI TIMEOUT")
		get_tree().quit(1))
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.weather_enabled = false
	MatchConfig.forced_seed = 4242
	MatchConfig.rival_count = 2
	MatchConfig.rival_civ_ids = ["franks", "britons"] as Array[String]
	MatchConfig.player_teams = {0: 1, 1: 1}
	EventBus.ally_message.connect(func(pid: int, kind: String) -> void:
		if kind == "assist":
			_assist_from = pid)
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await get_tree().create_timer(2.0).timeout

	# Give the allied AI an army it can spare.
	var tcs: Dictionary = world.get("_ai_town_centers") as Dictionary
	var ally_tc: Node2D = tcs.get(1) as Node2D
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	for i: int in range(5):
		var m: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
		m.set("player_id", 1)
		m.set("civ_id", "franks")
		(world.get("units_layer") as Node).add_child(m)
		m.global_position = ally_tc.global_position + Vector2(60.0 + i * 24.0, 40.0)
		EventBus.unit_spawned.emit(m, 1)

	# An enemy raider jumps a player villager at the player's base.
	var villager: Node2D = null
	for u: Node in (world.get("units_layer") as Node).get_children():
		if (u.get("player_id") as int) == 0 and u.has_method("order_gather"):
			villager = u as Node2D
			break
	var raider: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	raider.set("player_id", 2)
	raider.set("civ_id", "britons")
	(world.get("units_layer") as Node).add_child(raider)
	raider.global_position = villager.global_position + Vector2(40.0, 0.0)
	EventBus.unit_spawned.emit(raider, 2)
	raider.call("order_attack", villager)
	print("ALLY_AI raid started")

	var deadline: float = Time.get_ticks_msec() / 1000.0 + 25.0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().create_timer(0.5).timeout
		if _assist_from == 1:
			var assist_cmd: bool = false
			for entry: Dictionary in CommandBus.log_entries():
				if (entry.get("player", -1) as int) == 1 \
						and (entry.get("kind", "") as String) == "unit_point":
					assist_cmd = true
			print("ALLY_AI assist message from AI 1, squad command logged=%s" % str(assist_cmd))
			if assist_cmd:
				print("ALLY_AI ok")
				get_tree().quit(0)
				return
	print("ALLY_AI FAIL — the allied AI never came (assist_from=%d)" % _assist_from)
	get_tree().quit(1)

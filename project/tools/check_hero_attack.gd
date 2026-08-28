extends Node2D

## Repro: can melee units (hero included) damage buildings after the combat
## machine refactor? Boots a real match, teleports the hero and a militia-line
## unit next to the enemy TC, issues order_attack and reports health deltas.
## Run: $GODOT --path project res://tools/check_hero_attack.tscn

var _world: Node2D = null

func _ready() -> void:
	if OS.get_environment("CALIMA_SEED").is_empty():
		OS.set_environment("CALIMA_SEED", "42")
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout

	var units_layer: Node = _world.get_node_or_null("UnitsLayer")
	var buildings_layer: Node = _world.get_node_or_null("BuildingsLayer")
	var hero: Node2D = null
	for u: Node in units_layer.get_children():
		if u is HeroUnit and (u.get("player_id") as int) == 0:
			hero = u as Node2D
	var enemy_tc: Node2D = null
	for b: Node in buildings_layer.get_children():
		if (b.get("player_id") as int) == 1:
			enemy_tc = b as Node2D
	if hero == null or enemy_tc == null:
		printerr("HERO_ATTACK: missing hero=", hero, " tc=", enemy_tc)
		get_tree().quit(1)
		return

	# Click-picking test: probe _find_enemy_building_at with world positions
	# derived from SCREEN offsets around the TC origin (what the player clicks).
	var probes: Dictionary = {
		"origin":          Vector2.ZERO,
		"facade_mid":      Vector2(0.0, -40.0),
		"roof":            Vector2(0.0, -80.0),
		"left_wall":       Vector2(-50.0, -30.0),
		"far_above_miss":  Vector2(0.0, -220.0),
		"far_side_miss":   Vector2(-260.0, 0.0),
	}
	print("HERO_ATTACK massing meta: top=%s bot=%s half=%s" % [
		str(enemy_tc.get_meta("massing_top_y")) if enemy_tc.has_meta("massing_top_y") else "-",
		str(enemy_tc.get_meta("massing_bot_y")) if enemy_tc.has_meta("massing_bot_y") else "-",
		str(((enemy_tc.get_node_or_null("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size * 0.5) if enemy_tc.get_node_or_null("CollisionShape2D") != null else "-"])
	for label: String in probes:
		var wpos: Vector2 = enemy_tc.global_position + IsoProjection.screen_to_world(probes[label] as Vector2)
		var hit: Node = _world.call("_find_enemy_building_at", wpos)
		print("HERO_ATTACK pick[%s] -> %s" % [label, hit.name if hit != null else "null"])

	var hp0: float = enemy_tc.get("health") as float
	print("HERO_ATTACK: tc=%s hp=%.1f hero_reach=%.1f" % [enemy_tc.name, hp0, hero.call("_attack_reach_to", enemy_tc)])
	hero.global_position = enemy_tc.global_position + Vector2(90.0, 0.0)
	hero.call("order_attack", enemy_tc)
	Engine.time_scale = 5.0
	for i: int in range(6):
		await get_tree().create_timer(2.5).timeout
		var dist: float = hero.global_position.distance_to(enemy_tc.global_position)
		print("HERO_ATTACK t+%.0fs state=%d dist=%.0f target_valid=%s tc_hp=%.1f" % [
			(i + 1) * 2.5, hero.get("current_state") as int, dist,
			str(is_instance_valid(hero.get("attack_target"))), enemy_tc.get("health") as float])
	Engine.time_scale = 1.0
	var hp1: float = enemy_tc.get("health") as float
	print("HERO_ATTACK: RESULT delta=%.1f (%s)" % [hp0 - hp1, "DAMAGE OK" if hp1 < hp0 else "NO DAMAGE"])
	get_tree().quit(0)

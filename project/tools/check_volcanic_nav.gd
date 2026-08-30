extends Node2D

## Regression gate for pathfinding around impassable terrain zones: on a
## Volcanic Coast map, a land unit ordered to the far side of a caldera must
## walk AROUND it and arrive. Before the zones were carved into the navmesh
## they were RVO-only obstacles, so paths crossed the lava and units ground to
## a halt against the rim (speed multiplier 0) — the playtest screenshot with
## a whole army parked on the caldera edge.
## Run: $GODOT --headless --path project res://tools/check_volcanic_nav.tscn
## Env: CALIMA_SEED (default 4242)

var _failures: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	MatchConfig.map_type = MatchConfig.MapType.VOLCANIC_COAST
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1
	Engine.time_scale = 4.0

	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	var caldera: Dictionary = {}
	for z: Dictionary in TerrainManager.get_zones():
		if (z["type"] as TerrainManager.TerrainType) == TerrainManager.TerrainType.CALDERA:
			if caldera.is_empty() or (z["radius"] as float) > (caldera["radius"] as float):
				caldera = z
	if caldera.is_empty():
		print("VOLCANIC_NAV: FAIL — no caldera zone on a Volcanic Coast map")
		get_tree().quit(1)
		return
	var center: Vector2 = caldera["center"] as Vector2
	var radius: float = caldera["radius"] as float
	var start: Vector2 = TerrainManager.nearest_passable(
		center + Vector2(radius + 160.0, 0.0), "castellanos")
	var goal: Vector2 = TerrainManager.nearest_passable(
		center - Vector2(radius + 160.0, 0.0), "castellanos")
	print("VOLCANIC_NAV caldera c=(%.0f,%.0f) r=%.0f start=(%.0f,%.0f) goal=(%.0f,%.0f)" % [
		center.x, center.y, radius, start.x, start.y, goal.x, goal.y])

	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	unit.set("player_id", 0)
	unit.set("civ_id", "castellanos")
	(world.units_layer as Node).add_child(unit)
	unit.global_position = start
	await get_tree().process_frame

	# Layer sanity: traversal civs ride the malpaís mesh, everyone else layer 1.
	var guanche: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	guanche.set("player_id", 0)
	guanche.set("civ_id", "guanches")
	(world.units_layer as Node).add_child(guanche)
	guanche.global_position = start + Vector2(40.0, 0.0)
	await get_tree().process_frame
	var lay_c: int = (unit.get("nav_agent") as NavigationAgent2D).navigation_layers
	var lay_g: int = (guanche.get("nav_agent") as NavigationAgent2D).navigation_layers
	if lay_c != 1 or lay_g != NavMeshBuilder.MALPAIS_LAYER:
		print("    FAIL: nav layers castellanos=%d (want 1) guanches=%d (want %d)" % [
			lay_c, lay_g, NavMeshBuilder.MALPAIS_LAYER])
		_failures += 1

	CommandBus.submit(UnitPointCommand.make(0, "move",
		[EntityRegistry.id_of(unit)] as Array[int], goal))

	var min_center_dist: float = INF
	var reached: bool = false
	for _i: int in range(240):   # up to 60 sim-seconds
		await get_tree().create_timer(0.25).timeout
		min_center_dist = minf(min_center_dist, unit.global_position.distance_to(center))
		if unit.global_position.distance_to(goal) < 80.0:
			reached = true
			break

	print("    reached=%s min_dist_to_caldera=%.0f (radius %.0f)" % [
		str(reached), min_center_dist, radius])
	if not reached:
		print("    FAIL: the unit never made it around the caldera")
		_failures += 1
	if min_center_dist < radius * 0.8:
		print("    FAIL: the path cut through the caldera")
		_failures += 1

	print("VOLCANIC_NAV: %s" % ("done" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

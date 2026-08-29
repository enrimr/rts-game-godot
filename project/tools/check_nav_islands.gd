extends Node2D

## Regression harness for the runtime navmesh rebake (`WorldPlacement`).
##
## The rebake that runs ~1 s into a match re-bakes the *land* region from
## scratch. If it uses the full-map rect as walkable surface it silently erases
## the island carving of an Islands map and land units get a walking route
## across open sea (transports become pointless). This harness boots a real
## match, then asks the navigation server for a LAND path (navigation_layers = 1,
## what every land unit uses) between the two town centers, before and after the
## rebake, and reports how many waypoints sit on open water.
##
## Expected: 0 sea waypoints on Islands at both samples; on land maps the same
## query reaches the enemy town center normally.
## Run: CALIMA_MAP=4 $GODOT --headless --path project res://tools/check_nav_islands.tscn
## Env: CALIMA_MAP (default 4 = ISLANDS), CALIMA_SEED (default 4242)

var _world: Node2D = null
var _failures: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.ISLANDS
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame

	print("NAV_ISLANDS map_type=%d" % MatchConfig.map_type)
	_report("right after generation")
	# The rebake is debounced by WorldPlacement.NAV_REBAKE_DELAY (1 s) and the
	# bake itself is async, so leave room for both.
	await get_tree().create_timer(2.5).timeout
	_report("after the nav rebake")

	print("NAV_ISLANDS: %s" % ("done" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _report(label: String) -> void:
	var region: NavigationRegion2D = _world.get_node("NavigationRegion2D") as NavigationRegion2D
	var poly: NavigationPolygon = region.navigation_polygon
	print("--- %s ---" % label)
	print("    land navmesh: outlines=%d polygons=%d" % [
		poly.get_outline_count() if poly != null else -1,
		poly.get_polygon_count() if poly != null else -1])

	var from: Vector2 = (_world.drop_off as Node2D).global_position
	var to: Vector2 = Vector2.ZERO
	for pid: Variant in (_world._ai_town_centers as Dictionary):
		to = ((_world._ai_town_centers as Dictionary)[pid] as Node2D).global_position
		break

	var params: NavigationPathQueryParameters2D = NavigationPathQueryParameters2D.new()
	params.map = region.get_navigation_map()
	params.navigation_layers = 1
	params.start_position = from
	params.target_position = to
	var result: NavigationPathQueryResult2D = NavigationPathQueryResult2D.new()
	NavigationServer2D.query_path(params, result)

	var path: PackedVector2Array = result.path
	var sea_points: int = 0
	for pt: Vector2 in path:
		if TerrainManager.is_ocean(pt):
			sea_points += 1
	var gap: int = roundi(path[path.size() - 1].distance_to(to)) if path.size() > 0 else -1
	print("    land path own TC → enemy TC: points=%d ends %d px short, %d over open sea" % [
		path.size(), gap, sea_points])

	if MatchConfig.map_type == MatchConfig.MapType.ISLANDS:
		if sea_points > 0:
			print("    FAIL: land units can walk to the enemy island")
			_failures += 1
	elif gap > 200:
		print("    FAIL: no land route on a land map")
		_failures += 1

extends Node2D

## Regression harness for the Islands map layout and its two navigation meshes.
##
## Three failure modes this catches:
##  1. Islands overlapping each other (they visually merge and land units get a
##     route between players) or spilling past the map boundary.
##  2. An invalid ocean NavigationPolygon — overlapping hole outlines make
##     Godot's convex partition fail, the mesh ends up with 0 polygons and every
##     ship is frozen (it can't path anywhere).
##  3. Ships unable to sail between islands even with a valid mesh (spawn point
##     outside the walkable surface, or no route at all).
##
## Run: CALIMA_RIVALS=3 CALIMA_MAP_SIZE=0 $GODOT --headless --path project \
##          res://tools/check_islands_layout.tscn
## Env: CALIMA_RIVALS (default 1), CALIMA_MAP_SIZE (0 small/1 medium/2 large,
##      default 1), CALIMA_SEED (default 4242)

# Minimum open-water channel required between two islands (px).
const MIN_CHANNEL: float = 120.0

var _world: Node2D = null
var _failures: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	var rivals_env: String = OS.get_environment("CALIMA_RIVALS")
	var size_env: String = OS.get_environment("CALIMA_MAP_SIZE")
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = int(rivals_env) if not rivals_env.is_empty() else 1
	MatchConfig.map_size = int(size_env) if not size_env.is_empty() else MatchConfig.MapSize.MEDIUM

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	# The NavigationServer syncs regions on its own schedule; on slow machines
	# (CI runners) two frames are not enough and the ocean queries below answer
	# garbage — poll until the map responds (same cure as check_nav_islands).
	await _wait_ocean_synced(8.0)

	print("ISLANDS_LAYOUT players=%d map_size=%d map_half=%d seed=%s" % [
		MatchConfig.rival_count + 1, MatchConfig.map_size,
		roundi(MatchConfig.get_map_half()), OS.get_environment("CALIMA_SEED")])
	_check_geometry()
	_check_meshes()
	_check_ship_route()

	print("ISLANDS_LAYOUT: %s" % ("done" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _fail(msg: String) -> void:
	print("    FAIL: %s" % msg)
	_failures += 1

func _wait_ocean_synced(timeout_sec: float) -> void:
	var region: NavigationRegion2D = _world.get_node_or_null(
		"OceanNavigationRegion2D") as NavigationRegion2D
	if region == null:
		return
	var probe: Vector2 = TerrainManager.nearest_ocean((_world.drop_off as Node2D).global_position)
	var deadline: int = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var snapped: Vector2 = NavigationServer2D.map_get_closest_point(
			region.get_navigation_map(), probe)
		if probe.distance_to(snapped) < 80.0:
			return
		await get_tree().create_timer(0.4).timeout

# ── Land polygon layout ─────────────────────────────────────────────────────

func _check_geometry() -> void:
	var polys: Array = TerrainManager.get_land_polys()
	var half: float = MatchConfig.get_map_half()
	print("--- land polygons: %d (islands + islets) ---" % polys.size())

	var overlaps: int = 0
	var min_gap: float = INF
	for i: int in range(polys.size()):
		var a: PackedVector2Array = polys[i] as PackedVector2Array
		for j: int in range(i + 1, polys.size()):
			var b: PackedVector2Array = polys[j] as PackedVector2Array
			if not Geometry2D.intersect_polygons(a, b).is_empty():
				overlaps += 1
				print("    polys %d and %d overlap" % [i, j])
				min_gap = 0.0
				continue
			min_gap = minf(min_gap, _poly_gap(a, b))
	print("    overlapping pairs=%d  narrowest channel=%s px" % [
		overlaps, "n/a" if min_gap == INF else str(roundi(min_gap))])
	if overlaps > 0:
		_fail("land polygons overlap — islands merge into one land mass")
	elif min_gap < MIN_CHANNEL:
		_fail("channel of %d px is narrower than the %d px minimum" % [
			roundi(min_gap), roundi(MIN_CHANNEL)])

	var outside: int = 0
	for p: Variant in polys:
		for pt: Vector2 in (p as PackedVector2Array):
			if absf(pt.x) > half or absf(pt.y) > half:
				outside += 1
	print("    vertices outside the map boundary: %d" % outside)
	if outside > 0:
		_fail("land spills past the ±%d boundary the ocean mesh is cut to" % roundi(half))

func _poly_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best: float = INF
	for pa: Vector2 in a:
		for pb: Vector2 in b:
			best = minf(best, pa.distance_to(pb))
	return best

# ── Navigation meshes ───────────────────────────────────────────────────────

func _check_meshes() -> void:
	print("--- navigation meshes ---")
	for entry: Array in [["NavigationRegion2D", "land"], ["OceanNavigationRegion2D", "ocean"]]:
		var region: NavigationRegion2D = _world.get_node_or_null(entry[0] as String) as NavigationRegion2D
		if region == null:
			_fail("%s region missing" % entry[1])
			continue
		var poly: NavigationPolygon = region.navigation_polygon
		var count: int = poly.get_polygon_count() if poly != null else -1
		print("    %s: polygons=%d" % [entry[1], count])
		if count <= 0:
			_fail("%s mesh is empty — nothing can move on it" % entry[1])

# ── Ships ───────────────────────────────────────────────────────────────────

## Sails from the water next to the player's town center (where a dock would
## spawn its ships) to the water next to a rival's island.
func _check_ship_route() -> void:
	print("--- ship route (navigation layer 2) ---")
	var ocean_region: NavigationRegion2D = _world.get_node_or_null(
		"OceanNavigationRegion2D") as NavigationRegion2D
	if ocean_region == null:
		return
	var from: Vector2 = TerrainManager.nearest_ocean((_world.drop_off as Node2D).global_position)
	var to: Vector2 = Vector2.ZERO
	for pid: Variant in (_world._ai_town_centers as Dictionary):
		to = TerrainManager.nearest_ocean(
			((_world._ai_town_centers as Dictionary)[pid] as Node2D).global_position)
		break
	if from == Vector2.ZERO or to == Vector2.ZERO:
		_fail("no ocean tile next to a town center — docks would spawn ships on land")
		return

	var nav_map: RID = ocean_region.get_navigation_map()
	var snap_from: float = from.distance_to(NavigationServer2D.map_get_closest_point(nav_map, from))
	var snap_to: float = to.distance_to(NavigationServer2D.map_get_closest_point(nav_map, to))
	print("    spawn point sits %d px from the ocean mesh (target %d px)" % [
		roundi(snap_from), roundi(snap_to)])
	if snap_from > 80.0:
		_fail("a ship spawned at the dock would start off-mesh and never move")

	var params: NavigationPathQueryParameters2D = NavigationPathQueryParameters2D.new()
	params.map = nav_map
	params.navigation_layers = 2
	params.start_position = from
	params.target_position = to
	var result: NavigationPathQueryResult2D = NavigationPathQueryResult2D.new()
	NavigationServer2D.query_path(params, result)
	var path: PackedVector2Array = result.path
	var gap: int = roundi(path[path.size() - 1].distance_to(to)) if path.size() > 0 else -1
	var on_land: int = 0
	for pt: Vector2 in path:
		if not TerrainManager.is_ocean(pt):
			on_land += 1
	print("    own island → rival island: points=%d ends %d px short, %d over land" % [
		path.size(), gap, on_land])
	if path.size() < 2 or gap > 200:
		_fail("ships cannot sail from their island to the rival's")

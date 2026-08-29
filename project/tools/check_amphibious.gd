extends Node2D

## Regression harness for the Atlantes amphibious identity (GDD M6).
##
## Three things have to hold in a real match, and none of them can be checked
## from a unit test because they all depend on the baked navigation meshes:
##
## 1. A Tidecaller ordered into open water actually swims: it gets a path on the
##    amphibious mesh and leaves the island. The land and ocean meshes are each
##    baked with agent_radius 10, so they stop ~10 px short of the shoreline and
##    never share an edge — giving the unit both layers would NOT work, hence the
##    dedicated AmphibiousNavigationRegion2D.
## 2. A regular Atlantes land unit stays dry: its destination is clamped back to
##    the beach. Before UnitBase.is_amphibious existed the civ flag alone opened
##    the ocean to every Atlantes unit, whose nav target then sat off the land
##    mesh — the unit froze in place, exactly like the fishing boats did.
## 3. Passengers unloaded from a Transport Ship land on solid ground, never in
##    the surf.
##
## Run: $GODOT --headless --path project res://tools/check_amphibious.tscn
## Env: CALIMA_SEED (default 4242)

const SWIM_FRAMES: int = 240          # ~4 s of physics at 60 Hz
const MIN_SWIM_DISTANCE: float = 60.0 # px of progress that proves it moved

var _world: Node2D = null
var _failures: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	MatchConfig.map_type = MatchConfig.MapType.ISLANDS
	MatchConfig.player_civ_id = "atlantes"
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	# Let the debounced navmesh rebake land before measuring, so the harness
	# checks the mesh the match actually runs on.
	await get_tree().create_timer(2.5).timeout

	print("AMPHIBIOUS map_type=%d civ=%s" % [MatchConfig.map_type, MatchConfig.player_civ_id])
	_report_meshes()
	await _check_tidecaller_swims()
	await _check_land_unit_stays_dry()
	_check_disembark()

	print("AMPHIBIOUS: %s" % ("done" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _fail(msg: String) -> void:
	print("    FAIL: %s" % msg)
	_failures += 1

func _shore_position() -> Vector2:
	return (_world.drop_off as Node2D).global_position

func _report_meshes() -> void:
	for region_name: String in ["NavigationRegion2D", "OceanNavigationRegion2D",
			"AmphibiousNavigationRegion2D"]:
		var region: NavigationRegion2D = _world.get_node_or_null(region_name) as NavigationRegion2D
		if region == null:
			_fail("%s is missing from the world scene" % region_name)
			continue
		var poly: NavigationPolygon = region.navigation_polygon
		var polygons: int = poly.get_polygon_count() if poly != null else -1
		print("    %s: layers=%d polygons=%d" % [region_name, region.navigation_layers, polygons])
		if polygons <= 0:
			_fail("%s has an empty mesh" % region_name)

func _spawn(path: String, pos: Vector2) -> Node2D:
	var unit: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	unit.set("player_id", 0)
	_world.units_layer.add_child(unit)
	unit.global_position = pos
	return unit

## 1 — the Tidecaller swims out to sea.
func _check_tidecaller_swims() -> void:
	# Start on the beach: the nearest water to the town center, clamped back to
	# land with a land-only civ so the unit begins a step away from the surf.
	var start: Vector2 = TerrainManager.nearest_passable(
		TerrainManager.nearest_ocean(_shore_position()), "guanches")
	var unit: Node2D = _spawn("res://scenes/units/tidecaller.tscn", start)
	await get_tree().process_frame
	print("--- tidecaller ---")
	print("    amphibious=%s" % str(unit.call("is_amphibious")))
	if not (unit.call("is_amphibious") as bool):
		_fail("the Tidecaller does not report itself amphibious")

	var target: Vector2 = TerrainManager.nearest_ocean(_shore_position())
	# Push the goal well past the shallow band so the route has to cross water.
	target += (target - _shore_position()).normalized() * 400.0
	unit.call("order_move", target)
	await get_tree().process_frame
	var agent: NavigationAgent2D = unit.get_node("NavigationAgent2D") as NavigationAgent2D
	print("    nav target=%s ocean=%s path_points=%d" % [
		str(agent.target_position.round()), str(TerrainManager.is_ocean(agent.target_position)),
		agent.get_current_navigation_path().size()])
	if not TerrainManager.is_ocean(agent.target_position):
		_fail("the swim order was clamped back to land")
	if agent.get_current_navigation_path().size() < 2:
		_fail("no amphibious path to open water")

	for i: int in range(SWIM_FRAMES):
		await get_tree().physics_frame
		if (i + 1) % 60 == 0:
			print("    t=%.1fs pos=%s %s state=%s finished=%s" % [
				float(i + 1) / 60.0, str(unit.global_position.round()),
				"water" if TerrainManager.is_ocean(unit.global_position) else "land",
				str(unit.get("current_state")), str(agent.is_navigation_finished())])
	var travelled: float = unit.global_position.distance_to(start)
	print("    travelled %d px, now in %s" % [
		roundi(travelled), "water" if TerrainManager.is_ocean(unit.global_position) else "land"])
	if travelled < MIN_SWIM_DISTANCE:
		_fail("the Tidecaller never moved (%d px)" % roundi(travelled))
	elif not TerrainManager.is_ocean(unit.global_position):
		_fail("the Tidecaller stopped at the water's edge")
	unit.queue_free()

## 2 — an ordinary Atlantes unit refuses the same order.
func _check_land_unit_stays_dry() -> void:
	var start: Vector2 = TerrainManager.nearest_passable(_shore_position(), "atlantes")
	var unit: Node2D = _spawn("res://scenes/units/militia.tscn", start)
	unit.set("civ_id", "atlantes")
	await get_tree().process_frame
	print("--- atlantes militia ---")
	var target: Vector2 = TerrainManager.nearest_ocean(_shore_position())
	unit.call("order_move", target)
	await get_tree().process_frame
	var agent: NavigationAgent2D = unit.get_node("NavigationAgent2D") as NavigationAgent2D
	print("    amphibious=%s nav target ocean=%s" % [
		str(unit.call("is_amphibious")), str(TerrainManager.is_ocean(agent.target_position))])
	if unit.call("is_amphibious") as bool:
		_fail("a militia reports itself amphibious")
	if TerrainManager.is_ocean(agent.target_position):
		_fail("a land unit was sent into the sea — its nav target is off-mesh")
	unit.queue_free()

## 3 — disembarking puts passengers ashore, amphibious or not.
func _check_disembark() -> void:
	var water: Vector2 = TerrainManager.nearest_ocean(_shore_position())
	var transport: Node2D = _spawn("res://scenes/units/transport_ship.tscn", water)
	var passenger: Node2D = _spawn("res://scenes/units/tidecaller.tscn", water)
	print("--- disembark ---")
	if not (transport.call("board", passenger) as bool):
		_fail("the Tidecaller could not board the transport")
		return
	transport.call("unload_all")
	var dropped: Vector2 = passenger.global_position
	print("    dropped at %s, %s" % [
		str(dropped.round()), "water" if TerrainManager.is_ocean(dropped) else "land"])
	if TerrainManager.is_ocean(dropped):
		_fail("the passenger was dropped in the water")

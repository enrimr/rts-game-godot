extends Node2D

## Regression harness for the runtime navmesh rebake against diagonal footprints.
##
## Two buildings placed diagonally on the 16 px grid can leave a 20 px carved gap
## on both axes; inflated by the 10 px agent radius the two holes meet at exactly
## one point, Godot's convex partition fails and the bake returns an EMPTY mesh
## for the whole board. Before NavMeshBuilder.RADIUS_NUDGE that meant every
## rebake failed for as long as the pair stood: the regions kept a stale
## uncarved mesh and the log filled with partition errors every second.
##
## This harness boots a real match, places that pair of houses next to the town
## center, waits for the debounced rebake and checks every region still holds a
## usable mesh that actually carves the new buildings out.
## Run: $GODOT --headless --path project res://tools/check_nav_bake_diag.tscn
## Env: CALIMA_MAP (default 1 = STANDARD), CALIMA_SEED (default 4242)

const GRID: float = 16.0
## 48 px on both axes: house half extents are 38 px (64 px shape + 6 px carve),
## so the carved gap is 20 px = twice the agent radius.
const DIAGONAL_STEP: float = 96.0

var _world: Node2D = null
var _failures: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.STANDARD
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	# Let the startup rebake settle before the pair goes down.
	await get_tree().create_timer(2.0).timeout

	var before: Dictionary = _mesh_census()
	print("NAV_BAKE_DIAG map_type=%d" % MatchConfig.map_type)
	print("    before: %s" % str(before))

	var anchor: Vector2 = _snap((_world.drop_off as Node2D).global_position + Vector2(420.0, 420.0))
	_place_house(anchor)
	_place_house(anchor + Vector2(DIAGONAL_STEP, DIAGONAL_STEP))
	print("    placed two diagonal houses at %s / %s" % [
		str(anchor), str(anchor + Vector2(DIAGONAL_STEP, DIAGONAL_STEP))])

	# NAV_REBAKE_DELAY is 1 s and the bake itself is async.
	await get_tree().create_timer(3.0).timeout
	var after: Dictionary = _mesh_census()
	print("    after:  %s" % str(after))

	for region_name: String in before:
		var polygons: int = after[region_name] as int
		if polygons <= 0:
			print("    FAIL: %s came back empty — units lost their walkable surface" % region_name)
			_failures += 1
		elif polygons == (before[region_name] as int):
			print("    FAIL: %s never changed — the rebake failed and the stale mesh was kept" % region_name)
			_failures += 1

	print("NAV_BAKE_DIAG: %s" % ("done" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _snap(pos: Vector2) -> Vector2:
	return Vector2(round(pos.x / GRID) * GRID + GRID * 0.5, round(pos.y / GRID) * GRID + GRID * 0.5)

func _place_house(pos: Vector2) -> void:
	var house: Node2D = (load("res://scenes/buildings/house.tscn") as PackedScene).instantiate() as Node2D
	house.set("player_id", 0)
	(_world.buildings_layer as Node).add_child(house)
	house.global_position = pos
	house.call("force_complete")
	EventBus.building_placed.emit(house, 0)

func _mesh_census() -> Dictionary:
	var census: Dictionary = {}
	for region_name: String in ["NavigationRegion2D", "OceanNavigationRegion2D",
			"AmphibiousNavigationRegion2D"]:
		var region: NavigationRegion2D = _world.get_node_or_null(region_name) as NavigationRegion2D
		if region == null:
			continue
		var poly: NavigationPolygon = region.navigation_polygon
		census[region_name] = poly.get_polygon_count() if poly != null else -1
	# The ocean region is never rebaked at runtime, so it must not be asserted on.
	census.erase("OceanNavigationRegion2D")
	return census

extends GutTest

## Fishing boats filling up and never unloading.
##
## A dock straddles the shoreline, so its own origin is normally *on land* — and
## land is off the ocean navmesh. Ships pretend to be the amphibious "atlantes"
## civ, so the base _safe_destination() considered that origin passable and left
## it alone: the agent reported navigation finished at once, the boat sat still
## with a full hold, and RETURNING re-set the same unreachable target forever.
## Boats now sail to the dock's offshore water_access_point().

const LAND_Y: float = 0.0
const DOCK_POS: Vector2 = Vector2(0.0, -8.0)
const PLAYER: int = 0

var _dock: Node2D = null
var _boat: Node2D = null

func before_each() -> void:
	TerrainManager.reset()
	# Island map: land is the y < 0 half of a square, everything else is ocean.
	TerrainManager.set_land_polys([PackedVector2Array([
		Vector2(-600.0, -600.0), Vector2(600.0, -600.0),
		Vector2(600.0, LAND_Y), Vector2(-600.0, LAND_Y)])], true)
	ResourceManager.init_player(PLAYER, {"food": 0.0})

	_dock = (load("res://scenes/buildings/dock.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(_dock)
	_dock.global_position = DOCK_POS
	_dock.set("player_id", PLAYER)

	_boat = (load("res://scenes/units/fishing_boat.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(_boat)
	_boat.set("player_id", PLAYER)
	_boat.global_position = Vector2(0.0, 400.0)

func after_each() -> void:
	TerrainManager.reset()

# 1 — the destination clamp is the actual bug: ships must never aim at land
func test_ship_destination_snaps_to_water() -> void:
	var on_land: Vector2 = Vector2(0.0, -300.0)
	var safe: Vector2 = _boat.call("_safe_destination", on_land) as Vector2
	assert_true(TerrainManager.is_ocean(safe),
		"a land destination is pulled to the nearest water, not kept off-mesh")
	var at_sea: Vector2 = Vector2(0.0, 300.0)
	assert_eq(_boat.call("_safe_destination", at_sea) as Vector2, at_sea,
		"a destination already at sea is untouched")

# 2 — the dock's berth is open water, unlike its own origin
func test_drop_off_position_is_open_water_off_the_pier() -> void:
	_boat.set("drop_off_target", _dock)
	var berth: Vector2 = _boat.call("_drop_off_position") as Vector2
	assert_true(TerrainManager.is_ocean(berth), "the berth is at sea")
	assert_gt(berth.y, LAND_Y, "on the seaward side of the dock")
	assert_ne(berth, _dock.global_position, "not the dock's own on-land origin")

func test_berth_is_resolved_once() -> void:
	assert_eq(_dock.call("water_access_point") as Vector2,
		_dock.call("water_access_point") as Vector2,
		"a returning boat asks every frame — the answer is cached, not re-searched")

# 3 — the nav target a full boat gets must be reachable water
func test_return_to_dock_navigates_to_water() -> void:
	_boat.set("drop_off_target", _dock)
	_boat.set("carried_amount", 15.0)
	_boat.call("_return_to_dock")
	var agent: NavigationAgent2D = _boat.get_node("NavigationAgent2D") as NavigationAgent2D
	assert_true(TerrainManager.is_ocean(agent.target_position),
		"the boat is sent to water it can actually reach")

# 4 — arriving at the berth credits the hold
func test_arriving_at_the_berth_unloads() -> void:
	_boat.set("drop_off_target", _dock)
	_boat.set("carried_amount", 15.0)
	_boat.global_position = _boat.call("_drop_off_position") as Vector2
	_boat.call("_handle_returning", 0.1)
	assert_eq(ResourceManager.get_resources(PLAYER).get("food", 0.0) as float, 15.0,
		"the catch lands in the stockpile")
	assert_eq(_boat.get("carried_amount") as float, 0.0, "the hold is emptied")

# 5 — a drop-off without a berth (any non-dock building) still works
func test_non_dock_drop_off_falls_back_to_its_origin() -> void:
	var plain: Node2D = Node2D.new()
	add_child_autofree(plain)
	plain.global_position = Vector2(120.0, 240.0)
	_boat.set("drop_off_target", plain)
	assert_eq(_boat.call("_drop_off_position") as Vector2, plain.global_position,
		"buildings with no water_access_point() are approached directly")

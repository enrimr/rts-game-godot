extends GutTest

## The wire trusts nobody (review #09 finding 2): commands deserialized off
## the network are branded remote_origin by NetworkSession._rx_command, and
## every privilege the local simulation grants itself dies at that brand —
## instant placement, AI-only scenes, ghost-skipping illegal positions,
## board_instant teleports. The host's own AI path (remote_origin false)
## keeps all of them.

const PID: int = 7

class MockWorld extends Node2D:
	var buildings_layer: Node = null

var _world: MockWorld = null
var _layer: Node2D = null

func before_each() -> void:
	_world = MockWorld.new()
	_layer = Node2D.new()
	_layer.name = "BuildingsLayer"
	_world.add_child(_layer)
	_world.buildings_layer = _layer
	add_child_autofree(_world)
	ResourceManager.init_player(PID, {"food": 5000, "wood": 5000, "gold": 5000})
	TerrainManager.reset()

func after_each() -> void:
	TerrainManager.reset()

func _place_cmd(instant: bool, remote: bool, type: String = "house",
		pos: Vector2 = Vector2(100, 100)) -> PlaceBuildingCommand:
	var cmd: PlaceBuildingCommand = PlaceBuildingCommand.make(PID, type,
		[pos] as Array[Vector2], 0.0, [] as Array[int], instant)
	cmd.remote_origin = remote
	return cmd

func test_remote_instant_placement_is_refused() -> void:
	var wood: float = ResourceManager.get_resources(PID).get("wood", 0.0) as float
	_place_cmd(true, true).execute(_world)
	assert_eq(_layer.get_child_count(), 0, "the AI's instant path is host-local only")
	assert_almost_eq(ResourceManager.get_resources(PID).get("wood", 0.0) as float,
		wood, 0.01, "and not a coin moved")

func test_remote_ai_only_scene_is_refused() -> void:
	_place_cmd(false, true, "town_center_ai").execute(_world)
	assert_eq(_layer.get_child_count(), 0, "EXTRA_SCENES never come off the wire")

func test_remote_placement_on_ocean_is_refused() -> void:
	TerrainManager.add_zone(Vector2(100, 100), 400.0, TerrainManager.TerrainType.OCEAN)
	_place_cmd(false, true).execute(_world)
	assert_eq(_layer.get_child_count(), 0,
		"the host re-runs the terrain check the client's ghost was supposed to do")

func test_remote_overlapping_placement_is_refused() -> void:
	var blocker: StaticBody2D = StaticBody2D.new()
	blocker.collision_layer = 1
	var cs: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(52, 52)
	cs.shape = shape
	blocker.add_child(cs)
	_world.add_child(blocker)
	blocker.global_position = Vector2(100, 100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_place_cmd(false, true).execute(_world)
	assert_eq(_layer.get_child_count(), 0, "no stacking buildings from the wire")

func test_legal_remote_placement_still_works() -> void:
	_place_cmd(false, true).execute(_world)
	assert_eq(_layer.get_child_count(), 1, "an honest client is not punished")

func test_local_instant_placement_keeps_working() -> void:
	_place_cmd(true, false).execute(_world)
	assert_eq(_layer.get_child_count(), 1, "the host AI path is untouched")

func test_remote_board_instant_is_refused() -> void:
	var transport: CharacterBody2D = (load("res://scenes/units/transport_ship.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	transport.set("player_id", PID)
	add_child_autofree(transport)
	var soldier: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	soldier.set("player_id", PID)
	add_child_autofree(soldier)
	soldier.global_position = transport.global_position + Vector2(2000, 0)
	var cmd: UnitTargetCommand = UnitTargetCommand.make(PID, "board_instant",
		[EntityRegistry.id_of(soldier)] as Array[int], EntityRegistry.id_of(transport))
	cmd.remote_origin = true
	cmd.execute(_world)
	assert_eq((transport.call("get_garrison") as Array).size(), 0,
		"no teleport boarding off the wire")

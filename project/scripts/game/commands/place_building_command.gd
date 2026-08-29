class_name PlaceBuildingCommand extends GameCommand

## Places one or more construction sites of a building type (a wall drag is
## one command with the whole run of segment positions), paying per site and
## stopping when the stockpile runs out — then sends the chosen builders to
## work. Placement legality (overlap, terrain, coast) is validated at the
## submission site where the ghost preview lives; the command re-validates
## affordability because it spends.

var building_type: String = ""
var positions: Array[Vector2] = []
var build_rotation: float = 0.0
var builder_ids: Array[int] = []

static func make(p_player: int, p_type: String, p_positions: Array[Vector2],
		p_rotation: float, p_builders: Array[int]) -> PlaceBuildingCommand:
	var cmd: PlaceBuildingCommand = PlaceBuildingCommand.new()
	cmd.player_id = p_player
	cmd.building_type = p_type
	cmd.positions = p_positions
	cmd.build_rotation = p_rotation
	cmd.builder_ids = p_builders
	return cmd

func kind() -> String:
	return "place_building"

func _payload() -> Dictionary:
	var pts: Array = []
	for p: Vector2 in positions:
		pts.append(encode_vec(p))
	return {"type": building_type, "positions": pts,
		"rot": build_rotation, "builders": encode_ids(builder_ids)}

func _read_payload(d: Dictionary) -> void:
	building_type = d.get("type", "") as String
	positions.clear()
	if d.get("positions") is Array:
		for p: Variant in d.get("positions") as Array:
			positions.append(decode_vec(p))
	build_rotation = d.get("rot", 0.0) as float
	builder_ids = decode_ids(d.get("builders"))

func execute(world: Node2D) -> void:
	if not WorldPlacement.BUILDING_SCENES.has(building_type) or positions.is_empty():
		return
	var costs: Dictionary = WorldPlacement.BUILDING_COSTS.get(building_type, {})
	var scene: PackedScene = load(WorldPlacement.BUILDING_SCENES[building_type]) as PackedScene
	if scene == null:
		return
	var builders: Array[Node] = _own_entities(builder_ids)
	var buildings_layer: Node = world.get("buildings_layer") as Node
	var placed: int = 0
	for pos: Vector2 in positions:
		if not ResourceManager.spend_resource(player_id, costs):
			break
		var building: Node2D = scene.instantiate() as Node2D
		building.global_position = pos
		building.rotation = build_rotation
		building.set("player_id", player_id)
		building.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
		building.set_meta("building_id", building_type)
		buildings_layer.add_child(building)
		EventBus.building_placed.emit(building, player_id)
		for unit: Node in builders:
			if unit.has_method("order_build"):
				unit.call("order_build", building)
		placed += 1
	if placed > 0 and player_id == 0:
		AudioManager.play("build_place")

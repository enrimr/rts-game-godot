class_name PlaceBuildingCommand extends GameCommand

## Places one or more construction sites of a building type (a wall drag is
## one command with the whole run of segment positions), paying per site and
## stopping when the stockpile runs out — then sends the chosen builders to
## work. Placement legality (overlap, terrain, coast) is validated at the
## submission site where the ghost preview / AI position search lives; the
## command re-validates affordability because it spends.
##
## The AI places through the same command with a real builder: a villager (or
## fishing boat) raises the site over the same construction time the player
## pays. `instant = true` survives as a privileged local-only flag (tools and
## tests; refused from the wire like the EXTRA_SCENES). Player and AI pay the
## same price: WorldPlacement.building_costs, the single table loaded from the
## BuildingResource .tres files — costs resolve at execute time and are never
## part of the payload, so a remote command cannot name its own price.

## AI-only scenes the player build menu never offers.
const EXTRA_SCENES: Dictionary = {
	"town_center_ai": "res://scenes/buildings/town_center_ai.tscn",
}

var building_type: String = ""
var positions: Array[Vector2] = []
var build_rotation: float = 0.0
var builder_ids: Array[int] = []
var instant: bool = false

## Nodes created by the last execute(), in placement order — a runtime result
## for the submission site (the AI keeps refs to its new TC), never serialized.
var last_placed: Array[Node] = []

static func make(p_player: int, p_type: String, p_positions: Array[Vector2],
		p_rotation: float, p_builders: Array[int], p_instant: bool = false) -> PlaceBuildingCommand:
	var cmd: PlaceBuildingCommand = PlaceBuildingCommand.new()
	cmd.player_id = p_player
	cmd.building_type = p_type
	cmd.positions = p_positions
	cmd.build_rotation = p_rotation
	cmd.builder_ids = p_builders
	cmd.instant = p_instant
	return cmd

func kind() -> String:
	return "place_building"

func _payload() -> Dictionary:
	var pts: Array = []
	for p: Vector2 in positions:
		pts.append(encode_vec(p))
	return {"type": building_type, "positions": pts, "rot": build_rotation,
		"builders": encode_ids(builder_ids), "instant": instant}

func _read_payload(d: Dictionary) -> void:
	building_type = d.get("type", "") as String
	positions.clear()
	if d.get("positions") is Array:
		for p: Variant in d.get("positions") as Array:
			positions.append(decode_vec(p))
	build_rotation = d.get("rot", 0.0) as float
	builder_ids = decode_ids(d.get("builders"))
	instant = d.get("instant", false) as bool

func _scene_path() -> String:
	if WorldPlacement.BUILDING_SCENES.has(building_type):
		return WorldPlacement.BUILDING_SCENES[building_type] as String
	return EXTRA_SCENES.get(building_type, "") as String

func _costs() -> Dictionary:
	return WorldPlacement.building_costs(building_type)

func execute(world: Node2D) -> void:
	last_placed.clear()
	# Wire-borne commands lose every local privilege: `instant` is the host
	# AI's building path, and the EXTRA_SCENES (AI town center) are not in
	# the player build menu for a reason. A legitimate client never sends
	# either — refusing them wholesale closes the cheat vector.
	if remote_origin and (instant or not WorldPlacement.BUILDING_SCENES.has(building_type)):
		return
	var scene_path: String = _scene_path()
	if scene_path.is_empty() or positions.is_empty():
		return
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return
	# Per-civ discounts (Mahos timber) resolve at execute time, same as the
	# base price — the wire can never name its own cost.
	var costs: Dictionary = CivBonusManager.get_building_costs(player_id, _costs())
	var builders: Array[Node] = _own_entities(builder_ids)
	var buildings_layer: Node = world.get("buildings_layer") as Node
	for pos: Vector2 in positions:
		# The ghost preview validates at the submission site, which only the
		# HOST's own UI is guaranteed to have run — every remote placement is
		# re-validated here (terrain class + overlap) before a coin moves.
		if remote_origin and not WorldPlacement.placement_legal(
				world, building_type, pos, build_rotation):
			continue
		if not ResourceManager.spend_resource(player_id, costs):
			break
		var building: Node2D = scene.instantiate() as Node2D
		building.global_position = pos
		building.rotation = build_rotation
		building.set("player_id", player_id)
		building.set_meta("building_id", building_type)
		if instant:
			# The AI's pre-command sequence: state and construction are applied
			# AFTER _ready so add_construction completes the building in place.
			buildings_layer.add_child(building)
			building.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
			if building.has_method("add_construction"):
				building.call("add_construction", 100.0)
		else:
			building.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
			buildings_layer.add_child(building)
		EventBus.building_placed.emit(building, player_id)
		for unit: Node in builders:
			if unit.has_method("order_build"):
				unit.call("order_build", building)
		last_placed.append(building)
	if not last_placed.is_empty() and player_id == 0:
		AudioManager.play("build_place")

class_name SpawnUnitCommand extends GameCommand

## Spends a cost and spawns a unit at a position instantly — the AI's villager
## production (it does not queue at the Town Center like the player does).
## The civ is derived from the owner, never carried in the payload.

var unit_type: String = ""
var pos: Vector2 = Vector2.ZERO
var costs: Dictionary = {}

static func make(p_player: int, p_type: String, p_pos: Vector2, p_costs: Dictionary) -> SpawnUnitCommand:
	var cmd: SpawnUnitCommand = SpawnUnitCommand.new()
	cmd.player_id = p_player
	cmd.unit_type = p_type
	cmd.pos = p_pos
	cmd.costs = p_costs
	return cmd

func kind() -> String:
	return "spawn_unit"

func _payload() -> Dictionary:
	return {"type": unit_type, "pos": encode_vec(pos), "costs": costs}

func _read_payload(d: Dictionary) -> void:
	unit_type = d.get("type", "") as String
	pos = decode_vec(d.get("pos"))
	costs = d.get("costs", {}) as Dictionary

func execute(world: Node2D) -> void:
	var packed: PackedScene = load("res://scenes/units/%s.tscn" % unit_type) as PackedScene
	if packed == null:
		return
	if not ResourceManager.spend_resource(player_id, costs):
		return
	var unit: Node2D = packed.instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0
		else MatchConfig.get_rival_civ_id(player_id))
	(world.get("units_layer") as Node).add_child(unit)
	unit.global_position = pos
	PopulationManager.add_unit(player_id)
	EventBus.unit_spawned.emit(unit, player_id)

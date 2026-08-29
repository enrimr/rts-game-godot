class_name BuildingActionCommand extends GameCommand

## A non-production order to one own building: set the rally point, toggle a
## gate's lock, or demolish it (delete routes through take_damage so the
## regular destruction flow — signals, rubble, victory checks — still runs).

var verb: String = "set_rally"   # "set_rally" | "gate_lock" | "delete"
var building_id: int = 0
var pos: Vector2 = Vector2.ZERO

static func make(p_player: int, p_verb: String, p_building: int,
		p_pos: Vector2 = Vector2.ZERO) -> BuildingActionCommand:
	var cmd: BuildingActionCommand = BuildingActionCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.building_id = p_building
	cmd.pos = p_pos
	return cmd

func kind() -> String:
	return "building_action"

func _payload() -> Dictionary:
	return {"verb": verb, "building": building_id, "pos": encode_vec(pos)}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "set_rally") as String
	building_id = d.get("building", 0) as int
	pos = decode_vec(d.get("pos"))

func execute(_world: Node2D) -> void:
	var building: Node = _own_entity(building_id)
	if building == null:
		return
	match verb:
		"set_rally":
			if building.has_method("set_rally_point"):
				building.call("set_rally_point", pos)
		"gate_lock":
			if building is Gate:
				(building as Gate).toggle_lock()
		"delete":
			if building.has_method("take_damage"):
				var hp: Variant = building.get("health")
				var dmg: float = (hp as float + 1.0) if hp != null else 9999.0
				building.call("take_damage", dmg)
			else:
				building.queue_free()

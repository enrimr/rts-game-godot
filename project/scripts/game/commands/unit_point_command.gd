class_name UnitPointCommand extends GameCommand

## A point-targeted order over a set of units: move, attack-move or
## attack-ground. Move and attack-move fan the units out over concentric
## formation rings around the click; attack-ground (siege/archer cover fire)
## sends the exact point to every unit.

const FORMATION_SPACING: float = 34.0   # px between formation slots

var verb: String = "move"   # "move" | "attack_move" | "attack_ground"
var unit_ids: Array[int] = []
var pos: Vector2 = Vector2.ZERO

static func make(p_player: int, p_verb: String, p_units: Array[int], p_pos: Vector2) -> UnitPointCommand:
	var cmd: UnitPointCommand = UnitPointCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.unit_ids = p_units
	cmd.pos = p_pos
	return cmd

func kind() -> String:
	return "unit_point"

func _payload() -> Dictionary:
	return {"verb": verb, "units": encode_ids(unit_ids), "pos": encode_vec(pos)}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "move") as String
	unit_ids = decode_ids(d.get("units"))
	pos = decode_vec(d.get("pos"))

func execute(_world: Node2D) -> void:
	var units: Array[Node] = []
	for unit: Node in _own_entities(unit_ids):
		if unit.has_method("order_move"):
			units.append(unit)
	if units.is_empty():
		return
	if verb == "attack_ground":
		for unit: Node in units:
			if unit.has_method("order_attack_ground"):
				unit.call("order_attack_ground", pos)
		return
	var slots: Array[Vector2] = formation_slots(pos, units)
	for i: int in range(units.size()):
		if verb == "attack_move" and units[i].has_method("order_attack_move"):
			units[i].call("order_attack_move", slots[i])
		else:
			units[i].call("order_move", slots[i])

## World-space positions for the units in concentric rings around `center`,
## facing away from the units' average origin (the nearest ring lands on the
## side they arrive from). Deterministic given the same units and center.
static func formation_slots(center: Vector2, units: Array[Node]) -> Array[Vector2]:
	var avg_origin: Vector2 = Vector2.ZERO
	for unit: Node in units:
		avg_origin += (unit as Node2D).global_position
	avg_origin /= float(units.size())
	var back_dir: Vector2 = (avg_origin - center).normalized()
	if back_dir == Vector2.ZERO:
		back_dir = Vector2.DOWN

	var slots: Array[Vector2] = []
	slots.append(center)   # slot 0: the exact target point
	var ring: int = 1
	while slots.size() < units.size():
		var slots_in_ring: int = 6 * ring
		var radius: float = ring * FORMATION_SPACING
		var start_angle: float = back_dir.angle()
		for s: int in range(slots_in_ring):
			if slots.size() >= units.size():
				break
			var angle: float = start_angle + s * TAU / float(slots_in_ring)
			slots.append(center + Vector2(cos(angle), sin(angle)) * radius)
		ring += 1
	return slots

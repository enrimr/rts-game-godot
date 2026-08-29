class_name UnitPointCommand extends GameCommand

## A point-targeted order over a set of units: move, attack-move or
## attack-ground. Move and attack-move fan the units out over the selected
## formation around the click — "line" (rows facing the target, melee front,
## ranged behind, siege and villagers in the rear), "box" (square block),
## "spread" (double-spaced line) or "rings" (the classic concentric blob).
## attack-ground (siege/archer cover fire) sends the exact point to everyone.

const FORMATION_SPACING: float = 34.0   # px between formation slots
const FORMATIONS: Array[String] = ["line", "box", "spread", "rings"]

var verb: String = "move"   # "move" | "attack_move" | "attack_ground"
var unit_ids: Array[int] = []
var pos: Vector2 = Vector2.ZERO
var formation: String = "rings"

static func make(p_player: int, p_verb: String, p_units: Array[int], p_pos: Vector2,
		p_formation: String = "rings") -> UnitPointCommand:
	var cmd: UnitPointCommand = UnitPointCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.unit_ids = p_units
	cmd.pos = p_pos
	cmd.formation = p_formation
	return cmd

func kind() -> String:
	return "unit_point"

func _payload() -> Dictionary:
	return {"verb": verb, "units": encode_ids(unit_ids), "pos": encode_vec(pos),
		"form": formation}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "move") as String
	unit_ids = decode_ids(d.get("units"))
	pos = decode_vec(d.get("pos"))
	formation = d.get("form", "rings") as String

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
	var ordered: Array[Node] = rank_ordered(units) if formation != "rings" else units
	var slots: Array[Vector2] = formation_slots(pos, ordered, formation)
	for i: int in range(ordered.size()):
		if verb == "attack_move" and ordered[i].has_method("order_attack_move"):
			ordered[i].call("order_attack_move", slots[i])
		else:
			ordered[i].call("order_move", slots[i])

## Battle-order rank: melee screens the front, ranged shoots over it, then
## everything soft (villagers, unarmed), siege last. Deterministic and stable.
static func formation_rank(unit: Node) -> int:
	if unit is BatteringRam or unit is Mangonel or unit is Trebuchet:
		return 3
	var combat: bool = unit.has_method("is_combat_unit") and unit.call("is_combat_unit")
	if not combat:
		return 2
	var ud: Variant = unit.get("unit_data")
	# attack_range is in TILES (melee ~1.5, archers 4+); ranged forms up behind.
	if ud is UnitResource and (ud as UnitResource).attack_range > 2.0:
		return 1
	return 0

static func rank_ordered(units: Array[Node]) -> Array[Node]:
	var ordered: Array[Node] = units.duplicate()
	# Stable: equal ranks keep their original relative order.
	var indexed: Array = []
	for i: int in range(ordered.size()):
		indexed.append([formation_rank(ordered[i]), i])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return (a[0] as int) < (b[0] as int)
		return (a[1] as int) < (b[1] as int))
	var out: Array[Node] = []
	for entry: Variant in indexed:
		out.append(ordered[(entry as Array)[1] as int])
	return out

## World-space positions for the units around `center`, facing away from the
## units' average origin. Deterministic given the same units and center.
static func formation_slots(center: Vector2, units: Array[Node],
		formation_id: String = "rings") -> Array[Vector2]:
	var avg_origin: Vector2 = Vector2.ZERO
	for unit: Node in units:
		avg_origin += (unit as Node2D).global_position
	avg_origin /= float(units.size())
	var back_dir: Vector2 = (avg_origin - center).normalized()
	if back_dir == Vector2.ZERO:
		back_dir = Vector2.DOWN
	match formation_id:
		"line":
			return _grid_slots(center, units.size(), back_dir, FORMATION_SPACING,
				maxi(1, int(ceil(sqrt(float(units.size()) * 2.0)))))
		"box":
			return _grid_slots(center, units.size(), back_dir, FORMATION_SPACING,
				maxi(1, int(ceil(sqrt(float(units.size()))))))
		"spread":
			return _grid_slots(center, units.size(), back_dir, FORMATION_SPACING * 2.0,
				maxi(1, int(ceil(sqrt(float(units.size()) * 2.0)))))
	return _ring_slots(center, units.size(), back_dir)

## Rows perpendicular to the travel direction: row 0 sits AT the click (the
## front — units[0..] land there, which is why callers rank-order first),
## later rows step back toward where the group came from.
static func _grid_slots(center: Vector2, count: int, back_dir: Vector2,
		spacing: float, per_row: int) -> Array[Vector2]:
	var right: Vector2 = Vector2(-back_dir.y, back_dir.x)
	var slots: Array[Vector2] = []
	var row: int = 0
	while slots.size() < count:
		var in_row: int = mini(per_row, count - slots.size())
		for c: int in range(in_row):
			var lateral: float = (float(c) - float(in_row - 1) * 0.5) * spacing
			slots.append(center + right * lateral + back_dir * (float(row) * spacing))
		row += 1
	return slots

static func _ring_slots(center: Vector2, count: int, back_dir: Vector2) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	slots.append(center)   # slot 0: the exact target point
	var ring: int = 1
	while slots.size() < count:
		var slots_in_ring: int = 6 * ring
		var radius: float = ring * FORMATION_SPACING
		var start_angle: float = back_dir.angle()
		for s: int in range(slots_in_ring):
			if slots.size() >= count:
				break
			var angle: float = start_angle + s * TAU / float(slots_in_ring)
			slots.append(center + Vector2(cos(angle), sin(angle)) * radius)
		ring += 1
	return slots

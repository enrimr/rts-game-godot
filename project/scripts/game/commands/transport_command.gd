class_name TransportCommand extends GameCommand

## An order to one own transport ship: unload everything, unload one garrison
## slot, or sail to a point and unload there.

var verb: String = "unload_all"   # "unload_all" | "unload_one" | "move_unload"
var transport_id: int = 0
var index: int = -1               # garrison slot for "unload_one"
var pos: Vector2 = Vector2.ZERO   # destination for "move_unload"

static func make(p_player: int, p_verb: String, p_transport: int,
		p_index: int = -1, p_pos: Vector2 = Vector2.ZERO) -> TransportCommand:
	var cmd: TransportCommand = TransportCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.transport_id = p_transport
	cmd.index = p_index
	cmd.pos = p_pos
	return cmd

func kind() -> String:
	return "transport"

func _payload() -> Dictionary:
	return {"verb": verb, "transport": transport_id, "index": index, "pos": encode_vec(pos)}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "unload_all") as String
	transport_id = d.get("transport", 0) as int
	index = d.get("index", -1) as int
	pos = decode_vec(d.get("pos"))

func execute(_world: Node2D) -> void:
	var node: Node = _own_entity(transport_id)
	if not (node is TransportShip):
		return
	var transport: TransportShip = node as TransportShip
	match verb:
		"unload_all":
			transport.unload_all()
		"unload_one":
			transport.unload_one(index)
		"move_unload":
			transport.order_move_then_unload(pos)

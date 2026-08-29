class_name GameCommand extends RefCounted

## Base class of the command pattern: every simulation-mutating player intent
## is a GameCommand submitted through the CommandBus autoload, never a direct
## method call from input/UI code. A command carries only serializable data
## (entity IDs from EntityRegistry, positions, type strings) so the tick-stamped
## command log can be stored for replays and, later, shipped over the network
## for LAN lockstep. UI feedback (flashes, sounds, selection changes) stays at
## the submission site — execute() touches the simulation only.

var player_id: int = 0

## Serialization tag; must match a key in CommandBus.KINDS.
func kind() -> String:
	return ""

func execute(_world: Node2D) -> void:
	pass

func to_dict() -> Dictionary:
	var d: Dictionary = {"kind": kind(), "player": player_id}
	d.merge(_payload())
	return d

## Populates this command from a to_dict() dictionary; returns self for chaining.
func read(d: Dictionary) -> GameCommand:
	player_id = d.get("player", 0) as int
	_read_payload(d)
	return self

func _payload() -> Dictionary:
	return {}

func _read_payload(_d: Dictionary) -> void:
	pass

# --- Shared helpers -----------------------------------------------------------

static func encode_vec(v: Vector2) -> Array:
	return [v.x, v.y]

static func decode_vec(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() == 2:
		return Vector2((a as Array)[0] as float, (a as Array)[1] as float)
	return Vector2.ZERO

static func encode_ids(ids: Array[int]) -> Array:
	return ids.duplicate()

static func decode_ids(a: Variant) -> Array[int]:
	var out: Array[int] = []
	if a is Array:
		for v: Variant in a as Array:
			out.append(v as int)
	return out

## Resolves `ids` and keeps only entities owned by this command's player —
## the ownership check that makes a command safe to accept from a remote peer.
func _own_entities(ids: Array[int]) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in EntityRegistry.resolve_many(ids):
		var pid: Variant = node.get("player_id")
		if pid != null and (pid as int) == player_id:
			out.append(node)
	return out

func _own_entity(id: int) -> Node:
	var node: Node = EntityRegistry.resolve(id)
	if node == null:
		return null
	var pid: Variant = node.get("player_id")
	if pid == null or (pid as int) != player_id:
		return null
	return node

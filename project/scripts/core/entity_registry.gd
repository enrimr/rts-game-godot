extends Node

## EntityRegistry (autoload) — stable per-match numeric IDs for every unit,
## building and resource node, so a GameCommand can reference entities as
## serializable integers instead of node pointers. IDs are assigned in
## registration order: `CommandBus.start_match` rescans the world in tree order
## and the spawn signals register everything created afterwards, so two runs of
## the same simulation hand out the same IDs — the property replays and LAN
## lockstep will build on.

const META_KEY: StringName = &"entity_id"

var _next_id: int = 1
var _by_id: Dictionary = {}   # int → Node

func _ready() -> void:
	EventBus.unit_spawned.connect(func(unit: Node, _pid: int) -> void: register(unit))
	EventBus.building_placed.connect(func(building: Node, _pid: int) -> void: register(building))
	EventBus.unit_died.connect(func(unit: Node, _pid: int) -> void: unregister(unit))
	EventBus.building_destroyed.connect(func(building: Node, _pid: int) -> void: unregister(building))

func reset() -> void:
	_next_id = 1
	_by_id.clear()

## Walks the world's entity containers in tree order, registering everything
## already alive (setup-spawned starting units, TCs, map resources) so their
## IDs are deterministic. Called once per match by CommandBus.start_match.
func rescan(world: Node) -> void:
	reset()
	var drop_off: Variant = world.get("drop_off")
	if drop_off is Node and is_instance_valid(drop_off as Node):
		register(drop_off as Node)
	for layer_name: String in ["UnitsLayer", "BuildingsLayer"]:
		var layer: Node = world.get_node_or_null(layer_name)
		if layer == null:
			continue
		for child: Node in layer.get_children():
			if is_instance_valid(child):
				register(child)
	for child: Node in world.get_children():
		if child is ResourceNode:
			register(child)

## Idempotent: a node keeps its ID for the whole match. A stale ID from a
## previous match (meta survives, the map doesn't) is re-assigned.
func register(node: Node) -> int:
	if not is_instance_valid(node):
		return 0
	if node.has_meta(META_KEY):
		var existing: int = node.get_meta(META_KEY) as int
		if _by_id.get(existing) == node:
			return existing
	var id: int = _next_id
	_next_id += 1
	node.set_meta(META_KEY, id)
	_by_id[id] = node
	return id

## Replication: a client creates puppets for host-spawned entities and must
## adopt the HOST's id verbatim so later commands/snapshots resolve.
func register_as(node: Node, id: int) -> void:
	if not is_instance_valid(node) or id <= 0:
		return
	node.set_meta(META_KEY, id)
	_by_id[id] = node
	_next_id = maxi(_next_id, id + 1)

func unregister(node: Node) -> void:
	if not is_instance_valid(node) or not node.has_meta(META_KEY):
		return
	var id: int = node.get_meta(META_KEY) as int
	if _by_id.get(id) == node:
		_by_id.erase(id)

## Lazy fallback for nodes no signal covers (e.g. a converted sheep): assigns
## on first reference, so a live pointer always has an ID to serialize.
func id_of(node: Node) -> int:
	return register(node)

func ids_of(nodes: Array) -> Array[int]:
	var out: Array[int] = []
	for node: Variant in nodes:
		# is_instance_valid FIRST: `x is Node` on a freed instance is an error.
		if is_instance_valid(node) and node is Node:
			out.append(id_of(node as Node))
	return out

func resolve(id: int) -> Node:
	var node: Variant = _by_id.get(id)
	if is_instance_valid(node) and node is Node and (node as Node).is_inside_tree():
		return node as Node
	_by_id.erase(id)
	return null

func resolve_many(ids: Array) -> Array[Node]:
	var out: Array[Node] = []
	for id: Variant in ids:
		var node: Node = resolve(id as int)
		if node != null:
			out.append(node)
	return out

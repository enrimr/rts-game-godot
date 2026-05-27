extends Node

## ResourceManager — tracks each player's resource stockpiles.

signal resources_updated(player_id: int, resources: Dictionary)

var _player_resources: Dictionary = {}

# Spatial cache: resource_name (String) → Array[ResourceNode]
# Populated by ResourceNode._ready() via register_node(), pruned on depletion.
var _resource_cache: Dictionary = {}

func register_node(node: ResourceNode) -> void:
	var key: String = node.get_resource_name()
	if not _resource_cache.has(key):
		_resource_cache[key] = []
	(_resource_cache[key] as Array).append(node)
	node.depleted.connect(_on_node_depleted)

func _on_node_depleted(node: ResourceNode) -> void:
	var key: String = node.get_resource_name()
	if _resource_cache.has(key):
		(_resource_cache[key] as Array).erase(node)

func get_nearest_resource(resource_name: String, from: Vector2, max_range: float, exclude: Node = null) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = max_range
	var nodes: Array = _resource_cache.get(resource_name, []) as Array
	var stale: Array = []
	for n: Variant in nodes:
		if not is_instance_valid(n):
			stale.append(n)
			continue
		var node: ResourceNode = n as ResourceNode
		if node == exclude:
			continue
		var d: float = from.distance_to((node as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = node
	for s: Variant in stale:
		nodes.erase(s)
	return best

func reset_resource_cache() -> void:
	_resource_cache.clear()

func init_player(player_id: int, starting_resources: Dictionary = {}) -> void:
	_player_resources[player_id] = {
		"food": starting_resources.get("food", 200),
		"wood": starting_resources.get("wood", 75),
		"gold": starting_resources.get("gold", 50),
		"stone": starting_resources.get("stone", 0),
	}

func get_resources(player_id: int) -> Dictionary:
	return _player_resources.get(player_id, {})

func add_resource(player_id: int, resource: String, amount: float) -> void:
	if not _player_resources.has(player_id):
		return
	_player_resources[player_id][resource] = _player_resources[player_id].get(resource, 0.0) + amount
	EventBus.resource_changed.emit(player_id, resource, _player_resources[player_id][resource])
	resources_updated.emit(player_id, _player_resources[player_id])

func spend_resource(player_id: int, costs: Dictionary) -> bool:
	if not can_afford(player_id, costs):
		return false
	for resource in costs:
		_player_resources[player_id][resource] -= costs[resource]
		EventBus.resource_changed.emit(player_id, resource, _player_resources[player_id][resource])
	resources_updated.emit(player_id, _player_resources[player_id])
	return true

func can_afford(player_id: int, costs: Dictionary) -> bool:
	var res: Dictionary = _player_resources.get(player_id, {})
	for resource in costs:
		if res.get(resource, 0) < costs[resource]:
			return false
	return true

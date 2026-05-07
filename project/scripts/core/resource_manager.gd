extends Node

## ResourceManager — tracks each player's resource stockpiles.

signal resources_updated(player_id: int, resources: Dictionary)

var _player_resources: Dictionary = {}

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
	resources_updated.emit(player_id, _player_resources[player_id])
	return true

func can_afford(player_id: int, costs: Dictionary) -> bool:
	var res: Dictionary = _player_resources.get(player_id, {})
	for resource in costs:
		if res.get(resource, 0) < costs[resource]:
			return false
	return true

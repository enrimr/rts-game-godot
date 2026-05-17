extends Node

var _population: Dictionary = {}   # player_id -> {current, cap}

func init_player(player_id: int) -> void:
	_population[player_id] = {"current": 0, "cap": 15}

func get_population(player_id: int) -> Dictionary:
	return _population.get(player_id, {"current": 0, "cap": 200})

func get_cap(player_id: int) -> int:
	var p: Dictionary = get_population(player_id)
	return p["cap"] as int

func add_unit(player_id: int, cost: int = 1) -> void:
	if not _population.has(player_id):
		init_player(player_id)
	_population[player_id]["current"] += cost
	var p: Dictionary = _population[player_id]
	EventBus.population_changed.emit(player_id, p["current"] as int, p["cap"] as int)

func remove_unit(player_id: int, cost: int = 1) -> void:
	if not _population.has(player_id):
		return
	_population[player_id]["current"] = maxi(0, _population[player_id]["current"] - cost)
	var p: Dictionary = _population[player_id]
	EventBus.population_changed.emit(player_id, p["current"] as int, p["cap"] as int)

func add_cap(player_id: int, amount: int) -> void:
	if not _population.has(player_id):
		init_player(player_id)
	_population[player_id]["cap"] = (_population[player_id]["cap"] as int) + amount
	var p: Dictionary = _population[player_id]
	EventBus.population_cap_changed.emit(player_id, p["cap"] as int)
	EventBus.population_changed.emit(player_id, p["current"] as int, p["cap"] as int)

func reduce_cap(player_id: int, amount: int) -> void:
	if not _population.has(player_id):
		return
	var new_cap: int = maxi(0, (_population[player_id]["cap"] as int) - amount)
	_population[player_id]["cap"] = new_cap
	var p: Dictionary = _population[player_id]
	EventBus.population_cap_changed.emit(player_id, p["cap"] as int)
	EventBus.population_changed.emit(player_id, p["current"] as int, p["cap"] as int)

func at_cap(player_id: int) -> bool:
	var p: Dictionary = get_population(player_id)
	return p["current"] >= p["cap"]

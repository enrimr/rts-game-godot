class_name UnitTargetCommand extends GameCommand

## An entity-targeted order over a set of units: attack, gather (resource
## node / farm / fish trap, restoring a depleted one first), build/repair,
## resource drop-off or transport boarding. The target is any registry ID;
## only "attack" may target another player's entity.

const MAX_BOARD_ATTEMPTS: int = 100   # 10 seconds of 0.1 s polls

var verb: String = "attack"   # "attack" | "gather" | "build" | "drop_off" | "board"
var unit_ids: Array[int] = []
var target_id: int = 0

static func make(p_player: int, p_verb: String, p_units: Array[int], p_target: int) -> UnitTargetCommand:
	var cmd: UnitTargetCommand = UnitTargetCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.unit_ids = p_units
	cmd.target_id = p_target
	return cmd

func kind() -> String:
	return "unit_target"

func _payload() -> Dictionary:
	return {"verb": verb, "units": encode_ids(unit_ids), "target": target_id}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "attack") as String
	unit_ids = decode_ids(d.get("units"))
	target_id = d.get("target", 0) as int

func execute(world: Node2D) -> void:
	var target: Node = EntityRegistry.resolve(target_id)
	if target == null:
		return
	var units: Array[Node] = _own_entities(unit_ids)
	if units.is_empty():
		return
	match verb:
		"attack":
			for unit: Node in units:
				if unit.has_method("order_attack"):
					unit.call("order_attack", target)
		"gather":
			_execute_gather(world, units, target)
		"build":
			for unit: Node in units:
				if unit.has_method("order_build"):
					unit.call("order_build", target)
		"drop_off":
			_execute_drop_off(units, target)
		"board":
			_execute_board(world, units, target)

func _execute_gather(world: Node2D, units: Array[Node], target: Node) -> void:
	if target is Farm:
		var farm: Farm = target as Farm
		if farm.is_depleted():
			if not ResourceManager.spend_resource(player_id, farm.get_restore_cost()):
				return
			farm.restore()
		for unit: Node in units:
			if unit.has_method("order_gather"):
				unit.call("order_gather", farm, "food", null)
		return
	if target is FishTrap:
		var trap: FishTrap = target as FishTrap
		if trap.is_depleted():
			if not ResourceManager.spend_resource(player_id, trap.get_restore_cost()):
				return
			trap.restore()
		for unit: Node in units:
			if unit is FishingBoat:
				(unit as FishingBoat).order_fish(trap, _nearest_own_dock(world, unit as Node2D))
		return
	if target is ResourceNode:
		var rn: ResourceNode = target as ResourceNode
		var resource_name: String = rn.get_resource_name()
		var is_fish: bool = rn.resource_type == ResourceNode.ResourceType.FOOD_FISH
		var drop_off: Node = world.get("drop_off") as Node if player_id == 0 else null
		for unit: Node in units:
			if is_fish and unit is FishingBoat:
				(unit as FishingBoat).order_fish(rn, _nearest_own_dock(world, unit as Node2D))
			elif not is_fish and unit.has_method("order_gather"):
				unit.call("order_gather", rn, resource_name, drop_off)

func _execute_drop_off(units: Array[Node], target: Node) -> void:
	for unit: Node in units:
		if unit is FishingBoat:
			var fb: FishingBoat = unit as FishingBoat
			fb.drop_off_target = target
			if fb.carried_amount > 0.0:
				fb.current_state = UnitBase.UnitState.RETURNING
				fb.nav_agent.target_position = fb._safe_destination((target as Node2D).global_position)
		elif unit.has_method("order_drop_off"):
			unit.call("order_drop_off", target)

func _execute_board(world: Node2D, units: Array[Node], target: Node) -> void:
	if not (target is TransportShip):
		return
	var transport: TransportShip = target as TransportShip
	for unit: Node in units:
		if unit is ShipBase or transport.is_full():
			continue
		var dist: float = (unit as Node2D).global_position.distance_to(transport.global_position)
		if dist <= TransportShip.BOARD_RANGE:
			transport.board(unit)
		elif unit.has_method("order_move"):
			unit.call("order_move", transport.global_position)
			_board_poll(world, unit, transport, 0)

## Walk-then-board: re-checks every 0.1 s until the unit reaches boarding range
## or the poll times out. Boarding emits EventBus.garrison_changed, which the
## selection layer listens to for its own cleanup.
func _board_poll(world: Node2D, unit: Node, transport: TransportShip, attempts: int) -> void:
	var timer: SceneTreeTimer = world.get_tree().create_timer(0.1)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(unit) or not is_instance_valid(transport):
			return
		if transport.is_full():
			return
		var d: float = (unit as Node2D).global_position.distance_to(transport.global_position)
		if d <= TransportShip.BOARD_RANGE:
			transport.board(unit)
		elif attempts < MAX_BOARD_ATTEMPTS and is_instance_valid(world):
			_board_poll(world, unit, transport, attempts + 1)
	)

func _nearest_own_dock(world: Node2D, requester: Node2D) -> Node:
	var best: Node = null
	var best_dist: float = INF
	var buildings: Node = world.get_node_or_null("BuildingsLayer")
	if buildings == null:
		return null
	for b: Node in buildings.get_children():
		if not (b is Dock):
			continue
		var pid: Variant = b.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var d: float = requester.global_position.distance_to((b as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best

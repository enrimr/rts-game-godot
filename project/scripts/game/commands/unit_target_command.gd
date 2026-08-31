class_name UnitTargetCommand extends GameCommand

## An entity-targeted order over a set of units: attack, gather (resource
## node / farm / fish trap, restoring a depleted one first), build/repair,
## resource drop-off, transport boarding or drop-off reassignment. The target
## is any registry ID; only "attack" may target another player's entity.
## `drop_id` optionally pins the drop-off building a gather order should use
## (the AI assigns specific camps/docks; the player falls back to the TC).

const MAX_BOARD_ATTEMPTS: int = 100   # 10 seconds of 0.1 s polls

var verb: String = "attack"   # "attack" | "gather" | "build" | "drop_off" | "board"
                              # | "board_instant" | "set_drop_off"
var unit_ids: Array[int] = []
var target_id: int = 0
var drop_id: int = 0          # gather only; 0 = default drop-off

static func make(p_player: int, p_verb: String, p_units: Array[int], p_target: int,
		p_drop: int = 0) -> UnitTargetCommand:
	var cmd: UnitTargetCommand = UnitTargetCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.unit_ids = p_units
	cmd.target_id = p_target
	cmd.drop_id = p_drop
	return cmd

func kind() -> String:
	return "unit_target"

func _payload() -> Dictionary:
	return {"verb": verb, "units": encode_ids(unit_ids), "target": target_id, "drop": drop_id}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "attack") as String
	unit_ids = decode_ids(d.get("units"))
	target_id = d.get("target", 0) as int
	drop_id = d.get("drop", 0) as int

func execute(world: Node2D) -> void:
	var target: Node = EntityRegistry.resolve(target_id)
	if target == null:
		return
	var units: Array[Node] = _own_entities(unit_ids)
	if units.is_empty():
		return
	for unit: Node in units:
		if unit.has_method("clear_waypoints"):
			unit.call("clear_waypoints")
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
		"garrison":
			_execute_garrison(world, units, target)
		"board_instant":
			# The AI garrisons idle troops without the walk: distance is not
			# checked, matching its pre-command behaviour.
			if target is TransportShip:
				for unit: Node in units:
					if not (unit is ShipBase) and not (target as TransportShip).is_full():
						(target as TransportShip).board(unit)
		"set_drop_off":
			var tpid: Variant = target.get("player_id")
			if tpid != null and (tpid as int) == player_id:
				for unit: Node in units:
					unit.set("drop_off_target", target)

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
				(unit as FishingBoat).order_fish(trap, _dock_for(world, unit as Node2D))
		return
	if target is ResourceNode:
		var rn: ResourceNode = target as ResourceNode
		var resource_name: String = rn.get_resource_name()
		var is_fish: bool = rn.resource_type == ResourceNode.ResourceType.FOOD_FISH
		var drop_off: Node = _own_entity(drop_id) if drop_id != 0 else null
		if drop_off == null and player_id == 0:
			drop_off = world.get("drop_off") as Node
		for unit: Node in units:
			if is_fish and unit is FishingBoat:
				(unit as FishingBoat).order_fish(rn, _dock_for(world, unit as Node2D))
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

## Walk-then-enter for buildings (TC/towers): same poll pattern as boarding.
## The building's can_garrison_unit is the gatekeeper (capacity, unit class).
func _execute_garrison(world: Node2D, units: Array[Node], target: Node) -> void:
	if not target.has_method("garrison_unit"):
		return
	var reach: float = _garrison_reach(target)
	for unit: Node in units:
		if not target.call("can_garrison_unit", unit):
			continue
		var dist: float = (unit as Node2D).global_position.distance_to((target as Node2D).global_position)
		if dist <= reach:
			target.call("garrison_unit", unit)
		elif unit.has_method("order_move"):
			unit.call("order_move", (target as Node2D).global_position)
			_garrison_poll(world, unit, target, 0)

func _garrison_poll(world: Node2D, unit: Node, target: Node, attempts: int) -> void:
	var timer: SceneTreeTimer = world.get_tree().create_timer(0.1, true, true)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(unit) or not is_instance_valid(target):
			return
		if not target.call("can_garrison_unit", unit):
			return
		var d: float = (unit as Node2D).global_position.distance_to((target as Node2D).global_position)
		if d <= _garrison_reach(target):
			target.call("garrison_unit", unit)
		elif attempts < MAX_BOARD_ATTEMPTS and is_instance_valid(world):
			_garrison_poll(world, unit, target, attempts + 1)
	)

## Entry distance: the building footprint half-diagonal plus a step.
static func _garrison_reach(building: Node) -> float:
	var cs: CollisionShape2D = building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).size.length() * 0.5 + 26.0
	return 80.0

## Walk-then-board: re-checks every 0.1 s until the unit reaches boarding range
## or the poll times out. Boarding emits EventBus.garrison_changed, which the
## selection layer listens to for its own cleanup.
func _board_poll(world: Node2D, unit: Node, transport: TransportShip, attempts: int) -> void:
	# process_in_physics: the poll fires on simulation ticks, not render frames.
	var timer: SceneTreeTimer = world.get_tree().create_timer(0.1, true, true)
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

## Dock a fishing order should unload at: the pinned drop_id when it is an own
## dock, otherwise the nearest own dock.
func _dock_for(world: Node2D, requester: Node2D) -> Node:
	if drop_id != 0:
		var pinned: Node = _own_entity(drop_id)
		if pinned is Dock:
			return pinned
	return _nearest_own_dock(world, requester)

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

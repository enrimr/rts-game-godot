extends ShipBase

class_name FishingBoat

## Fishing Boat — gathers fish from FOOD_FISH resource nodes in the ocean.
## Drops off food at the Dock that trained it.

const GATHER_RANGE: float = 52.0
const DROP_OFF_RANGE: float = 80.0

var fish_target: Node = null
var drop_off_target: Node = null
var carried_amount: float = 0.0
var _gather_timer: float = 0.0

var build_target: Node = null
const BUILD_RANGE: float = 56.0

const GATHER_RATE: float = 0.8   # food/sec
const CARRY_CAPACITY: float = 15.0

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_velocity_computed(safe_vel: Vector2) -> void:
	velocity = safe_vel
	move_and_slide()

func _on_auto_attack_target(_target: Node) -> void:
	pass  # Fishing boats don't fight

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.GATHERING:
			_handle_fishing(delta)
		UnitState.RETURNING:
			_handle_returning(delta)
		UnitState.BUILDING:
			_handle_boat_building(delta)

func order_build(target: Node) -> void:
	fish_target = null
	build_target = target
	current_state = UnitState.MOVING
	nav_agent.target_position = _safe_destination((target as Node2D).global_position)
	var bstate: Variant = target.get("state")
	if bstate != null and (bstate as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
		target.construction_complete.connect(_on_construction_complete, CONNECT_ONE_SHOT)

func _on_construction_complete() -> void:
	var completed: Node = build_target
	build_target = null
	# Immediately start fishing from the just-built trap if it's a FishTrap
	if is_instance_valid(completed) and completed is FishTrap and is_instance_valid(drop_off_target):
		order_fish(completed, drop_off_target)
	else:
		current_state = UnitState.IDLE

func order_move(destination: Vector2) -> void:
	fish_target = null
	build_target = null
	nav_agent.target_position = _safe_destination(destination)
	current_state = UnitState.MOVING

func order_fish(target: Node, dock: Node) -> void:
	fish_target = target
	drop_off_target = dock
	current_state = UnitState.MOVING
	nav_agent.target_position = _safe_destination((target as Node2D).global_position)

func _handle_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		if is_instance_valid(build_target):
			current_state = UnitState.BUILDING
		elif is_instance_valid(fish_target):
			current_state = UnitState.GATHERING
		else:
			current_state = UnitState.IDLE
		return
	if _advance_stuck(delta):
		current_state = UnitState.IDLE
	var vel: Vector2 = _nav_velocity()
	nav_agent.set_velocity(vel)

func _handle_fishing(delta: float) -> void:
	if not is_instance_valid(fish_target):
		_find_new_fish()
		return
	# FishTrap depletes without freeing — treat depleted trap like a gone node
	if fish_target is FishTrap and (fish_target as FishTrap).is_depleted():
		fish_target = null
		_find_new_fish()
		return
	var dist: float = global_position.distance_to((fish_target as Node2D).global_position)
	if dist > GATHER_RANGE:
		nav_agent.target_position = _safe_destination((fish_target as Node2D).global_position)
		current_state = UnitState.MOVING
		return
	_gather_timer += delta
	if _gather_timer >= 1.0:
		_gather_timer = 0.0
		var gathered: float = fish_target.call("gather", GATHER_RATE)
		carried_amount += gathered
	if carried_amount >= CARRY_CAPACITY:
		_return_to_dock()

func _handle_returning(delta: float) -> void:
	if not is_instance_valid(drop_off_target):
		current_state = UnitState.IDLE
		return
	var dist: float = global_position.distance_to((drop_off_target as Node2D).global_position)
	if dist <= DROP_OFF_RANGE:
		ResourceManager.add_resource(player_id, "food", carried_amount)
		carried_amount = 0.0
		if is_instance_valid(fish_target):
			order_fish(fish_target, drop_off_target)
		else:
			current_state = UnitState.IDLE
		return
	if nav_agent.is_navigation_finished():
		nav_agent.target_position = _safe_destination((drop_off_target as Node2D).global_position)
	if _advance_stuck(delta):
		current_state = UnitState.IDLE
	nav_agent.set_velocity(_nav_velocity())

func _return_to_dock() -> void:
	if not is_instance_valid(drop_off_target):
		current_state = UnitState.IDLE
		return
	current_state = UnitState.RETURNING
	nav_agent.target_position = _safe_destination((drop_off_target as Node2D).global_position)

func _handle_boat_building(delta: float) -> void:
	if not is_instance_valid(build_target):
		build_target = null
		current_state = UnitState.IDLE
		return
	var build_pos: Vector2 = (build_target as Node2D).global_position
	var dist: float = global_position.distance_to(build_pos)
	if dist > BUILD_RANGE:
		nav_agent.target_position = _safe_destination(build_pos)
		if _advance_stuck(delta):
			current_state = UnitState.IDLE
		nav_agent.set_velocity(_nav_velocity())
		return
	nav_agent.set_velocity(Vector2.ZERO)
	var bstate: Variant = build_target.get("state")
	if bstate != null and (bstate as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
		build_target.add_construction(25.0 * delta)
	else:
		build_target = null
		current_state = UnitState.IDLE

func _find_new_fish() -> void:
	var best: Node = null
	var best_dist: float = 9999.0
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		var rtype: Variant = node.get("resource_type")
		if rtype == null or (rtype as int) != ResourceNode.ResourceType.FOOD_FISH:
			continue
		var d: float = global_position.distance_to((node as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = node
	# Also check own fish traps
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is FishTrap):
			continue
		var ft: FishTrap = node as FishTrap
		var ft_pid: Variant = ft.get("player_id")
		if ft_pid == null or (ft_pid as int) != player_id:
			continue
		if ft.state != BuildingBase.BuildingState.COMPLETE or ft.is_depleted():
			continue
		var d: float = global_position.distance_to((ft as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = ft
	if best != null:
		order_fish(best, drop_off_target)
	else:
		current_state = UnitState.IDLE

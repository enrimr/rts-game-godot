extends ShipBase

class_name TransportShip

## Transport Ship — carries up to CAPACITY land units across water.
## Board:  right-click this ship with land units selected → they walk to the
##         ship, vanish, and are stored in _garrison.
## Unload: select the ship, click the Unload button OR right-click on land →
##         ship moves there then places all garrisoned units on the shore.

const CAPACITY: int = 8
const BOARD_RANGE: float = 52.0   # land unit must be within this distance to board
const UNLOAD_OFFSET: float = 56.0 # spacing between unloaded units
const SHORE_CHECK_RADIUS: float = 80.0  # max distance to shore for unloading
const SHORE_CHECK_STEPS: int = 16       # angular samples when probing for shore

var _garrison: Array[Node] = []   # stored land units (hidden, process disabled)

# Pending unload destination — ship moves here then dumps units.
var _unload_target: Vector2 = Vector2.ZERO
var _unloading: bool = false

# UnitBase exposes order_attack on every unit; declaring the ship non-combat
# makes it refuse attack orders and keeps it off the attack cursor.
func is_combat_unit() -> bool:
	return false

func _on_velocity_computed(safe_vel: Vector2) -> void:
	if current_state != UnitState.MOVING:
		return
	velocity = safe_vel
	move_and_slide()

func _on_auto_attack_target(_target: Node) -> void:
	pass

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)

func order_move(destination: Vector2) -> void:
	_unloading = false
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_move_then_unload(destination: Vector2) -> void:
	_unload_target = destination
	_unloading = true
	_navigate_to(destination)
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = UnitState.IDLE
		if _unloading:
			_unloading = false
			unload_all()
		return
	if _advance_stuck(delta):
		_unstick()
		return
	nav_agent.set_velocity(_nav_velocity())

# Returns true if the ship is close enough to shore to allow unloading.
func _is_near_shore() -> bool:
	for i: int in range(SHORE_CHECK_STEPS):
		var angle: float = TAU * float(i) / float(SHORE_CHECK_STEPS)
		var probe: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * SHORE_CHECK_RADIUS
		if not TerrainManager.is_ocean(probe):
			return true
	return false

# Called by game_world when a land unit right-clicks this ship.
# Ships and fishing boats may not board; all land units (including villagers) can.
func board(unit: Node) -> bool:
	if _garrison.size() >= CAPACITY:
		return false
	if not is_instance_valid(unit):
		return false
	if unit is ShipBase or unit is FishingBoat:
		return false
	_garrison.append(unit)
	unit.set_process(false)
	unit.set_physics_process(false)
	unit.visible = false
	if unit.has_method("set_selected"):
		unit.call("set_selected", false)
	EventBus.garrison_changed.emit(self, _garrison.size(), CAPACITY)
	return true

## Dry ground beside the ship for a disembarking passenger. Deliberately asks for
## a land tile even when the passenger is amphibious: troops land on the beach,
## not in the surf, and an off-mesh drop used to leave the unit unable to path.
func _disembark_position(around: Vector2, unit: Node) -> Vector2:
	return TerrainManager.nearest_passable(around, unit.get("civ_id") as String)

# Unload all garrisoned units near current position.
func unload_all() -> void:
	if _garrison.is_empty():
		return
	if not _is_near_shore():
		return
	var count: int = _garrison.size()
	for i: int in range(count):
		var unit: Node = _garrison[i]
		if not is_instance_valid(unit):
			continue
		var angle: float = TAU * float(i) / float(count)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * UNLOAD_OFFSET
		var land_pos: Vector2 = _disembark_position(global_position + offset, unit)
		unit.set_process(true)
		unit.set_physics_process(true)
		unit.visible = true
		(unit as Node2D).global_position = land_pos
	_garrison.clear()
	EventBus.garrison_changed.emit(self, 0, CAPACITY)

func unload_one(index: int) -> void:
	if index < 0 or index >= _garrison.size():
		return
	if not _is_near_shore():
		return
	var unit: Node = _garrison[index]
	_garrison.remove_at(index)
	if not is_instance_valid(unit):
		EventBus.garrison_changed.emit(self, _garrison.size(), CAPACITY)
		return
	var angle: float = MatchRng.randf() * TAU
	var land_pos: Vector2 = _disembark_position(
		global_position + Vector2(cos(angle), sin(angle)) * UNLOAD_OFFSET, unit)
	unit.set_process(true)
	unit.set_physics_process(true)
	unit.visible = true
	(unit as Node2D).global_position = land_pos
	EventBus.garrison_changed.emit(self, _garrison.size(), CAPACITY)

func die() -> void:
	for unit: Node in _garrison:
		if is_instance_valid(unit):
			if unit.has_method("die"):
				unit.call("die")
			else:
				unit.queue_free()
	_garrison.clear()
	super.die()

func get_garrison() -> Array:
	return _garrison.duplicate()

func get_capacity() -> int:
	return CAPACITY

func is_full() -> bool:
	return _garrison.size() >= CAPACITY

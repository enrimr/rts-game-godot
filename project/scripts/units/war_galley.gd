extends ShipBase

class_name WarGalley

## War Galley — naval combat unit. Ranged attack against ships and coastal targets.

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_velocity_computed(safe_vel: Vector2) -> void:
	if current_state != UnitState.MOVING:
		return
	velocity = safe_vel
	move_and_slide()

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_attacking(delta)

func order_move(destination: Vector2) -> void:
	_attack_move_active = false
	attack_target = null
	_destination_state = UnitState.IDLE
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_attack(target: Node) -> void:
	attack_target = target
	_destination_state = UnitState.ATTACKING
	_move_destination = _safe_destination(_nav_target_for(target))
	nav_agent.target_position = _move_destination
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = _destination_state
		return
	if _advance_stuck(delta):
		if _destination_state == UnitState.ATTACKING and is_instance_valid(attack_target):
			_move_destination = _safe_destination(_nav_target_for(attack_target))
			nav_agent.target_position = _move_destination
		else:
			_unstick()
	nav_agent.set_velocity(_nav_velocity())

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		current_state = UnitState.IDLE
		return
	var reach: float = _attack_reach_to(attack_target)
	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	if dist > reach:
		nav_agent.target_position = _safe_destination(_nav_target_for(attack_target))
		current_state = UnitState.MOVING
		_destination_state = UnitState.ATTACKING
		return
	_attack_timer += delta
	if _attack_timer >= 1.0 / unit_data.attack_speed:
		_attack_timer = 0.0
		var armor: float = _get_target_armor(attack_target)
		var dmg: float = maxf(1.0, unit_data.attack - armor)
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(dmg, self)

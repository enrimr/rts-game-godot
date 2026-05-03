extends UnitBase

class_name Militia

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_attacking(delta)

func order_move(destination: Vector2) -> void:
	attack_target = null
	_destination_state = UnitState.IDLE
	nav_agent.target_position = destination
	current_state = UnitState.MOVING

func order_attack(target: Node) -> void:
	attack_target = target
	_destination_state = UnitState.ATTACKING
	nav_agent.target_position = (target as Node2D).global_position
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = _destination_state
		_destination_state = UnitState.IDLE
		return

	var next_pos: Vector2 = nav_agent.get_next_path_position()
	var desired_velocity: Vector2 = (next_pos - global_position).normalized() * unit_data.move_speed
	nav_agent.set_velocity(desired_velocity)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		current_state = UnitState.IDLE
		return

	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	if dist > unit_data.attack_range * 32.0:
		nav_agent.target_position = (attack_target as Node2D).global_position
		var next_pos: Vector2 = nav_agent.get_next_path_position()
		var desired_velocity: Vector2 = (next_pos - global_position).normalized() * unit_data.move_speed
		nav_agent.set_velocity(desired_velocity)
		return

	nav_agent.set_velocity(Vector2.ZERO)
	_attack_timer += delta
	if _attack_timer >= 1.0 / unit_data.attack_speed:
		_attack_timer = 0.0
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(unit_data.attack - _get_target_armor(), self)
			EventBus.unit_attacked.emit(self, attack_target)

func _get_target_armor() -> float:
	var armor: Variant = attack_target.get("armor_melee")
	if armor != null:
		return armor as float
	return 0.0

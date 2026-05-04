extends UnitBase

class_name Militia

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

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
		nav_agent.set_velocity(Vector2.ZERO)
		return

	if _advance_stuck(delta):
		var jitter: Vector2 = Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
		nav_agent.target_position = nav_agent.target_position + jitter
		return

	nav_agent.set_velocity(_nav_velocity())

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		attack_target = null
		current_state = UnitState.IDLE
		_scan_area_for_target()
		return

	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var attack_reach: float = unit_data.attack_range * 32.0
	if dist > attack_reach:
		nav_agent.target_position = (attack_target as Node2D).global_position
		if _advance_stuck(delta):
			var jitter: Vector2 = Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
			nav_agent.target_position = nav_agent.target_position + jitter
			return
		nav_agent.set_velocity(_nav_velocity())
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

func _scan_area_for_target() -> void:
	if not is_instance_valid(attack_range_area):
		return
	for body: Node in attack_range_area.get_overlapping_bodies():
		var pid: Variant = body.get("player_id")
		if pid != null and (pid as int) != player_id:
			order_attack(body)
			return

extends UnitBase

class_name Pikeman

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
		UnitState.MOVING:    _handle_movement(delta)
		UnitState.ATTACKING: _handle_attacking(delta)

func order_move(destination: Vector2) -> void:
	_attack_move_active = false
	attack_target = null
	_destination_state = UnitState.IDLE
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_attack(target: Node) -> void:
	attack_target = target
	_destination_state = UnitState.ATTACKING
	_move_destination = _nav_target_for(target)
	nav_agent.target_position = _move_destination
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if _destination_state == UnitState.ATTACKING and is_instance_valid(attack_target):
		if global_position.distance_to((attack_target as Node2D).global_position) <= _attack_reach_to(attack_target):
			current_state = UnitState.ATTACKING
			_destination_state = UnitState.IDLE
			nav_agent.set_velocity(Vector2.ZERO)
			return
	if nav_agent.is_navigation_finished():
		current_state = _destination_state
		_destination_state = UnitState.IDLE
		nav_agent.set_velocity(Vector2.ZERO)
		return
	if _advance_stuck(delta):
		_unstick()
		return
	nav_agent.set_velocity(_nav_velocity())

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if current_state != UnitState.MOVING:
		return
	velocity = safe_velocity
	move_and_slide()

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		attack_target = null
		current_state = UnitState.IDLE
		_scan_for_target()
		return

	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var reach: float = _attack_reach_to(attack_target)
	if dist > reach:
		nav_agent.target_position = _nav_target_for(attack_target)
		if _advance_stuck(delta):
			_unstick()
			return
		nav_agent.set_velocity(_nav_velocity())
		return

	nav_agent.set_velocity(Vector2.ZERO)
	_attack_timer += delta
	if _attack_timer >= 1.0 / unit_data.attack_speed:
		_attack_timer = 0.0
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(_get_effective_attack_vs(attack_target) - _get_target_armor(attack_target), self)
			AudioManager.play_if_visible("hit_melee", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)

func _scan_for_target() -> void:
	if not is_instance_valid(attack_range_area):
		return
	for body: Node in attack_range_area.get_overlapping_bodies():
		var pid: Variant = body.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if body.get("unit_data") == null and not (body is Animal):
			continue
		order_attack(body)
		return

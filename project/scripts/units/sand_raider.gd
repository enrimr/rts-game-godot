extends UnitBase

class_name SandRaider

var _retreating: bool = false
var _retreat_destination: Vector2 = Vector2.ZERO

const RETREAT_DISTANCE: float = 90.0

func get_selection_sound() -> String:
	return "select_cavalry"

func _ready() -> void:
	super._ready()

# Stripe + shadow sized for the horse footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 9.9, 12.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 15.0, 4.5, 11.0)

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
	_retreating = false
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_attack(target: Node) -> void:
	attack_target = target
	_destination_state = UnitState.ATTACKING
	_retreating = false
	_move_destination = _nav_target_for(target)
	nav_agent.target_position = _move_destination
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if _retreating:
		if nav_agent.is_navigation_finished() or global_position.distance_to(_retreat_destination) < 16.0:
			_retreating = false
			if is_instance_valid(attack_target):
				_destination_state = UnitState.ATTACKING
				nav_agent.target_position = _nav_target_for(attack_target)
			else:
				current_state = UnitState.IDLE
				_destination_state = UnitState.IDLE
				return
		if _advance_stuck(delta):
			_retreating = false
			return
		nav_agent.set_velocity(_nav_velocity())
		return
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
		_retreating = false
		_scan_area_for_target()
		return
	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var attack_reach: float = _attack_reach_to(attack_target)
	if dist > attack_reach:
		nav_agent.target_position = _nav_target_for(attack_target)
		if _advance_stuck(delta):
			_unstick()
			return
		nav_agent.set_velocity(_nav_velocity())
		return
	nav_agent.set_velocity(Vector2.ZERO)
	_attack_timer += delta
	var effective_speed: float = unit_data.attack_speed * CivBonusManager.get_attack_speed_multiplier(player_id, unit_data.id)
	if _attack_timer >= 1.0 / effective_speed:
		_attack_timer = 0.0
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(_get_effective_attack_vs(attack_target) - _get_target_armor(attack_target), self)
			AudioManager.play_if_visible("hit_melee", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)
		_begin_retreat()

func _begin_retreat() -> void:
	if not is_instance_valid(attack_target):
		return
	var away_dir: Vector2 = (global_position - (attack_target as Node2D).global_position).normalized()
	_retreat_destination = global_position + away_dir * RETREAT_DISTANCE
	_retreating = true
	_navigate_to(_retreat_destination)
	current_state = UnitState.MOVING

func _scan_area_for_target() -> void:
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

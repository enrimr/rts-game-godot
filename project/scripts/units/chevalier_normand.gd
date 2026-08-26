extends UnitBase

class_name ChevalierNormand

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE
var _distance_moved: float = 0.0
var _charge_ready: bool = false

const CHARGE_DISTANCE_THRESHOLD: float = 80.0
const CHARGE_DAMAGE_MULTIPLIER: float = 2.5

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

# Stripe + shadow sized for the warhorse footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 11.0, 13.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 16.0, 5.0, 12.0)

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
	_move_destination = _nav_target_for(target)
	nav_agent.target_position = _move_destination
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	_distance_moved += velocity.length() * delta
	if _distance_moved >= CHARGE_DISTANCE_THRESHOLD:
		_charge_ready = true
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
	if _attack_timer >= 1.0 / unit_data.attack_speed:
		_attack_timer = 0.0
		if attack_target.has_method("take_damage"):
			var dmg: float = _get_effective_attack_vs(attack_target) - _get_target_armor(attack_target)
			if _charge_ready:
				dmg *= CHARGE_DAMAGE_MULTIPLIER
				_charge_ready = false
				_distance_moved = 0.0
			attack_target.take_damage(dmg, self)
			EventBus.unit_attacked.emit(self, attack_target)
		_distance_moved = 0.0
		_charge_ready = false

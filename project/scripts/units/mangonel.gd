extends UnitBase

class_name Mangonel

const SPLASH_RADIUS: float = 72.0
const MIN_RANGE_RATIO: float = 0.35

func get_selection_sound() -> String:
	return "select_siege"

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 15.4, 5.0)

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

func order_attack_ground(world_pos: Vector2) -> void:
	attack_target = null
	_destination_state = UnitState.IDLE
	current_state = UnitState.IDLE
	nav_agent.set_velocity(Vector2.ZERO)
	_fire_at(world_pos)

func order_attack(target: Node) -> void:
	attack_target = target
	_destination_state = UnitState.ATTACKING
	_move_destination = _nav_target_for(target)
	nav_agent.target_position = _move_destination
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if _destination_state == UnitState.ATTACKING and is_instance_valid(attack_target):
		var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
		var reach: float = _attack_reach_to(attack_target)
		if dist <= reach and dist >= reach * MIN_RANGE_RATIO:
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
	var reach: float = _attack_reach_to(attack_target)
	var min_range: float = reach * MIN_RANGE_RATIO

	# Move away if target is too close (minimum range)
	if dist < min_range:
		var away: Vector2 = global_position + (global_position - (attack_target as Node2D).global_position).normalized() * 120.0
		nav_agent.target_position = away
		nav_agent.set_velocity(_nav_velocity())
		return

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
		_fire_at((attack_target as Node2D).global_position)

func _fire_at(target_pos: Vector2) -> void:
	# Drift impact point with wind/storm conditions
	var dist: float = global_position.distance_to(target_pos)
	var flight_time: float = clampf(dist / 500.0, 0.3, 0.8)
	var drifted_target: Vector2 = target_pos + WeatherManager.get_projectile_drift() * flight_time

	var dmg: float = _get_effective_attack() * CivBonusManager.get_siege_attack_bonus(player_id)
	# Splash: hit all units and buildings in radius around impact
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = SPLASH_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, drifted_target)
	query.collision_mask = 1
	var results: Array[Dictionary] = space.intersect_shape(query, 32)
	for result: Dictionary in results:
		var body: Node = result["collider"] as Node
		if not is_instance_valid(body):
			continue
		var body_pid: Variant = body.get("player_id")
		if body_pid == null or (body_pid as int) == player_id:
			continue
		var armor: float = _get_target_armor(body)
		var actual_dmg: float = maxf(dmg - armor, 1.0)
		if body.has_method("take_damage"):
			body.take_damage(actual_dmg, self)
			EventBus.unit_attacked.emit(self, body)
	AudioManager.play_if_visible("hit_ranged", global_position, -2.0)

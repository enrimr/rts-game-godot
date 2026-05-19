extends UnitBase

class_name Scout

const EXPLORE_DURATION: float = 60.0
const EXPLORE_WAYPOINT_RADIUS: float = 400.0

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE
var _exploring: bool = false
var _explore_timer: float = 0.0
var _explore_waypoint_cooldown: float = 0.0

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func start_auto_explore() -> void:
	_exploring = true
	_explore_timer = EXPLORE_DURATION
	_pick_explore_waypoint()

func stop_auto_explore() -> void:
	_exploring = false
	_explore_timer = 0.0

func is_exploring() -> bool:
	return _exploring

func get_explore_fraction() -> float:
	return clampf(_explore_timer / EXPLORE_DURATION, 0.0, 1.0)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_attacking(delta)
	if _exploring:
		_explore_timer -= delta
		if _explore_timer <= 0.0:
			stop_auto_explore()
		else:
			_explore_waypoint_cooldown -= delta
			if _explore_waypoint_cooldown <= 0.0 or current_state == UnitState.IDLE:
				_pick_explore_waypoint()

func _pick_explore_waypoint() -> void:
	_explore_waypoint_cooldown = randf_range(3.0, 7.0)
	const MAP_MIN: float = 200.0
	const MAP_MAX: float = 7480.0
	# Try up to 12 random candidates; keep the first one that is passable for
	# this unit's civ (avoids sending the scout into ocean, malpais, etc.).
	for _i: int in range(12):
		var candidate: Vector2 = Vector2(
			randf_range(MAP_MIN, MAP_MAX),
			randf_range(MAP_MIN, MAP_MAX)
		)
		if not TerrainManager.is_impassable_for(candidate, civ_id):
			order_move(candidate)
			return
	# Fallback: nearest passable point from current position in a random direction.
	var angle: float = randf_range(0.0, TAU)
	var far: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * randf_range(400.0, 1200.0)
	order_move(TerrainManager.nearest_passable(far, civ_id))

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
			attack_target.take_damage(_get_effective_attack_vs(attack_target) - _get_target_armor(attack_target), self)
			EventBus.unit_attacked.emit(self, attack_target)

extends UnitBase

class_name Trebuchet

const SPLASH_RADIUS: float = 48.0
# Trebuchet cannot fire when target is within this fraction of max range
const MIN_RANGE_RATIO: float = 0.40

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

# Trebuchet must be "deployed" (unpacked) before it can fire.
# While packed it moves freely; deploying/undeploying takes _deploy_time seconds.
var is_deployed: bool = false
var _deploy_timer: float = 0.0
var _deploying: bool = false
var _undeploying: bool = false

const DEPLOY_TIME: float = 3.0

@onready var _packed_label: Label = get_node_or_null("PackedIndicator")

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	_refresh_packed_label()

func _add_player_color_stripe() -> void:
	PlayerColors.apply_color_stripe(self, player_id, 28.0, 6.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _physics_process(delta: float) -> void:
	if _deploying or _undeploying:
		_handle_deploy_animation(delta)
		return
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_attacking(delta)

func order_move(destination: Vector2) -> void:
	_attack_move_active = false
	attack_target = null
	_destination_state = UnitState.IDLE
	# Must undeploy before moving
	if is_deployed:
		_start_undeploy()
		return
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_attack(target: Node) -> void:
	attack_target = target
	_destination_state = UnitState.ATTACKING
	_move_destination = _nav_target_for(target)
	nav_agent.target_position = _move_destination
	if is_deployed:
		_start_undeploy()
	else:
		current_state = UnitState.MOVING

func order_deploy() -> void:
	if is_deployed or _deploying or _undeploying:
		return
	_start_deploy()

func order_undeploy() -> void:
	if not is_deployed or _deploying or _undeploying:
		return
	_start_undeploy()

func _start_deploy() -> void:
	_deploying = true
	_deploy_timer = 0.0
	nav_agent.set_velocity(Vector2.ZERO)

func _start_undeploy() -> void:
	_undeploying = true
	_deploy_timer = 0.0
	nav_agent.set_velocity(Vector2.ZERO)

func _handle_deploy_animation(delta: float) -> void:
	_deploy_timer += delta
	if _deploy_timer >= DEPLOY_TIME:
		if _deploying:
			is_deployed = true
			_deploying = false
			current_state = UnitState.ATTACKING
		else:
			is_deployed = false
			_undeploying = false
			# Resume movement if we had a pending order
			if attack_target != null and is_instance_valid(attack_target):
				nav_agent.target_position = _nav_target_for(attack_target)
				current_state = UnitState.MOVING
				_destination_state = UnitState.ATTACKING
			else:
				current_state = UnitState.IDLE
		_refresh_packed_label()

func _handle_movement(delta: float) -> void:
	if _destination_state == UnitState.ATTACKING and is_instance_valid(attack_target):
		var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
		var reach: float = _attack_reach_to(attack_target)
		if dist <= reach and dist >= reach * MIN_RANGE_RATIO:
			nav_agent.set_velocity(Vector2.ZERO)
			_start_deploy()
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
	if not is_deployed:
		_start_deploy()
		return
	if not is_instance_valid(attack_target):
		attack_target = null
		current_state = UnitState.IDLE
		return

	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var reach: float = _attack_reach_to(attack_target)
	var min_range: float = reach * MIN_RANGE_RATIO

	# Out of range: undeploy and move
	if dist > reach or dist < min_range:
		_start_undeploy()
		return

	nav_agent.set_velocity(Vector2.ZERO)
	_attack_timer += delta
	if _attack_timer >= 1.0 / unit_data.attack_speed:
		_attack_timer = 0.0
		_fire_at((attack_target as Node2D).global_position)

func _fire_at(target_pos: Vector2) -> void:
	var dmg: float = _get_effective_attack() * CivBonusManager.get_siege_attack_bonus(player_id)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = SPLASH_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, target_pos)
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
	AudioManager.play("hit_ranged", -2.0)

func _refresh_packed_label() -> void:
	if not is_instance_valid(_packed_label):
		return
	_packed_label.text = "[P]" if not is_deployed else "[D]"
	_packed_label.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.30, 1.0) if not is_deployed else Color(0.30, 1.0, 0.50, 1.0))

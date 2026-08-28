extends ShipBase

class_name Trireme

var _gold_timer: float = 0.0

const RAM_PUSH_DISTANCE: float = 40.0
const RAM_DAMAGE_MULTIPLIER: float = 2.0
## Passive gold trickle: 5 gold every 30 s, scaled by merchant_ship_gold_rate.
const GOLD_TICK_AMOUNT: float = 5.0
const GOLD_TICK_INTERVAL: float = 30.0

func _ready() -> void:
	super._ready()

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
	_tick_passive_gold(delta)

func _tick_passive_gold(delta: float) -> void:
	_gold_timer += delta
	if _gold_timer >= GOLD_TICK_INTERVAL:
		_gold_timer = 0.0
		var rate: float = CivBonusManager.get_multiplier(player_id, "merchant_ship_gold_rate")
		if rate > 0.0:
			ResourceManager.add_resource(player_id, "gold", int(GOLD_TICK_AMOUNT * rate))

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
		attack_target = null
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
	var effective_speed: float = unit_data.attack_speed * CivBonusManager.get_attack_speed_multiplier(player_id, unit_data.id)
	if _attack_timer >= 1.0 / effective_speed:
		_attack_timer = 0.0
		var armor: float = _get_target_armor(attack_target)
		var dmg: float = _get_effective_attack_vs(attack_target) - armor
		if _is_ship_target(attack_target):
			dmg *= RAM_DAMAGE_MULTIPLIER
		dmg = maxf(dmg, 1.0)
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(dmg, self)
			if _is_ship_target(attack_target):
				_push_target(attack_target)
			AudioManager.play_if_visible("hit_melee", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)

func _is_ship_target(target: Node) -> bool:
	return target is ShipBase

func _push_target(target: Node) -> void:
	var push_dir: Vector2 = ((target as Node2D).global_position - global_position).normalized()
	(target as Node2D).global_position += push_dir * RAM_PUSH_DISTANCE

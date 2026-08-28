extends UnitBase

class_name Conquistador

var _salvo_cooldown: float = 0.0
var _salvo_active: bool = false
var _salvo_shots_remaining: int = 0
var _salvo_shot_timer: float = 0.0

const SALVO_COOLDOWN_MAX: float = 12.0
const SALVO_SHOT_COUNT: int = 3
const SALVO_SHOT_INTERVAL: float = 0.3
const SALVO_SHOT_DAMAGE: float = 6.0

func get_selection_sound() -> String:
	return "select_infantry"

func _ready() -> void:
	super._ready()

# Stripe + shadow sized for the warhorse footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 11.0, 13.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 16.0, 5.0, 12.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:   _handle_movement(delta)
		UnitState.ATTACKING: _handle_attacking(delta)
	if _salvo_cooldown > 0.0:
		_salvo_cooldown -= delta
	if _salvo_active:
		_tick_salvo(delta)

func _tick_salvo(delta: float) -> void:
	if not is_instance_valid(attack_target):
		_salvo_active = false
		_salvo_shots_remaining = 0
		return
	_salvo_shot_timer -= delta
	if _salvo_shot_timer <= 0.0:
		_salvo_shot_timer = SALVO_SHOT_INTERVAL
		if attack_target.has_method("take_damage"):
			var dmg: float = SALVO_SHOT_DAMAGE * CivBonusManager.get_unit_attack_multiplier(player_id, unit_data.id) \
				- _get_target_armor(attack_target)
			attack_target.take_damage(maxf(dmg, 0.0), self)
			AudioManager.play_if_visible("hit_ranged", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)
		_salvo_shots_remaining -= 1
		if _salvo_shots_remaining <= 0:
			_salvo_active = false
			_salvo_cooldown = SALVO_COOLDOWN_MAX

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
		_scan_area_for_target()
		return
	if _salvo_active:
		nav_agent.set_velocity(Vector2.ZERO)
		return
	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var attack_reach: float = _attack_reach_to(attack_target)
	# Back away if enemy closes past 50% of attack range
	if dist < attack_reach * 0.5:
		var away: Vector2 = global_position + (global_position - (attack_target as Node2D).global_position).normalized() * 64.0
		nav_agent.target_position = _safe_destination(away)
		nav_agent.set_velocity(_nav_velocity())
		return
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
		if _salvo_cooldown <= 0.0:
			_salvo_active = true
			_salvo_shots_remaining = SALVO_SHOT_COUNT
			_salvo_shot_timer = 0.0
			return
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(_get_effective_attack_vs(attack_target) - _get_target_armor(attack_target), self)
			AudioManager.play_if_visible("hit_ranged", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)

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

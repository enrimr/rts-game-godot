extends UnitBase

class_name Longbowman

const ARROW_SCENE: PackedScene = preload("res://scenes/combat/arrow.tscn")

var attack_target: Node = null
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE
var _cover_fire_pos: Vector2 = Vector2.ZERO
var _cover_fire_pending: bool = false

const CAVALRY_IDS: Array[String] = ["scout", "heavy_scout", "knight", "chevalier_normand", "sand_raider"]
const CAVALRY_BONUS_DAMAGE: float = 4.0

func get_selection_sound() -> String:
	return "select_archer"

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 6.6, 10.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:   _handle_movement(delta)
		UnitState.ATTACKING: _handle_attacking(delta)

func order_move(destination: Vector2) -> void:
	_attack_move_active = false
	attack_target = null
	_cover_fire_pending = false
	_destination_state = UnitState.IDLE
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_attack_ground(world_pos: Vector2) -> void:
	attack_target = null
	_attack_move_active = false
	_cover_fire_pending = false
	var reach: float = unit_data.attack_range * 32.0
	if global_position.distance_to(world_pos) <= reach:
		_destination_state = UnitState.IDLE
		current_state = UnitState.IDLE
		nav_agent.set_velocity(Vector2.ZERO)
		_launch_arrow_to(world_pos)
	else:
		var dir: Vector2 = (world_pos - global_position).normalized()
		var stop_pos: Vector2 = world_pos - dir * reach * 0.85
		_cover_fire_pos = world_pos
		_cover_fire_pending = true
		_destination_state = UnitState.IDLE
		_navigate_to(stop_pos)
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
		if _cover_fire_pending:
			_cover_fire_pending = false
			_launch_arrow_to(_cover_fire_pos)
		current_state = _destination_state
		_destination_state = UnitState.IDLE
		nav_agent.set_velocity(Vector2.ZERO)
		return
	if _advance_stuck(delta):
		if _cover_fire_pending:
			_cover_fire_pending = false
			_launch_arrow_to(_cover_fire_pos)
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
	# Kiting: back away when enemy closes in, exploiting the Longbowman's superior range
	if dist < reach * 0.5:
		var away: Vector2 = global_position + (global_position - (attack_target as Node2D).global_position).normalized() * 96.0
		nav_agent.target_position = _safe_destination(away)
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
	var effective_speed: float = unit_data.attack_speed * CivBonusManager.get_attack_speed_multiplier(player_id, unit_data.id)
	if _attack_timer >= 1.0 / effective_speed:
		_attack_timer = 0.0
		_launch_arrow(attack_target)

func _launch_arrow(target: Node) -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	var dmg: float = _get_effective_attack_vs(target) - _get_target_armor(target)
	dmg += _get_cavalry_bonus(target)
	arrow.damage = dmg
	arrow.shooter = self
	arrow.target_pos = (target as Node2D).global_position
	arrow._original_target = target
	get_parent().add_child(arrow)
	arrow.global_position = global_position

func _launch_arrow_to(world_pos: Vector2) -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	arrow.damage = 0.0
	arrow.shooter = self
	arrow.target_pos = world_pos
	arrow._original_target = null
	get_parent().add_child(arrow)
	arrow.global_position = global_position

func _get_cavalry_bonus(target: Node) -> float:
	var udata: Variant = target.get("unit_data")
	if not (udata is UnitResource):
		return 0.0
	var uid: String = (udata as UnitResource).id
	for cavalry_id: String in CAVALRY_IDS:
		if uid == cavalry_id:
			return CAVALRY_BONUS_DAMAGE
	return 0.0

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

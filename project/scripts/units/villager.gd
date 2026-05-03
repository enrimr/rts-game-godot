extends UnitBase

class_name Villager

## Villager — gathers resources, drops them off, and constructs buildings.

@export var carry_capacity: float = 10.0
@export var gather_rate: float = 1.0
@export var build_rate: float = 25.0
@export var gather_interval: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gather_indicator: Label = $GatherIndicator
@onready var attack_range_area: Area2D = $AttackRange

var gather_target: Node = null
var carried_resource: String = ""
var carried_amount: float = 0.0
var drop_off_target: Node = null
var build_target: Node = null
var attack_target: Node = null

var _gather_timer: float = 0.0
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

const BUILD_RANGE: float = 60.0
const DROP_OFF_RANGE: float = 72.0
const GATHER_RANGE: float = 48.0

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.GATHERING:
			_handle_gathering(delta)
		UnitState.RETURNING:
			_handle_returning(delta)
		UnitState.BUILDING:
			_handle_building(delta)
		UnitState.ATTACKING:
			_handle_attacking(delta)

# --- Public API ---

func order_gather(target: Node, resource_type: String, drop_off: Node) -> void:
	_unregister_from_build_target()
	gather_target = target
	carried_resource = resource_type
	drop_off_target = drop_off
	build_target = null
	attack_target = null
	_destination_state = UnitState.GATHERING
	_start_move_to((target as Node2D).global_position)

func order_build(target: Node) -> void:
	_unregister_from_build_target()
	if is_instance_valid(build_target) and build_target.construction_complete.is_connected(_on_construction_complete):
		build_target.construction_complete.disconnect(_on_construction_complete)
	build_target = target
	gather_target = null
	attack_target = null
	_destination_state = UnitState.BUILDING
	build_target.construction_complete.connect(_on_construction_complete, CONNECT_ONE_SHOT)
	_start_move_to((target as Node2D).global_position)

func order_move(destination: Vector2) -> void:
	_unregister_from_build_target()
	gather_target = null
	build_target = null
	attack_target = null
	_destination_state = UnitState.IDLE
	_start_move_to(destination)

func order_attack(target: Node) -> void:
	_unregister_from_build_target()
	attack_target = target
	gather_target = null
	build_target = null
	_destination_state = UnitState.ATTACKING
	_start_move_to(target.global_position)

# --- Internal helpers ---

func _start_move_to(destination: Vector2) -> void:
	nav_agent.target_position = destination
	current_state = UnitState.MOVING
	_play_animation(_get_animation_name())

func _handle_movement(delta: float) -> void:
	# Distance-based transitions for targets with collision — don't rely on is_navigation_finished
	if _destination_state == UnitState.BUILDING and is_instance_valid(build_target):
		if global_position.distance_to((build_target as Node2D).global_position) <= BUILD_RANGE:
			_enter_state(UnitState.BUILDING)
			return
	elif _destination_state == UnitState.GATHERING and is_instance_valid(gather_target):
		if global_position.distance_to((gather_target as Node2D).global_position) <= GATHER_RANGE:
			_enter_state(UnitState.GATHERING)
			return
	elif _destination_state == UnitState.RETURNING and is_instance_valid(drop_off_target):
		if global_position.distance_to((drop_off_target as Node2D).global_position) <= DROP_OFF_RANGE:
			_enter_state(UnitState.RETURNING)
			return

	if nav_agent.is_navigation_finished():
		_enter_state(_destination_state)
		return

	if _advance_stuck(delta):
		_jitter_repath()
		return

	nav_agent.set_velocity(_nav_velocity())

func _enter_state(new_state: UnitState) -> void:
	if new_state == UnitState.BUILDING and is_instance_valid(build_target):
		build_target.register_builder()
	current_state = new_state
	_destination_state = UnitState.IDLE
	nav_agent.set_velocity(Vector2.ZERO)
	_play_animation(_get_animation_name())

func _unregister_from_build_target() -> void:
	if current_state == UnitState.BUILDING and is_instance_valid(build_target):
		build_target.unregister_builder()

func _jitter_repath() -> void:
	var jitter: Vector2 = Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	nav_agent.target_position = nav_agent.target_position + jitter

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func _handle_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())
		return

	var dist: float = global_position.distance_to((gather_target as Node2D).global_position)
	if dist > GATHER_RANGE:
		_destination_state = UnitState.GATHERING
		_start_move_to((gather_target as Node2D).global_position)
		return

	_gather_timer += delta
	if _gather_timer >= gather_interval:
		_gather_timer = 0.0
		var available: float = gather_target.gather(gather_rate)
		carried_amount = minf(carried_amount + available, carry_capacity)
		_update_gather_indicator()

		if not (gather_target is ResourceNode):
			ResourceManager.add_resource(player_id, carried_resource, carried_amount)
			carried_amount = 0.0
			_update_gather_indicator()
		elif carried_amount >= carry_capacity:
			var drop_off: Node = _resolve_drop_off()
			if is_instance_valid(drop_off):
				drop_off_target = drop_off
				_destination_state = UnitState.RETURNING
				_start_move_to((drop_off as Node2D).global_position)
			else:
				ResourceManager.add_resource(player_id, carried_resource, carried_amount)
				carried_amount = 0.0
				_update_gather_indicator()

func _handle_returning(delta: float) -> void:
	if not is_instance_valid(drop_off_target):
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())
		return

	var dist: float = global_position.distance_to((drop_off_target as Node2D).global_position)
	if dist <= DROP_OFF_RANGE:
		ResourceManager.add_resource(player_id, carried_resource, carried_amount)
		carried_amount = 0.0
		_update_gather_indicator()
		if is_instance_valid(gather_target):
			_destination_state = UnitState.GATHERING
			_start_move_to((gather_target as Node2D).global_position)
		else:
			current_state = UnitState.IDLE
			_play_animation(_get_animation_name())
		return

	if _advance_stuck(delta):
		_jitter_repath()
		return

	nav_agent.set_velocity(_nav_velocity())

func _handle_building(delta: float) -> void:
	if not is_instance_valid(build_target):
		build_target = null
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())
		return

	var build_pos: Vector2 = (build_target as Node2D).global_position
	var dist: float = global_position.distance_to(build_pos)
	if dist > BUILD_RANGE:
		var approach: Vector2 = build_pos + (global_position - build_pos).normalized() * (BUILD_RANGE * 0.5)
		nav_agent.target_position = approach
		if _advance_stuck(delta):
			_jitter_repath()
			return
		nav_agent.set_velocity(_nav_velocity())
		return

	nav_agent.set_velocity(Vector2.ZERO)
	build_target.add_construction(build_rate * delta)

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())
		return

	var dist: float = global_position.distance_to(attack_target.global_position)
	var attack_reach: float = unit_data.attack_range * 32.0
	if dist > attack_reach:
		nav_agent.target_position = attack_target.global_position
		if _advance_stuck(delta):
			_jitter_repath()
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

func _resolve_drop_off() -> Node:
	return _find_nearest_drop_off()

func _find_nearest_drop_off() -> Node:
	var root: Node = get_tree().root
	var best: Node = null
	var best_dist: float = INF
	var queue: Array[Node] = [root]
	var idx: int = 0
	while idx < queue.size():
		var current: Node = queue[idx]
		idx += 1
		if current is DropOffBuilding:
			var drop: DropOffBuilding = current as DropOffBuilding
			if drop.player_id == player_id:
				var pos_node: Node2D = current as Node2D
				var d: float = global_position.distance_to(pos_node.global_position)
				if d < best_dist:
					best_dist = d
					best = current
		for child: Node in current.get_children():
			queue.append(child)
	return best

func _on_construction_complete() -> void:
	_unregister_from_build_target()
	build_target = null
	current_state = UnitState.IDLE
	_play_animation(_get_animation_name())

func _update_gather_indicator() -> void:
	if not is_instance_valid(gather_indicator):
		return
	if carried_amount > 0.0:
		gather_indicator.text = carried_resource + " " + str(int(carried_amount))
	else:
		gather_indicator.text = ""

func _get_animation_name() -> String:
	match current_state:
		UnitState.IDLE:
			return "idle"
		UnitState.MOVING:
			return "walk"
		UnitState.GATHERING:
			return "gather"
		UnitState.RETURNING:
			return "walk"
		UnitState.BUILDING:
			return "build"
		UnitState.ATTACKING:
			return "attack"
		UnitState.DEAD:
			return "die"
	return "idle"

func _play_animation(anim_name: String) -> void:
	if not is_instance_valid(animated_sprite):
		return
	if animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)

func die() -> void:
	_unregister_from_build_target()
	current_state = UnitState.DEAD
	_play_animation("die")
	EventBus.unit_died.emit(self, player_id)
	get_tree().create_timer(1.0).timeout.connect(queue_free)

extends UnitBase

class_name Villager

## Villager — gathers resources, drops them off, and constructs buildings.

@export var carry_capacity: float = 10.0
@export var gather_rate: float = 1.0
@export var build_rate: float = 25.0
@export var gather_interval: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gather_indicator: Label = $GatherIndicator

var gather_target: Node = null
var carried_resource: String = ""
var carried_amount: float = 0.0
var drop_off_target: Node = null
var build_target: Node = null
var attack_target: Node = null

var _gather_timer: float = 0.0
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE
var _farm_gathered: float = 0.0

const BUILD_RANGE: float = 60.0
const DROP_OFF_RANGE: float = 72.0
const GATHER_RANGE: float = 48.0
const FALLBACK_RESOURCE_RANGE: float = 400.0
const REPAIR_RATE: float = 10.0  # HP per second restored when repairing

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_enemy_entered_range(_body: Node) -> void:
	pass  # Villagers do not proactively attack; they only retaliate via take_damage.

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

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
	_farm_gathered = 0.0
	_destination_state = UnitState.GATHERING
	_start_move_to((target as Node2D).global_position)

func order_drop_off(target: Node) -> void:
	if carried_amount <= 0.0:
		return
	_unregister_from_build_target()
	drop_off_target = target
	build_target = null
	attack_target = null
	_destination_state = UnitState.RETURNING
	_start_move_to((target as Node2D).global_position)

func order_build(target: Node) -> void:
	_unregister_from_build_target()
	if is_instance_valid(build_target) and build_target.get("construction_complete") != null:
		if build_target.construction_complete.is_connected(_on_construction_complete):
			build_target.construction_complete.disconnect(_on_construction_complete)
	build_target = target
	gather_target = null
	attack_target = null
	_destination_state = UnitState.BUILDING
	var bstate: Variant = target.get("state")
	var is_under_construction: bool = bstate != null and (bstate as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION
	if is_under_construction:
		build_target.construction_complete.connect(_on_construction_complete, CONNECT_ONE_SHOT)
	# For complete buildings (repair) approach the edge, not the center
	var dest: Vector2 = _nav_target_for(target) if not is_under_construction else (target as Node2D).global_position
	_start_move_to(dest)

func order_move(destination: Vector2) -> void:
	_attack_move_active = false
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
	_start_move_to(_nav_target_for(target))

# --- Internal helpers ---

func _start_move_to(destination: Vector2) -> void:
	nav_agent.target_position = _safe_destination(destination)
	current_state = UnitState.MOVING
	_play_animation(_get_animation_name())

func _handle_movement(delta: float) -> void:
	# Distance-based transitions for targets with collision — don't rely on is_navigation_finished
	if _destination_state == UnitState.ATTACKING and is_instance_valid(attack_target):
		var attack_reach: float = _attack_reach_to(attack_target)
		if global_position.distance_to((attack_target as Node2D).global_position) <= attack_reach:
			_enter_state(UnitState.ATTACKING)
			return
	elif _destination_state == UnitState.BUILDING and is_instance_valid(build_target):
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
		# register_builder only exists on BuildingBase (under-construction buildings)
		var bstate: Variant = build_target.get("state")
		if bstate != null and (bstate as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			build_target.register_builder()
	current_state = new_state
	_destination_state = UnitState.IDLE
	nav_agent.set_velocity(Vector2.ZERO)
	_play_animation(_get_animation_name())

func _unregister_from_build_target() -> void:
	if current_state == UnitState.BUILDING and is_instance_valid(build_target):
		var bstate: Variant = build_target.get("state")
		if bstate != null and (bstate as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			build_target.unregister_builder()

func _jitter_repath() -> void:
	var jitter: Vector2 = Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	nav_agent.target_position = nav_agent.target_position + jitter

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func _handle_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		var fallback: Node = _find_nearest_same_resource()
		if fallback != null:
			gather_target = fallback
			_destination_state = UnitState.GATHERING
			_start_move_to((fallback as Node2D).global_position)
		else:
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
		var rate_mult: float = CivBonusManager.get_gather_rate_multiplier(player_id, carried_resource)
		carried_amount = minf(carried_amount + available * rate_mult, carry_capacity)

		if not (gather_target is ResourceNode):
			_farm_gathered += available
			ResourceManager.add_resource(player_id, carried_resource, carried_amount)
			carried_amount = 0.0
			if is_instance_valid(gather_indicator):
				gather_indicator.text = carried_resource + " " + str(int(_farm_gathered))
		else:
			_update_gather_indicator()

		if gather_target is ResourceNode and carried_amount >= carry_capacity:
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
		nav_agent.target_position = _safe_destination(approach)
		if _advance_stuck(delta):
			_jitter_repath()
			return
		nav_agent.set_velocity(_nav_velocity())
		return

	nav_agent.set_velocity(Vector2.ZERO)

	# Repair: building is complete (or has no state, e.g. TownCenterBuilding) and damaged
	var bstate: Variant = build_target.get("state")
	var is_complete: bool = bstate == null or (bstate as int) == BuildingBase.BuildingState.COMPLETE
	if is_complete:
		var cur_hp: Variant = build_target.get("health")
		var max_hp: Variant = build_target.get("max_health")
		if cur_hp != null and max_hp != null:
			var new_hp: float = minf((cur_hp as float) + REPAIR_RATE * delta, max_hp as float)
			build_target.set("health", new_hp)
			var hbar: ProgressBar = build_target.get_node_or_null("HealthBar") as ProgressBar
			if is_instance_valid(hbar):
				hbar.value = new_hp / (max_hp as float) * 100.0
			if new_hp >= (max_hp as float):
				build_target = null
				current_state = UnitState.IDLE
				_play_animation(_get_animation_name())
		return

	# Construction: building is under construction
	build_target.add_construction(build_rate * delta)

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		attack_target = null
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())
		return

	var target_pos: Vector2 = (attack_target as Node2D).global_position
	var dist: float = global_position.distance_to(target_pos)
	var attack_reach: float = _attack_reach_to(attack_target)
	if dist > attack_reach:
		nav_agent.target_position = _nav_target_for(attack_target)
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
			attack_target.take_damage(_get_effective_attack() - _get_target_armor(attack_target), self)
			AudioManager.play("hit_melee", -4.0)
			EventBus.unit_attacked.emit(self, attack_target)

func _find_nearest_same_resource() -> Node:
	if carried_resource.is_empty():
		return null
	var best: Node = null
	var best_dist: float = FALLBACK_RESOURCE_RANGE
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.get_resource_name() != carried_resource:
			continue
		var d: float = global_position.distance_to((rn as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = rn
	return best

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
	var next: Node = _find_nearest_construction()
	if next != null:
		order_build(next)
	else:
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())

const CONSTRUCTION_SEARCH_RANGE: float = 400.0

func _find_nearest_construction() -> Node:
	var best: Node = null
	var best_dist: float = CONSTRUCTION_SEARCH_RANGE
	for building: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		var bpid: Variant = building.get("player_id")
		if bpid == null or (bpid as int) != player_id:
			continue
		var bstate: Variant = building.get("state")
		if bstate == null or (bstate as int) != BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			continue
		var d: float = global_position.distance_to((building as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = building
	return best

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

extends UnitBase

class_name Villager

## Villager — gathers resources, drops them off, and constructs buildings.

@export var carry_capacity: float = 10.0
@export var gather_rate: float = 1.0
@export var build_rate: float = 25.0
@export var gather_interval: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gather_indicator: Label = $GatherIndicator
@onready var _body_node: Node2D = $Body
@onready var _head_poly: Node2D = $Body/Head
@onready var _tool_poly: Node2D = $Body/Tool

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
var _gather_blocked_retries: int = 0
var _gathering_active: bool = false

# Transport embark state — set when villager needs to cross water to reach target
var _pending_transport_target: Node = null      # resource node to reach after crossing
var _pending_transport_resource: String = ""    # resource type for the pending gather
var _pending_transport_drop_off: Node = null    # drop-off for the pending gather
var _boarding_ship: Node = null                 # ship we're walking toward to board

const BUILD_RANGE: float = 60.0
const DROP_OFF_RANGE: float = 72.0
const GATHER_RANGE: float = 48.0
const FALLBACK_RESOURCE_RANGE: float = 400.0
const BLOCKED_RESOURCE_RANGE: float = 180.0
const GATHER_BLOCKED_MAX: int = 3
const REPAIR_RATE: float = 10.0  # HP per second restored when repairing
const BOARD_APPROACH_RANGE: float = 60.0

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _process(delta: float) -> void:
	_anim_time += delta
	_animate_body()

func _animate_body() -> void:
	if not is_instance_valid(_body_node):
		return
	var t: float = _anim_time
	match current_state:
		UnitState.GATHERING:
			# Chop swing: body rocks forward, tool swings down then up
			var chop: float = sin(t * TAU * 2.5)
			_body_node.rotation = chop * 0.18
			if is_instance_valid(_tool_poly):
				_tool_poly.rotation = -chop * 0.55
			if is_instance_valid(_head_poly):
				_head_poly.rotation = chop * 0.12
		UnitState.BUILDING:
			# Hammer swing: faster, tool pivots more aggressively
			var hammer: float = sin(t * TAU * 3.0)
			_body_node.rotation = hammer * 0.14
			if is_instance_valid(_tool_poly):
				_tool_poly.rotation = -hammer * 0.70
			if is_instance_valid(_head_poly):
				_head_poly.rotation = hammer * 0.10
		UnitState.MOVING, UnitState.RETURNING:
			# Walk: gentle body sway + head bob
			var walk: float = sin(t * TAU * 2.8)
			_body_node.rotation = walk * 0.10
			if is_instance_valid(_head_poly):
				_head_poly.position.y = abs(walk) * -1.5
			if is_instance_valid(_tool_poly):
				_tool_poly.rotation = walk * 0.20
		UnitState.ATTACKING:
			var swing: float = sin(t * TAU * 4.0)
			_body_node.rotation = swing * 0.20
			if is_instance_valid(_tool_poly):
				_tool_poly.rotation = -swing * 0.60
			if is_instance_valid(_head_poly):
				_head_poly.rotation = 0.0
		_:
			# Idle: very slow breathing sway
			var idle: float = sin(t * TAU * 0.5)
			_body_node.rotation = idle * 0.03
			if is_instance_valid(_head_poly):
				_head_poly.position.y = idle * -0.5
				_head_poly.rotation = 0.0
			if is_instance_valid(_tool_poly):
				_tool_poly.rotation = 0.0

func _on_enemy_entered_range(_body: Node) -> void:
	pass  # Villagers do not proactively attack; they only retaliate via take_damage.

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _physics_process(delta: float) -> void:
	if is_instance_valid(_boarding_ship):
		_handle_boarding_approach(delta)
		return
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

func _cancel_transport() -> void:
	if EventBus.garrison_changed.is_connected(_on_transport_garrison_changed):
		EventBus.garrison_changed.disconnect(_on_transport_garrison_changed)
	_boarding_ship = null
	_pending_transport_target = null
	_pending_transport_resource = ""
	_pending_transport_drop_off = null

func get_selection_sound() -> String:
	return "select_villager"

func order_gather(target: Node, resource_type: String, drop_off: Node) -> void:
	_stop_gathering_active()
	_release_gather_target()
	_unregister_from_build_target()
	_cancel_transport()
	gather_target = target
	carried_resource = resource_type
	drop_off_target = drop_off
	build_target = null
	attack_target = null
	_farm_gathered = 0.0
	if _needs_transport_to((target as Node2D).global_position):
		_try_board_transport(target, resource_type, drop_off)
		return
	_destination_state = UnitState.GATHERING
	_gather_blocked_retries = 0
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
	_stop_gathering_active()
	_release_gather_target()
	_cancel_transport()
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
	_stop_gathering_active()
	_release_gather_target()
	_attack_move_active = false
	_cancel_transport()
	_unregister_from_build_target()
	gather_target = null
	build_target = null
	attack_target = null
	_destination_state = UnitState.IDLE
	_move_destination = destination
	_start_move_to(destination)

func order_attack(target: Node) -> void:
	_stop_gathering_active()
	_release_gather_target()
	_cancel_transport()
	_unregister_from_build_target()
	attack_target = target
	gather_target = null
	build_target = null
	_destination_state = UnitState.ATTACKING
	_start_move_to(_nav_target_for(target))

func _release_gather_target() -> void:
	if is_instance_valid(gather_target) and gather_target is ResourceNode:
		if (gather_target as ResourceNode).resource_type == ResourceNode.ResourceType.WOOD:
			(gather_target as ResourceNode).set_being_gathered(false)

func _stop_gathering_active() -> void:
	if _gathering_active:
		_gathering_active = false
		EventBus.gatherer_changed.emit(player_id, carried_resource, -1)

func _start_gathering_active() -> void:
	if not _gathering_active:
		_gathering_active = true
		EventBus.gatherer_changed.emit(player_id, carried_resource, 1)

# --- Internal helpers ---

func _start_move_to(destination: Vector2) -> void:
	_move_destination = destination
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
	_unstick()

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if current_state == UnitState.IDLE or current_state == UnitState.DEAD:
		return
	velocity = safe_velocity
	move_and_slide()

func _handle_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		var fallback: Node = _find_nearest_same_resource()
		if fallback != null:
			_release_gather_target()
			gather_target = fallback
			_gather_blocked_retries = 0
			_destination_state = UnitState.GATHERING
			_start_move_to((fallback as Node2D).global_position)
		else:
			_stop_gathering_active()
			current_state = UnitState.IDLE
			_play_animation(_get_animation_name())
		return

	var dist: float = global_position.distance_to((gather_target as Node2D).global_position)
	if dist > GATHER_RANGE:
		_gather_blocked_retries += 1
		if _gather_blocked_retries >= GATHER_BLOCKED_MAX:
			_gather_blocked_retries = 0
			var alt: Node = ResourceManager.get_nearest_resource(
				carried_resource, global_position, BLOCKED_RESOURCE_RANGE, gather_target)
			if alt != null:
				gather_target = alt
		_destination_state = UnitState.GATHERING
		_start_move_to((gather_target as Node2D).global_position)
		return
	_gather_blocked_retries = 0

	_gather_timer += delta
	if _gather_timer >= gather_interval:
		_gather_timer = 0.0
		if gather_target is ResourceNode \
				and (gather_target as ResourceNode).resource_type == ResourceNode.ResourceType.WOOD:
			(gather_target as ResourceNode).set_being_gathered(true)
		_start_gathering_active()
		var available: float = gather_target.gather(gather_rate)
		var rate_mult: float = CivBonusManager.get_gather_rate_multiplier(player_id, carried_resource) \
			* WeatherManager.get_gather_rate_multiplier(carried_resource, global_position)
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
				_release_gather_target()
				drop_off_target = drop_off
				_destination_state = UnitState.RETURNING
				_start_move_to((drop_off as Node2D).global_position)
			else:
				pass  # No drop-off exists — hold resources until one becomes available

func _handle_returning(_delta: float) -> void:
	if not is_instance_valid(drop_off_target):
		var fallback: Node = _find_nearest_drop_off()
		if fallback != null:
			drop_off_target = fallback
			_destination_state = UnitState.RETURNING
			_start_move_to((fallback as Node2D).global_position)
		else:
			current_state = UnitState.IDLE
			_play_animation(_get_animation_name())
		return

	var dist: float = global_position.distance_to((drop_off_target as Node2D).global_position)
	if dist > DROP_OFF_RANGE * 2.5:
		var alt: Node = _find_nearest_drop_off()
		if is_instance_valid(alt):
			drop_off_target = alt
		_destination_state = UnitState.RETURNING
		_start_move_to((drop_off_target as Node2D).global_position)
		return

	ResourceManager.add_resource(player_id, carried_resource, carried_amount)
	carried_amount = 0.0
	_update_gather_indicator()
	if is_instance_valid(gather_target):
		_gather_blocked_retries = 0
		_destination_state = UnitState.GATHERING
		_start_move_to((gather_target as Node2D).global_position)
	else:
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())

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
			attack_target.take_damage(_get_effective_attack_vs(attack_target) - _get_target_armor(attack_target), self)
			AudioManager.play_if_visible("hit_melee", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)

func _needs_transport_to(target_pos: Vector2) -> bool:
	if not MatchConfig.map_type == MatchConfig.MapType.ISLANDS:
		return false
	if TerrainManager.is_ocean(global_position):
		return false
	if not TerrainManager.is_ocean(target_pos):
		return false
	# Confirm there's no land path by checking a midpoint sample
	var mid: Vector2 = global_position.lerp(target_pos, 0.5)
	return TerrainManager.is_ocean(mid)

func _find_allied_transport() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for unit: Node in get_parent().get_children():
		if not is_instance_valid(unit) or not (unit is TransportShip):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if (unit as TransportShip).is_full():
			continue
		var d: float = global_position.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

func _try_board_transport(target: Node, resource_type: String, drop_off: Node) -> bool:
	var transport: Node = _find_allied_transport()
	if transport == null:
		return false
	_pending_transport_target   = target
	_pending_transport_resource = resource_type
	_pending_transport_drop_off = drop_off
	_boarding_ship = transport
	_destination_state = UnitState.IDLE
	_start_move_to((transport as Node2D).global_position)
	return true

func _handle_boarding_approach(delta: float) -> void:
	if not is_instance_valid(_boarding_ship):
		_boarding_ship = null
		_pending_transport_target = null
		current_state = UnitState.IDLE
		return
	var dist: float = global_position.distance_to((_boarding_ship as Node2D).global_position)
	if dist <= BOARD_APPROACH_RANGE:
		var boarded: bool = (_boarding_ship as TransportShip).board(self)
		if boarded:
			# After unloading the ship calls set_process(true) and restores position.
			# Connect to garrison_changed to detect when we've been dropped off.
			if not EventBus.garrison_changed.is_connected(_on_transport_garrison_changed):
				EventBus.garrison_changed.connect(_on_transport_garrison_changed)
		else:
			# Ship full — abort transport, try direct path
			_boarding_ship = null
			_pending_transport_target = null
		return
	if _advance_stuck(delta):
		_jitter_repath()
		return
	nav_agent.set_velocity(_nav_velocity())

func _on_transport_garrison_changed(ship: Node, _current_size: int, _capacity: int) -> void:
	if ship != _boarding_ship:
		return
	if not visible:
		return
	var garrison: Array = (_boarding_ship as TransportShip).get_garrison()
	if garrison.has(self):
		return
	var target: Node = _pending_transport_target
	var res:    String = _pending_transport_resource
	var drop:   Node = _pending_transport_drop_off
	_cancel_transport()
	if is_instance_valid(target) and not res.is_empty():
		order_gather(target, res, drop)

func _find_nearest_same_resource() -> Node:
	if carried_resource.is_empty():
		return null
	return ResourceManager.get_nearest_resource(carried_resource, global_position, FALLBACK_RESOURCE_RANGE)

func _resolve_drop_off() -> Node:
	return _find_nearest_drop_off()

func _find_nearest_drop_off() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		if not is_instance_valid(node):
			continue
		var drop: DropOffBuilding = node as DropOffBuilding
		if drop.player_id != player_id:
			continue
		var d: float = global_position.distance_to((node as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

const _DROP_OFF_RESOURCE_TYPES: Dictionary = {
	"lumber_camp":  [ResourceNode.ResourceType.WOOD],
	"mining_camp":  [ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE],
}

func _on_construction_complete() -> void:
	_unregister_from_build_target()
	var just_built: Node = build_target
	build_target = null

	# If the completed building is a resource drop-off, go gather the nearest
	# matching resource instead of looking for more construction.
	if is_instance_valid(just_built):
		var resource_target: Node = _find_gather_target_for_drop_off(just_built)
		if resource_target != null:
			var rname: String = (resource_target as ResourceNode).get_resource_name()
			order_gather(resource_target, rname, just_built)
			return

	var next: Node = _find_nearest_construction()
	if next != null:
		order_build(next)
	else:
		current_state = UnitState.IDLE
		_play_animation(_get_animation_name())

func _find_gather_target_for_drop_off(building: Node) -> Node:
	var bdata: Variant = building.get("building_data")
	if bdata == null:
		return null
	var bid: String = (bdata as Resource).get("id") as String
	var rtypes: Array = _DROP_OFF_RESOURCE_TYPES.get(bid, []) as Array
	if rtypes.is_empty():
		return null
	var best: Node = null
	var best_dist: float = INF
	for rtype: Variant in rtypes:
		var node: ResourceNode = ResourceManager.get_nearest_resource(
			ResourceNode.RESOURCE_NAMES.get(rtype as ResourceNode.ResourceType, ""),
			(building as Node2D).global_position,
			600.0
		)
		if node == null:
			continue
		var d: float = (building as Node2D).global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

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
	_stop_gathering_active()
	_cancel_transport()
	_unregister_from_build_target()
	current_state = UnitState.DEAD
	_play_animation("die")
	EventBus.unit_died.emit(self, player_id)
	get_tree().create_timer(1.0).timeout.connect(queue_free)

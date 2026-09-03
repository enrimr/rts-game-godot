extends UnitBase

## Presa Canario — the Mill's herding dog. It never fights: its machine is
## fetch-and-lead. An explicit herd order (right-click an animal with a
## dogs-only selection) walks it to the animal, puts the animal in tow
## (a sheep converts on contact — the dog carries the owner's player_id into
## the ConvertArea — wild game merely follows), then leads it back to the
## nearest own drop-off and releases it there: sheep join the flock, deer
## settle within hunting range of the base.

const HERD_REACH: float = 44.0        # close enough to take the animal in tow
const RELEASE_REACH: float = 90.0     # close enough to home to let it go
const HERD_LAG_LIMIT: float = 150.0   # never outrun the animal by more than this

enum HerdPhase { NONE, FETCH, LEAD }

var herd_target: Animal = null
var _herd_phase: HerdPhase = HerdPhase.NONE
var _home: Vector2 = Vector2.ZERO
var _trot_time: float = 0.0

func _ready() -> void:
	super._ready()
	stance = Stance.PASSIVE

func is_combat_unit() -> bool:
	return false

func get_selection_sound() -> String:
	return "select_dog"

## The command layer's entry point (UnitTargetCommand "herd" verb).
func order_herd(target: Node) -> void:
	if not (target is Animal) or (target as Animal).current_state == Animal.AnimalState.DEAD:
		return
	clear_waypoints()
	attack_target = null
	herd_target = target as Animal
	_herd_phase = HerdPhase.FETCH
	_home = _resolve_home()
	current_state = UnitState.ATTACKING   # reused as the "working" state
	_navigate_to(herd_target.global_position)

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_herding()

func _handle_herding() -> void:
	if not is_instance_valid(herd_target) \
			or herd_target.current_state == Animal.AnimalState.DEAD:
		_finish_herd()
		return
	match _herd_phase:
		HerdPhase.FETCH:
			if global_position.distance_to(herd_target.global_position) <= HERD_REACH:
				herd_target.start_following(self)
				_herd_phase = HerdPhase.LEAD
				_repath_to(_home)
			else:
				_repath_to(herd_target.global_position)
			_drive_agent(_nav_velocity())
		HerdPhase.LEAD:
			if global_position.distance_to(_home) <= RELEASE_REACH:
				_finish_herd()
				return
			# Pause when the animal falls behind: a herd arrives together.
			if global_position.distance_to(herd_target.global_position) > HERD_LAG_LIMIT:
				_drive_agent(Vector2.ZERO)
			else:
				_repath_to(_home)
				_drive_agent(_nav_velocity())
		_:
			_finish_herd()

func _finish_herd() -> void:
	if is_instance_valid(herd_target) and _herd_phase == HerdPhase.LEAD:
		herd_target.stop_following()
	herd_target = null
	_herd_phase = HerdPhase.NONE
	current_state = UnitState.IDLE
	_drive_agent(Vector2.ZERO)

## Home is the nearest own drop-off (TC, Mill, any camp) at ORDER time — a
## fixed point, so mid-trip building losses don't strand the pair mid-map.
func _resolve_home() -> Vector2:
	var best: Vector2 = global_position
	var best_dist: float = INF
	for b: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		var owner_node: Node = b.get_parent()
		if owner_node == null or (owner_node.get("player_id") as int) != player_id:
			continue
		var pos: Vector2 = (owner_node as Node2D).global_position
		var d: float = global_position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = pos
	return best

## He never fights back — a barked warning is not a combat state.
func _auto_engage(_target: Node) -> void:
	pass

## Quadruped footprint: the humanoid-width plinth/shadow looked like a
## saucer under a long low body.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 13.0, 9.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 13.0, 5.0, 9.0)

## Diagonal-pair trot, the Animal gait on a UnitBase machine: the rig's four
## legs (Front/Back × Near/Far) swing in counter-phase while moving.
func _animate_body(delta: float) -> void:
	var moving: bool = current_state != UnitState.DEAD and velocity.length_squared() > 4.0
	if moving:
		_trot_time += delta
	var phases: Dictionary = {
		"LegFrontFar": 0.0, "LegBackNear": 0.0,
		"LegBackFar": PI, "LegFrontNear": PI,
	}
	for leg_name: String in phases:
		var leg: Polygon2D = get_node_or_null("Body/" + leg_name) as Polygon2D
		if leg == null:
			continue
		var target_x: float = 0.0
		if moving:
			target_x = sin(_trot_time * TAU * 3.4 + (phases[leg_name] as float)) * 2.2
		leg.position.x = lerpf(leg.position.x, target_x, clampf(delta * 12.0, 0.0, 1.0))

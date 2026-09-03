extends UnitBase

## Presa Canario — the Mill's herding dog, and a guard dog when pressed: a
## villager-grade bite on a fast frame, DEFENSIVE by default. Herding is
## sacred, though — while a trip is underway he ignores auto-engagement
## entirely, and only an explicit attack order makes him drop the flock
## (releasing the animal where it stands, paying the approach earned so far).
## The herd machine: an explicit herd order (right-click an animal with a
## dogs-only selection) walks him to the animal, puts it in tow (a sheep
## converts on contact — the dog carries the owner's player_id into the
## ConvertArea — wild game merely follows), then leads it back to the
## nearest own drop-off and releases it there: sheep join the flock, deer
## settle within hunting range of the base.

const HERD_REACH: float = 44.0        # close enough to take the animal in tow
const RELEASE_REACH: float = 90.0     # close enough to home to let it go
const HERD_LAG_LIMIT: float = 150.0   # never outrun the animal by more than this

## The shepherd's yield: every herding trip pays food for the NET distance
## the animal was brought toward home (1 food / HERD_FOOD_PX px). Net, not
## walked — shuttling a sheep in circles pays nothing, only real approach
## does, so the reward can't be farmed without doing the actual job.
const HERD_FOOD_PX: float = 40.0

enum HerdPhase { NONE, FETCH, LEAD }

var herd_target: Animal = null
var _herd_phase: HerdPhase = HerdPhase.NONE
var _home: Vector2 = Vector2.ZERO
var _pickup_home_dist: float = 0.0
var _trot_time: float = 0.0

func _ready() -> void:
	super._ready()
	stance = Stance.DEFENSIVE
	# The collar IS the ownership mark on a natural-coat animal: dye it the
	# team colour directly (TeamDress's cloth rules never matched it, so it
	# shipped stuck on its authored red whoever owned the dog).
	var collar: Polygon2D = get_node_or_null("Body/Collar") as Polygon2D
	if collar != null:
		collar.color = PlayerColors.get_color(player_id)

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

## Herding rides the ATTACKING state (phase set); real combat is the base
## machine untouched.
func _physics_process(delta: float) -> void:
	if current_state == UnitState.ATTACKING and _herd_phase != HerdPhase.NONE:
		_handle_herding()
		return
	super._physics_process(delta)

## An explicit attack order drops the flock first — the animal is released
## where it stands and the approach earned so far is paid out.
func order_attack(target: Node) -> void:
	if _herd_phase != HerdPhase.NONE:
		_finish_herd()
	super.order_attack(target)

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
				_pickup_home_dist = herd_target.global_position.distance_to(_home)
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
		var approach: float = _pickup_home_dist \
			- herd_target.global_position.distance_to(_home)
		var gained: int = int(maxf(approach, 0.0) / HERD_FOOD_PX)
		if gained > 0:
			ResourceManager.add_resource(player_id, "food", gained)
			if player_id == 0:
				AudioManager.play("gather_food")
		EventBus.animal_herded.emit(herd_target, player_id)
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

## Herding is sacred: no auto-acquired scrap may abandon a flock mid-trip.
## Idle or guarding, he engages like any DEFENSIVE unit.
func _auto_engage(target: Node) -> void:
	if _herd_phase != HerdPhase.NONE:
		return
	super._auto_engage(target)

## Quadruped footprint: the humanoid-width plinth/shadow looked like a
## saucer under a long low body.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 13.0, 9.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 13.0, 5.0, 9.0)

## Diagonal-pair trot, the Animal gait on a UnitBase machine: the rig's four
## legs (Front/Back × Near/Far) swing in counter-phase while moving. This
## replaces the base _animate_body wholesale, so it must ALSO face the dog:
## the base orientation helper only knows attack/gather/build targets, and a
## herding dog steers at herd_target or home instead.
func _animate_body(delta: float) -> void:
	var body: Node2D = get_node_or_null("Body") as Node2D
	if body == null:
		return
	var face: Vector2 = Vector2.INF
	if current_state == UnitState.ATTACKING and _herd_phase == HerdPhase.FETCH \
			and is_instance_valid(herd_target):
		face = herd_target.global_position
	elif current_state == UnitState.ATTACKING and _herd_phase == HerdPhase.LEAD:
		face = _home
	elif current_state == UnitState.ATTACKING and is_instance_valid(attack_target):
		face = (attack_target as Node2D).global_position
	elif current_state == UnitState.MOVING and is_instance_valid(nav_agent) \
			and not nav_agent.is_navigation_finished():
		face = nav_agent.target_position
	elif velocity.length_squared() > 4.0:
		face = global_position + velocity
	if face != Vector2.INF:
		var screen_dx: float = IsoProjection.world_to_screen(face - global_position).x
		if absf(screen_dx) > 2.0:
			body.scale.x = -1.0 if screen_dx < 0.0 else 1.0
	body.rotation = IsoBillboard.UPRIGHT_ROTATION

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

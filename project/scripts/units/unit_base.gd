extends CharacterBody2D

class_name UnitBase

enum UnitState { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, DEAD }

@export var unit_data: UnitResource

var player_id: int = 0
var current_state: UnitState = UnitState.IDLE
var health: float = 0.0
var is_selected: bool = false
var civ_id: String = ""   # set at spawn time from MatchConfig for player units
var is_cloaked: bool = false
var is_taunted: bool = false
var taunt_source: Node = null
# Visual gender. Human units roll this 50/50 at _ready unless a spawner/save set
# it first. Setting the property (e.g. unit.set("is_female", true) before the
# unit enters the tree, or a save restore) marks it as decided so _ready won't
# re-roll. Non-human units (ships, siege, animals) ignore it.
var _gender_assigned: bool = false
var is_female: bool = false:
	set(value):
		is_female = value
		_gender_assigned = true
# True while unit is executing an attack-move order: auto-attacks enemies spotted
# during movement rather than ignoring them.
var _attack_move_active: bool = false

# ── Combat state machine (shared) ──────────────────────────────────────────
# One canonical move/chase/strike machine for every combat unit. Leaf classes
# customise through the hook methods below instead of copying the machine.
var attack_target: Node = null

## AoE2-style combat stances. They govern AUTONOMOUS behaviour only — an
## explicit attack order always chases. DEFENSIVE units chase up to
## DEFENSIVE_LEASH px from their anchor (their last ordered position) and then
## walk home; STAND_GROUND units strike whatever is in reach but never move
## for it; PASSIVE units never auto-acquire at all.
enum Stance { AGGRESSIVE, DEFENSIVE, STAND_GROUND, PASSIVE }
const DEFENSIVE_LEASH: float = 200.0

var stance: int = Stance.AGGRESSIVE
var _stance_anchor: Vector2 = Vector2.INF   # INF = unset; falls back to current pos

## Alternate approach angles a blocked building-attacker walks through
## (relative to its current bearing) before giving up — alternating sides,
## widening to the far face.
const APPROACH_STEPS: Array[float] = [
	PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5, PI * 0.75, -PI * 0.75, PI,
]
var _approach_step: int = 0
# True while the CURRENT engagement came from auto-acquire (range Area2D,
# retaliation, guard response, post-kill rescan) rather than an order.
var _auto_engaged: bool = false
var _auto_engage_pending: bool = false
var _attack_timer: float = 0.0
var _destination_state: UnitState = UnitState.IDLE

# How long a unit stays visible after striking, even while hidden by sea fog:
# opening fire gives your position away.
const COMBAT_REVEAL_TIME: float = 3.0
var _last_strike_msec: int = -1

var _hit_tween: Tween = null
var _hero_low_hp_fired: bool = false   # tracks if low-HP alert has been emitted this life
var _anim_time: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_retries: int = 0
var _last_position: Vector2 = Vector2.ZERO
# Original requested destination — kept so we can re-issue after escaping a stuck.
var _move_destination: Vector2 = Vector2.ZERO

# ── Shift-queued waypoints + patrol ─────────────────────────────────────────
# Queued legs [{pos, attack}] walked one by one; any explicit new order
# clears them (the command layer calls clear_waypoints). Patrol bounces
# between two points with attack-move legs until another order arrives.
var _waypoints: Array = []
var _patrol_a: Vector2 = Vector2.ZERO
var _patrol_b: Vector2 = Vector2.ZERO
var _patrol_active: bool = false
var _patrol_to_b: bool = true

func clear_waypoints() -> void:
	_waypoints.clear()
	_patrol_active = false

## Shift-order: walk there after everything already queued. From idle the
## first leg starts immediately, like AoE2.
func queue_waypoint(p: Vector2, attack: bool) -> void:
	if current_state == UnitState.IDLE and _waypoints.is_empty() and not _patrol_active:
		_run_leg(p, attack)
	else:
		_waypoints.append({"pos": p, "attack": attack})

func order_patrol(target: Vector2) -> void:
	clear_waypoints()
	_patrol_a = global_position
	_patrol_b = target
	_patrol_active = true
	_patrol_to_b = true
	order_attack_move(target)
	_patrol_active = true   # order_attack_move must not cancel its own patrol

func _run_leg(p: Vector2, attack: bool) -> void:
	var keep: Array = _waypoints
	var keep_patrol: bool = _patrol_active
	if attack:
		order_attack_move(p)
	else:
		order_move(p)
	_waypoints = keep
	_patrol_active = keep_patrol

## Destination reached with nothing else to do: next queued leg, or the
## patrol bounce. Returns true when a new leg started.
func _advance_waypoints() -> bool:
	if _patrol_active:
		_patrol_to_b = not _patrol_to_b
		_run_leg(_patrol_b if _patrol_to_b else _patrol_a, true)
		return true
	if _waypoints.is_empty():
		return false
	var leg: Dictionary = _waypoints.pop_front() as Dictionary
	_run_leg(leg["pos"] as Vector2, leg["attack"] as bool)
	return true

const PATH_COLOR: Color = Color(0.3, 0.85, 1.0, 0.8)
const PATH_FAIL_COLOR: Color = Color(1.0, 0.32, 0.25, 0.9)
const PATH_FAIL_FADE: float = 2.5
const STUCK_TIMEOUT: float = 1.2
const STUCK_THRESHOLD: float = 6.0
const MAX_STUCK_RETRIES: int = 6
# ── Timed status effects (hero abilities: sandstorm slow, boarding stun) ────
var _slow_mult: float = 1.0
var _slow_until_msec: int = 0
var _stun_until_msec: int = 0

func apply_slow(mult: float, duration_msec: int) -> void:
	_slow_mult = mult
	_slow_until_msec = Time.get_ticks_msec() + duration_msec

func apply_stun(duration_msec: int) -> void:
	_stun_until_msec = Time.get_ticks_msec() + duration_msec

func is_stunned() -> bool:
	return Time.get_ticks_msec() < _stun_until_msec

# The idle-sidestep "shove": a slowed mover asks own idle units ahead to step
# aside well before the full stuck recovery kicks in.
const SHOVE_AFTER: float = 0.45
const SHOVE_SCAN_AHEAD: float = 26.0
const SHOVE_SCAN_RADIUS: float = 30.0
const NUDGE_STEP: float = 30.0
const NUDGE_COOLDOWN_MSEC: int = 900
var _shoved_this_period: bool = false
var _last_nudge_msec: int = -10000
const GUARD_RADIUS: float = 250.0

# ── RVO avoidance tuning (applied programmatically in _tune_avoidance) ──────
# The scenes leave the agent at Godot defaults, and two of those defaults hurt:
# max_speed 100 CLAMPS the avoidance-safe velocity, silently capping every
# faster unit (the 180 px/s Scout moved at 55 % of design speed); and
# neighbor_distance 500 makes every agent brake for units half a map away —
# the "molasses" jams in big groups.
const AVOID_MAX_SPEED_HEADROOM: float = 1.6   # over move_speed, room for civ/tech/weather boosts
const AVOID_NEIGHBOR_DISTANCE: float = 80.0
const AVOID_MAX_NEIGHBORS: int = 7
const AVOID_TIME_HORIZON: float = 0.7
## Moving units carry the higher priority so parked ones yield the way instead
## of both bowing to each other (the old uniform 0.5 gridlocked crowds).
const AVOID_PRIORITY_MOVING: float = 0.7
const AVOID_PRIORITY_IDLE: float = 0.4

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var selection_indicator: Node2D = $SelectionIndicator
@onready var attack_range_area: Area2D = get_node_or_null("AttackRange")

var _path_line: Line2D = null
var _path_failed: bool = false   # freezes the red gave-up route during its fade
var _path_visible: bool = false

func _ready() -> void:
	# The "units" group is load-bearing: watch towers, the Menceyes Guard aura
	# and several hero abilities scan it. No unit scene declares it, so without
	# this line the group was empty and all of those silently did nothing.
	add_to_group("units")
	# Malpaís-traversal civs ride the layer-8 mesh, where malpaís stays
	# walkable (the land mesh carves it out so everyone else routes around).
	# Only plain land units switch: ships (2) and the Tidecaller (4) keep the
	# layer their scene declares.
	if is_instance_valid(nav_agent) and nav_agent.navigation_layers == 1 \
			and TerrainManager.civ_traverses_malpais(civ_id):
		nav_agent.navigation_layers = NavMeshBuilder.MALPAIS_LAYER
	if unit_data:
		var hp_mult: float = CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
		health = unit_data.max_health * hp_mult
		if player_id != 0 and GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL:
			health *= 0.5
		health_bar.max_value = health
		health_bar.value = health
	_refresh_health_bar()
	_last_position = global_position
	if is_instance_valid(attack_range_area):
		attack_range_area.monitoring = true
		attack_range_area.body_entered.connect(_on_enemy_entered_range)
	if is_instance_valid(nav_agent) \
			and not nav_agent.velocity_computed.is_connected(_on_velocity_computed):
		nav_agent.velocity_computed.connect(_on_velocity_computed)
	_tune_avoidance()
	if player_id == 0:
		EventBus.player_entity_under_attack.connect(_on_player_entity_under_attack)
	EventBus.unit_upgrade_applied.connect(_on_unit_upgrade_applied)
	EventBus.technology_researched.connect(_on_technology_researched)
	# Decide visual gender (50/50) unless a spawner or save already set it.
	if not _gender_assigned:
		is_female = MatchRng.randf() < 0.5
	call_deferred("_add_player_color_stripe")
	call_deferred("_add_ground_shadow")
	call_deferred("_apply_gender_appearance")
	call_deferred("_apply_team_dress")
	call_deferred("_setup_iso_billboard")

## One tuning source for every unit's avoidance agent — the scenes stay at
## engine defaults, which are wrong for an RTS (see the AVOID_* constants).
func _tune_avoidance() -> void:
	if not is_instance_valid(nav_agent):
		return
	if unit_data != null:
		nav_agent.max_speed = unit_data.move_speed * AVOID_MAX_SPEED_HEADROOM
	var body_radius: float = _collision_radius()
	if body_radius > 0.0:
		nav_agent.radius = body_radius + 1.0
	nav_agent.neighbor_distance = AVOID_NEIGHBOR_DISTANCE
	nav_agent.max_neighbors = AVOID_MAX_NEIGHBORS
	nav_agent.time_horizon_agents = AVOID_TIME_HORIZON
	nav_agent.avoidance_priority = AVOID_PRIORITY_IDLE

## Radius of the physics body, whatever shape the scene uses (infantry are
## capsules, some ships rectangles). 0 = unknown, keep the agent default.
func _collision_radius() -> float:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return 0.0
	if cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius
	if cs.shape is CapsuleShape2D:
		return (cs.shape as CapsuleShape2D).radius
	if cs.shape is RectangleShape2D:
		return maxf((cs.shape as RectangleShape2D).size.x,
			(cs.shape as RectangleShape2D).size.y) * 0.5
	return 0.0

## Parked units yield to marching ones. Assigned only on change — the setter
## is a NavigationServer call.
func _update_avoidance_priority() -> void:
	if not is_instance_valid(nav_agent):
		return
	var want: float = AVOID_PRIORITY_IDLE if current_state == UnitState.IDLE \
		else AVOID_PRIORITY_MOVING
	if nav_agent.avoidance_priority != want:
		nav_agent.avoidance_priority = want

# Stand the unit's art upright on the projected ground (see IsoBillboard).
# HealthBar/GatherIndicator are uprighted so they stay horizontal in screen
# space above the head. SelectionIndicator, GroundShadow and the player-colour
# plinth stay ground-projected: the authored filled selection disc is rebuilt
# here into the genre-classic ellipse ring under the feet.
func _setup_iso_billboard() -> void:
	IsoBillboard.setup_entity(self,
		["Body", "HealthBar", "GatherIndicator", "AnimatedSprite2D"])
	VisualFx.make_ground_selection_ring(selection_indicator, _foot_anchor_y())

# SCREEN-space distance from the unit anchor down to the feet, where ground
# markers (selection ring, hero ring) sit. Derived from the ground shadow the
# unit already placed at its feet; 9 px matches the default shadow offset.
func _foot_anchor_y() -> float:
	var shadow: Node2D = get_node_or_null("GroundShadow") as Node2D
	if shadow != null:
		return IsoProjection.world_to_screen(shadow.position).y
	return 9.0

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 11.0, 6.0)
	_apply_owner_marker_last()

## Screen-space height of the owner pennant pole base; ships override with
## their mast tops.
func _pennant_top_y() -> float:
	return -20.0

## Bodies are built procedurally in deferred steps and the civ dress repaints
## them — so both the human-or-ship decision AND the tint must run a couple
## of frames later, as the LAST paint layer.
func _apply_owner_marker_last() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if VisualFx.find_head(self) != null:
		# Human figure: the tunic wears the team colour.
		VisualFx.apply_owner_tint(self, player_id)
	else:
		# Ships and siege keep their art; they fly a team pennant instead
		# (animals never run this — they don't extend UnitBase).
		VisualFx.add_owner_pennant(self, player_id, _pennant_top_y())

# Applies the female look to human units. Non-human units (no head polygon) and
# male units are left as-is. Subclasses that style gender themselves (HeroUnit)
# override this to opt out.
func _apply_gender_appearance() -> void:
	if is_female:
		VisualFx.add_female_hair(self)

func _apply_team_dress() -> void:
	TeamDress.apply(self, player_id)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 11.0, 4.5, 9.0)

## Terrain containment cadence. The navmesh is the only thing keeping land
## units out of the sea (water has no physics body), and RVO shoves or the
## straight-line combat gap-closer can push a body off the mesh right at the
## shoreline — after which nothing brings it back. A cheap periodic check
## heals any entry vector. Lives in _process because leaf classes replace
## _physics_process wholesale (villager!); staggered start so 400 units
## don't all query the same frame. Client mirrors are excluded — their
## positions belong to the host's stream.
const CONTAINMENT_CHECK_SEC: float = 0.8

@onready var _containment_timer: float = float(get_instance_id() % 16) * 0.05

func _contain_to_passable() -> void:
	if TerrainManager.is_impassable_for(global_position, civ_id, is_amphibious()):
		global_position = TerrainManager.nearest_passable(
			global_position, civ_id, is_amphibious())
		reset_physics_interpolation()

## Water has no physics body, so nothing but the navmesh keeps land units
## ashore — and two movement paths bypass the mesh: RVO's safe_velocity
## (a shove near the shoreline) and the straight-line combat gap-closer.
## This guard vetoes any step that would ENTER the sea. Cheap by
## construction: amphibians and units away from the coast (memoized
## distance_to_coast cell lookup) exit before the precise terrain test,
## and a unit already overboard is left to the containment teleport, so a
## mesh/polygon sliver at the waterline can never freeze anyone.
const COAST_GUARD_DIST: float = 64.0

func _step_enters_sea(next_pos: Vector2) -> bool:
	if is_amphibious():
		return false
	if TerrainManager.distance_to_coast(global_position) > COAST_GUARD_DIST:
		return false
	return TerrainManager.is_ocean(next_pos) and not TerrainManager.is_ocean(global_position)

func _process(delta: float) -> void:
	_containment_timer += delta
	if _containment_timer >= CONTAINMENT_CHECK_SEC:
		_containment_timer = 0.0
		if current_state != UnitState.DEAD and not NetworkSession.is_client():
			_contain_to_passable()
	_anim_time += delta
	IsoBillboard.update_depth(self)
	_update_avoidance_priority()
	_animate_body(delta)
	if _path_visible and is_instance_valid(_path_line) and not _path_failed:
		var pts: PackedVector2Array = nav_agent.get_current_navigation_path()
		if pts.size() >= 2:
			var local_pts: PackedVector2Array = PackedVector2Array()
			for p: Vector2 in pts:
				local_pts.append(p - global_position)
			_path_line.points = local_pts
			_path_line.visible = true
		else:
			_path_line.visible = false

func _animate_body(_delta: float) -> void:
	var body: Node = get_node_or_null("Body")
	if body == null:
		return
	var t: float = _anim_time

	# Determine facing direction based on state and target
	_update_body_orientation(body)

	# Apply rotation animation if the body supports it (Node2D). Rotations
	# compose on top of the upright billboard base angle (see IsoBillboard).
	if body is Node2D:
		match current_state:
			UnitState.ATTACKING:
				var swing: float = sin(t * TAU * 3.5)
				(body as Node2D).rotation = IsoBillboard.UPRIGHT_ROTATION + swing * 0.20
			UnitState.MOVING:
				(body as Node2D).rotation = IsoBillboard.UPRIGHT_ROTATION + sin(t * TAU * 2.8) * 0.08
			_:
				(body as Node2D).rotation = move_toward((body as Node2D).rotation,
					IsoBillboard.UPRIGHT_ROTATION, _delta * 4.0)

func _update_body_orientation(body: Node) -> void:
	var target_pos: Vector2 = Vector2.ZERO
	var has_target: bool = false

	# Check for attack target (most units)
	var attack_tgt: Variant = get("attack_target")
	if attack_tgt != null and is_instance_valid(attack_tgt as Node):
		target_pos = (attack_tgt as Node2D).global_position
		has_target = true

	# Check for gather target (villagers)
	if not has_target:
		var gather_tgt: Variant = get("gather_target")
		if gather_tgt != null and is_instance_valid(gather_tgt as Node):
			target_pos = (gather_tgt as Node2D).global_position
			has_target = true

	# Check for build target (villagers)
	if not has_target:
		var build_tgt: Variant = get("build_target")
		if build_tgt != null and is_instance_valid(build_tgt as Node):
			target_pos = (build_tgt as Node2D).global_position
			has_target = true

	# If moving, face the navigation destination rather than the instantaneous
	# velocity. The destination is stable, so a unit travelling on a diagonal or
	# near-vertical path still faces the side it's heading to, and the facing
	# doesn't flicker when the path serpentines (velocity.x noise).
	if not has_target and current_state == UnitState.MOVING:
		if is_instance_valid(nav_agent) and not nav_agent.is_navigation_finished():
			target_pos = nav_agent.target_position
			has_target = true
		elif velocity.length_squared() > 1.0:
			target_pos = global_position + velocity.normalized() * 10.0
			has_target = true

	# Flip body horizontally based on the target direction AS PROJECTED ON
	# SCREEN: under the rotated camera, world +x is a screen diagonal, so the
	# decision axis must be the projected screen x or units read as walking
	# backwards. The flip itself composes cleanly with the upright billboard
	# basis (scale.x = -1 mirrors in screen space). Small dead zone prevents
	# flicker when the target is nearly straight above/below on screen.
	if has_target:
		var direction: float = IsoProjection.world_to_screen(target_pos - global_position).x
		if absf(direction) > 2.0:
			var new_scale_x: float = -1.0 if direction < 0.0 else 1.0
			# Handle both Node2D (uses scale) and Control (uses size/scale differently)
			if body is Node2D:
				(body as Node2D).scale.x = new_scale_x
			elif body is Control:
				(body as Control).scale.x = new_scale_x

func toggle_path_display() -> void:
	_path_visible = not _path_visible
	if _path_visible and _path_line == null:
		_path_line = Line2D.new()
		_path_line.width = 2.0
		_path_line.default_color = PATH_COLOR
		_path_line.z_index = 10
		add_child(_path_line)
	if is_instance_valid(_path_line):
		_path_line.visible = _path_visible
		if not _path_visible:
			_reset_path_style()

## When the unit gives up on a blocked destination, the last attempted route
## freezes in red and fades out — telling the player "this path is impossible".
func _show_path_failure() -> void:
	if not _path_visible or not is_instance_valid(_path_line) \
			or _path_line.points.size() < 2:
		return
	_path_failed = true
	_path_line.default_color = PATH_FAIL_COLOR
	_path_line.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_path_line, "modulate:a", 0.0, PATH_FAIL_FADE)
	tween.tween_callback(_reset_path_style)

func _reset_path_style() -> void:
	_path_failed = false
	if is_instance_valid(_path_line):
		_path_line.default_color = PATH_COLOR
		_path_line.modulate.a = 1.0
		_path_line.visible = false

## HP technologies apply to LIVING units, AoE2 style: rescale max HP keeping
## the current health ratio. Upgrades already did this; plain HP techs
## (Loom-likes, Sanctity, Shipwright) only reached freshly spawned units.
func _on_technology_researched(pid: int, _tech_id: String) -> void:
	if pid != player_id or unit_data == null or not is_instance_valid(health_bar):
		return
	var new_max: float = unit_data.max_health \
		* CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
	if is_equal_approx(new_max, float(health_bar.max_value)):
		return
	var ratio: float = clampf(health / maxf(float(health_bar.max_value), 1.0), 0.0, 1.0)
	health = new_max * ratio
	health_bar.max_value = new_max
	health_bar.value = health
	_refresh_health_bar()

func _on_unit_upgrade_applied(pid: int, from_id: String, to_res: UnitResource) -> void:
	if pid != player_id:
		return
	if unit_data == null or unit_data.id != from_id:
		return
	var old_max: float = unit_data.max_health * CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
	var ratio: float = clampf(health / old_max, 0.0, 1.0)
	unit_data = to_res
	var new_max: float = unit_data.max_health * CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
	health = new_max * ratio
	health_bar.max_value = new_max
	health_bar.value = health
	_refresh_health_bar()

func set_selected(value: bool) -> void:
	is_selected = value
	selection_indicator.visible = value
	var plinth: Node = get_node_or_null("PlayerColorStripe")
	if plinth is Line2D:
		# Always visible; selection makes the owner ring pop.
		var ring_col: Color = PlayerColors.get_color(player_id)
		ring_col.a = 0.95 if value else 0.55
		(plinth as Line2D).default_color = ring_col
	if value:
		var col: Color = Color(0.0, 1.0, 0.0, 0.8) if player_id == 0 else Color(1.0, 0.85, 0.0, 0.85)
		var circle: Node = selection_indicator.get_node_or_null("SelectionCircle")
		if circle is Line2D:
			(circle as Line2D).default_color = col
		elif circle is Polygon2D:
			(circle as Polygon2D).color = col

func get_selection_sound() -> String:
	return "select_generic"

func move_to(target_position: Vector2) -> void:
	nav_agent.target_position = target_position
	current_state = UnitState.MOVING

# AoE2 convention: the health bar only shows once the unit has taken damage.
func _refresh_health_bar() -> void:
	if is_instance_valid(health_bar):
		health_bar.visible = health < health_bar.max_value - 0.01

## Canonical healing — EVERY heal in the game goes through here (temple
## hospital, the Harimaguada, hero abilities). Ad-hoc health writes kept
## re-inventing this and missing the bar refresh or the civ-scaled cap
## (the Rising Tide bug called a refresh method that never existed).
func heal(amount: float) -> void:
	if current_state == UnitState.DEAD or amount <= 0.0:
		return
	var max_hp: float = health
	if is_instance_valid(health_bar):
		max_hp = float(health_bar.max_value)
	elif unit_data != null:
		max_hp = unit_data.max_health * CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
	health = minf(health + amount, max_hp)
	if is_instance_valid(health_bar):
		health_bar.value = health
	_refresh_health_bar()

func is_fully_healed() -> bool:
	if not is_instance_valid(health_bar):
		return true
	return health >= float(health_bar.max_value) - 0.01

func take_damage(amount: float, source: Node = null) -> void:
	# Replication puppet (LAN client mirror): the host owns all damage; local
	# hits would kill entities the authority still considers alive.
	if get_meta(&"rep_puppet", false):
		return
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	health_bar.value = health
	_refresh_health_bar()
	_flash_hit()
	if health <= 0.0:
		die()
		return
	_check_hero_low_hp()
	if player_id == 0:
		AudioManager.play_if_visible("hit_melee", global_position, -8.0)
	if source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and not GameManager.are_allied(src_pid as int, player_id):
			if player_id != 0:
				EventBus.ai_unit_under_attack.emit(player_id)
			else:
				EventBus.player_entity_under_attack.emit(global_position, source)
			if current_state == UnitState.IDLE:
				_auto_engage(source)

func die() -> void:
	# Re-entry guard: a dying unit can absorb further hits before queue_free
	# lands, and a second die() would double-emit unit_died (double population
	# refund, duplicate kill triggers).
	if current_state == UnitState.DEAD:
		return
	current_state = UnitState.DEAD
	if player_id == 0:
		AudioManager.play("unit_die", -6.0)
		if EventBus.player_entity_under_attack.is_connected(_on_player_entity_under_attack):
			EventBus.player_entity_under_attack.disconnect(_on_player_entity_under_attack)
	if is_instance_valid(attack_range_area):
		attack_range_area.monitoring = false
	EventBus.unit_died.emit(self, player_id)
	queue_free()

func _flash_hit() -> void:
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _check_hero_low_hp() -> void:
	if _hero_low_hp_fired:
		return
	if unit_data == null or not unit_data.is_hero:
		return
	var max_hp: float = unit_data.max_health * CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
	if max_hp <= 0.0:
		return
	if health / max_hp < 0.25:
		_hero_low_hp_fired = true
		EventBus.hero_low_hp.emit(player_id)

## Guard response: react when a nearby allied unit or building is attacked.
## Only fires for player-0 units that are IDLE and within GUARD_RADIUS of the event.
func _on_player_entity_under_attack(world_pos: Vector2, attacker: Node) -> void:
	if current_state != UnitState.IDLE:
		return
	if not _responds_to_guard():
		return
	if not is_instance_valid(attacker):
		return
	if global_position.distance_to(world_pos) > GUARD_RADIUS:
		return
	var att_pid: Variant = attacker.get("player_id")
	if att_pid == null or (att_pid as int) == player_id:
		return
	if attacker.get("is_cloaked") == true:
		return
	_auto_engage(attacker)

## Whether this unit reacts to the "ally under attack" guard signal. Only
## military land units do; villagers, ships and animals stay put so the player's
## economy doesn't run off to defend on its own.
func _responds_to_guard() -> bool:
	if has_method("order_gather"):   # villagers
		return false
	if has_method("get_garrison") or has_method("order_fish"):  # transport / fishing ships
		return false
	return true

## Called when any body enters the attack-range Area2D.
## Triggers auto-attack only from IDLE, or from MOVING when attack-move is active.
func _on_enemy_entered_range(body: Node) -> void:
	if current_state != UnitState.IDLE and not (current_state == UnitState.MOVING and _attack_move_active):
		return
	var body_pid: Variant = body.get("player_id")
	if body_pid == null or GameManager.are_allied(body_pid as int, player_id):
		return
	# Only auto-attack units, not buildings (buildings don't have unit_data)
	if body.get("unit_data") == null and not (body is Animal):
		return
	if body.get("is_cloaked") == true:
		return
	_auto_engage(body)

## Move to destination, auto-attacking any enemy spotted along the way.
## Subclasses' order_move clears _attack_move_active; we re-set it right after.
func order_attack_move(destination: Vector2) -> void:
	if has_method("order_move"):
		call("order_move", destination)
	_attack_move_active = true

# Override in subclasses to trigger attack logic. The default (non-combat
# units: villagers only via their own override, ships without weapons, etc.)
# ignores the target so retaliation/guard signals don't send them to war.
func _on_auto_attack_target(_target: Node) -> void:
	_attack_move_active = false

## Every autonomous acquisition funnels through here so the stance can veto it
## and the engagement gets marked as auto (the leash/stand-ground rules apply
## only to auto engagements — explicit orders always chase).
func _auto_engage(target: Node) -> void:
	if not _stance_allows_auto_engage():
		return
	_auto_engage_pending = true
	_on_auto_attack_target(target)
	_auto_engage_pending = false

func _stance_allows_auto_engage() -> bool:
	if stance == Stance.PASSIVE:
		return false
	# A defensive unit beyond its leash is walking home; re-acquiring here
	# would ping-pong it further and further from its post.
	if stance == Stance.DEFENSIVE \
			and global_position.distance_to(_stance_home()) > DEFENSIVE_LEASH:
		return false
	return true

func _stance_home() -> Vector2:
	return _stance_anchor if _stance_anchor != Vector2.INF else global_position

## Stance orders come through the CommandBus; the anchor re-pins to wherever
## the unit stands when the stance is set.
func set_stance(new_stance: int) -> void:
	stance = new_stance
	_stance_anchor = global_position
	if stance == Stance.PASSIVE and _auto_engaged \
			and current_state == UnitState.ATTACKING:
		_break_off_combat()

# ── Combat state machine ────────────────────────────────────────────────────
# Canonical machine: order_* set the intent, _handle_movement travels (and
# flips to ATTACKING when in position), _handle_attacking chases/strikes.
# Units with their own machines (Villager, Trebuchet, transports) override the
# top-level methods wholesale; everyone else overrides only the hooks.

func _physics_process(delta: float) -> void:
	if is_stunned():
		# Stunned: no walking, no swinging — but side ticks (hero ability
		# timers, cooldowns) keep counting.
		if is_instance_valid(nav_agent):
			_drive_agent(Vector2.ZERO)
		_combat_side_tick(delta)
		return
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_attacking(delta)
	_combat_side_tick(delta)

func order_move(destination: Vector2) -> void:
	_patrol_active = false
	_attack_move_active = false
	attack_target = null
	# A defensive/stand-ground unit holds its latest ordered position.
	_stance_anchor = destination
	_destination_state = UnitState.IDLE
	_on_move_ordered()
	_navigate_to(destination)
	current_state = UnitState.MOVING

func order_attack(target: Node) -> void:
	if not _accepts_attack_order(target):
		return
	_auto_engaged = _auto_engage_pending
	_approach_step = 0
	attack_target = target
	_destination_state = UnitState.ATTACKING
	_on_attack_ordered()
	_move_destination = _nav_target_for(target)
	nav_agent.target_position = _safe_destination(_move_destination)
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	_on_movement_tick(delta)
	if _handle_movement_override(delta):
		return
	if _destination_state == UnitState.ATTACKING and is_instance_valid(attack_target):
		var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
		if _in_attack_position(dist, _attack_reach_to(attack_target)):
			current_state = UnitState.ATTACKING
			_destination_state = UnitState.IDLE
			_drive_agent(Vector2.ZERO)
			return
	if nav_agent.is_navigation_finished():
		_on_destination_reached()
		if _destination_state == UnitState.IDLE and _advance_waypoints():
			return
		current_state = _destination_state
		_destination_state = UnitState.IDLE
		_drive_agent(Vector2.ZERO)
		return
	# Well before declaring "stuck", ask idle friends parked on the path to
	# step aside — the AoE2 shuffle. RVO alone never moves an idle agent.
	if _stuck_timer >= SHOVE_AFTER and not _shoved_this_period:
		_shoved_this_period = true
		_try_shove_blockers()
	if _advance_stuck(delta):
		_on_movement_stuck()
		_unstick()
		return
	_drive_agent(_nav_velocity())

## Blocked mover: find own idle units in front and nudge them sideways.
func _try_shove_blockers() -> void:
	var heading: Vector2 = velocity.normalized()
	if heading == Vector2.ZERO:
		heading = global_position.direction_to(nav_agent.get_next_path_position())
	if heading == Vector2.ZERO:
		return
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = SHOVE_SCAN_RADIUS
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position + heading * SHOVE_SCAN_AHEAD)
	params.collision_mask = 2   # units layer
	params.exclude = [get_rid()]
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(params, 6):
		var other: Node = hit.get("collider") as Node
		if other == null or not (other is UnitBase):
			continue
		if (other as UnitBase).player_id != player_id:
			continue
		(other as UnitBase).nudge_aside(heading, global_position)

## An own moving unit is blocked by us: take one deterministic side-step
## (away from its path line) and settle back to idle. Never touches order
## state — the stance anchor stays where the player put it.
func nudge_aside(travel_dir: Vector2, mover_pos: Vector2) -> void:
	if current_state != UnitState.IDLE:
		return
	if Time.get_ticks_msec() - _last_nudge_msec < NUDGE_COOLDOWN_MSEC:
		return
	_last_nudge_msec = Time.get_ticks_msec()
	var side: Vector2 = UnitBase.nudge_side_vector(travel_dir, mover_pos, global_position)
	# Forward-aside diagonal: in a corridor a pure side-step just presses into
	# the wall — flowing with the traffic clears the lane anywhere.
	var step: Vector2 = (side * 0.7 + travel_dir.normalized() * 0.7).normalized()
	var dest: Vector2 = TerrainManager.nearest_passable(
		global_position + step * NUDGE_STEP, civ_id, is_amphibious())
	_destination_state = UnitState.IDLE
	_navigate_to(dest)
	current_state = UnitState.MOVING

## Pure: the perpendicular of the mover's travel direction on WHICHEVER side
## the blocker already leans toward — the shortest way off the path line.
static func nudge_side_vector(travel_dir: Vector2, mover_pos: Vector2, blocker_pos: Vector2) -> Vector2:
	var side: Vector2 = travel_dir.orthogonal().normalized()
	if (blocker_pos - mover_pos).dot(side) < 0.0:
		side = -side
	return side

## Single funnel into the avoidance pipeline. The engine dispatches
## velocity_computed to EVERY avoidance agent EVERY physics tick, connected
## or not — in a 200v200 melee that was thousands of GDScript calls per
## rendered frame for units standing still trading blows. A parked unit
## flushes one final zero (so neighbors stop dodging its ghost trajectory),
## then disconnects its callback until it drives again; the agent itself
## stays in the RVO space, so movers keep steering around parked units.
## Measured: 200v200 from 7.5 to ~13 fps.
var _agent_stopped: bool = false

func _drive_agent(vel: Vector2) -> void:
	if vel == Vector2.ZERO:
		velocity = Vector2.ZERO
		if _agent_stopped:
			return
		_agent_stopped = true
		nav_agent.set_velocity(Vector2.ZERO)
		if nav_agent.velocity_computed.is_connected(_on_velocity_computed):
			nav_agent.velocity_computed.disconnect(_on_velocity_computed)
		return
	if _agent_stopped and not nav_agent.velocity_computed.is_connected(_on_velocity_computed):
		nav_agent.velocity_computed.connect(_on_velocity_computed)
	_agent_stopped = false
	nav_agent.set_velocity(vel)

# ATTACKING is included on purpose: chase and kite steps issue set_velocity
# while in that state, and gating on MOVING alone silently dropped them —
# units froze the moment a target stepped out of reach.
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if current_state != UnitState.MOVING and current_state != UnitState.ATTACKING:
		return
	if _step_enters_sea(global_position + safe_velocity * get_physics_process_delta_time()):
		velocity = Vector2.ZERO
		return
	velocity = safe_velocity
	move_and_slide()

func _handle_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		attack_target = null
		current_state = UnitState.IDLE
		_on_target_lost()
		return
	if _attack_paused():
		_drive_agent(Vector2.ZERO)
		return
	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var reach: float = _attack_reach_to(attack_target)
	if _combat_reposition(dist, reach):
		return
	if dist > reach:
		# Stance chase rules apply to AUTO engagements only.
		if _auto_engaged and stance == Stance.STAND_GROUND:
			_break_off_combat()
			_scan_area_for_target()   # something else may already be in reach
			return
		if _auto_engaged and stance == Stance.DEFENSIVE \
				and global_position.distance_to(_stance_home()) > DEFENSIVE_LEASH:
			var home: Vector2 = _stance_home()
			call("order_move", home)
			return
		# While an alternate approach is held (_approach_step > 0, buildings
		# only) the rotated destination must survive — re-deriving it here
		# every tick silently undid the manoeuvre.
		if _approach_step == 0:
			_repath_to(_nav_target_for(attack_target))
		if _advance_stuck(delta):
			_unstick()
			return
		var vel: Vector2 = _nav_velocity()
		if vel == Vector2.ZERO and nav_agent.is_navigation_finished():
			# The agent declares arrival target_desired_distance (24 px) short
			# of the approach point; short-reach units parked 3 px out of
			# strike range and froze there forever. Close the last gap on a
			# straight line WITHOUT avoidance — RVO crushes a push toward a
			# wall flanked by parked allies, and the building's collision is
			# what stops us anyway.
			velocity = global_position.direction_to((attack_target as Node2D).global_position) \
				* _nav_speed()
			# ...unless the last gap is WATER: unlike a wall, the sea has no
			# collision to stop the push — hold the shoreline instead.
			if _step_enters_sea(global_position + velocity * delta):
				velocity = Vector2.ZERO
				return
			move_and_slide()
			return
		_drive_agent(vel)
		return
	_drive_agent(Vector2.ZERO)
	_attack_timer += delta
	if _attack_timer >= _attack_interval():
		_attack_timer = 0.0
		_last_strike_msec = Time.get_ticks_msec()
		_execute_strike(attack_target)

func _attack_interval() -> float:
	var speed: float = unit_data.attack_speed \
		* CivBonusManager.get_attack_speed_multiplier(player_id, unit_data.id)
	return 1.0 / maxf(speed, 0.01)

# Direct-hit strike. Melee floor is 1 damage (genre convention; ships already
# did this) so over-armoured targets chip instead of healing from negatives.
func _execute_strike(target: Node) -> void:
	_approach_step = 0   # reached the target: the approach search starts fresh
	if target.has_method("take_damage"):
		target.take_damage(maxf(_strike_damage(target), 1.0), self)
		var snd: String = _strike_sound()
		if not snd.is_empty():
			AudioManager.play_if_visible(snd, global_position, _strike_sound_db())
		EventBus.unit_attacked.emit(self, target)
	_after_strike(target)

func _strike_damage(target: Node) -> float:
	return _get_effective_attack_vs(target) - _get_target_armor(target)

## True for COMBAT_REVEAL_TIME after the last strike. Read by FogOfWar so a unit
## shooting from inside a fog bank cannot stay invisible while it fires.
func is_revealed_by_combat() -> bool:
	if _last_strike_msec < 0:
		return false
	return float(Time.get_ticks_msec() - _last_strike_msec) / 1000.0 < COMBAT_REVEAL_TIME

## Re-acquire something in range after the current target dies. Taunts win.
func _scan_area_for_target() -> void:
	if is_taunted and is_instance_valid(taunt_source):
		order_attack(taunt_source)
		return
	if not is_instance_valid(attack_range_area):
		return
	for body: Node in attack_range_area.get_overlapping_bodies():
		var pid: Variant = body.get("player_id")
		if pid == null or GameManager.are_allied(pid as int, player_id):
			continue
		if body.get("unit_data") == null and not (body is Animal):
			continue
		if body.get("is_cloaked") == true:
			continue
		_auto_engage(body)
		return

# ── Combat machine hooks (override points for leaf classes) ────────────────

## Whether this unit can fight. Drives the attack cursor / military filters in
## game_world and the default attack-order gate below.
func is_combat_unit() -> bool:
	return true

## Gate for player/auto attack orders (e.g. taunted units refuse other targets).
func _accepts_attack_order(_target: Node) -> bool:
	return is_combat_unit()

## order_move housekeeping (clear pending cover fire, retreats, charges...).
func _on_move_ordered() -> void:
	pass

## order_attack housekeeping.
func _on_attack_ordered() -> void:
	pass

## Every MOVING frame, before any transition (e.g. charge distance tracking).
func _on_movement_tick(_delta: float) -> void:
	pass

## Full-frame movement takeover; return true when handled (e.g. hit&run retreat).
func _handle_movement_override(_delta: float) -> bool:
	return false

## Whether the unit may open fire from here (siege overrides add minimum range).
func _in_attack_position(dist: float, reach: float) -> bool:
	return dist <= reach

## Ran when a plain move order arrives at its destination (cover fire release).
func _on_destination_reached() -> void:
	pass

## Ran when movement is stuck, just before _unstick's recovery.
func _on_movement_stuck() -> void:
	pass

## Target died or vanished. Default re-scans the range area for a new one.
func _on_target_lost() -> void:
	_scan_area_for_target()

## While true the unit holds position and does not tick its attack timer.
func _attack_paused() -> bool:
	return false

## In-combat repositioning (kiting, minimum range). Return true when the unit
## moved this frame instead of attacking.
func _combat_reposition(_dist: float, _reach: float) -> bool:
	return false

## Per-physics-frame side effects independent of state (auras, salvos, trickles).
func _combat_side_tick(_delta: float) -> void:
	pass

## Impact sound for the default melee-style strike; empty string mutes it
## (projectile units handle audio on impact instead).
func _strike_sound() -> String:
	return "hit_melee"

func _strike_sound_db() -> float:
	return -4.0

## After a successful strike (splash damage, retreat trigger, charge reset...).
func _after_strike(_target: Node) -> void:
	pass

# Armour the target reduces from THIS unit's attack. The attacker's
# unit_data.damage_type selects which armour value applies: PIERCE attacks
# (archers, gunpowder, ships, siege artillery) are reduced by armor_pierce,
# everything else by armor_melee. Buildings only define armor_melee, so they
# use it against both damage types.
func _get_target_armor(target: Node) -> float:
	if not is_instance_valid(target):
		return 0.0
	var pierce: bool = unit_data != null and unit_data.damage_type == UnitResource.DamageType.PIERCE
	var base_armor: float = 0.0
	var udata: Variant = target.get("unit_data")
	if udata is UnitResource:
		base_armor = (udata as UnitResource).armor_pierce if pierce else (udata as UnitResource).armor_melee
		# Archer-LINE targets gain extra pierce armour from padded_archer_armor
		# (the whole roster, not just the base archer — unique archers count).
		if pierce and (udata as UnitResource).id in CivBonusManager._ARCHER_IDS:
			var atid: Variant = target.get("player_id")
			if atid != null:
				base_armor += CivBonusManager.get_archer_armor_pierce_bonus(atid as int)
	else:
		var bdata: Variant = target.get("building_data")
		if bdata is BuildingResource:
			base_armor = (bdata as BuildingResource).get("armor_melee") if (bdata as BuildingResource).get("armor_melee") != null else 0.0
	# Barding melee armour: cavalry only (the target's unit id decides), and
	# never against pierce.
	if not pierce and udata is UnitResource:
		var target_pid: Variant = target.get("player_id")
		if target_pid != null:
			base_armor += CivBonusManager.get_unit_armor_bonus(
				target_pid as int, (udata as UnitResource).id)
	return base_armor

func _get_effective_attack() -> float:
	var base: float = unit_data.attack * CivBonusManager.get_unit_attack_multiplier(player_id, unit_data.id)
	return base

func _get_effective_attack_vs(target: Node) -> float:
	var base: float = _get_effective_attack()
	if target is BuildingBase or target is StaticBody2D:
		base *= CivBonusManager.get_siege_attack_bonus(player_id)
	return base

# Effective attack reach toward a target, extended by half the target's
# footprint so units stop and fight at the edge rather than trying to reach center.
func _attack_reach_to(target: Node) -> float:
	var range_mult: float = CivBonusManager.get_archer_range_multiplier(player_id) \
		if unit_data.id in CivBonusManager._ARCHER_IDS else 1.0
	var flat_bonus: float = CivBonusManager.get_archer_range_flat(player_id) \
		if unit_data.id in CivBonusManager._ARCHER_IDS else 0.0
	var base: float = unit_data.attack_range * 32.0 * range_mult + flat_bonus * 32.0
	# Risco vantage: ranged units shooting from beside a cliff reach farther.
	if unit_data.damage_type == UnitResource.DamageType.PIERCE \
			and TerrainManager.is_near_risco(global_position):
		base += TerrainManager.RISCO_RANGE_BONUS_TILES * 32.0
	if not is_instance_valid(target):
		return base
	# Prefer CollisionShape2D rectangle (buildings with StaticBody2D)
	var cs: CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var rect: RectangleShape2D = cs.shape as RectangleShape2D
		return base + maxf(rect.size.x, rect.size.y) * 0.5
	# Fallback: use the Body ColorRect dimensions (e.g. Town Center Node2D)
	var body_rect: ColorRect = target.get_node_or_null("Body") as ColorRect
	if body_rect == null:
		body_rect = target.get_node_or_null("DropOffVisual") as ColorRect
	if body_rect != null:
		var w: float = body_rect.offset_right - body_rect.offset_left
		var h: float = body_rect.offset_bottom - body_rect.offset_top
		return base + maxf(w, h) * 0.5
	return base

# Returns the best navigation target position toward a node.
# For buildings (StaticBody2D), approaches to the edge of their footprint
# instead of the center, which is inside their collision shape.
func _nav_target_for(target: Node, from_pos: Vector2 = Vector2.INF) -> Vector2:
	var target_pos: Vector2 = (target as Node2D).global_position
	if not (target is StaticBody2D):
		return target_pos
	var origin: Vector2 = from_pos if from_pos != Vector2.INF else global_position
	# Find footprint half-extents from CollisionShape2D
	var cs: CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		var to_self: Vector2 = origin - target_pos
		# Clamp the approach point to just outside the bounding box, past the
		# navmesh carve margin (12 px) so the destination is on walkable mesh.
		var clamped: Vector2 = Vector2(
			clampf(to_self.x, -half.x, half.x),
			clampf(to_self.y, -half.y, half.y)
		)
		return target_pos + clamped + to_self.normalized() * 14.0
	return target_pos

# Distance from this unit to the nearest point on a target's footprint (its
# CollisionShape2D bounding box), rather than to its centre. Range checks for
# large buildings must use this so the reach doesn't depend on footprint size —
# a fixed centre-distance threshold can never be met on a big building's corner.
func _edge_distance_to(target: Node) -> float:
	var target_pos: Vector2 = (target as Node2D).global_position
	var cs: CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		var d: Vector2 = (global_position - target_pos).abs() - half
		return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	return global_position.distance_to(target_pos)

## True for units that can enter water. Land units stay on land no matter which
## civ owns them; the Atlantes Tidecaller and every ship override this.
func is_amphibious() -> bool:
	return false

# Clamps a movement destination to the nearest passable tile for this unit.
# Call this before setting nav_agent.target_position.
func _safe_destination(destination: Vector2) -> Vector2:
	return TerrainManager.nearest_passable(destination, civ_id, is_amphibious())

# Sets the nav target and records the original destination for unstick recovery.
func _navigate_to(destination: Vector2) -> void:
	_reset_path_style()
	_move_destination = destination
	_last_repath_goal = Vector2.INF
	nav_agent.target_position = _safe_destination(destination)

## Chase repath with hysteresis. Chasers used to assign target_position every
## tick against a moving goal, forcing a nearest_passable terrain query plus a
## full A* per unit per tick — the single largest per-tick cost of a big
## battle's chase scrum. Recompute only when the goal drifted enough to change
## the answer, or the current path ran out while the goal is still away.
const REPATH_DISTANCE: float = 24.0
var _last_repath_goal: Vector2 = Vector2.INF

func _repath_to(goal: Vector2) -> void:
	if goal.distance_to(_last_repath_goal) <= REPATH_DISTANCE \
			and not nav_agent.is_navigation_finished():
		return
	_last_repath_goal = goal
	nav_agent.target_position = _safe_destination(goal)

# Returns the desired velocity toward the next nav path point.
# Returns ZERO when already at the point or navigation is finished.
func _nav_velocity() -> Vector2:
	if nav_agent.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = nav_agent.get_next_path_position()
	var dir: Vector2 = next - global_position
	if dir.length_squared() < 1.0:
		return Vector2.ZERO
	return dir.normalized() * _nav_speed()

## Current effective movement speed (all multipliers applied).
func _nav_speed() -> float:
	var status: float = _slow_mult if Time.get_ticks_msec() < _slow_until_msec else 1.0
	return unit_data.move_speed * status \
		* CivBonusManager.get_unit_speed_multiplier(player_id, unit_data.id) \
		* CivBonusManager.get_unit_move_speed_multiplier(player_id) \
		* WeatherManager.get_move_speed_multiplier(global_position, player_id) \
		* TerrainManager.get_speed_mult(global_position, civ_id, is_amphibious())

# Tracks movement over time. Returns true once per stuck period so the
# caller can take corrective action. On each trigger _stuck_retries increments
# and the caller should use _unstick() for escalating recovery.
func _advance_stuck(delta: float) -> bool:
	if global_position.distance_squared_to(_last_position) >= STUCK_THRESHOLD * STUCK_THRESHOLD:
		_stuck_timer = 0.0
		_stuck_retries = 0
		_shoved_this_period = false
		_last_position = global_position
		return false
	_stuck_timer += delta
	if _stuck_timer >= STUCK_TIMEOUT:
		_stuck_timer = 0.0
		_shoved_this_period = false
		_last_position = global_position
		_stuck_retries += 1
		return true
	return false

# Escalating unstick strategy called every time _advance_stuck fires.
# Retries 1-4: re-path with growing jitter toward a passable point near the
#              destination (path-only; never teleports the unit).
# After MAX_STUCK_RETRIES: give up and return to idle, so an unreachable
# target (e.g. an enemy on another island chased via guard/auto-scan) can no
# longer make the unit twitch in place. Earlier versions pushed global_position
# directly here, which is what produced the "units move on their own" jitter.
func _unstick() -> void:
	if _stuck_retries > MAX_STUCK_RETRIES:
		_stuck_retries = 0
		# A blocked BUILDING attacker rotates its approach around the footprint
		# instead of giving up: in a crowd, most of a melee group used to jam
		# on the same face, exhaust the retries and go permanently idle — the
		# army "couldn't damage buildings". Bounded to a full circle so a truly
		# unreachable building (another island) still abandons eventually.
		if current_state == UnitState.ATTACKING and is_instance_valid(attack_target) \
				and attack_target is StaticBody2D and _approach_step < APPROACH_STEPS.size():
			var tp: Vector2 = (attack_target as Node2D).global_position
			var dist: float = maxf(global_position.distance_to(tp), 60.0)
			var a: float = (global_position - tp).angle() + APPROACH_STEPS[_approach_step]
			_approach_step += 1
			var from: Vector2 = tp + Vector2(cos(a), sin(a)) * dist
			nav_agent.target_position = _safe_destination(_nav_target_for(attack_target, from))
			return
		_approach_step = 0
		_abandon_movement()
		return
	var dest: Vector2 = _move_destination if _move_destination != Vector2.ZERO \
		else nav_agent.target_position
	var jitter: float = 28.0 * float(mini(_stuck_retries, 2))
	nav_agent.target_position = _safe_destination(
		dest + Vector2(MatchRng.randf_range(-jitter, jitter), MatchRng.randf_range(-jitter, jitter)))

## Drop the current engagement cleanly (stance veto): no failure visuals,
## just stop and go idle so the next acquisition can happen from rest.
func _break_off_combat() -> void:
	attack_target = null
	_auto_engaged = false
	_destination_state = UnitState.IDLE
	current_state = UnitState.IDLE
	if is_instance_valid(nav_agent):
		_drive_agent(Vector2.ZERO)

# Give up the current move/chase and return to idle. Clears the combat targets
# so an abandoned unit is not immediately re-engaged by _handle_attacking.
func _abandon_movement() -> void:
	_show_path_failure()
	if is_instance_valid(nav_agent):
		_drive_agent(Vector2.ZERO)
		# Giving up means having no destination: clearing the target empties
		# the agent's path, or the cyan route would repaint after the red
		# failure fade ends (the stale path survived in the NavigationAgent).
		nav_agent.target_position = global_position
	_attack_move_active = false
	attack_target = null
	_destination_state = UnitState.IDLE
	current_state = UnitState.IDLE

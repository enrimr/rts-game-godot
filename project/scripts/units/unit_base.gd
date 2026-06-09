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

var _hit_tween: Tween = null
var _hero_low_hp_fired: bool = false   # tracks if low-HP alert has been emitted this life
var _anim_time: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_retries: int = 0
var _last_position: Vector2 = Vector2.ZERO
# Original requested destination — kept so we can re-issue after escaping a stuck.
var _move_destination: Vector2 = Vector2.ZERO

const STUCK_TIMEOUT: float = 1.2
const STUCK_THRESHOLD: float = 6.0
const MAX_STUCK_RETRIES: int = 6
const GUARD_RADIUS: float = 600.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var selection_indicator: Node2D = $SelectionIndicator
@onready var attack_range_area: Area2D = get_node_or_null("AttackRange")

var _path_line: Line2D = null
var _path_visible: bool = false

func _ready() -> void:
	if unit_data:
		var hp_mult: float = CivBonusManager.get_unit_hp_multiplier(player_id, unit_data.id)
		health = unit_data.max_health * hp_mult
		if player_id != 0 and GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL:
			health *= 0.5
		health_bar.max_value = health
		health_bar.value = health
	_last_position = global_position
	if is_instance_valid(attack_range_area):
		attack_range_area.monitoring = true
		attack_range_area.body_entered.connect(_on_enemy_entered_range)
	if player_id == 0:
		EventBus.player_entity_under_attack.connect(_on_player_entity_under_attack)
	EventBus.unit_upgrade_applied.connect(_on_unit_upgrade_applied)
	# Decide visual gender (50/50) unless a spawner or save already set it.
	if not _gender_assigned:
		is_female = randf() < 0.5
	call_deferred("_add_player_color_stripe")
	call_deferred("_add_ground_shadow")
	call_deferred("_apply_gender_appearance")

func _add_player_color_stripe() -> void:
	PlayerColors.apply_color_stripe(self, player_id, 20.0, 4.0)

# Applies the female look to human units. Non-human units (no head polygon) and
# male units are left as-is. Subclasses that style gender themselves (HeroUnit)
# override this to opt out.
func _apply_gender_appearance() -> void:
	if is_female:
		VisualFx.add_female_hair(self)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 11.0, 4.5, 9.0)

func _process(delta: float) -> void:
	_anim_time += delta
	_animate_body(delta)
	if _path_visible and is_instance_valid(_path_line):
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

	# Apply rotation animation if the body supports it (Node2D)
	if body is Node2D:
		match current_state:
			UnitState.ATTACKING:
				var swing: float = sin(t * TAU * 3.5)
				(body as Node2D).rotation = swing * 0.20
			UnitState.MOVING:
				(body as Node2D).rotation = sin(t * TAU * 2.8) * 0.08
			_:
				(body as Node2D).rotation = move_toward((body as Node2D).rotation, 0.0, _delta * 4.0)

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

	# Flip body horizontally based on target direction. Small dead zone prevents
	# flicker when the target is nearly straight above/below.
	if has_target:
		var direction: float = target_pos.x - global_position.x
		if abs(direction) > 2.0:
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
		_path_line.default_color = Color(0.3, 0.85, 1.0, 0.8)
		_path_line.z_index = 10
		add_child(_path_line)
	if is_instance_valid(_path_line):
		_path_line.visible = _path_visible

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

func set_selected(value: bool) -> void:
	is_selected = value
	selection_indicator.visible = value
	if value:
		var circle: Node = selection_indicator.get_node_or_null("SelectionCircle")
		if circle != null:
			var col: Color = Color(0.0, 1.0, 0.0, 0.7) if player_id == 0 else Color(1.0, 0.85, 0.0, 0.85)
			(circle as Polygon2D).color = col

func get_selection_sound() -> String:
	return "select_generic"

func move_to(target_position: Vector2) -> void:
	nav_agent.target_position = target_position
	current_state = UnitState.MOVING

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	health_bar.value = health
	_flash_hit()
	if health <= 0.0:
		die()
		return
	_check_hero_low_hp()
	if player_id == 0:
		AudioManager.play_if_visible("hit_melee", global_position, -8.0)
	if source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and (src_pid as int) != player_id:
			if player_id != 0:
				EventBus.ai_unit_under_attack.emit(player_id)
			else:
				EventBus.player_entity_under_attack.emit(global_position, source)
			if current_state == UnitState.IDLE:
				_on_auto_attack_target(source)

func die() -> void:
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
	if not is_instance_valid(attacker):
		return
	if global_position.distance_to(world_pos) > GUARD_RADIUS:
		return
	var att_pid: Variant = attacker.get("player_id")
	if att_pid == null or (att_pid as int) == player_id:
		return
	if attacker.get("is_cloaked") == true:
		return
	_on_auto_attack_target(attacker)

## Called when any body enters the attack-range Area2D.
## Triggers auto-attack only from IDLE, or from MOVING when attack-move is active.
func _on_enemy_entered_range(body: Node) -> void:
	if current_state != UnitState.IDLE and not (current_state == UnitState.MOVING and _attack_move_active):
		return
	var body_pid: Variant = body.get("player_id")
	if body_pid == null or (body_pid as int) == player_id:
		return
	# Only auto-attack units, not buildings (buildings don't have unit_data)
	if body.get("unit_data") == null and not (body is Animal):
		return
	if body.get("is_cloaked") == true:
		return
	_on_auto_attack_target(body)

## Move to destination, auto-attacking any enemy spotted along the way.
## Subclasses' order_move clears _attack_move_active; we re-set it right after.
func order_attack_move(destination: Vector2) -> void:
	if has_method("order_move"):
		call("order_move", destination)
	_attack_move_active = true

# Override in subclasses to trigger attack logic.
func _on_auto_attack_target(_target: Node) -> void:
	_attack_move_active = false

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
		# Archer-type targets gain extra pierce armour from the padded_archer_armor tech
		if pierce and (udata as UnitResource).id == "archer":
			var atid: Variant = target.get("player_id")
			if atid != null:
				base_armor += CivBonusManager.get_archer_armor_pierce_bonus(atid as int)
	else:
		var bdata: Variant = target.get("building_data")
		if bdata is BuildingResource:
			base_armor = (bdata as BuildingResource).get("armor_melee") if (bdata as BuildingResource).get("armor_melee") != null else 0.0
	# The generic per-civ armour bonus is melee armour; it does not shield against pierce.
	if not pierce:
		var target_pid: Variant = target.get("player_id")
		if target_pid != null:
			base_armor += CivBonusManager.get_unit_armor_bonus(target_pid as int)
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
func _nav_target_for(target: Node) -> Vector2:
	var target_pos: Vector2 = (target as Node2D).global_position
	if not (target is StaticBody2D):
		return target_pos
	# Find footprint half-extents from CollisionShape2D
	var cs: CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		var to_self: Vector2 = global_position - target_pos
		# Clamp the approach point to just outside the bounding box
		var clamped: Vector2 = Vector2(
			clampf(to_self.x, -half.x, half.x),
			clampf(to_self.y, -half.y, half.y)
		)
		return target_pos + clamped + to_self.normalized() * 8.0
	return target_pos

# Clamps a movement destination to the nearest passable tile for this unit.
# Call this before setting nav_agent.target_position.
func _safe_destination(destination: Vector2) -> Vector2:
	return TerrainManager.nearest_passable(destination, civ_id)

# Sets the nav target and records the original destination for unstick recovery.
func _navigate_to(destination: Vector2) -> void:
	_move_destination = destination
	nav_agent.target_position = _safe_destination(destination)

# Returns the desired velocity toward the next nav path point.
# Returns ZERO when already at the point or navigation is finished.
func _nav_velocity() -> Vector2:
	if nav_agent.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = nav_agent.get_next_path_position()
	var dir: Vector2 = next - global_position
	if dir.length_squared() < 1.0:
		return Vector2.ZERO
	var spd: float = unit_data.move_speed \
		* CivBonusManager.get_unit_speed_multiplier(player_id, unit_data.id) \
		* CivBonusManager.get_unit_move_speed_multiplier(player_id) \
		* WeatherManager.get_move_speed_multiplier(global_position) \
		* TerrainManager.get_speed_mult(global_position, civ_id)
	return dir.normalized() * spd

# Tracks movement over time. Returns true once per stuck period so the
# caller can take corrective action. On each trigger _stuck_retries increments
# and the caller should use _unstick() for escalating recovery.
func _advance_stuck(delta: float) -> bool:
	if global_position.distance_squared_to(_last_position) >= STUCK_THRESHOLD * STUCK_THRESHOLD:
		_stuck_timer = 0.0
		_stuck_retries = 0
		_last_position = global_position
		return false
	_stuck_timer += delta
	if _stuck_timer >= STUCK_TIMEOUT:
		_stuck_timer = 0.0
		_last_position = global_position
		_stuck_retries += 1
		return true
	return false

# Escalating unstick strategy called every time _advance_stuck fires.
# Retries 1-2: small target jitter.
# Retries 3-4: large jitter + re-path to passable position near destination.
# Retries 5+:  physically push the unit sideways out of the obstacle.
func _unstick() -> void:
	var dest: Vector2 = _move_destination if _move_destination != Vector2.ZERO \
		else nav_agent.target_position
	match _stuck_retries:
		1, 2:
			var jitter: float = 28.0 * float(_stuck_retries)
			nav_agent.target_position = _safe_destination(
				dest + Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter)))
		3, 4:
			var jitter: float = 56.0
			var new_dest: Vector2 = _safe_destination(
				dest + Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter)))
			nav_agent.target_position = new_dest
			# Also nudge the unit itself slightly away from where it's stuck
			var push: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * 20.0
			global_position += push
		_:
			# Push unit toward destination, stepping around the blocker
			var to_dest: Vector2 = (dest - global_position).normalized()
			var perp: Vector2 = Vector2(-to_dest.y, to_dest.x)
			var side: float = 1.0 if (_stuck_retries % 2 == 0) else -1.0
			global_position += perp * side * 32.0 + to_dest * 16.0
			nav_agent.target_position = _safe_destination(dest)
			if _stuck_retries > MAX_STUCK_RETRIES:
				_stuck_retries = 0

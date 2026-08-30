extends StaticBody2D

class_name BuildingBase

enum BuildingState { BLUEPRINT, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

@export var building_data: BuildingResource

const MAX_BUILD_SPEED_MULTIPLIER: float = 3.0

var player_id: int = 0
var state: BuildingState = BuildingState.BLUEPRINT
# Property setter: EVERY writer (take_damage, villager repair via
# set("health"), save restore) refreshes the health bar, so building damage is
# always visible — most building scenes ship without a HealthBar node and
# nothing ever showed their HP before.
var health: float = 0.0:
	set(value):
		health = value
		_refresh_health_bar()
var max_health: float = 0.0
var construction_progress: float = 0.0
var _active_builders: int = 0

signal construction_complete
signal building_destroyed(building: Node)

@onready var _progress_bar: ProgressBar = get_node_or_null("ConstructionBar")
@onready var _body_node: CanvasItem  = get_node_or_null("Body")

var _selection_line: Line2D = null
var rally_point: Vector2 = Vector2.ZERO
var _rally_marker: Node2D = null
var _hit_tween: Tween = null
var _under_attack_timer: float = 0.0
var _blink_phase: float = 0.0

func set_rally_point(world_pos: Vector2) -> void:
	rally_point = world_pos
	if not is_instance_valid(_rally_marker):
		_rally_marker = _make_rally_marker()
		add_child(_rally_marker)
	_rally_marker.global_position = world_pos
	_rally_marker.visible = true

func _show_rally_marker(show: bool) -> void:
	if is_instance_valid(_rally_marker):
		_rally_marker.visible = show and rally_point != Vector2.ZERO

# Returns a free spawn position near `origin` using an outward spiral.
# Skips positions occupied by other units/buildings (physics query).
# `step` is the grid cell size; `max_rings` limits search depth.
static func find_spawn_pos(origin: Vector2, space: PhysicsDirectSpaceState2D,
		step: float = 32.0, max_rings: int = 8) -> Vector2:
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = step * 0.45
	query.shape = shape
	query.collision_mask = 3
	# Ring 0 = the offset just outside the building
	for ring: int in range(1, max_rings + 1):
		var r: float = step * float(ring)
		var steps_in_ring: int = maxi(4, ring * 4)
		for s: int in range(steps_in_ring):
			var angle: float = s * TAU / float(steps_in_ring)
			var candidate: Vector2 = origin + Vector2(cos(angle), sin(angle)) * r
			query.transform = Transform2D(0.0, candidate)
			if space.intersect_shape(query, 1).is_empty():
				return candidate
	# Fallback: just use a fixed offset
	return origin + Vector2(step * 2.0, 0.0)

static func _make_rally_marker() -> Node2D:
	var root: Node2D = Node2D.new()
	root.z_index = 5
	var line: Line2D = Line2D.new()
	line.width = 1.0
	line.default_color = Color(1.0, 0.92, 0.2, 0.7)
	line.points = PackedVector2Array([
		Vector2(-6.0, 0.0), Vector2(6.0, 0.0),
		Vector2(0.0, 0.0), Vector2(0.0, -12.0),
	])
	# The pole stands upright on the projected ground (see IsoBillboard);
	# the base circle below stays flat as the classic ground ring.
	IsoBillboard.make_upright(line)
	root.add_child(line)
	var circle: Line2D = Line2D.new()
	circle.width = 1.0
	circle.default_color = Color(1.0, 0.92, 0.2, 0.7)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(17):
		var a: float = i * TAU / 16.0
		pts.append(Vector2(cos(a), sin(a)) * 5.0)
	circle.points = pts
	root.add_child(circle)
	return root

func set_selected(value: bool) -> void:
	if value:
		if not is_instance_valid(_selection_line):
			_selection_line = _make_selection_line(_footprint_rect())
			add_child(_selection_line)
		_selection_line.visible = true
	else:
		if is_instance_valid(_selection_line):
			_selection_line.visible = false
	VisualFx.set_nameplate_visible(self, value)
	_show_rally_marker(value)

func _footprint_rect() -> Rect2:
	const PAD: float = 4.0
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var h: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		return Rect2(-h.x - PAD, -h.y - PAD, (h.x + PAD) * 2.0, (h.y + PAD) * 2.0)
	return Rect2(-28.0, -28.0, 56.0, 56.0)

static func _make_selection_line(r: Rect2) -> Line2D:
	var line: Line2D = Line2D.new()
	line.width = 1.5
	line.default_color = Color(1.0, 0.92, 0.2, 0.95)
	line.z_index = 6
	line.points = PackedVector2Array([
		r.position,
		Vector2(r.end.x,    r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
		r.position,
	])
	return line

func _ready() -> void:
	add_to_group("buildings")
	if building_data:
		var hp_mult: float = CivBonusManager.get_building_hp_multiplier(player_id, building_data.id)
		max_health = building_data.max_health * hp_mult
		health = max_health
	# Before IsoBuildingMassing.apply so the massing pass positions the bar
	# above the roof and the billboard pass uprights it ("HealthBar" is in
	# _iso_upright_children).
	_ensure_health_bar()
	IsoBuildingMassing.apply(self)
	_refresh_visuals()
	_localize_nameplate()
	VisualFx.set_nameplate_visible(self, false)
	call_deferred("_apply_player_color_stripe")
	call_deferred("_apply_team_accents")
	call_deferred("_add_ground_shadow")
	call_deferred("_setup_iso_billboard")
	call_deferred("_setup_damage_fx")

func _localize_nameplate() -> void:
	var nameplate: Label = get_node_or_null("NameLabel") as Label
	if nameplate == null or building_data == null:
		return
	var localized: String = EntityNames.building_name(building_data)
	if not localized.is_empty():
		nameplate.text = localized

# Stand the building's art upright on the projected ground (see IsoBillboard).
# The footprint selection rectangle, ground shadow and colour stripe stay
# ground-projected so they read as flat on the diamond.
func _setup_iso_billboard() -> void:
	IsoBillboard.setup_entity(self, _iso_upright_children())

# Overridable: which visual children stand upright. Ground-plane buildings
# (e.g. Farm) override this to keep their body flat.
func _iso_upright_children() -> Array:
	return ["Body", "ScaffoldRig", "NameLabel", "StateLabel", "HealthBar",
		"ConstructionBar", "TrainingBar", "FoodBar", "PlayerColorStripe"]

# Recolours team-accent polygons (flags, roofs, banners) to the owner's colour so
# buildings are identifiable at a glance. Any Polygon2D/Line2D under Body whose
# name starts with "Team" is tinted; a name containing "Dark" gets a shaded
# variant (e.g. roof underside) so accents keep some depth.
func _apply_team_accents() -> void:
	var body: Node = get_node_or_null("Body")
	if body == null:
		return
	var col: Color = PlayerColors.get_color(player_id)
	var dark: Color = Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 1.0)
	for node: Node in body.get_children():
		if not node.name.begins_with("Team"):
			continue
		var tint: Color = dark if node.name.contains("Dark") else col
		if node is Polygon2D:
			(node as Polygon2D).color = tint
		elif node is Line2D:
			(node as Line2D).default_color = tint

func _add_ground_shadow() -> void:
	# Iso-massed buildings get a footprint-matching contact shadow from the
	# massing pass; a second detached ellipse would read as floating.
	if has_meta("massing_bot_y"):
		return
	var rx: float = 30.0
	var ry: float = 14.0
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var h: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		rx = h.x * 1.05
		ry = h.y * 0.55
	VisualFx.add_ground_shadow(self, rx, ry, ry * 0.7)

func register_builder() -> void:
	_active_builders += 1

func unregister_builder() -> void:
	_active_builders = maxi(0, _active_builders - 1)

func add_construction(base_amount: float) -> void:
	var multiplier: float = minf(float(_active_builders), MAX_BUILD_SPEED_MULTIPLIER)
	if multiplier < 1.0:
		multiplier = 1.0
	construction_progress = minf(construction_progress + base_amount * multiplier, 100.0)
	_refresh_visuals()
	if construction_progress >= 100.0:
		_complete_construction()

func _complete_construction() -> void:
	state = BuildingState.COMPLETE
	_refresh_health_bar()
	if is_instance_valid(_progress_bar):
		_progress_bar.visible = false
	if is_instance_valid(_body_node):
		_body_node.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_update_scaffold()
	if player_id == 0:
		AudioManager.play("build_complete")
	construction_complete.emit()
	EventBus.building_construction_complete.emit(self)

# Mark a building as already-built without a construction phase (e.g. the
# player's starting Town Center). Sets full progress and clears the
# blueprint/under-construction visuals; does NOT play the build sound or emit
# construction_complete, since nothing was actually constructed.
func force_complete() -> void:
	construction_progress = 100.0
	state = BuildingState.COMPLETE
	_refresh_health_bar()
	if is_instance_valid(_progress_bar):
		_progress_bar.visible = false
	if is_instance_valid(_body_node):
		_body_node.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_update_scaffold()

## The building HP bar, shown only while a COMPLETE building is damaged (the
## construction phase has its own ConstructionBar). Scenes that already ship a
## HealthBar node (dock, wonder) keep it; everyone else gets one at runtime.
var _health_bar: ProgressBar = null

func _ensure_health_bar() -> void:
	_health_bar = get_node_or_null("HealthBar") as ProgressBar
	if _health_bar == null:
		_health_bar = ProgressBar.new()
		_health_bar.name = "HealthBar"
		_health_bar.offset_left = -40.0
		_health_bar.offset_top = -44.0
		_health_bar.offset_right = 40.0
		_health_bar.offset_bottom = -38.0
		_health_bar.max_value = 100.0
		_health_bar.value = 100.0
		_health_bar.show_percentage = false
		_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_health_bar)
	_health_bar.visible = false

func _refresh_health_bar() -> void:
	if not is_instance_valid(_health_bar) or max_health <= 0.0:
		return
	_health_bar.value = clampf(health / max_health * 100.0, 0.0, 100.0)
	_health_bar.visible = state == BuildingState.COMPLETE \
		and health < max_health - 0.01 and health > 0.0

func _refresh_visuals() -> void:
	if is_instance_valid(_progress_bar):
		_progress_bar.value = construction_progress
		_progress_bar.visible = state == BuildingState.UNDER_CONSTRUCTION or construction_progress < 100.0
	# Blueprint/under-construction tint: semi-transparent
	if is_instance_valid(_body_node):
		var alpha: float = 0.4 + construction_progress / 100.0 * 0.6
		_body_node.modulate = Color(1.0, 1.0, 1.0, alpha)
	_update_scaffold()

# Wooden scaffold rig (generated with the iso massing) framing the volume
# while it is being built; hidden on placement ghosts and finished buildings.
func _update_scaffold() -> void:
	var rig: Node2D = get_node_or_null("ScaffoldRig") as Node2D
	if rig != null:
		rig.visible = state == BuildingState.UNDER_CONSTRUCTION \
			and construction_progress < 100.0

func _apply_player_color_stripe() -> void:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	var w: float = 48.0
	var b: float = 36.0
	if cs != null and cs.shape is RectangleShape2D:
		var h: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		w = h.x * 2.0
		b = h.y
	if has_meta("massing_bot_y"):
		# With iso massing the ownership marker is a ground trim along the two
		# near footprint edges — a screen-space bar would cut through the walls.
		var half: Vector2 = IsoBuildingMassing._half_extents(self)
		PlayerColors.apply_iso_ownership_trim(self, player_id, half)
		return
	PlayerColors.apply_color_stripe(self, player_id, w, b)

func take_damage(amount: float, source: Node = null) -> void:
	# Replication puppet (LAN client mirror): the host owns all damage; local
	# hits would kill entities the authority still considers alive.
	if get_meta(&"rep_puppet", false):
		return
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	_flash_hit()
	if source != null and is_instance_valid(source):
		var src_pid: Variant = source.get("player_id")
		if src_pid != null and (src_pid as int) != player_id:
			if player_id != 0:
				EventBus.ai_unit_under_attack.emit(player_id)
			else:
				EventBus.player_entity_under_attack.emit(global_position, source)
	if health <= 0.0:
		_destroy()

func _flash_hit() -> void:
	_under_attack_timer = 3.0
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _process(delta: float) -> void:
	# Volcanic ash: slow HP drain for any standing building (including pre-placed
	# Town Centers whose state never transitions through add_construction).
	if state != BuildingState.UNDER_CONSTRUCTION and state != BuildingState.DESTROYED:
		var ash_dmg: float = WeatherManager.get_building_damage_rate(global_position, player_id) * delta
		if ash_dmg > 0.0:
			take_damage(ash_dmg)
	if _under_attack_timer <= 0.0:
		return
	_under_attack_timer -= delta
	# Let the sharp hit-flash finish before the slow pulse takes over
	if is_instance_valid(_hit_tween) and _hit_tween.is_running():
		return
	_blink_phase += delta * 4.0
	var t: float = (sin(_blink_phase) * 0.5 + 0.5)  # 0..1
	var r: float = lerpf(1.0, 1.0, t)
	var g: float = lerpf(0.35, 1.0, t)
	var b: float = lerpf(0.35, 1.0, t)
	modulate = Color(r, g, b, 1.0)
	if _under_attack_timer <= 0.0:
		modulate = Color(1.0, 1.0, 1.0, 1.0)

func _setup_damage_fx() -> void:
	BuildingDamageFx.attach(self)

# NOTE: buildings deliberately have NO RVO avoidance obstacle. They used to
# carry one at collision + 16 px per side — LARGER than the navmesh carve
# margin (6 px + agent radius), so two grid-adjacent buildings sealed the very
# corridor the mesh had opened between them: the path said "through here", the
# physics gap fit the unit, and the RVO solver returned a safe velocity of
# exactly zero forever (the frozen-villager-in-a-gap playtest bug). The mesh is
# the single static authority; physics collision is the hard backstop. The
# vertex-less NavigationObstacle2D nodes still in some scenes are inert (the
# Gate toggles its own for the open/close flow).

func _nav_bake_half_extents() -> Vector2:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		# 6 px carve. Combined with the nav agent_radius (10 px) the effective
		# dead-zone is ~16 px = one grid cell, so a 1-cell gap stays passable
		# while a 0-cell gap is closed. A larger margin (e.g. 12 px) made many
		# obstruction outlines overlap heavily and could make Godot's convex
		# partition fail, leaving an EMPTY navmesh (units frozen).
		return (cs.shape as RectangleShape2D).size * 0.5 + Vector2(6.0, 6.0)
	return Vector2(34.0, 34.0)

# Returns the world-space obstacle polygon (4 corners) used by the nav bake.
func get_nav_obstacle_polygon() -> PackedVector2Array:
	var half: Vector2 = _nav_bake_half_extents()
	return PackedVector2Array([
		global_position + Vector2(-half.x, -half.y),
		global_position + Vector2( half.x, -half.y),
		global_position + Vector2( half.x,  half.y),
		global_position + Vector2(-half.x,  half.y),
	])

func _destroy() -> void:
	state = BuildingState.DESTROYED
	# AoE2 rule: whoever is inside dies with the building.
	for unit: Node in _garrison:
		if is_instance_valid(unit) and unit.has_method("die"):
			unit.call("die")
	_garrison.clear()
	AudioManager.play("build_destroy", -2.0)
	EventBus.building_destroyed.emit(self, player_id)
	building_destroyed.emit(self)
	queue_free()

# ── Garrison (AoE2-style: TC and towers shelter land units) ────────────────

var _garrison: Array[Node] = []

## 0 = this building cannot garrison. Overridden by WatchTower (5) and
## TownCenterBuildable (10).
func garrison_capacity() -> int:
	return 0

func get_garrison() -> Array:
	return _garrison

## Land military and villagers fit; ships and siege never do.
func can_garrison_unit(unit: Node) -> bool:
	if garrison_capacity() <= 0 or state != BuildingState.COMPLETE:
		return false
	if _garrison.size() >= garrison_capacity():
		return false
	if not is_instance_valid(unit) or not (unit is UnitBase) or unit is ShipBase:
		return false
	if unit is BatteringRam or unit is Mangonel or unit is Trebuchet:
		return false
	return true

func garrison_unit(unit: Node) -> bool:
	if not can_garrison_unit(unit):
		return false
	_garrison.append(unit)
	unit.set_process(false)
	unit.set_physics_process(false)
	(unit as Node2D).visible = false
	if unit.has_method("set_selected"):
		unit.call("set_selected", false)
	EventBus.garrison_changed.emit(self, _garrison.size(), garrison_capacity())
	return true

func ungarrison_all() -> void:
	if _garrison.is_empty():
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for unit: Node in _garrison:
		if not is_instance_valid(unit):
			continue
		unit.set_process(true)
		unit.set_physics_process(true)
		(unit as Node2D).visible = true
		(unit as Node2D).global_position = find_spawn_pos(
			global_position + Vector2(0.0, _garrison_exit_offset()), space)
	_garrison.clear()
	EventBus.garrison_changed.emit(self, 0, garrison_capacity())

## How far below the origin units re-appear (past the footprint).
func _garrison_exit_offset() -> float:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).size.y * 0.5 + 24.0
	return 56.0

# ── Building ranged attack (towers; the TC when garrisoned) ─────────────────
# Volley size comes from _ranged_attack_arrows(): 0 disables the whole block,
# so plain buildings pay one virtual call per physics tick and nothing else.

var _attack_timer: float = 0.0
var _attack_target: Node = null

func _ranged_attack_arrows() -> int:
	return 0

func _attack_range() -> float:
	return 220.0

func _attack_damage() -> float:
	return 5.0

func _attack_rate() -> float:
	return 1.2   # volleys per second

## CivBonusManager attack-multiplier key for this building.
func _attack_bonus_id() -> String:
	return "watch_tower"

func _physics_process(delta: float) -> void:
	var arrows: int = _ranged_attack_arrows()
	if arrows <= 0 or state != BuildingState.COMPLETE:
		return
	if not is_instance_valid(_attack_target) or \
			global_position.distance_to((_attack_target as Node2D).global_position) > _attack_range():
		_attack_target = _find_nearest_enemy()
	if not is_instance_valid(_attack_target):
		return
	_attack_timer += delta
	if _attack_timer >= 1.0 / _attack_rate():
		_attack_timer = 0.0
		_launch_volley(_attack_target, arrows)

## `count` arrows at the target with a small deterministic spread — garrisoned
## units multiply the volley, AoE2-style.
func _launch_volley(target: Node, count: int) -> void:
	var dmg: float = _attack_damage() * CivBonusManager.get_unit_attack_multiplier(player_id, _attack_bonus_id())
	var to_target: Vector2 = ((target as Node2D).global_position - global_position).normalized()
	var side: Vector2 = Vector2(-to_target.y, to_target.x)
	for i: int in range(count):
		var arrow: Arrow = (preload("res://scenes/combat/arrow.tscn").instantiate()) as Arrow
		arrow.damage = dmg
		arrow.shooter = self
		arrow.target_pos = (target as Node2D).global_position \
			+ side * (float(i) - float(count - 1) * 0.5) * 10.0
		arrow._original_target = target
		get_parent().add_child(arrow)
		arrow.global_position = global_position \
			+ IsoProjection.screen_to_world(Vector2(0.0, -60.0)) \
			+ side * (float(i) - float(count - 1) * 0.5) * 6.0
		arrow.reset_physics_interpolation()

func _find_nearest_enemy() -> Node:
	var best: Node = null
	var best_dist: float = _attack_range()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var d: float = global_position.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

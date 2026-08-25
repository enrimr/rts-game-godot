extends CharacterBody2D

class_name Animal

enum AnimalState { WILD, OWNED, FLEEING, DEAD }

const FOOD_AMOUNT: float = 150.0
const WANDER_SPEED: float = 40.0
const FLEE_SPEED: float   = 110.0
const WANDER_RADIUS: float = 220.0
const FLEE_DURATION: float = 3.0

@export var max_health: float = 40.0
@export var animal_name: String = "Deer"
@export var convertible: bool = false
@export var line_of_sight: float = 1.0

var player_id: int = -1
var health: float = 0.0
var current_state: AnimalState = AnimalState.WILD

var _wander_timer: float = 0.0
var _flee_timer: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _hit_tween: Tween = null

# Leg walk animation: each entry is {node, base, phase}. Legs swing back/forth
# in counter-phase while the animal moves, easing back to rest when it stops.
var _legs: Array[Dictionary] = []
var _walk_time: float = 0.0
const _LEG_SWING: float = 2.2   # px of fore/aft swing
const _LEG_FREQ: float = 3.2    # stride cycles per second

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _selection_indicator: Node2D = $SelectionIndicator
@onready var _body: Node2D = $Body
@onready var _body_torso: Polygon2D = $Body/Torso
@onready var _nav: NavigationAgent2D = $NavigationAgent2D
@onready var _convert_area: Area2D = $ConvertArea

func _ready() -> void:
	health = max_health
	_origin = global_position
	_pick_wander_target()
	add_to_group("animals")
	_nav.velocity_computed.connect(_on_velocity_computed)
	_convert_area.body_entered.connect(_on_body_entered_range)
	_collect_legs()
	call_deferred("_setup_iso_billboard")

func _setup_iso_billboard() -> void:
	IsoBillboard.setup_entity(self, ["Body", "HealthBar"])

# Gathers the leg polygons (deer has 4, sheep has 2) with their rest position and
# a stride phase so diagonal legs swing together (a natural trot/walk).
func _collect_legs() -> void:
	var phases: Dictionary = {
		"LegFrontFar": 0.0, "LegBackNear": 0.0,   # diagonal pair A
		"LegBackFar": PI,   "LegFrontNear": PI,    # diagonal pair B
		"LegFront": 0.0,    "LegBack": PI,          # sheep's two legs
	}
	for leg_name: String in phases:
		var leg: Polygon2D = _body.get_node_or_null(leg_name) as Polygon2D
		if leg != null:
			_legs.append({"node": leg, "base": leg.position, "phase": phases[leg_name]})

func _process(delta: float) -> void:
	IsoBillboard.update_depth(self)
	if _legs.is_empty():
		return
	var moving: bool = current_state != AnimalState.DEAD and velocity.length_squared() > 4.0
	if moving:
		_walk_time += delta
	var amount: float = _LEG_SWING if moving else 0.0
	for entry: Dictionary in _legs:
		var leg: Polygon2D = entry["node"] as Polygon2D
		if not is_instance_valid(leg):
			continue
		var base: Vector2 = entry["base"] as Vector2
		var target_x: float = base.x
		if moving:
			target_x += sin(_walk_time * TAU * _LEG_FREQ + (entry["phase"] as float)) * amount
		# Ease toward the target so stopping settles smoothly.
		leg.position.x = lerpf(leg.position.x, target_x, clampf(delta * 12.0, 0.0, 1.0))

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if current_state == AnimalState.DEAD:
		return
	velocity = safe_velocity
	move_and_slide()
	_face_movement(safe_velocity)

# Flips the body to face the travel direction. The sprite is drawn facing right
# (head at +x), so scale.x = 1 faces right, -1 faces left. A small horizontal
# dead zone avoids flicker when moving almost straight up or down.
func _face_movement(vel: Vector2) -> void:
	if not is_instance_valid(_body):
		return
	if absf(vel.x) > 2.0:
		_body.scale.x = -1.0 if vel.x < 0.0 else 1.0

func set_selected(value: bool) -> void:
	_selection_indicator.visible = value

func take_damage(amount: float, source: Node = null) -> void:
	if current_state == AnimalState.DEAD:
		return
	health -= amount
	_health_bar.value = (health / max_health) * 100.0
	if is_instance_valid(_hit_tween):
		_hit_tween.kill()
	modulate = Color(1.0, 0.2, 0.2, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)
	if health <= 0.0:
		_die()
		return
	if current_state == AnimalState.WILD and source != null:
		_start_flee(source)

func _physics_process(delta: float) -> void:
	# Teleport back to nearest passable ground if the nav mesh walked us into
	# impassable terrain (ocean, risco, caldera).
	if TerrainManager.is_impassable_for(global_position, ""):
		global_position = TerrainManager.nearest_passable(global_position, "")
		_nav.target_position = global_position
		velocity = Vector2.ZERO
		return
	match current_state:
		AnimalState.WILD:
			_handle_wander(delta)
		AnimalState.OWNED:
			_handle_owned_move()
		AnimalState.FLEEING:
			_handle_flee(delta)

func _handle_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_target()
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	_nav.set_velocity(_direction_to_target() * WANDER_SPEED)

func _handle_owned_move() -> void:
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	_nav.set_velocity(_direction_to_target() * WANDER_SPEED)

func order_move(destination: Vector2) -> void:
	if current_state != AnimalState.OWNED:
		return
	var target: Vector2 = destination if not TerrainManager.is_impassable_for(destination, "") \
		else TerrainManager.nearest_passable(destination, "")
	_nav.target_position = target

func _handle_flee(delta: float) -> void:
	_flee_timer -= delta
	if _flee_timer <= 0.0 or _nav.is_navigation_finished():
		current_state = AnimalState.WILD
		_pick_wander_target()
		return
	_nav.set_velocity(_direction_to_target() * FLEE_SPEED)

func _on_body_entered_range(body: Node) -> void:
	if not convertible:
		return
	if current_state == AnimalState.DEAD:
		return
	var pid: Variant = body.get("player_id")
	if pid == null:
		return
	var owner_id: int = pid as int
	if owner_id < 0:
		return
	_try_convert(owner_id)

func _try_convert(owner_id: int) -> void:
	if current_state == AnimalState.DEAD:
		return
	if player_id == owner_id:
		return
	_convert_to(owner_id)

func _convert_to(owner_id: int) -> void:
	player_id = owner_id
	current_state = AnimalState.OWNED
	_on_converted()
	_origin = global_position
	_nav.target_position = global_position
	velocity = Vector2.ZERO

func _on_converted() -> void:
	_body_torso.color = Color(0.78, 0.55, 0.18, 1.0)

func _start_flee(from_source: Node) -> void:
	current_state = AnimalState.FLEEING
	_flee_timer = FLEE_DURATION
	var flee_dir: Vector2 = (global_position - (from_source as Node2D).global_position).normalized()
	# Try to flee directly away; if that lands on impassable terrain, rotate
	# the direction in steps until a passable spot is found.
	for step: int in range(8):
		var rot: float = step * (PI / 4.0) * (1 if step % 2 == 0 else -1)
		var rotated: Vector2 = flee_dir.rotated(rot)
		var away: Vector2 = global_position + rotated * 300.0
		if not TerrainManager.is_impassable_for(away, ""):
			_nav.target_position = away
			return
	_nav.target_position = global_position

func _pick_wander_target() -> void:
	_wander_timer = randf_range(3.0, 8.0)
	# Try up to 10 candidates; skip any that land on impassable terrain (ocean,
	# risco, caldera) so the animal stays on its home terrain type.
	for _i: int in range(10):
		var angle: float = randf() * TAU
		var dist: float  = randf_range(60.0, WANDER_RADIUS)
		var candidate: Vector2 = _origin + Vector2(cos(angle), sin(angle)) * dist
		if not TerrainManager.is_impassable_for(candidate, ""):
			_nav.target_position = candidate
			return
	# All candidates were impassable — stay put
	_nav.target_position = global_position

func _direction_to_target() -> Vector2:
	if _nav.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = _nav.get_next_path_position()
	var dir: Vector2  = next - global_position
	if dir.length_squared() < 1.0:
		return Vector2.ZERO
	return dir.normalized()

func _die() -> void:
	current_state = AnimalState.DEAD
	_health_bar.visible = false
	_selection_indicator.visible = false
	var food_node: Node2D = Node2D.new()
	food_node.set_script(load("res://scripts/economy/resource_node.gd"))
	food_node.set("resource_type", ResourceNode.ResourceType.FOOD_HUNT)
	food_node.set("initial_amount", FOOD_AMOUNT)
	get_parent().get_parent().add_child(food_node)
	food_node.global_position = global_position
	_build_carcass(food_node)
	IsoBillboard.setup_drawn_node(food_node)
	queue_free()

# Procedural carcass sprite for the food drop (replaces the old red square):
# a fallen body lying on a blood patch, with legs sticking up.
func _build_carcass(parent: Node2D) -> void:
	var blood: Color = Color(0.45, 0.10, 0.08, 0.55)
	var hide: Color = Color(0.42, 0.30, 0.20, 1.0)      # brown carcass
	var hide_dark: Color = Color(0.30, 0.21, 0.14, 1.0)
	var bone: Color = Color(0.78, 0.74, 0.62, 1.0)

	# Blood pool under the carcass (flat ellipse made of a polygon).
	# z < 0 marks it as a ground decal so IsoBillboard keeps it flat.
	var pool: Polygon2D = Polygon2D.new()
	pool.z_index = -1
	pool.color = blood
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(12):
		var a: float = float(i) / 12.0 * TAU
		pts.append(Vector2(cos(a) * 15.0, sin(a) * 8.0 + 2.0))
	pool.polygon = pts
	parent.add_child(pool)

	# Body lying on its side (rounded rectangle-ish lump).
	var body: Polygon2D = Polygon2D.new()
	body.color = hide
	body.polygon = PackedVector2Array([
		Vector2(-12, 1), Vector2(-9, -5), Vector2(8, -6),
		Vector2(12, -1), Vector2(10, 4), Vector2(-10, 4)])
	parent.add_child(body)

	# Belly shading.
	var shade: Polygon2D = Polygon2D.new()
	shade.color = hide_dark
	shade.polygon = PackedVector2Array([Vector2(-10, 4), Vector2(10, 4), Vector2(8, 1), Vector2(-9, 1)])
	parent.add_child(shade)

	# Head drooping to the left.
	var head: Polygon2D = Polygon2D.new()
	head.color = hide_dark
	head.polygon = PackedVector2Array([Vector2(-12, 1), Vector2(-17, 2), Vector2(-16, 5), Vector2(-11, 4)])
	parent.add_child(head)

	# Two stiff legs pointing up.
	for lx: float in [-3.0, 4.0]:
		var leg: Polygon2D = Polygon2D.new()
		leg.color = hide_dark
		leg.polygon = PackedVector2Array([
			Vector2(lx - 1.2, -6), Vector2(lx + 1.2, -6),
			Vector2(lx + 1.0, -13), Vector2(lx - 1.0, -13)])
		parent.add_child(leg)
		var hoof: Polygon2D = Polygon2D.new()
		hoof.color = bone
		hoof.polygon = PackedVector2Array([
			Vector2(lx - 1.0, -13), Vector2(lx + 1.0, -13),
			Vector2(lx + 1.0, -15), Vector2(lx - 1.0, -15)])
		parent.add_child(hoof)

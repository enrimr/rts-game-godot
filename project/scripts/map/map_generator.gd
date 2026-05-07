class_name MapGenerator

## Generates a symmetric random map.
## Placement order: TCs → units → animals → resources.
## A spatial registry prevents any two objects from overlapping.

const MAX_PLACE_TRIES: int = 40

# --- Radii used when registering objects ---
const R_TC: float        = 130.0   # large exclusion zone around each TC
const R_UNIT: float      = 22.0
const R_ANIMAL: float    = 28.0
const R_RES_WOOD: float  = 22.0
const R_RES_OTHER: float = 30.0

const RES_COLORS: Dictionary = {
	ResourceNode.ResourceType.WOOD:       Color(0.10, 0.55, 0.10, 1.0),
	ResourceNode.ResourceType.GOLD:       Color(0.90, 0.75, 0.10, 1.0),
	ResourceNode.ResourceType.STONE:      Color(0.62, 0.60, 0.58, 1.0),
	ResourceNode.ResourceType.FOOD_HUNT:  Color(0.65, 0.28, 0.10, 1.0),
}
const RES_LABELS: Dictionary = {
	ResourceNode.ResourceType.WOOD:       "Wood",
	ResourceNode.ResourceType.GOLD:       "Gold",
	ResourceNode.ResourceType.STONE:      "Stone",
	ResourceNode.ResourceType.FOOD_HUNT:  "Food",
}

const ANIMAL_SCENE: String = "res://scenes/units/animal.tscn"
const SHEEP_SCENE:  String = "res://scenes/units/sheep.tscn"
const VILLAGER_SCENE: String = "res://scenes/units/villager.tscn"
const SCOUT_SCENE:    String = "res://scenes/units/scout.tscn"

# Placement registry: Array of {pos: Vector2, radius: float}
var _placed: Array[Dictionary] = []
var _rng: RandomNumberGenerator = null
var _map_half: float = 1800.0
var _res_mult: float = 1.0

# ── Public entry point ──────────────────────────────────────────────────────

static func generate(parent: Node2D, units_layer: Node2D,
		rng: RandomNumberGenerator) -> Dictionary:
	var gen: MapGenerator = MapGenerator.new()
	gen._map_half = MatchConfig.get_map_half()
	gen._res_mult = MatchConfig.get_resource_multiplier()
	return gen._run(parent, units_layer, rng)

# ── Main pipeline ───────────────────────────────────────────────────────────

func _run(parent: Node2D, units_layer: Node2D,
		rng: RandomNumberGenerator) -> Dictionary:
	_rng = rng

	# 1. Town Centres
	var tc0: Vector2 = _random_tc_pos()
	var tc1: Vector2 = -tc0
	_register(tc0, R_TC)
	_register(tc1, R_TC)

	# 2. Units (fixed offsets from TC — registered so resources stay clear)
	_register_unit_cluster(tc0)
	_register_unit_cluster(tc1)

	# 3. Animals
	_spawn_animals(units_layer, tc0, tc1)

	# 4. Resources
	_spawn_player_resources(parent, tc0, 0.0)
	_spawn_player_resources(parent, tc1, PI)
	_spawn_neutral_resources(parent)

	return {"tc0": tc0, "tc1": tc1}

# ── Registry helpers ────────────────────────────────────────────────────────

func _register(pos: Vector2, radius: float) -> void:
	_placed.append({"pos": pos, "radius": radius})

func _is_free(pos: Vector2, radius: float) -> bool:
	for entry: Dictionary in _placed:
		var min_dist: float = radius + (entry["radius"] as float)
		if pos.distance_to(entry["pos"] as Vector2) < min_dist:
			return false
	return true

# Try up to MAX_PLACE_TRIES random positions around center in [dist_min,dist_max].
# Returns Vector2.INF if no free spot found.
func _find_free_arc(center: Vector2, dist_min: float, dist_max: float,
		obj_radius: float, angle_hint: float = -1.0) -> Vector2:
	for _i: int in range(MAX_PLACE_TRIES):
		var angle: float = _rng.randf() * TAU if angle_hint < 0.0 \
				else angle_hint + _rng.randf_range(-0.8, 0.8)
		var dist: float = _rng.randf_range(dist_min, dist_max)
		var pos: Vector2 = _clamp_map(center + Vector2(cos(angle), sin(angle)) * dist)
		if _is_free(pos, obj_radius):
			return pos
	return Vector2.INF

# Try up to MAX_PLACE_TRIES random positions inside a circle of given radius.
func _find_free_near(center: Vector2, zone_radius: float,
		obj_radius: float) -> Vector2:
	for _i: int in range(MAX_PLACE_TRIES):
		var angle: float = _rng.randf() * TAU
		var dist: float  = _rng.randf_range(0.0, zone_radius) * _rng.randf_range(0.4, 1.0)
		var pos: Vector2 = _clamp_map(center + Vector2(cos(angle), sin(angle)) * dist)
		if _is_free(pos, obj_radius):
			return pos
	return Vector2.INF

func _clamp_map(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -_map_half, _map_half), clampf(p.y, -_map_half, _map_half))

# ── TC placement ────────────────────────────────────────────────────────────

func _random_tc_pos() -> Vector2:
	return Vector2(
		_rng.randf_range(-_map_half * 0.55, -_map_half * 0.25),
		_rng.randf_range(-_map_half * 0.40,  _map_half * 0.40))

# Register the starting unit footprint around a TC so resources keep clear.
func _register_unit_cluster(tc: Vector2) -> void:
	var offsets: Array[Vector2] = [
		Vector2(-40, 60), Vector2(0, 60), Vector2(40, 60),  # 3 villagers
		Vector2(80, -60),                                    # scout
	]
	for off: Vector2 in offsets:
		_register(tc + off, R_UNIT)

# ── Animals ─────────────────────────────────────────────────────────────────

func _spawn_animals(units_layer: Node2D, tc0: Vector2, tc1: Vector2) -> void:
	var deer_scene:  PackedScene = load(ANIMAL_SCENE) as PackedScene
	var sheep_scene: PackedScene = load(SHEEP_SCENE)  as PackedScene

	# 4 sheep near each TC
	for tc: Vector2 in [tc0, tc1]:
		var placed: int = 0
		for _attempt: int in range(MAX_PLACE_TRIES * 4):
			if placed >= 4:
				break
			var pos: Vector2 = _find_free_arc(tc, 180.0, 340.0, R_ANIMAL)
			if pos == Vector2.INF:
				break
			_register(pos, R_ANIMAL)
			_place_animal(sheep_scene, units_layer, pos, true)
			placed += 1

	# 8 deer scattered
	var placed_deer: int = 0
	for _attempt: int in range(MAX_PLACE_TRIES * 8):
		if placed_deer >= 8:
			break
		var pos: Vector2 = Vector2(
			_rng.randf_range(-_map_half * 0.85, _map_half * 0.85),
			_rng.randf_range(-_map_half * 0.85, _map_half * 0.85))
		if pos.distance_to(tc0) < 300.0 or pos.distance_to(tc1) < 300.0:
			continue
		if not _is_free(pos, R_ANIMAL):
			continue
		_register(pos, R_ANIMAL)
		_place_animal(deer_scene, units_layer, pos, false)
		placed_deer += 1

func _place_animal(scene: PackedScene, units_layer: Node2D,
		pos: Vector2, is_sheep: bool) -> void:
	var animal: Node2D = scene.instantiate() as Node2D
	units_layer.add_child(animal)
	animal.global_position = pos
	if is_sheep:
		animal.set("max_health", 8.0)
		animal.set("health", 8.0)
	else:
		var hp: float = _rng.randf_range(30.0, 50.0)
		animal.set("max_health", hp)
		animal.set("health", hp)

# ── Resources ────────────────────────────────────────────────────────────────

func _spawn_player_resources(parent: Node2D, tc: Vector2,
		angle_offset: float) -> void:
	var gold_angle:  float = _rng.randf_range(0.0, TAU)
	var stone_angle: float = gold_angle + _rng.randf_range(PI * 0.55, PI * 0.85)

	var gc: int = roundi(5.0 * _res_mult)
	var sc: int = roundi(5.0 * _res_mult)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.GOLD,
		gc, 160.0 * _res_mult, gold_angle + angle_offset, 320.0, 480.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.STONE,
		sc, 180.0 * _res_mult, stone_angle + angle_offset, 360.0, 530.0)

	var forest_base: float = _rng.randf_range(0.0, TAU)
	for i: int in range(3):
		var fangle: float = forest_base + (TAU / 3.0) * float(i) \
				+ _rng.randf_range(-0.3, 0.3) + angle_offset
		var fdist:  float = _rng.randf_range(200.0, 420.0)
		var fcenter: Vector2 = _clamp_map(tc + Vector2(cos(fangle), sin(fangle)) * fdist)
		_spawn_forest_zone(parent, fcenter, roundi(_rng.randf_range(12.0, 16.0) * _res_mult), 180.0 * _res_mult, 70.0)

	var food_angle: float = _rng.randf_range(0.0, TAU) + angle_offset
	var fc: int = roundi(3.0 * _res_mult)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		fc, 110.0 * _res_mult, food_angle,            160.0, 280.0)
	_spawn_deposit(parent, tc, ResourceNode.ResourceType.FOOD_HUNT,
		fc, 110.0 * _res_mult, food_angle + PI * 0.6, 180.0, 300.0)

func _spawn_neutral_resources(parent: Node2D) -> void:
	var base_angle: float = _rng.randf_range(0.0, TAU)
	var ngc: int = roundi(6.0 * _res_mult)
	var nsc: int = roundi(5.0 * _res_mult)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		ngc, 200.0 * _res_mult, base_angle,            400.0, 700.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		ngc, 200.0 * _res_mult, base_angle + PI,       400.0, 700.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		nsc, 200.0 * _res_mult, base_angle + PI * 0.5, 450.0, 720.0)
	_spawn_deposit(parent, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		nsc, 200.0 * _res_mult, base_angle + PI * 1.5, 450.0, 720.0)
	var fangle: float = _rng.randf_range(0.0, TAU)
	_spawn_forest_zone(parent,
		_clamp_map(Vector2(cos(fangle),       sin(fangle))       * _rng.randf_range(300.0, 600.0)),
		roundi(18.0 * _res_mult), 200.0 * _res_mult, 90.0)
	_spawn_forest_zone(parent,
		_clamp_map(Vector2(cos(fangle + PI),  sin(fangle + PI))  * _rng.randf_range(300.0, 600.0)),
		roundi(18.0 * _res_mult), 200.0 * _res_mult, 90.0)

func _spawn_deposit(parent: Node2D, center: Vector2,
		rtype: ResourceNode.ResourceType, count: int, amount: float,
		anchor_angle: float, dist_min: float, dist_max: float) -> void:
	var obj_radius: float = R_RES_WOOD if rtype == ResourceNode.ResourceType.WOOD else R_RES_OTHER
	var deposit_center: Vector2 = _find_free_arc(center, dist_min, dist_max,
			obj_radius, anchor_angle)
	if deposit_center == Vector2.INF:
		return
	# Place the first node at deposit_center
	_register(deposit_center, obj_radius)
	_create_resource_node(parent, deposit_center, rtype,
		amount * _rng.randf_range(0.85, 1.15))
	# Place remaining nodes clustered around deposit_center
	var placed: int = 1
	for _i: int in range(MAX_PLACE_TRIES * count):
		if placed >= count:
			break
		var pos: Vector2 = _find_free_near(deposit_center, 90.0, obj_radius)
		if pos == Vector2.INF:
			break
		_register(pos, obj_radius)
		_create_resource_node(parent, pos, rtype,
			amount * _rng.randf_range(0.85, 1.15))
		placed += 1

func _spawn_forest_zone(parent: Node2D, zone_center: Vector2,
		count: int, amount: float, zone_radius: float) -> void:
	for _i: int in range(MAX_PLACE_TRIES * count):
		if count <= 0:
			break
		var pos: Vector2 = _find_free_near(zone_center, zone_radius, R_RES_WOOD)
		if pos == Vector2.INF:
			continue
		_register(pos, R_RES_WOOD)
		_create_resource_node(parent, pos, ResourceNode.ResourceType.WOOD,
			amount * _rng.randf_range(0.8, 1.2))
		count -= 1

# ── Resource node factory ────────────────────────────────────────────────────

func _create_resource_node(parent: Node2D, pos: Vector2,
		rtype: ResourceNode.ResourceType, amount: float) -> void:
	var node: Node2D = Node2D.new()
	node.set_script(load("res://scripts/economy/resource_node.gd"))
	node.set("resource_type", rtype)
	node.set("initial_amount", amount)
	parent.add_child(node)
	node.global_position = pos

	var is_wood: bool = rtype == ResourceNode.ResourceType.WOOD
	var w: float = (12.0 if not is_wood else 16.0) + _rng.randf_range(-2.0, 4.0)
	var h: float = (w if not is_wood else w * 1.6) + _rng.randf_range(0.0, 6.0)

	var rect: ColorRect = ColorRect.new()
	rect.color = RES_COLORS.get(rtype, Color(1, 1, 1)) as Color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.offset_left   = -w
	rect.offset_top    = -h
	rect.offset_right  =  w
	rect.offset_bottom =  w * 0.4
	node.add_child(rect)

	if not is_wood:
		var label: Label = Label.new()
		label.text = RES_LABELS.get(rtype, "") as String
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.offset_left   = -20.0
		label.offset_top    = -h - 14.0
		label.offset_right  =  20.0
		label.offset_bottom = -h - 2.0
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		node.add_child(label)

	var area: Area2D = Area2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = w + 4.0
	shape.shape = circle
	area.add_child(shape)
	node.add_child(area)

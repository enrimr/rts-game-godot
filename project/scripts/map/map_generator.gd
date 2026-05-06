class_name MapGenerator

## Generates a symmetric random map for two players.
## Each player gets an identical resource layout, rotated 180° around center.

const MAP_HALF: float = 1800.0

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

static func generate(parent: Node2D, units_layer: Node2D, rng: RandomNumberGenerator) -> Dictionary:
	var tc0_pos: Vector2 = _random_tc_pos(rng)
	var tc1_pos: Vector2 = -tc0_pos

	_spawn_player_resources(parent, rng, tc0_pos, 0.0)
	_spawn_player_resources(parent, rng, tc1_pos, PI)

	_spawn_neutral_resources(parent, rng)

	_spawn_animals(units_layer, rng, tc0_pos, tc1_pos)

	return {"tc0": tc0_pos, "tc1": tc1_pos}

static func _random_tc_pos(rng: RandomNumberGenerator) -> Vector2:
	var x: float = rng.randf_range(-MAP_HALF * 0.55, -MAP_HALF * 0.25)
	var y: float = rng.randf_range(-MAP_HALF * 0.40,  MAP_HALF * 0.40)
	return Vector2(x, y)

static func _spawn_player_resources(parent: Node2D, rng: RandomNumberGenerator, tc: Vector2, angle_offset: float) -> void:
	# Gold and stone get dedicated anchor angles, kept well apart from each other.
	var gold_angle:  float = rng.randf_range(0.0, TAU)
	var stone_angle: float = gold_angle + rng.randf_range(PI * 0.55, PI * 0.85)

	# --- Gold deposit: tight cluster, moderate distance ---
	_spawn_deposit(parent, rng, tc, ResourceNode.ResourceType.GOLD,
		5, 160.0, gold_angle + angle_offset, 320.0, 480.0, 55.0)

	# --- Stone deposit: tight cluster, separate angle, slightly further ---
	_spawn_deposit(parent, rng, tc, ResourceNode.ResourceType.STONE,
		5, 180.0, stone_angle + angle_offset, 360.0, 530.0, 55.0)

	# --- Forest zones: 3 separate patches, lush and dense ---
	var forest_base_angle: float = rng.randf_range(0.0, TAU)
	for i: int in range(3):
		var fangle: float = forest_base_angle + (TAU / 3.0) * float(i) + rng.randf_range(-0.3, 0.3) + angle_offset
		var fdist:  float = rng.randf_range(200.0, 420.0)
		var fcenter: Vector2 = _offset(tc, fangle, fdist)
		# 12–16 trees per forest zone, packed within a small radius
		var tree_count: int = rng.randi_range(12, 16)
		_spawn_forest_zone(parent, rng, fcenter, tree_count, 180.0, 70.0)

	# --- Food (hunt): two small groups near TC ---
	var food_angle: float = rng.randf_range(0.0, TAU) + angle_offset
	_spawn_deposit(parent, rng, tc, ResourceNode.ResourceType.FOOD_HUNT,
		3, 110.0, food_angle,              160.0, 280.0, 60.0)
	_spawn_deposit(parent, rng, tc, ResourceNode.ResourceType.FOOD_HUNT,
		3, 110.0, food_angle + PI * 0.6,  180.0, 300.0, 60.0)

static func _spawn_neutral_resources(parent: Node2D, rng: RandomNumberGenerator) -> void:
	# Two gold and two stone deposits equidistant from center, well separated.
	var base_angle: float = rng.randf_range(0.0, TAU)
	_spawn_deposit(parent, rng, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		6, 200.0, base_angle,            400.0, 700.0, 65.0)
	_spawn_deposit(parent, rng, Vector2.ZERO, ResourceNode.ResourceType.GOLD,
		6, 200.0, base_angle + PI,       400.0, 700.0, 65.0)
	_spawn_deposit(parent, rng, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		5, 200.0, base_angle + PI * 0.5, 450.0, 720.0, 60.0)
	_spawn_deposit(parent, rng, Vector2.ZERO, ResourceNode.ResourceType.STONE,
		5, 200.0, base_angle + PI * 1.5, 450.0, 720.0, 60.0)
	# Large central forest
	var fangle: float = rng.randf_range(0.0, TAU)
	_spawn_forest_zone(parent, rng, _offset(Vector2.ZERO, fangle,        rng.randf_range(300.0, 600.0)), 18, 200.0, 90.0)
	_spawn_forest_zone(parent, rng, _offset(Vector2.ZERO, fangle + PI,   rng.randf_range(300.0, 600.0)), 18, 200.0, 90.0)

# Places a tight deposit of a single resource type around an anchor direction.
static func _spawn_deposit(
		parent: Node2D, rng: RandomNumberGenerator,
		center: Vector2, rtype: ResourceNode.ResourceType,
		count: int, amount: float,
		anchor_angle: float, dist_min: float, dist_max: float,
		jitter: float) -> void:

	var dist: float = rng.randf_range(dist_min, dist_max)
	var deposit_center: Vector2 = _offset(center, anchor_angle, dist)

	for _i: int in range(count):
		var jx: float = rng.randf_range(-jitter, jitter)
		var jy: float = rng.randf_range(-jitter, jitter)
		var pos: Vector2 = deposit_center + Vector2(jx, jy)
		pos.x = clampf(pos.x, -MAP_HALF, MAP_HALF)
		pos.y = clampf(pos.y, -MAP_HALF, MAP_HALF)
		_create_resource_node(parent, rng, pos, rtype, amount * rng.randf_range(0.85, 1.15))

# Places a dense forest patch: trees scattered within zone_radius of zone_center.
static func _spawn_forest_zone(
		parent: Node2D, rng: RandomNumberGenerator,
		zone_center: Vector2, count: int,
		amount: float, zone_radius: float) -> void:

	for _i: int in range(count):
		var angle: float = rng.randf() * TAU
		# Bias toward the center so the forest feels dense in the middle
		var dist: float = rng.randf_range(0.0, zone_radius) * rng.randf_range(0.4, 1.0)
		var pos: Vector2 = zone_center + Vector2(cos(angle), sin(angle)) * dist
		pos.x = clampf(pos.x, -MAP_HALF, MAP_HALF)
		pos.y = clampf(pos.y, -MAP_HALF, MAP_HALF)
		_create_resource_node(parent, rng, pos, ResourceNode.ResourceType.WOOD,
			amount * rng.randf_range(0.8, 1.2))

const ANIMAL_SCENE: String = "res://scenes/units/animal.tscn"

static func _spawn_animals(units_layer: Node2D, rng: RandomNumberGenerator,
		tc0: Vector2, tc1: Vector2) -> void:
	var scene: PackedScene = load(ANIMAL_SCENE) as PackedScene
	# 4 deer near each TC start (lurable food source close to home)
	for tc: Vector2 in [tc0, tc1]:
		for _i: int in range(4):
			var angle: float = rng.randf() * TAU
			var dist: float  = rng.randf_range(250.0, 450.0)
			_place_animal(scene, units_layer, tc + Vector2(cos(angle), sin(angle)) * dist, rng)
	# 10 deer scattered across the rest of the map
	for _i: int in range(10):
		var pos: Vector2 = Vector2(
			rng.randf_range(-MAP_HALF * 0.85, MAP_HALF * 0.85),
			rng.randf_range(-MAP_HALF * 0.85, MAP_HALF * 0.85))
		# Keep away from TC starts
		if pos.distance_to(tc0) > 300.0 and pos.distance_to(tc1) > 300.0:
			_place_animal(scene, units_layer, pos, rng)

static func _place_animal(scene: PackedScene, units_layer: Node2D, pos: Vector2,
		rng: RandomNumberGenerator) -> void:
	var animal: Node2D = scene.instantiate() as Node2D
	units_layer.add_child(animal)
	animal.global_position = pos
	# Small random health variation
	var hp: float = rng.randf_range(30.0, 50.0)
	animal.set("max_health", hp)
	animal.set("health", hp)

static func _offset(origin: Vector2, angle: float, dist: float) -> Vector2:
	return origin + Vector2(cos(angle), sin(angle)) * dist

static func _create_resource_node(
		parent: Node2D, rng: RandomNumberGenerator,
		pos: Vector2, rtype: ResourceNode.ResourceType, amount: float) -> void:

	var node: Node2D = Node2D.new()
	node.set_script(load("res://scripts/economy/resource_node.gd"))
	node.set("resource_type", rtype)
	node.set("initial_amount", amount)
	parent.add_child(node)
	node.global_position = pos

	var is_wood: bool = rtype == ResourceNode.ResourceType.WOOD
	# Trees are taller and wider than other resources
	var w: float = (12.0 if not is_wood else 16.0) + rng.randf_range(-2.0, 4.0)
	var h: float = (w if not is_wood else w * 1.6) + rng.randf_range(0.0, 6.0)

	var rect: ColorRect = ColorRect.new()
	rect.color = RES_COLORS.get(rtype, Color(1, 1, 1)) as Color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.offset_left   = -w
	rect.offset_top    = -h
	rect.offset_right  =  w
	rect.offset_bottom =  w * 0.4
	node.add_child(rect)

	# Only show label for non-wood nodes to reduce clutter in dense forests
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

class_name MapGenerator

## Generates a symmetric random map for two players.
## Each player gets an identical resource layout, rotated 180° around the
## map center so both starts are fair.

const MAP_HALF: float = 1800.0   # usable radius from center

# Visual colors per resource type
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

# Resource pack spawned near each Town Center.
# Each entry: [type, count, amount_per_node, radius_min, radius_max]
const RESOURCE_PACK: Array = [
	[ResourceNode.ResourceType.WOOD,      8, 200.0, 180.0, 380.0],
	[ResourceNode.ResourceType.GOLD,      3, 150.0, 220.0, 380.0],
	[ResourceNode.ResourceType.STONE,     3, 180.0, 220.0, 380.0],
	[ResourceNode.ResourceType.FOOD_HUNT, 4, 120.0, 160.0, 320.0],
]

# Neutral shared resources near the center of the map.
const NEUTRAL_PACK: Array = [
	[ResourceNode.ResourceType.GOLD,  4, 200.0],
	[ResourceNode.ResourceType.STONE, 4, 220.0],
	[ResourceNode.ResourceType.WOOD,  6, 200.0],
]

static func generate(parent: Node2D, rng: RandomNumberGenerator) -> Dictionary:
	# Pick TC positions: two opposite quadrants, random within bounds
	var tc0_pos: Vector2 = _random_tc_pos(rng, -1.0)
	var tc1_pos: Vector2 = -tc0_pos   # symmetric

	# Spawn resources for each player around their TC
	_spawn_player_resources(parent, rng, tc0_pos)
	_spawn_player_resources(parent, rng, tc1_pos)

	# Neutral resources near the center
	_spawn_neutral_resources(parent, rng)

	return {"tc0": tc0_pos, "tc1": tc1_pos}

static func _random_tc_pos(rng: RandomNumberGenerator, side: float) -> Vector2:
	# Place TC in the left-ish half, far enough from the edge
	var x: float = rng.randf_range(-MAP_HALF * 0.55, -MAP_HALF * 0.25) * side
	var y: float = rng.randf_range(-MAP_HALF * 0.45,  MAP_HALF * 0.45)
	return Vector2(x, y)

static func _spawn_player_resources(parent: Node2D, rng: RandomNumberGenerator, tc_pos: Vector2) -> void:
	for entry: Variant in RESOURCE_PACK:
		var arr: Array = entry as Array
		var rtype: ResourceNode.ResourceType = arr[0] as ResourceNode.ResourceType
		var count: int  = arr[1] as int
		var amount: float = arr[2] as float
		var rmin: float  = arr[3] as float
		var rmax: float  = arr[4] as float
		_spawn_cluster(parent, rng, tc_pos, rtype, count, amount, rmin, rmax)

static func _spawn_neutral_resources(parent: Node2D, rng: RandomNumberGenerator) -> void:
	for entry: Variant in NEUTRAL_PACK:
		var arr: Array = entry as Array
		var rtype: ResourceNode.ResourceType = arr[0] as ResourceNode.ResourceType
		var count: int   = arr[1] as int
		var amount: float = arr[2] as float
		_spawn_cluster(parent, rng, Vector2.ZERO, rtype, count, amount, 200.0, 600.0)

static func _spawn_cluster(
		parent: Node2D,
		rng: RandomNumberGenerator,
		center: Vector2,
		rtype: ResourceNode.ResourceType,
		count: int,
		amount: float,
		radius_min: float,
		radius_max: float) -> void:

	# Pick a random anchor angle for the whole cluster, then spread nodes around it.
	var anchor_angle: float = rng.randf() * TAU
	var spread: float = PI * 0.35  # ±~63° around anchor

	for i: int in range(count):
		var angle: float = anchor_angle + rng.randf_range(-spread, spread)
		var dist: float  = rng.randf_range(radius_min, radius_max)
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist
		pos.x = clampf(pos.x, -MAP_HALF, MAP_HALF)
		pos.y = clampf(pos.y, -MAP_HALF, MAP_HALF)
		var node_amount: float = amount * rng.randf_range(0.8, 1.2)
		_create_resource_node(parent, rng, pos, rtype, node_amount)

static func _create_resource_node(
		parent: Node2D,
		rng: RandomNumberGenerator,
		pos: Vector2,
		rtype: ResourceNode.ResourceType,
		amount: float) -> void:

	var node: Node2D = Node2D.new()
	node.set_script(load("res://scripts/economy/resource_node.gd"))
	node.set("resource_type", rtype)
	node.set("initial_amount", amount)
	parent.add_child(node)
	node.global_position = pos

	# Visual rect — size varies a bit per node for a natural look
	var base_size: float = 14.0 + rng.randf_range(-2.0, 4.0)
	var rect: ColorRect = ColorRect.new()
	rect.color = RES_COLORS.get(rtype, Color(1, 1, 1)) as Color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.offset_left   = -base_size
	rect.offset_top    = -base_size
	rect.offset_right  =  base_size
	rect.offset_bottom =  base_size * 0.6
	node.add_child(rect)

	var label: Label = Label.new()
	label.text = RES_LABELS.get(rtype, "") as String
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.offset_left   = -20.0
	label.offset_top    = -base_size - 14.0
	label.offset_right  =  20.0
	label.offset_bottom = -base_size - 2.0
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	node.add_child(label)

	# Collision for click detection
	var area: Area2D = Area2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = base_size + 4.0
	shape.shape = circle
	area.add_child(shape)
	node.add_child(area)

extends Node2D

class_name ResourceNode

enum ResourceType { WOOD, GOLD, STONE, FOOD_HUNT, FOOD_FISH, FOOD_BERRY, OLIVINA }

const RESOURCE_NAMES: Dictionary = {
	ResourceType.WOOD:       "wood",
	ResourceType.GOLD:       "gold",
	ResourceType.STONE:      "stone",
	ResourceType.FOOD_HUNT:  "food",
	ResourceType.FOOD_FISH:  "food",
	ResourceType.FOOD_BERRY: "food",
	ResourceType.OLIVINA:    "olivina",
}

@export var resource_type: ResourceType = ResourceType.WOOD
@export var initial_amount: float = 100.0

var remaining_amount: float = 0.0
var _selection_ring: Node2D = null
var _being_gathered: bool = false
var _visual_scale: float = 1.0

signal depleted(node: Node)

func _ready() -> void:
	remaining_amount = initial_amount
	add_to_group("resource_nodes")
	ResourceManager.register_node(self)
	_setup_nav_obstacle()

func _setup_nav_obstacle() -> void:
	var obs: NavigationObstacle2D = NavigationObstacle2D.new()
	# RVO radius: wide enough for units to start steering around resource nodes early
	obs.vertices = PackedVector2Array([
		Vector2(-20.0, -20.0), Vector2(20.0, -20.0),
		Vector2(20.0,  20.0), Vector2(-20.0,  20.0),
	])
	obs.avoidance_enabled = true
	obs.affect_navigation_mesh = false
	add_child(obs)

func get_nav_obstacle_polygon() -> PackedVector2Array:
	# Bake footprint: tight so gatherers can still reach the node edge
	const H: float = 14.0
	return PackedVector2Array([
		global_position + Vector2(-H, -H),
		global_position + Vector2( H, -H),
		global_position + Vector2( H,  H),
		global_position + Vector2(-H,  H),
	])

func set_selected(value: bool) -> void:
	if value:
		if not is_instance_valid(_selection_ring):
			_selection_ring = Node2D.new()
			_selection_ring.set_meta(IsoBillboard.META_GROUND, true)
			var line: Line2D = Line2D.new()
			line.default_color = Color(1.0, 0.85, 0.2, 0.85)
			line.width = 1.5
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in range(17):
				var a: float = i * TAU / 16.0
				pts.append(Vector2(cos(a), sin(a)) * 18.0)
			line.points = pts
			_selection_ring.add_child(line)
			add_child(_selection_ring)
		_selection_ring.visible = true
	else:
		if is_instance_valid(_selection_ring):
			_selection_ring.visible = false

func get_resource_name() -> String:
	return RESOURCE_NAMES.get(resource_type, "food") as String

func set_being_gathered(value: bool) -> void:
	if resource_type != ResourceType.WOOD:
		return
	if _being_gathered or not value:
		return
	_being_gathered = true
	for child: Node in get_children():
		if child is Polygon2D:
			child.queue_free()
	MapGenerator._draw_tree_stump(self, _visual_scale)
	IsoBillboard.setup_drawn_node(self)

func gather(amount: float) -> float:
	var gathered: float = minf(amount, remaining_amount)
	remaining_amount -= gathered
	if remaining_amount <= 0.0:
		depleted.emit(self)
		queue_free()
	return gathered

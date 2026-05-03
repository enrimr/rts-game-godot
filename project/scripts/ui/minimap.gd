extends Control

class_name MinimapRenderer

const WORLD_MIN: Vector2 = Vector2(-2000.0, -2000.0)
const WORLD_SIZE: float = 4000.0

const COLOR_BG:               Color = Color(0.08, 0.18, 0.08, 1.0)
const COLOR_BORDER:           Color = Color(0.0,  0.0,  0.0,  1.0)
const COLOR_UNIT_FRIENDLY:    Color = Color(0.3,  0.75, 1.0,  1.0)
const COLOR_RESOURCE_WOOD:    Color = Color(0.15, 0.65, 0.15, 1.0)
const COLOR_RESOURCE_GOLD:    Color = Color(0.95, 0.8,  0.1,  1.0)
const COLOR_RESOURCE_STONE:   Color = Color(0.75, 0.75, 0.75, 1.0)
const COLOR_BUILDING:         Color = Color(0.7,  0.5,  0.2,  1.0)
const COLOR_CAMERA_RECT:      Color = Color(1.0,  1.0,  1.0,  0.75)
const COLOR_GRID:             Color = Color(1.0,  1.0,  1.0,  0.06)

var world_node: Node2D = null
var camera_node: Camera2D = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var ms: Vector2 = size

	draw_rect(Rect2(Vector2.ZERO, ms), COLOR_BG)

	# Subtle grid lines every 25% of the map
	for i: int in range(1, 4):
		var t: float = float(i) * 0.25
		draw_line(Vector2(ms.x * t, 0.0), Vector2(ms.x * t, ms.y), COLOR_GRID, 1.0)
		draw_line(Vector2(0.0, ms.y * t), Vector2(ms.x, ms.y * t), COLOR_GRID, 1.0)

	if world_node == null:
		draw_rect(Rect2(Vector2.ZERO, ms), COLOR_BORDER, false, 1.5)
		return

	# Resources
	for child: Node in world_node.get_children():
		if child is ResourceNode:
			var rn: ResourceNode = child as ResourceNode
			var mp: Vector2 = _to_mm(rn.global_position, ms)
			draw_rect(Rect2(mp - Vector2(2.5, 2.5), Vector2(5.0, 5.0)),
				_resource_color(rn.resource_type))

	# Drop-off buildings (Town Center etc.)
	for child: Node in world_node.get_children():
		if child is DropOffBuilding:
			var mp: Vector2 = _to_mm((child as Node2D).global_position, ms)
			draw_rect(Rect2(mp - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), COLOR_BUILDING)

	# Units
	var units_layer: Node = world_node.get_node_or_null("UnitsLayer")
	if units_layer != null:
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			var mp: Vector2 = _to_mm((unit as Node2D).global_position, ms)
			draw_circle(mp, 3.0, COLOR_UNIT_FRIENDLY)

	# Camera viewport rectangle
	if camera_node != null:
		var vp_world: Vector2 = get_viewport().get_visible_rect().size / camera_node.zoom
		var cam_pos: Vector2 = camera_node.global_position
		var r_min: Vector2 = _to_mm(cam_pos - vp_world * 0.5, ms)
		var r_max: Vector2 = _to_mm(cam_pos + vp_world * 0.5, ms)
		draw_rect(Rect2(r_min, r_max - r_min), COLOR_CAMERA_RECT, false, 1.5)

	draw_rect(Rect2(Vector2.ZERO, ms), COLOR_BORDER, false, 1.5)

# Click on minimap → move camera to that world position
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_move_camera_to(mb.position)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_camera_to(mm.position)

func _move_camera_to(minimap_pos: Vector2) -> void:
	if camera_node == null:
		return
	camera_node.global_position = _to_world(minimap_pos, size)

# --- Coordinate helpers ---

func _to_mm(world_pos: Vector2, ms: Vector2) -> Vector2:
	return (world_pos - WORLD_MIN) / WORLD_SIZE * ms

func _to_world(mm_pos: Vector2, ms: Vector2) -> Vector2:
	return mm_pos / ms * WORLD_SIZE + WORLD_MIN

func _resource_color(rtype: ResourceNode.ResourceType) -> Color:
	match rtype:
		ResourceNode.ResourceType.GOLD:
			return COLOR_RESOURCE_GOLD
		ResourceNode.ResourceType.STONE:
			return COLOR_RESOURCE_STONE
		_:
			return COLOR_RESOURCE_WOOD

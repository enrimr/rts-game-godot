extends Node2D

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const CAMERA_SPEED: float = 400.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
const CAMERA_ZOOM_STEP: float = 0.1
const UNIT_CLICK_RADIUS: float = 20.0

@onready var units_layer: Node2D = $UnitsLayer
@onready var camera: Camera2D = $Camera2D
@onready var drop_off: Node2D = $DropOffNode
@onready var hud: CanvasLayer = $HUD

var _selected_units: Array[Node] = []
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false

func _ready() -> void:
	ResourceManager.init_player(0)
	PopulationManager.init_player(0)

	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		units_layer.add_child(v)
		v.global_position = drop_off.global_position + Vector2(i * 40 - 40, 0.0)
		v.set("player_id", 0)
		EventBus.unit_spawned.emit(v, 0)

	hud.action_requested.connect(_on_action_requested)
	GameManager.start_game([{"id": 0}])

func _process(delta: float) -> void:
	_handle_camera(delta)

func _handle_camera(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("camera_pan_left"):  dir.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"): dir.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):    dir.y -= 1.0
	if Input.is_action_pressed("camera_pan_down"):  dir.y += 1.0
	camera.position += dir * CAMERA_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = mb.global_position
				_dragging = true
			else:
				if _dragging:
					_dragging = false
					_finish_selection(mb.global_position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(CAMERA_ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(-CAMERA_ZOOM_STEP)

func _zoom(step: float) -> void:
	camera.zoom = (camera.zoom + Vector2(step, step)).clamp(
		Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
		Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX))

# --- Selection ---

func _finish_selection(release_pos: Vector2) -> void:
	var world_start: Vector2 = _screen_to_world(_drag_start)
	var world_end: Vector2 = _screen_to_world(release_pos)
	var rect: Rect2 = Rect2(world_start, Vector2.ZERO).expand(world_end)

	for sel: Node in _selected_units:
		if is_instance_valid(sel):
			sel.set_selected(false)
	_selected_units.clear()

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var unit2d: Node2D = unit as Node2D
		var in_rect: bool = rect.get_area() >= 10.0 and rect.has_point(unit2d.global_position)
		var clicked: bool = rect.get_area() < 10.0 and world_start.distance_to(unit2d.global_position) < UNIT_CLICK_RADIUS
		if in_rect or clicked:
			unit.set_selected(true)
			_selected_units.append(unit)

	SelectionManager.select(_selected_units)

# --- Right-click: gather or move ---

func _handle_right_click(world_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return

	var resource_node: ResourceNode = _find_resource_at(world_pos)
	if resource_node != null:
		_order_gather_all(resource_node)
	else:
		_order_move_all(world_pos)

func _find_resource_at(world_pos: Vector2) -> ResourceNode:
	# Check all ResourceNode children of the world by proximity.
	for child: Node in get_children():
		if child is ResourceNode:
			var rn: ResourceNode = child as ResourceNode
			if world_pos.distance_to(rn.global_position) < 32.0:
				return rn
	return null

func _order_gather_all(resource_node: ResourceNode) -> void:
	var resource_name: String = resource_node.get_resource_name()
	for unit: Node in _selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("order_gather"):
			unit.order_gather(resource_node, resource_name, drop_off)

func _order_move_all(world_pos: Vector2) -> void:
	var count: int = _selected_units.size()
	for i: int in range(count):
		var unit: Node = _selected_units[i]
		if not is_instance_valid(unit):
			continue
		if unit.has_method("order_move"):
			# Spread units in a small grid so they don't pile up.
			var offset: Vector2 = Vector2(
				float(i % 4) * 30.0 - 45.0,
				float(i / 4) * 30.0
			)
			unit.order_move(world_pos + offset)

# --- HUD action buttons ---

func _on_action_requested(action_id: String) -> void:
	match action_id:
		"gather_wood":
			_order_gather_nearest_resource(ResourceNode.ResourceType.WOOD)
		"gather_gold":
			_order_gather_nearest_resource(ResourceNode.ResourceType.GOLD)
		"gather_stone":
			_order_gather_nearest_resource(ResourceNode.ResourceType.STONE)
		"gather_food":
			_order_gather_nearest_resource(ResourceNode.ResourceType.FOOD_HUNT)
		"stop":
			for unit: Node in _selected_units:
				if is_instance_valid(unit) and unit.has_method("order_move"):
					unit.order_move((unit as Node2D).global_position)

func _order_gather_nearest_resource(rtype: ResourceNode.ResourceType) -> void:
	if _selected_units.is_empty():
		return
	var pivot: Vector2 = (_selected_units[0] as Node2D).global_position
	var nearest: ResourceNode = _find_nearest_resource_of_type(rtype, pivot)
	if nearest == null:
		return
	var resource_name: String = nearest.get_resource_name()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(nearest, resource_name, drop_off)

func _find_nearest_resource_of_type(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for child: Node in get_children():
		if not (child is ResourceNode):
			continue
		var rn: ResourceNode = child as ResourceNode
		if rn.resource_type != rtype:
			continue
		var d: float = from.distance_to(rn.global_position)
		if d < best_dist:
			best_dist = d
			best = rn
	return best

# --- Helpers ---

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return camera.get_screen_center_position() + \
		(screen_pos - get_viewport().get_visible_rect().size * 0.5) / camera.zoom.x

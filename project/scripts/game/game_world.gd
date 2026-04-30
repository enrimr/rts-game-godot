extends Node2D

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const CAMERA_SPEED: float = 400.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
const CAMERA_ZOOM_STEP: float = 0.1

@onready var units_layer: Node2D = $UnitsLayer
@onready var camera: Camera2D = $Camera2D
@onready var drop_off: Node2D = $DropOffNode

var _selected_villagers: Array[Node] = []
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false

func _ready() -> void:
	ResourceManager.init_player(0)
	PopulationManager.init_player(0)

	# Spawn a few villagers around the drop-off point
	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		units_layer.add_child(v)
		v.global_position = drop_off.global_position + Vector2(i * 40 - 40, 0.0)
		v.player_id = 0
		EventBus.unit_spawned.emit(v, 0)

	GameManager.start_game([{"id": 0}])

func _process(delta: float) -> void:
	_handle_camera(delta)

func _handle_camera(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("camera_pan_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"):
		dir.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("camera_pan_down"):
		dir.y += 1.0
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
			_issue_move_order(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			camera.zoom = camera.zoom + Vector2(CAMERA_ZOOM_STEP, CAMERA_ZOOM_STEP)
			camera.zoom = camera.zoom.clamp(Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
				Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			camera.zoom = camera.zoom - Vector2(CAMERA_ZOOM_STEP, CAMERA_ZOOM_STEP)
			camera.zoom = camera.zoom.clamp(Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
				Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX))

func _finish_selection(release_pos: Vector2) -> void:
	var world_start: Vector2 = _screen_to_world(_drag_start)
	var world_end: Vector2 = _screen_to_world(release_pos)
	var rect: Rect2 = Rect2(world_start, Vector2.ZERO).expand(world_end)

	for sel: Node in _selected_villagers:
		if is_instance_valid(sel):
			sel.set_selected(false)
	_selected_villagers.clear()

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var unit2d: Node2D = unit as Node2D
		if rect.has_point(unit2d.global_position) or rect.get_area() < 10.0 and world_start.distance_to(unit2d.global_position) < 20.0:
			unit.set_selected(true)
			_selected_villagers.append(unit)

	SelectionManager.select(_selected_villagers)

func _issue_move_order(world_pos: Vector2) -> void:
	for unit: Node in _selected_villagers:
		if is_instance_valid(unit) and unit.has_method("order_move"):
			unit.order_move(world_pos)

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return camera.get_screen_center_position() + (screen_pos - get_viewport().get_visible_rect().size * 0.5) / camera.zoom.x

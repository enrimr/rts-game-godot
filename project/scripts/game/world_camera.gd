class_name WorldCamera extends RefCounted

## Camera control for the match: keyboard/edge-scroll panning, middle-mouse
## drag panning, zoom, selection follow, and the attack-alert camera jump.

const CAMERA_SPEED: float = 400.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
const CAMERA_ZOOM_STEP: float = 0.1
const EDGE_SCROLL_MARGIN: float = 60.0
const EDGE_SCROLL_DELAY: float = 0.3
const EDGE_SCROLL_MOUSE_THRESHOLD: float = 4.0  # px — movement above this resets the timer

var _world  # GameWorld — untyped so dynamic access works

var _following: bool = false
var _panning: bool = false
var _camera_moved_emitted: bool = false
# Recent "under attack" positions for the SPACE jump-to-last-event hotkey.
var _alert_ring: AlertRing = AlertRing.new()
var _edge_scroll_timer: float = 0.0
var _edge_scroll_last_mouse: Vector2 = Vector2.ZERO

func setup(world) -> void:
	_world = world

## Per-frame keyboard + edge-scroll panning; called from GameWorld._process.
func handle_camera(delta: float) -> void:
	# Keyboard input — immediate response
	# Use is_physical_key_pressed to bypass UI focus interception of arrow keys
	var key_dir: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):  key_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): key_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):    key_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):  key_dir.y += 1.0

	var edge_dir: Vector2 = Vector2.ZERO
	if GameSettings.edge_scroll_enabled:
		var vp: Vector2 = _world.get_viewport().get_visible_rect().size
		var mp: Vector2 = _world.get_viewport().get_mouse_position()
		if mp.x < EDGE_SCROLL_MARGIN:          edge_dir.x -= 1.0
		elif mp.x > vp.x - EDGE_SCROLL_MARGIN: edge_dir.x += 1.0
		if mp.y < EDGE_SCROLL_MARGIN:          edge_dir.y -= 1.0
		elif mp.y > vp.y - EDGE_SCROLL_MARGIN: edge_dir.y += 1.0

		if edge_dir != Vector2.ZERO:
			# Reset timer if the mouse is still moving — only count time while stationary in the margin
			if mp.distance_to(_edge_scroll_last_mouse) > EDGE_SCROLL_MOUSE_THRESHOLD:
				_edge_scroll_timer = 0.0
			else:
				_edge_scroll_timer += delta
		else:
			_edge_scroll_timer = 0.0
		_edge_scroll_last_mouse = mp

	var dir: Vector2 = key_dir
	if GameSettings.edge_scroll_enabled and _edge_scroll_timer >= EDGE_SCROLL_DELAY:
		dir += edge_dir

	if dir != Vector2.ZERO:
		if _following:
			_following = false
			EventBus.camera_follow_cancelled.emit()
		_world.camera.position += IsoProjection.screen_dir_to_world(dir) * CAMERA_SPEED * delta
		if not _camera_moved_emitted:
			_camera_moved_emitted = true
			EventBus.camera_moved.emit()
	var mh: float = TerrainManager.minimap_map_half
	_world.camera.position = _world.camera.position.clamp(Vector2(-mh, -mh), Vector2(mh, mh))

## Per-frame follow re-centre on the selection centroid; called from GameWorld._process.
func handle_follow() -> void:
	if not _following or _world._selected_units.is_empty():
		return
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit: Node in _world.live_selection():
		if is_instance_valid(unit):
			centroid += (unit as Node2D).global_position
			count += 1
	if count == 0:
		_following = false
		return
	_world.camera.position = centroid / float(count)

func toggle_follow() -> void:
	_following = not _following

## Stops follow WITHOUT emitting camera_follow_cancelled — used by handlers
## reacting to that very signal (emitting again would recurse).
func cancel_follow() -> void:
	_following = false

func is_panning() -> bool:
	return _panning

## Middle-mouse press/release; starting a pan drag breaks camera-follow.
func set_panning(pressed: bool) -> void:
	_panning = pressed
	if _panning and _following:
		_following = false
		EventBus.camera_follow_cancelled.emit()

## Applies a pan-drag mouse motion; routed from GameWorld._unhandled_input.
func apply_pan_motion(motion: InputEventMouseMotion) -> void:
	_world.camera.position -= IsoProjection.screen_delta_to_world(
		motion.relative, _world.camera.zoom)
	if not _camera_moved_emitted:
		_camera_moved_emitted = true
		EventBus.camera_moved.emit()

func reset_moved_flag() -> void:
	_camera_moved_emitted = false

func zoom(step: float) -> void:
	set_zoom(get_zoom() + step)

func get_zoom() -> float:
	return IsoProjection.user_zoom_from(_world.camera.zoom)

func set_zoom(value: float) -> void:
	_world.camera.zoom = IsoProjection.camera_zoom(
		clampf(value, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX))

## Instant camera jump used by alert hotkeys and clickable notifications.
## Cancels camera-follow so the per-frame re-centre does not undo the jump.
func jump_camera_to(world_pos: Vector2) -> void:
	_following = false
	EventBus.camera_follow_cancelled.emit()
	var mh: float = TerrainManager.minimap_map_half
	_world.camera.position = world_pos.clamp(Vector2(-mh, -mh), Vector2(mh, mh))

func record_alert(pos: Vector2) -> void:
	_alert_ring.record(pos)

func jump_to_last_alert() -> void:
	if not _alert_ring.has_entries():
		return
	jump_camera_to(_alert_ring.next_target(float(Time.get_ticks_msec()) / 1000.0))

func _on_unit_selected_follow(_units: Array) -> void:
	_following = false

func _on_building_destroyed_alert(building: Node, owner_id: int) -> void:
	if owner_id == NetworkSession.local_player_id and building is Node2D and is_instance_valid(building):
		_alert_ring.record((building as Node2D).global_position)

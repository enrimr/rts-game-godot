extends GutTest

## P4 — HUD/map integration under the camera-level isometric projection.
##
## Pins that:
##   1. The minimap camera-view indicator matches reality at several zooms:
##      each quad corner, mapped back to world, lands exactly on the matching
##      screen corner through the live camera transform (rotation + squash).
##   2. Right-clicking the minimap emits a move order at the correct world
##      spot, and move orders leave a visible flash on the minimap.
##   3. Navigating via the minimap (left click) moves the camera to the right
##      world point and cancels camera-follow so the jump is not undone.

const ISO := preload("res://scripts/utils/iso_projection.gd")

var _mm: MinimapRenderer
var _cam: Camera2D

func before_each() -> void:
	_mm = MinimapRenderer.new()
	_mm.size = Vector2(200.0, 200.0)
	add_child_autofree(_mm)
	_cam = autofree(Camera2D.new()) as Camera2D
	# The project enables 2D physics interpolation; the engine logs an override
	# notice for interpolated cameras, which GUT would flag as an error.
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cam)
	_mm.camera_node = _cam

# 1 — the view quad matches the real projection at several zooms
func test_camera_view_quad_matches_projection_at_several_zooms() -> void:
	_mm._refresh_world_bounds()
	var vp_half: Vector2 = _mm.get_viewport().get_visible_rect().size * 0.5
	var screen_corners: Array[Vector2] = [
		Vector2(-vp_half.x, -vp_half.y), Vector2(vp_half.x, -vp_half.y),
		vp_half, Vector2(-vp_half.x, vp_half.y),
	]
	for user_zoom: float in [0.5, 1.0, 2.0]:
		ISO.apply_to_camera(_cam, user_zoom)
		_cam.global_position = Vector2(300.0, -220.0)
		var quad: PackedVector2Array = _mm.camera_view_quad(_mm.size)
		assert_eq(quad.size(), 5, "closed polyline: first corner repeated last")
		assert_eq(quad[0], quad[4], "quad is closed")
		for i: int in range(4):
			var world_pt: Vector2 = _mm._to_world(quad[i], _mm.size)
			var screen_offset: Vector2 = ISO.world_to_screen(
				world_pt - _cam.global_position, user_zoom)
			assert_almost_eq(screen_offset.x, screen_corners[i].x, 0.5,
				"zoom %s corner %d x" % [user_zoom, i])
			assert_almost_eq(screen_offset.y, screen_corners[i].y, 0.5,
				"zoom %s corner %d y" % [user_zoom, i])

func test_camera_view_quad_empty_without_camera() -> void:
	_mm.camera_node = null
	assert_eq(_mm.camera_view_quad(_mm.size).size(), 0)

# 1b — the drawn indicator never leaves the widget, so it stays visible even
# when fully zoomed out (raw quad entirely outside the minimap rect)
func test_clamped_view_quad_stays_visible_when_zoomed_out() -> void:
	_mm._refresh_world_bounds()
	# Zoom derived from the live viewport so the view provably exceeds the
	# whole map regardless of the (tiny) headless test window size.
	var vp: Vector2 = _mm.get_viewport().get_visible_rect().size
	ISO.apply_to_camera(_cam, vp.x / (_mm._world_size * 10.0))
	_cam.global_position = Vector2.ZERO
	var raw: PackedVector2Array = _mm.camera_view_quad(_mm.size)
	var widget: Rect2 = Rect2(Vector2.ZERO, _mm.size)
	var all_outside: bool = true
	for i: int in range(4):
		if widget.has_point(raw[i]):
			all_outside = false
	assert_true(all_outside, "precondition: raw quad corners all off-widget")
	var clamped: PackedVector2Array = _mm.clamped_view_quad(_mm.size)
	assert_eq(clamped.size(), 5, "clamped quad stays a closed polyline")
	var inset: float = _mm.VIEW_QUAD_INSET
	var span: Rect2 = Rect2(clamped[0], Vector2.ZERO)
	for i: int in range(4):
		assert_true(widget.grow(-inset + 0.01).has_point(clamped[i]),
			"corner %d clamped inside the widget" % i)
		span = span.expand(clamped[i])
	assert_gt(span.size.x, _mm.size.x * 0.5, "outline spans the widget, not a dot")
	assert_gt(span.size.y, _mm.size.y * 0.5, "outline spans the widget, not a dot")

func test_clamped_view_quad_matches_raw_quad_when_inside() -> void:
	_mm._refresh_world_bounds()
	ISO.apply_to_camera(_cam, 4.0)    # zoomed in: view well inside the map
	_cam.global_position = Vector2.ZERO
	var raw: PackedVector2Array = _mm.camera_view_quad(_mm.size)
	var clamped: PackedVector2Array = _mm.clamped_view_quad(_mm.size)
	for i: int in range(raw.size()):
		assert_almost_eq(clamped[i].x, raw[i].x, 0.001, "corner %d unchanged" % i)
		assert_almost_eq(clamped[i].y, raw[i].y, 0.001, "corner %d unchanged" % i)

# 2 — right-click order lands at the right world spot and flashes
func test_right_click_emits_move_order_at_world_spot() -> void:
	_mm._refresh_world_bounds()
	watch_signals(EventBus)
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	mb.position = Vector2(150.0, 50.0)   # 75% across, 25% down the widget
	_mm._gui_input(mb)
	assert_signal_emitted(EventBus, "minimap_move_order")
	var params: Array = get_signal_parameters(EventBus, "minimap_move_order")
	var world_pos: Vector2 = params[0] as Vector2
	var mh: float = TerrainManager.minimap_map_half
	assert_almost_eq(world_pos.x, mh * 0.5, 0.01, "x = 75% of [-mh, mh]")
	assert_almost_eq(world_pos.y, -mh * 0.5, 0.01, "y = 25% of [-mh, mh]")

func test_move_order_leaves_visible_flash() -> void:
	EventBus.minimap_move_order.emit(Vector2(100.0, 100.0))
	assert_eq(_mm._flashes.size(), 1, "order leaves a visible flash")
	assert_eq(_mm._flashes[0]["world_pos"] as Vector2, Vector2(100.0, 100.0))

# 3 — minimap navigation moves the camera and cancels follow
func test_left_click_moves_camera_and_cancels_follow() -> void:
	_mm._refresh_world_bounds()
	watch_signals(EventBus)
	ISO.apply_to_camera(_cam, 1.0)
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = _mm.size * 0.5          # widget centre → world origin
	_mm._gui_input(mb)
	assert_signal_emitted(EventBus, "camera_follow_cancelled",
		"minimap navigation must defeat camera-follow")
	assert_almost_eq(_cam.global_position.x, 0.0, 0.01)
	assert_almost_eq(_cam.global_position.y, 0.0, 0.01)

extends GutTest

## Pins the pure maths of the camera-level isometric projection (piece P0).
##
## IsoProjection defines screen = Scale(zoom, zoom * Y_SQUASH) x Rotate(45deg)
## x world. Game logic stays cartesian; these tests guarantee the mapping,
## its inverse, and the screen-axis panning conversions stay consistent with
## what Godot's Camera2D produces from camera_rotation() + camera_zoom().

const ISO := preload("res://scripts/utils/iso_projection.gd")

const EPS: float = 0.0001

# --- projection shape ----------------------------------------------------------

func test_world_x_axis_maps_to_screen_down_right_diagonal() -> void:
	# +X in world reads as the "down-right" edge of the ground diamond.
	var s: Vector2 = ISO.world_to_screen(Vector2(100.0, 0.0))
	assert_almost_eq(s.x, 100.0 * cos(PI / 4.0), EPS)
	assert_almost_eq(s.y, 100.0 * sin(PI / 4.0) * 0.5, EPS, "Y is squashed to half")

func test_world_y_axis_maps_to_screen_down_left_diagonal() -> void:
	var s: Vector2 = ISO.world_to_screen(Vector2(0.0, 100.0))
	assert_almost_eq(s.x, -100.0 * sin(PI / 4.0), EPS)
	assert_almost_eq(s.y, 100.0 * cos(PI / 4.0) * 0.5, EPS)

func test_unit_square_becomes_two_to_one_diamond() -> void:
	# The classic iso check: a square's screen bounding box is twice as wide as tall.
	var corners: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(64.0, 0.0), Vector2(64.0, 64.0), Vector2(0.0, 64.0),
	]
	var min_p: Vector2 = Vector2(INF, INF)
	var max_p: Vector2 = Vector2(-INF, -INF)
	for c: Vector2 in corners:
		var s: Vector2 = ISO.world_to_screen(c)
		min_p = min_p.min(s)
		max_p = max_p.max(s)
	var size: Vector2 = max_p - min_p
	assert_almost_eq(size.x / size.y, 2.0, EPS, "diamond is 2:1 wide:tall")

# --- inverse -------------------------------------------------------------------

func test_screen_to_world_is_inverse_of_world_to_screen() -> void:
	var points: Array[Vector2] = [
		Vector2.ZERO, Vector2(123.4, -77.9), Vector2(-500.0, 250.0), Vector2(0.01, 800.0),
	]
	for zoom: float in [0.5, 1.0, 1.5, 2.0]:
		for p: Vector2 in points:
			var round_trip: Vector2 = ISO.screen_to_world(ISO.world_to_screen(p, zoom), zoom)
			assert_almost_eq(round_trip.x, p.x, EPS)
			assert_almost_eq(round_trip.y, p.y, EPS)

# --- camera composition --------------------------------------------------------

func test_matches_godot_camera_canvas_transform() -> void:
	# The pure mapping must equal what Camera2D produces: Godot's canvas
	# transform is Scale(zoom) * Rotate(-camera.rotation) * Translate(-position).
	for user_zoom: float in [0.5, 1.0, 2.0]:
		var xform: Transform2D = Transform2D(ISO.camera_rotation(), Vector2.ZERO).affine_inverse()
		var zoom: Vector2 = ISO.camera_zoom(user_zoom)
		var world_p: Vector2 = Vector2(320.0, -140.0)
		var screen_via_camera: Vector2 = (xform * world_p) * zoom
		var screen_via_helper: Vector2 = ISO.world_to_screen(world_p, user_zoom)
		assert_almost_eq(screen_via_camera.x, screen_via_helper.x, EPS)
		assert_almost_eq(screen_via_camera.y, screen_via_helper.y, EPS)

func test_camera_zoom_round_trip() -> void:
	assert_almost_eq(ISO.user_zoom_from(ISO.camera_zoom(1.5)), 1.5, EPS)
	assert_almost_eq(ISO.camera_zoom(2.0).y, 1.0, EPS, "Y squash halves the zoom")

func test_apply_to_camera_sets_rotation_and_composed_zoom() -> void:
	# Not added to the tree: in-tree cameras get force-switched to physics
	# interpolation here, which GUT flags as an unexpected engine error.
	var cam: Camera2D = autofree(Camera2D.new())
	ISO.apply_to_camera(cam, 1.5)
	assert_false(cam.ignore_rotation, "camera must honour rotation for the projection")
	assert_almost_eq(cam.rotation, -PI / 4.0, EPS)
	assert_almost_eq(cam.zoom.x, 1.5, EPS)
	assert_almost_eq(cam.zoom.y, 0.75, EPS)

# --- panning conversions -------------------------------------------------------

func test_screen_delta_to_world_keeps_content_under_cursor() -> void:
	# Dragging the mouse by `d` on screen must move the camera so the world
	# point under the cursor stays fixed: world_to_screen(delta) == d.
	var zoom: Vector2 = ISO.camera_zoom(1.5)
	var screen_delta: Vector2 = Vector2(37.0, -12.0)
	var world_delta: Vector2 = ISO.screen_delta_to_world(screen_delta, zoom)
	var back: Vector2 = ISO.world_to_screen(world_delta, 1.5)
	assert_almost_eq(back.x, screen_delta.x, EPS)
	assert_almost_eq(back.y, screen_delta.y, EPS)

func test_screen_dir_right_pans_view_straight_right_on_screen() -> void:
	# Pressing "right" must move the view right on SCREEN, i.e. along the
	# world +X/-Y diagonal (rotated back through -45deg, Y un-squashed).
	var dir: Vector2 = ISO.screen_dir_to_world(Vector2.RIGHT)
	assert_almost_eq(dir.length(), 1.0, EPS, "normalized")
	var on_screen: Vector2 = ISO.world_to_screen(dir)
	assert_gt(on_screen.x, 0.0)
	assert_almost_eq(on_screen.y, 0.0, EPS, "no vertical drift on screen")

func test_screen_dir_zero_is_zero() -> void:
	assert_eq(ISO.screen_dir_to_world(Vector2.ZERO), Vector2.ZERO)

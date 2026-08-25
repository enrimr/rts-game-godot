extends GutTest

## Pins the billboard counter-transform that stands entities upright on the
## isometrically projected ground (piece P0, critic gap: entities must not lie
## skewed flat with the terrain).
##
## Invariant: for any node processed by IsoBillboard.make_upright, projecting
## its transform through the camera (screen = Scale(1, Y_SQUASH) x Rotate(45deg))
## must reproduce EXACTLY the transform the artist authored — upright,
## unsquashed, anchored at the authored screen offset.

const ISO := preload("res://scripts/utils/iso_projection.gd")
const BB := preload("res://scripts/utils/iso_billboard.gd")

const EPS: float = 0.0001

## The camera's linear projection as a Transform2D (no translation).
func _projection() -> Transform2D:
	return Transform2D(ISO.WORLD_ROTATION, Vector2.ZERO).scaled(Vector2(1.0, ISO.Y_SQUASH))

func _assert_xform_almost_eq(actual: Transform2D, expected: Transform2D, msg: String = "") -> void:
	for i: int in range(3):
		assert_almost_eq(actual[i].x, expected[i].x, EPS, msg + " (column %d x)" % i)
		assert_almost_eq(actual[i].y, expected[i].y, EPS, msg + " (column %d y)" % i)

# --- upright basis ---------------------------------------------------------------

func test_upright_basis_cancels_projection() -> void:
	var upright: Transform2D = Transform2D(BB.UPRIGHT_ROTATION, BB.UPRIGHT_SCALE, 0.0, Vector2.ZERO)
	for v: Vector2 in [Vector2(10.0, 0.0), Vector2(0.0, 10.0), Vector2(-7.5, 13.0)]:
		var on_screen: Vector2 = ISO.world_to_screen(upright * v)
		assert_almost_eq(on_screen.x, v.x, EPS, "projected point equals authored point")
		assert_almost_eq(on_screen.y, v.y, EPS, "projected point equals authored point")

# --- Node2D ----------------------------------------------------------------------

func test_make_upright_preserves_authored_screen_appearance() -> void:
	# A part with authored offset, rotation and scale (e.g. the stump's tilted
	# log) must render on screen exactly as authored pre-projection.
	var n: Node2D = autofree(Node2D.new())
	n.position = Vector2(12.0, -2.0)
	n.rotation = deg_to_rad(15.0)
	n.scale = Vector2(1.5, 0.75)
	var authored: Transform2D = n.transform
	BB.make_upright(n)
	_assert_xform_almost_eq(_projection() * n.transform, authored,
		"projection x upright == authored")

func test_make_upright_plain_body_gets_inverse_basis() -> void:
	var n: Node2D = autofree(Node2D.new())
	BB.make_upright(n)
	assert_almost_eq(n.rotation, BB.UPRIGHT_ROTATION, EPS)
	assert_almost_eq(n.scale.x, BB.UPRIGHT_SCALE.x, EPS)
	assert_almost_eq(n.scale.y, BB.UPRIGHT_SCALE.y, EPS)
	assert_almost_eq(n.position.x, 0.0, EPS)
	assert_almost_eq(n.position.y, 0.0, EPS)

func test_make_upright_is_idempotent() -> void:
	var n: Node2D = autofree(Node2D.new())
	n.position = Vector2(4.0, -20.0)
	BB.make_upright(n)
	var once: Transform2D = n.transform
	BB.make_upright(n)
	_assert_xform_almost_eq(n.transform, once, "second call must not re-compose")

func test_make_upright_skips_ground_tagged_nodes() -> void:
	var n: Node2D = autofree(Node2D.new())
	n.set_meta(BB.META_GROUND, true)
	BB.make_upright(n)
	assert_almost_eq(n.rotation, 0.0, EPS, "ground decals stay projected flat")

func test_horizontal_flip_composes_with_upright_basis() -> void:
	# Facing writers set Body.scale.x = -1 after the billboard setup; on screen
	# this must read as a pure horizontal mirror, still upright.
	var n: Node2D = autofree(Node2D.new())
	BB.make_upright(n)
	n.scale.x = -1.0
	var flipped: Transform2D = _projection() * n.transform
	_assert_xform_almost_eq(flipped,
		Transform2D(0.0, Vector2.ZERO).scaled(Vector2(-1.0, 1.0)), "screen-space mirror")

func test_animation_rotation_on_upright_base_stays_near_upright() -> void:
	# Writers set body.rotation = UPRIGHT_ROTATION + swing; the projected basis
	# must equal a small screen-space-ish swing, never the flat skew.
	var n: Node2D = autofree(Node2D.new())
	BB.make_upright(n)
	n.rotation = BB.UPRIGHT_ROTATION + 0.2
	var projected: Transform2D = _projection() * n.transform
	# The up vector (0,-1) must still point mostly up on screen.
	var up: Vector2 = projected.basis_xform(Vector2.UP).normalized()
	assert_lt(up.y, -0.9, "body reads upright (screen up), only slightly swung")

# --- Control ---------------------------------------------------------------------

func test_make_upright_control_preserves_screen_offset() -> void:
	var c: Control = autofree(Control.new())
	c.position = Vector2(-10.0, -22.0)   # authored: health bar above the unit
	BB.make_upright(c)
	assert_almost_eq(c.rotation, BB.UPRIGHT_ROTATION, EPS)
	var projected_offset: Vector2 = ISO.world_to_screen(c.position)
	assert_almost_eq(projected_offset.x, -10.0, EPS, "still 10 px left on screen")
	assert_almost_eq(projected_offset.y, -22.0, EPS, "still 22 px above on screen")

# --- drawn nodes (resource nodes, carcasses) --------------------------------------

func test_setup_drawn_node_uprights_parts_but_not_ground_decals() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var part: Polygon2D = Polygon2D.new()
	var container: Node2D = Node2D.new()
	var shadow: Polygon2D = Polygon2D.new()
	shadow.z_index = -1
	var area: Area2D = Area2D.new()
	root.add_child(part)
	root.add_child(container)
	root.add_child(shadow)
	root.add_child(area)
	BB.setup_drawn_node(root)
	assert_true(part.has_meta(BB.META_UPRIGHT), "polygon part stands upright")
	assert_true(container.has_meta(BB.META_UPRIGHT), "part container stands upright")
	assert_false(shadow.has_meta(BB.META_UPRIGHT), "z<0 shadow stays flat")
	assert_almost_eq(shadow.rotation, 0.0, EPS)
	assert_false(area.has_meta(BB.META_UPRIGHT), "physics/logic nodes untouched")
	assert_almost_eq(area.rotation, 0.0, EPS)

# --- depth band ------------------------------------------------------------------

func test_depth_z_grows_with_screen_depth() -> void:
	assert_lt(BB.depth_z(Vector2(-100.0, -100.0)), BB.depth_z(Vector2.ZERO))
	assert_lt(BB.depth_z(Vector2.ZERO), BB.depth_z(Vector2(100.0, 100.0)))

func test_depth_z_ties_along_screen_rows() -> void:
	# Points on the same projected screen row (equal x+y) share a depth.
	assert_eq(BB.depth_z(Vector2(300.0, 0.0)), BB.depth_z(Vector2(0.0, 300.0)))

func test_depth_z_band_is_clamped_below_overlays() -> void:
	var far_deep: int = BB.depth_z(Vector2(50000.0, 50000.0))
	var far_back: int = BB.depth_z(Vector2(-50000.0, -50000.0))
	assert_eq(far_deep, BB.DEPTH_Z_MAX)
	assert_eq(far_back, BB.DEPTH_Z_MIN)
	assert_lt(BB.DEPTH_Z_MAX, BB.Z_AIRBORNE, "projectiles above every entity")
	assert_lt(BB.Z_AIRBORNE, BB.Z_FOG, "fog of war above projectiles")
	assert_true(BB.DEPTH_Z_MIN > 10, "band above terrain and ground markers")

func test_update_depth_applies_band_to_node() -> void:
	var n: Node2D = add_child_autofree(Node2D.new())
	n.global_position = Vector2(600.0, 600.0)
	BB.update_depth(n)
	assert_eq(n.z_index, BB.depth_z(Vector2(600.0, 600.0)))

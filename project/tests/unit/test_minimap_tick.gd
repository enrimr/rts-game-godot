extends GutTest

## Event/tick-driven minimap — MinimapRenderer no longer rebuilds its entity
## picture every frame: content redraws on a decoupled 5 Hz tick and the
## overlay (camera rect + flashes) only marks itself dirty while changing.
##
## What is covered:
##   1.  Two child layers (content/overlay) exist and ignore mouse input.
##   2.  The content tick only fires every CONTENT_REDRAW_INTERVAL seconds.
##   3.  The unit-sight cache refreshes on the tick, not on every _process.
##   4.  Camera-change detection: dirty on first sight, clean while static,
##       dirty again after a move or zoom.
##   5.  Flashes expire after FLASH_DURATION.
##   6.  Minimap↔world coordinate mapping round-trips.

var _mm: MinimapRenderer

func before_each() -> void:
	_mm = MinimapRenderer.new()
	_mm.size = Vector2(200.0, 200.0)
	add_child_autofree(_mm)

# 1 — layer structure
func test_layers_created() -> void:
	var content: Control = _mm.get_node("ContentLayer") as Control
	var overlay: Control = _mm.get_node("OverlayLayer") as Control
	assert_not_null(content, "content layer exists")
	assert_not_null(overlay, "overlay layer exists")
	assert_eq(content.mouse_filter, Control.MOUSE_FILTER_IGNORE, "layers must not steal minimap clicks")
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE, "layers must not steal minimap clicks")

# 2 — decoupled content tick cadence
func test_content_tick_cadence() -> void:
	_mm._content_timer = 0.0
	_mm._process(0.1)
	assert_almost_eq(_mm._content_timer, 0.1, 0.0001, "accumulates below the interval")
	_mm._process(0.05)
	assert_almost_eq(_mm._content_timer, 0.15, 0.0001, "still below the interval")
	_mm._process(0.1)
	assert_eq(_mm._content_timer, 0.0, "resets when the interval elapses")

# 3 — the expensive sight cache only rebuilds on the tick
func test_sight_cache_refreshes_on_tick_only() -> void:
	var world: Node2D = autofree(Node2D.new()) as Node2D
	var units_layer: Node2D = Node2D.new()
	units_layer.name = "UnitsLayer"
	world.add_child(units_layer)
	_mm.world_node = world
	_mm._content_timer = 0.0
	var unit: Node2D = Node2D.new()
	units_layer.add_child(unit)
	# A bare Node2D has no player_id property, so the cache stays empty —
	# what matters here is WHEN _cache_own_unit_sights runs, observed via clear.
	_mm._own_unit_sights.append({"pos": Vector2.ZERO, "r": 1.0})
	_mm._process(0.1)
	assert_eq(_mm._own_unit_sights.size(), 1, "below the interval the stale cache is untouched")
	_mm._process(0.1)
	assert_eq(_mm._own_unit_sights.size(), 0, "the tick rebuilds (clears) the cache")

# 4 — camera-change detection drives overlay redraws
func test_camera_change_detection() -> void:
	var cam: Camera2D = autofree(Camera2D.new()) as Camera2D
	# The project enables 2D physics interpolation; the engine logs an override
	# notice for interpolated cameras, which GUT would flag as an error.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	_mm.camera_node = cam
	assert_true(_mm._camera_view_changed(), "first sight of the camera is a change")
	assert_false(_mm._camera_view_changed(), "static camera is clean")
	cam.global_position += Vector2(50.0, 0.0)
	assert_true(_mm._camera_view_changed(), "camera move is a change")
	assert_false(_mm._camera_view_changed(), "clean again after caching the move")
	cam.zoom = Vector2(2.0, 2.0)
	assert_true(_mm._camera_view_changed(), "zoom is a change")

func test_no_camera_never_dirty() -> void:
	_mm.camera_node = null
	assert_false(_mm._camera_view_changed())

# 5 — flash lifecycle
func test_flash_expires() -> void:
	_mm.add_flash(Vector2.ZERO, Color.RED)
	assert_eq(_mm._flashes.size(), 1)
	_mm._process(MinimapRenderer.FLASH_DURATION * 0.5)
	assert_eq(_mm._flashes.size(), 1, "alive at half duration")
	_mm._process(MinimapRenderer.FLASH_DURATION)
	assert_eq(_mm._flashes.size(), 0, "removed after FLASH_DURATION")

# 6 — coordinate mapping round-trips
func test_coordinate_round_trip() -> void:
	_mm._refresh_world_bounds()
	var ms: Vector2 = _mm.size
	var world_pos: Vector2 = Vector2(123.0, -456.0)
	var back: Vector2 = _mm._to_world(_mm._to_mm(world_pos, ms), ms)
	assert_almost_eq(back.x, world_pos.x, 0.01)
	assert_almost_eq(back.y, world_pos.y, 0.01)

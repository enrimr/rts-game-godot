extends Node2D

## WeatherOverlay — procedural visual effects for the weather system.
## Added as a child of GameWorld. Uses draw_set_transform_matrix to reset
## world→screen so all drawing happens in viewport (screen) coordinates.

const RAIN_LINE_COUNT: int  = 60
const WIND_LINE_COUNT: int  = 30
const DUST_PARTICLE_COUNT: int = 80
const ASH_PARTICLE_COUNT: int  = 60

# Per-particle state: pos, vel, life (0..1)
var _rain_particles:  Array[Dictionary] = []
var _wind_particles:  Array[Dictionary] = []
var _dust_particles:  Array[Dictionary] = []
var _ash_particles:   Array[Dictionary] = []

var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)

# Overlay tint that fades in/out with intensity
var _overlay_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var _target_overlay: Color = Color(0.0, 0.0, 0.0, 0.0)

func _ready() -> void:
	z_index = 15
	var vp: Viewport = get_viewport()
	if vp != null:
		_viewport_size = vp.get_visible_rect().size
	_init_particles()

func setup(_camera: Camera2D) -> void:
	# Camera reference not needed — drawing is always in screen space via
	# draw_set_transform_matrix in _draw(). Kept for call-site compatibility.
	pass

func _init_particles() -> void:
	for _i: int in range(RAIN_LINE_COUNT):
		_rain_particles.append(_make_rain_particle())
	for _i: int in range(WIND_LINE_COUNT):
		_wind_particles.append(_make_wind_particle())
	for _i: int in range(DUST_PARTICLE_COUNT):
		_dust_particles.append(_make_dust_particle())
	for _i: int in range(ASH_PARTICLE_COUNT):
		_ash_particles.append(_make_ash_particle())

func _make_rain_particle() -> Dictionary:
	return {
		"pos": Vector2(randf() * _viewport_size.x, randf() * _viewport_size.y),
		"vel": Vector2(randf_range(-30.0, 30.0), randf_range(400.0, 700.0)),
		"len": randf_range(8.0, 18.0),
		"life": randf(),
	}

func _make_wind_particle() -> Dictionary:
	return {
		"pos": Vector2(randf() * _viewport_size.x, randf() * _viewport_size.y),
		"vel": Vector2(randf_range(150.0, 350.0), randf_range(-20.0, 20.0)),
		"len": randf_range(20.0, 50.0),
		"life": randf(),
	}

func _make_dust_particle() -> Dictionary:
	return {
		"pos": Vector2(randf() * _viewport_size.x, randf() * _viewport_size.y),
		"vel": Vector2(randf_range(30.0, 90.0), randf_range(-15.0, 15.0)),
		"radius": randf_range(1.5, 4.0),
		"life": randf(),
	}

func _make_ash_particle() -> Dictionary:
	return {
		"pos": Vector2(randf() * _viewport_size.x, randf_range(-50.0, 0.0)),
		"vel": Vector2(randf_range(-20.0, 20.0), randf_range(40.0, 100.0)),
		"radius": randf_range(1.0, 3.0),
		"life": randf(),
	}

func _process(delta: float) -> void:
	if not is_instance_valid(WeatherManager):
		return
	var intensity: float = WeatherManager.intensity
	var wtype: WeatherManager.WeatherType = WeatherManager.current_weather

	# Update target overlay color based on weather
	match wtype:
		WeatherManager.WeatherType.CALIMA:
			_target_overlay = Color(0.60, 0.42, 0.10, 0.25 * intensity)
		WeatherManager.WeatherType.ATLANTIC_STORM:
			_target_overlay = Color(0.10, 0.12, 0.18, 0.30 * intensity)
		WeatherManager.WeatherType.SEA_FOG:
			_target_overlay = Color(0.80, 0.85, 0.90, 0.22 * intensity)
		WeatherManager.WeatherType.VOLCANIC_ASH:
			_target_overlay = Color(0.12, 0.10, 0.08, 0.28 * intensity)
		_:
			_target_overlay = Color(0.0, 0.0, 0.0, 0.0)

	_overlay_color = _overlay_color.lerp(_target_overlay, delta * 1.5)

	if intensity <= 0.0:
		queue_redraw()
		return

	# Update particles
	match wtype:
		WeatherManager.WeatherType.ATLANTIC_STORM:
			_update_rain(delta, intensity)
		WeatherManager.WeatherType.TRADE_WINDS:
			_update_wind(delta, intensity)
		WeatherManager.WeatherType.CALIMA:
			_update_dust(delta, intensity)
		WeatherManager.WeatherType.VOLCANIC_ASH:
			_update_ash(delta, intensity)

	queue_redraw()

func _update_rain(delta: float, intensity: float) -> void:
	for p: Dictionary in _rain_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var vel: Vector2 = p["vel"] as Vector2
		pos += vel * delta * intensity
		if pos.y > _viewport_size.y + 20.0:
			pos = Vector2(randf() * _viewport_size.x, -20.0)
		p["pos"] = pos

func _update_wind(delta: float, intensity: float) -> void:
	for p: Dictionary in _wind_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var vel: Vector2 = p["vel"] as Vector2
		pos += vel * delta * intensity
		if pos.x > _viewport_size.x + 60.0:
			pos = Vector2(-60.0, randf() * _viewport_size.y)
		p["pos"] = pos

func _update_dust(delta: float, intensity: float) -> void:
	for p: Dictionary in _dust_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var vel: Vector2 = p["vel"] as Vector2
		pos += vel * delta * intensity
		if pos.x > _viewport_size.x + 10.0:
			pos = Vector2(-10.0, randf() * _viewport_size.y)
		p["pos"] = pos

func _update_ash(delta: float, intensity: float) -> void:
	for p: Dictionary in _ash_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var vel: Vector2 = p["vel"] as Vector2
		pos += vel * delta * intensity
		if pos.y > _viewport_size.y + 10.0:
			pos = Vector2(randf() * _viewport_size.x, -10.0)
		p["pos"] = pos

func _draw() -> void:
	# Reset to screen coordinates so all drawing is viewport-relative,
	# not affected by the camera/world transform.
	draw_set_transform_matrix(get_canvas_transform().affine_inverse())
	if _overlay_color.a > 0.005:
		draw_rect(Rect2(Vector2.ZERO, _viewport_size), _overlay_color)

	var intensity: float = WeatherManager.intensity if is_instance_valid(WeatherManager) else 0.0
	if intensity <= 0.0:
		return

	var wtype: WeatherManager.WeatherType = WeatherManager.current_weather

	match wtype:
		WeatherManager.WeatherType.ATLANTIC_STORM:
			_draw_rain(intensity)
		WeatherManager.WeatherType.TRADE_WINDS:
			_draw_wind(intensity)
		WeatherManager.WeatherType.CALIMA:
			_draw_dust(intensity)
		WeatherManager.WeatherType.VOLCANIC_ASH:
			_draw_ash(intensity)
		WeatherManager.WeatherType.SEA_FOG:
			_draw_fog_vignette(intensity)

func _draw_rain(intensity: float) -> void:
	var col: Color = Color(0.55, 0.65, 0.80, 0.35 * intensity)
	for p: Dictionary in _rain_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var vel: Vector2 = p["vel"] as Vector2
		var len: float = p["len"] as float
		var end: Vector2 = pos + vel.normalized() * len
		draw_line(pos, end, col, 1.0)

func _draw_wind(intensity: float) -> void:
	var col: Color = Color(0.75, 0.85, 0.95, 0.25 * intensity)
	for p: Dictionary in _wind_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var len: float = p["len"] as float
		draw_line(pos, pos + Vector2(len, 0.0), col, 1.0)

func _draw_dust(intensity: float) -> void:
	var col: Color = Color(0.75, 0.55, 0.20, 0.40 * intensity)
	for p: Dictionary in _dust_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var r: float = p["radius"] as float
		draw_circle(pos, r, col)

func _draw_ash(intensity: float) -> void:
	var col: Color = Color(0.35, 0.30, 0.28, 0.50 * intensity)
	for p: Dictionary in _ash_particles:
		var pos: Vector2 = p["pos"] as Vector2
		var r: float = p["radius"] as float
		draw_circle(pos, r, col)

func _draw_fog_vignette(intensity: float) -> void:
	# Soft vignette on screen edges to suggest coastal fog without full overlay
	var cx: float = _viewport_size.x * 0.5
	var cy: float = _viewport_size.y * 0.5
	var steps: int = 8
	for i: int in range(steps):
		var t: float = float(i) / float(steps)
		var alpha: float = (1.0 - t) * 0.18 * intensity
		var margin_x: float = cx * (1.0 - t * 0.85)
		var margin_y: float = cy * (1.0 - t * 0.85)
		var rect: Rect2 = Rect2(cx - margin_x, cy - margin_y, margin_x * 2.0, margin_y * 2.0)
		draw_rect(rect, Color(0.80, 0.88, 0.95, alpha), false, 2.0)

extends Node

## Visual-review harness: boots a real match (real renderer, NOT --headless)
## and saves viewport PNGs so a reviewer can inspect the actual running game.
##
## Run:
##   CALIMA_SHOT_DIR=/tmp/calima-shots CALIMA_SEED=42 \
##   $GODOT --path project --resolution 1600x900 res://tools/screenshot_runner.tscn
##
## Env vars:
##   CALIMA_SHOT_DIR   output directory for PNGs (required, absolute path)
##   CALIMA_SEED       fixed map seed (optional; default 42)
##   CALIMA_MAP        MatchConfig.MapType int (optional; default STANDARD)
##   CALIMA_WARMUP     seconds of gameplay before the first shot (default 6)
##   CALIMA_TIMESCALE  Engine.time_scale during warmup (default 3.0)
##
## Shots taken (viewport captures — window occlusion does not matter):
##   01_tc_close.png     player TC, zoom 1.0
##   02_tc_medium.png    player TC, zoom 0.6
##   03_overview.png     map centre, zoom 0.35
##   04_tc_late.png      player TC after 12 more in-game seconds (units moving)

var _shot_dir: String = ""
var _world: Node2D = null
var _camera: Camera2D = null

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("SCREENSHOT_RUNNER: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	if OS.get_environment("CALIMA_SEED").is_empty():
		OS.set_environment("CALIMA_SEED", "42")

	MatchConfig.weather_enabled = false   # deterministic visuals
	MatchConfig.rival_count = 1
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.STANDARD

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_camera = _find_camera()
	if _camera == null:
		push_error("SCREENSHOT_RUNNER: camera not found")
		get_tree().quit(1)
		return

	var warmup: float = float(OS.get_environment("CALIMA_WARMUP")) if not OS.get_environment("CALIMA_WARMUP").is_empty() else 6.0
	var tscale: float = float(OS.get_environment("CALIMA_TIMESCALE")) if not OS.get_environment("CALIMA_TIMESCALE").is_empty() else 3.0
	Engine.time_scale = tscale
	await get_tree().create_timer(warmup).timeout
	Engine.time_scale = 1.0

	var tc_pos: Vector2 = _player_tc_position()
	await _shoot(tc_pos, 1.0, "01_tc_close")
	await _shoot(tc_pos, 0.6, "02_tc_medium")
	await _shoot(Vector2.ZERO, 0.35, "03_overview")
	Engine.time_scale = tscale
	await get_tree().create_timer(4.0).timeout
	Engine.time_scale = 1.0
	await _shoot(tc_pos, 0.8, "04_tc_late")

	print("SCREENSHOT_RUNNER: done -> ", _shot_dir)
	get_tree().quit(0)

func _find_camera() -> Camera2D:
	for c: Node in _world.get_children():
		if c is Camera2D:
			return c as Camera2D
	return _world.get_node_or_null("Camera2D") as Camera2D

func _player_tc_position() -> Vector2:
	var drop_off: Node2D = _world.get_node_or_null("DropOffNode") as Node2D
	if drop_off != null:
		return drop_off.global_position
	for b: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		if (b.get("player_id") as int) == 0:
			return (b as Node2D).global_position
	return Vector2.ZERO

func _shoot(world_pos: Vector2, zoom: float, name_base: String) -> void:
	_camera.global_position = world_pos
	_camera.zoom = Vector2(zoom, zoom)
	# Let the renderer settle (interpolation, redraws) before grabbing pixels.
	for _i: int in range(6):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _shot_dir.path_join(name_base + ".png")
	var err: int = img.save_png(path)
	if err != OK:
		push_error("SCREENSHOT_RUNNER: failed to save " + path)
	else:
		print("SCREENSHOT_RUNNER: saved ", path)

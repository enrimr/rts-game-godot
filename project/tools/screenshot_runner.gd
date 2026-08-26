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
##   01_tc_close.png     player TC close-up (units readable), zoom 2.4
##   02_tc_medium.png    player TC + surroundings, zoom 1.4
##   03_overview.png     whole map diamond, fog revealed, fit-to-frame zoom
##   04_tc_late.png      player TC after more in-game seconds (units moving)

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
	# Optional civ overrides so reviewers can capture each civilization's look.
	var civ_env: String = OS.get_environment("CALIMA_CIV")
	if not civ_env.is_empty():
		MatchConfig.player_civ_id = civ_env
	var rival_env: String = OS.get_environment("CALIMA_RIVAL_CIV")
	if not rival_env.is_empty() and MatchConfig.rival_civ_ids.size() > 0:
		MatchConfig.rival_civ_ids[0] = rival_env

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
	await _shoot(tc_pos, 2.4, "01_tc_close")
	await _shoot(tc_pos, 1.4, "02_tc_medium")
	Engine.time_scale = tscale
	await get_tree().create_timer(4.0).timeout
	Engine.time_scale = 1.0
	await _shoot(tc_pos, 2.0, "04_tc_late")

	if OS.get_environment("CALIMA_PREVIEW") == "1":
		await _shoot_placement_preview(tc_pos)

	# Overview goes last: fog is revealed so the reviewer can inspect the whole
	# projected map, which would otherwise be near-black unexplored fog.
	var fog: Node = _world.get("_fog") as Node
	if fog != null and fog.has_method("reveal_all"):
		fog.call("reveal_all")
	var center: Vector2 = _landmass_center()
	print("SCREENSHOT_RUNNER: overview centre = ", center)
	await _shoot(center, _overview_zoom(), "03_overview")

	print("SCREENSHOT_RUNNER: done -> ", _shot_dir)
	get_tree().quit(0)

func _find_camera() -> Camera2D:
	for c: Node in _world.get_children():
		if c is Camera2D:
			return c as Camera2D
	return _world.get_node_or_null("Camera2D") as Camera2D

# Zoom that fits the whole projected map diamond in the viewport with a margin.
# Under the iso projection a square map of side S spans S*sqrt(2)*zoom on screen.
func _overview_zoom() -> float:
	var side: float = MatchConfig.get_map_half() * 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(vp.x / (side * sqrt(2.0)),
		vp.y / (side * sqrt(2.0) * 0.5))
	return fit * 0.92

# The generated continent is an organic blob, not centred on the world origin;
# the resource-node centroid tracks where the actual landmass sits.
func _landmass_center() -> Vector2:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("resource_nodes")
	if nodes.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for n: Node in nodes:
		sum += (n as Node2D).global_position
	return sum / float(nodes.size())

func _player_tc_position() -> Vector2:
	var drop_off: Node2D = _world.get_node_or_null("DropOffNode") as Node2D
	if drop_off != null:
		return drop_off.global_position
	for b: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		if (b.get("player_id") as int) == 0:
			return (b as Node2D).global_position
	return Vector2.ZERO

# CALIMA_PREVIEW=1: exercises the real Barracks placement path (ghost building
# + ground-diamond footprint + snap-grid lattice) near the TC and captures it
# as 05_preview.png, then cancels so the flow leaves no side effects.
func _shoot_placement_preview(tc_pos: Vector2) -> void:
	ResourceManager.add_resource(0, "wood", 200.0)
	_camera.global_position = tc_pos
	_camera.zoom = IsoProjection.camera_zoom(2.0)
	if not _world.has_method("_start_placement"):
		push_error("SCREENSHOT_RUNNER: game world lacks _start_placement")
		return
	_world.call("_start_placement", "barracks")
	# The ghost follows the mouse each frame; park the cursor over a clear spot
	# beside the TC so the preview and its snap grid land on open ground.
	var offset_screen: Vector2 = IsoProjection.world_to_screen(Vector2(260.0, -60.0), 2.0)
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5 + offset_screen)
	for _i: int in range(6):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _shot_dir.path_join("05_preview.png")
	if img.save_png(path) == OK:
		print("SCREENSHOT_RUNNER: saved ", path)
	else:
		push_error("SCREENSHOT_RUNNER: failed to save " + path)
	_world.call("_cancel_placement")

func _shoot(world_pos: Vector2, zoom: float, name_base: String) -> void:
	_camera.global_position = world_pos
	# Compose with the isometric Y squash so shots match real gameplay framing.
	_camera.zoom = IsoProjection.camera_zoom(zoom)
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

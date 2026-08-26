extends Node

## Visual check for the building-placement preview: boots a real match, enters
## placement mode for a house and a dock, warps the mouse near the player TC,
## and saves PNGs showing the ghost + ground footprint diamond + snap lattice.
## Run (real renderer, not --headless):
##   CALIMA_SHOT_DIR=/tmp/calima-placement CALIMA_SEED=42 $GODOT --path project \
##     --resolution 1600x900 res://tools/check_placement_preview.tscn

var _shot_dir: String = ""
var _world: Node2D = null

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("CHECK_PLACEMENT_PREVIEW: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	if OS.get_environment("CALIMA_SEED").is_empty():
		OS.set_environment("CALIMA_SEED", "42")
	MatchConfig.weather_enabled = false
	MatchConfig.rival_count = 1
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	_run()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var camera: Camera2D = null
	for c: Node in _world.get_children():
		if c is Camera2D:
			camera = c as Camera2D
			break
	var tc_pos: Vector2 = Vector2.ZERO
	for b: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		if (b.get("player_id") as int) == 0:
			tc_pos = (b as Node2D).global_position
			break
	camera.global_position = tc_pos
	camera.zoom = IsoProjection.camera_zoom(1.8)
	camera.reset_physics_interpolation()
	# Point the cursor a bit off-centre so the ghost lands on open ground.
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5
		+ Vector2(180.0, 60.0))
	await get_tree().create_timer(0.4).timeout

	ResourceManager.add_resource(0, "wood", 500)
	for shot: Array in [["house", "placement_house"], ["barracks", "placement_barracks"]]:
		_world.call("_start_placement", shot[0] as String)
		await get_tree().create_timer(0.4).timeout
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[1] as String])
		print("CHECK_PLACEMENT_PREVIEW: saved %s.png" % (shot[1] as String))
		_world.call("_cancel_placement")
		await get_tree().process_frame
	get_tree().quit(0)

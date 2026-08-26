extends Node2D

## Visual check: renders every building scene under the isometric camera in a
## grid — top row force-completed, bottom row mid-construction (scaffold) —
## and saves one PNG per zoom level for review.
## Run (real renderer, not --headless):
##   CALIMA_SHOT_DIR=/tmp/calima-gallery $GODOT --path project \
##     --resolution 1600x900 res://tools/check_building_gallery.tscn

const SCENES: Array[String] = [
	"res://scenes/buildings/town_center.tscn",
	"res://scenes/buildings/town_center_ai.tscn",
	"res://scenes/buildings/house.tscn",
	"res://scenes/buildings/barracks.tscn",
	"res://scenes/buildings/archery_range.tscn",
	"res://scenes/buildings/stable.tscn",
	"res://scenes/buildings/blacksmith.tscn",
	"res://scenes/buildings/market.tscn",
	"res://scenes/buildings/temple.tscn",
	"res://scenes/buildings/university.tscn",
	"res://scenes/buildings/siege_workshop.tscn",
	"res://scenes/buildings/lumber_camp.tscn",
	"res://scenes/buildings/mining_camp.tscn",
	"res://scenes/buildings/dock.tscn",
	"res://scenes/buildings/farm.tscn",
	"res://scenes/buildings/fish_trap.tscn",
	"res://scenes/buildings/watch_tower.tscn",
	"res://scenes/buildings/wall_segment.tscn",
	"res://scenes/buildings/gate.tscn",
	"res://scenes/buildings/wonder.tscn",
]

const COLS: int = 5
const STEP: float = 190.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("CHECK_BUILDING_GALLERY: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)

	var bg: Polygon2D = Polygon2D.new()
	bg.color = Color(0.32, 0.52, 0.28)
	bg.polygon = PackedVector2Array([Vector2(-2000, -2000), Vector2(3000, -2000),
		Vector2(3000, 3000), Vector2(-2000, 3000)])
	bg.z_index = -10
	add_child(bg)

	for i: int in range(SCENES.size()):
		_spawn(SCENES[i], i, true)
		_spawn(SCENES[i], i, false)

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	IsoProjection.apply_to_camera(cam, 1.0)
	_run(cam)

func _spawn(path: String, i: int, complete: bool) -> void:
	var b: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	var col: int = i % COLS
	var row: int = i / COLS + (0 if complete else 4)
	# Lay the grid out along screen axes so the projected gallery stays a grid.
	var screen_pos: Vector2 = Vector2(float(col) * STEP, float(row) * STEP * 0.62)
	b.global_position = IsoProjection.screen_to_world(screen_pos)
	b.set("player_id", 2 if complete else 3)
	if not complete:
		b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
		b.set("construction_progress", 55.0)
	add_child(b)
	if complete and b.has_method("force_complete"):
		b.call("force_complete")

func _run(cam: Camera2D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var centre_screen: Vector2 = Vector2(float(COLS - 1) * STEP * 0.5, 3.6 * STEP * 0.62)
	for shot: Array in [["gallery_far", 0.85], ["gallery_close", 1.8]]:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(centre_screen)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_BUILDING_GALLERY: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

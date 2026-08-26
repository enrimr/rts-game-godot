extends Node2D

## Visual check: renders the shared unit roster (plus the civ's unique unit)
## under the isometric camera in a grid and saves one PNG per zoom level.
## Honors CALIMA_CIV so each civilization's dress pass can be reviewed.
## Run (real renderer, not --headless):
##   CALIMA_SHOT_DIR=/tmp/calima-ugallery CALIMA_CIV=mahos $GODOT --path project \
##     --resolution 1600x900 res://tools/check_unit_gallery.tscn

const SCENES: Array[String] = [
	"res://scenes/units/villager.tscn",
	"res://scenes/units/militia.tscn",
	"res://scenes/units/man_at_arms.tscn",
	"res://scenes/units/long_swordsman.tscn",
	"res://scenes/units/pikeman.tscn",
	"res://scenes/units/archer.tscn",
	"res://scenes/units/scout.tscn",
	"res://scenes/units/heavy_scout.tscn",
	"res://scenes/units/knight.tscn",
]

const CIV_UNIQUE: Dictionary = {
	"guanches":    "res://scenes/units/menceyes_guard.tscn",
	"canarii":     "res://scenes/units/ravine_archer.tscn",
	"mahos":       "res://scenes/units/sand_raider.tscn",
	"franks":      "res://scenes/units/chevalier_normand.tscn",
	"britons":     "res://scenes/units/longbowman.tscn",
	"castellanos": "res://scenes/units/conquistador.tscn",
	"atlantes":    "res://scenes/units/tidecaller.tscn",
	"fenicios":    "res://scenes/units/trireme.tscn",
}

const COLS: int = 5
const STEP: float = 90.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("CHECK_UNIT_GALLERY: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)

	var civ: String = OS.get_environment("CALIMA_CIV")
	if not civ.is_empty():
		MatchConfig.player_civ_id = civ

	var bg: Polygon2D = Polygon2D.new()
	bg.color = Color(0.32, 0.52, 0.28)
	bg.polygon = PackedVector2Array([Vector2(-2000, -2000), Vector2(3000, -2000),
		Vector2(3000, 3000), Vector2(-2000, 3000)])
	bg.z_index = -10
	add_child(bg)

	var scenes: Array[String] = SCENES.duplicate()
	if CIV_UNIQUE.has(MatchConfig.player_civ_id):
		scenes.append(CIV_UNIQUE[MatchConfig.player_civ_id] as String)
	for i: int in range(scenes.size()):
		_spawn(scenes[i], i)

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	IsoProjection.apply_to_camera(cam, 1.0)
	_run(cam, scenes.size())

func _spawn(path: String, i: int) -> void:
	var u: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	var col: int = i % COLS
	var row: int = i / COLS
	# Lay the grid out along screen axes so the projected gallery stays a grid.
	var screen_pos: Vector2 = Vector2(float(col) * STEP, float(row) * STEP * 0.85)
	u.set("player_id", 0)   # player 0 -> MatchConfig.player_civ_id dress
	add_child(u)
	u.global_position = IsoProjection.screen_to_world(screen_pos)

func _run(cam: Camera2D, count: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var rows: float = ceilf(float(count) / float(COLS))
	var centre_screen: Vector2 = Vector2(float(COLS - 1) * STEP * 0.5,
		(rows - 1.0) * STEP * 0.85 * 0.5)
	for shot: Array in [["ugallery_far", 2.0], ["ugallery_close", 3.4]]:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(centre_screen)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_UNIT_GALLERY: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

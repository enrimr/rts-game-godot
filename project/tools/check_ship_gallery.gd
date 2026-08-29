extends Node2D

## Visual check: renders every shared hull dressed for every civilization, one
## civ per row, so the naval identity pass (ShipDress + CivStyle.NAVAL) can be
## reviewed at a glance — Atlantes must read as the naval civ from across the
## board. The Fenicios row ends with their unique Trireme, which opts out of the
## dress pass and keeps its bespoke art.
## Run (real renderer, not --headless):
##   CALIMA_SHOT_DIR=/tmp/calima-ships $GODOT --path project \
##     --resolution 1600x900 res://tools/check_ship_gallery.tscn
## CALIMA_CIVS=atlantes,fenicios narrows the gallery to a few rows for a close
## look at one fleet.

const HULLS: Array[String] = [
	"res://scenes/units/fishing_boat.tscn",
	"res://scenes/units/transport_ship.tscn",
	"res://scenes/units/war_galley.tscn",
]
const TRIREME: String = "res://scenes/units/trireme.tscn"

const ALL_CIVS: Array[String] = [
	"guanches", "canarii", "mahos", "franks",
	"britons", "castellanos", "atlantes", "fenicios",
]

const COL_STEP: float = 78.0
const ROW_STEP: float = 74.0

var _shot_dir: String = ""
var _civs: Array[String] = []

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("CHECK_SHIP_GALLERY: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_civs = _requested_civs()

	var sea: Polygon2D = Polygon2D.new()
	sea.color = Color(0.13, 0.32, 0.46)
	sea.polygon = PackedVector2Array([Vector2(-2000, -2000), Vector2(3000, -2000),
		Vector2(3000, 3000), Vector2(-2000, 3000)])
	sea.z_index = -10
	add_child(sea)

	for row: int in range(_civs.size()):
		var civ: String = _civs[row]
		var scenes: Array[String] = HULLS.duplicate()
		if civ == "fenicios":
			scenes.append(TRIREME)
		for col: int in range(scenes.size()):
			_spawn(scenes[col], civ, col, row)

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	IsoProjection.apply_to_camera(cam, 1.0)
	_run(cam)

func _requested_civs() -> Array[String]:
	var raw: String = OS.get_environment("CALIMA_CIVS")
	if raw.is_empty():
		return ALL_CIVS.duplicate()
	var picked: Array[String] = []
	for name: String in raw.split(",", false):
		var civ: String = name.strip_edges()
		if ALL_CIVS.has(civ):
			picked.append(civ)
	return picked if not picked.is_empty() else ALL_CIVS.duplicate()

func _spawn(path: String, civ: String, col: int, row: int) -> void:
	var ship: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	ship.set("player_id", 0)
	# civ_id set before _ready so ShipBase keeps it and ShipDress paints this civ.
	ship.set("civ_id", civ)
	add_child(ship)
	# Lay the grid out along screen axes so the projected gallery stays a grid.
	ship.global_position = IsoProjection.screen_to_world(
		Vector2(float(col) * COL_STEP, float(row) * ROW_STEP))

func _run(cam: Camera2D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var centre_screen: Vector2 = Vector2(
		COL_STEP * 1.5, float(_civs.size() - 1) * ROW_STEP * 0.5)
	for shot: Array in [["sgallery_far", 1.5], ["sgallery_close", 3.0]]:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(centre_screen)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_SHIP_GALLERY: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

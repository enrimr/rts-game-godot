extends Node2D

## Visual check: dumps IconBaker textures for a set of entities as PNGs so the
## icon framing (centering, fill) can be reviewed at 1:1.
## Run (real renderer):
##   CALIMA_SHOT_DIR=/tmp/calima-icons CALIMA_CIV=mahos $GODOT --path project \
##     --resolution 400x300 res://tools/check_icon_bake.tscn

const SCENES: Array[String] = [
	"res://scenes/units/villager.tscn",
	"res://scenes/units/militia.tscn",
	"res://scenes/units/knight.tscn",
	"res://scenes/buildings/house.tscn",
	"res://scenes/buildings/barracks.tscn",
	"res://scenes/buildings/town_center.tscn",
	"res://scenes/buildings/watch_tower.tscn",
	"res://scenes/buildings/farm.tscn",
]

func _ready() -> void:
	var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if shot_dir.is_empty():
		push_error("CHECK_ICON_BAKE: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var civ: String = OS.get_environment("CALIMA_CIV")
	if not civ.is_empty():
		MatchConfig.player_civ_id = civ
	_run(shot_dir)

func _run(shot_dir: String) -> void:
	# Let the window/renderer warm up before the first bake request.
	await get_tree().process_frame
	await get_tree().process_frame
	var icons: Dictionary = {}
	for path: String in SCENES:
		icons[path] = IconBaker.get_icon(path, 0)
	# Bakes fill in asynchronously; give the deferred visual chains headroom.
	await get_tree().create_timer(2.5).timeout
	for path: String in SCENES:
		var tex: Texture2D = icons[path] as Texture2D
		var img: Image = tex.get_image()
		var out: String = shot_dir.path_join(path.get_file().get_basename() + ".png")
		img.save_png(out)
		print("CHECK_ICON_BAKE: saved ", out)
	get_tree().quit(0)

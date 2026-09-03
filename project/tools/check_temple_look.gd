extends Node2D

## Visual review of the Temple (almogarén) look: the temple alone close-up
## plus a lineup next to Barracks, Blacksmith, University and House for
## silhouette contrast at gameplay zoom.
##   CALIMA_SHOT_DIR=/tmp/calima-temple $GODOT --path project \
##     --resolution 1600x900 res://tools/check_temple_look.tscn

const LINEUP: Array[String] = [
	"res://scenes/buildings/barracks.tscn",
	"res://scenes/buildings/blacksmith.tscn",
	"res://scenes/buildings/temple.tscn",
	"res://scenes/buildings/university.tscn",
	"res://scenes/buildings/house.tscn",
]
const STEP: float = 200.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-temple"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.33, 0.42, 0.27))
	var bg: Polygon2D = Polygon2D.new()
	bg.color = Color(0.36, 0.46, 0.30)
	bg.polygon = PackedVector2Array([Vector2(-3000, -3000), Vector2(3000, -3000),
		Vector2(3000, 3000), Vector2(-3000, 3000)])
	bg.z_index = -10
	add_child(bg)
	for i: int in range(LINEUP.size()):
		var scene: PackedScene = load(LINEUP[i]) as PackedScene
		var building: Node2D = scene.instantiate() as Node2D
		building.set("player_id", 2)
		building.global_position = IsoProjection.screen_to_world(
			Vector2((float(i) - float(LINEUP.size() - 1) * 0.5) * STEP, 0.0))
		add_child(building)
		if building.has_method("force_complete"):
			building.call("force_complete")
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_run(cam)

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.6).timeout
	var shots: Array = [
		["temple_lineup", 1.15, Vector2.ZERO],
		["temple_close", 3.0, Vector2.ZERO],
		["temple_mid", 1.8, Vector2.ZERO],
	]
	for shot: Array in shots:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(shot[2] as Vector2)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.25).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_TEMPLE_LOOK: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

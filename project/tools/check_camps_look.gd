extends Node2D

## Visual review of the resource-camp looks: Lumber Camp, Mining Camp and the
## Mill lined up against a House and Barracks for silhouette contrast (a camp
## must NOT read as a house), plus the Presa Canario next to a Sheep for scale.
##   CALIMA_SHOT_DIR=/tmp/calima-camps $GODOT --path project \
##     --resolution 1600x900 res://tools/check_camps_look.tscn

const LINEUP: Array[String] = [
	"res://scenes/buildings/house.tscn",
	"res://scenes/buildings/lumber_camp.tscn",
	"res://scenes/buildings/mining_camp.tscn",
	"res://scenes/buildings/mill.tscn",
	"res://scenes/buildings/barracks.tscn",
]
const STEP: float = 200.0
const DOG_ROW_Y: float = 180.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-camps"
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
	_spawn_unit("res://scenes/units/presa_canario.tscn", Vector2(-30.0, DOG_ROW_Y))
	_spawn_unit("res://scenes/units/sheep.tscn", Vector2(30.0, DOG_ROW_Y))
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_run(cam)

func _spawn_unit(path: String, at: Vector2) -> void:
	var unit: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	unit.set("player_id", 2)
	add_child(unit)
	unit.global_position = IsoProjection.screen_to_world(at)
	unit.set_physics_process(false)

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.6).timeout
	var shots: Array = [
		["camps_lineup", 1.05, Vector2.ZERO],
		["lumber_close", 2.6, Vector2(-STEP, -10.0)],
		["mining_close", 2.6, Vector2(0.0, -10.0)],
		["mill_close", 2.6, Vector2(STEP, -20.0)],
		["dog_close", 4.5, Vector2(0.0, DOG_ROW_Y)],
	]
	for shot: Array in shots:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(shot[2] as Vector2)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.25).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_CAMPS_LOOK: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

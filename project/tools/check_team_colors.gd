extends Node2D

## Visual review of the team-colour dress (real renderer): a grid of unit
## types (columns) for four player colours (rows) on a flat backdrop. The
## cloth must read as the row's player colour at a glance; steel, leather,
## skin and natural horses must NOT change between rows.
##   CALIMA_SHOT_DIR=/tmp/calima-teams $GODOT --path project \
##     --resolution 1500x900 res://tools/check_team_colors.tscn

const UNIT_SCENES: Array[String] = [
	"res://scenes/units/villager.tscn",
	"res://scenes/units/militia.tscn",
	"res://scenes/units/archer.tscn",
	"res://scenes/units/pikeman.tscn",
	"res://scenes/units/scout.tscn",
	"res://scenes/units/knight.tscn",
	"res://scenes/units/man_at_arms.tscn",
	"res://scenes/units/long_swordsman.tscn",
]
const PLAYERS: Array[int] = [0, 1, 2, 4]   # blue, red, orange, green
const COL_STEP: float = 120.0
const ROW_STEP: float = 110.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-teams"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.30, 0.36, 0.24))

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()

	for row: int in range(PLAYERS.size()):
		for col: int in range(UNIT_SCENES.size()):
			var scene: PackedScene = load(UNIT_SCENES[col]) as PackedScene
			if scene == null:
				continue
			var unit: Node2D = scene.instantiate() as Node2D
			unit.set("player_id", PLAYERS[row])
			unit.set("civ_id", "guanches")
			unit.set("is_female", col == 0 and row % 2 == 1)
			add_child(unit)
			unit.global_position = IsoProjection.screen_to_world(Vector2(
				(float(col) - float(UNIT_SCENES.size() - 1) * 0.5) * COL_STEP,
				(float(row) - float(PLAYERS.size() - 1) * 0.5) * ROW_STEP))
			unit.set_physics_process(false)
	_run(cam)

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.8).timeout
	var shots: Array = [
		["team_colors", 1.6, Vector2.ZERO],
		["team_close_left", 3.4, Vector2(-COL_STEP * 2.2, 0.0)],
		["team_close_right", 3.4, Vector2(COL_STEP * 2.2, 0.0)],
	]
	for shot: Array in shots:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(shot[2] as Vector2)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.25).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_TEAM_COLORS: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

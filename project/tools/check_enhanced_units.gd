extends Node2D

## Visual review of the optional enhanced unit look (real renderer): a grid of
## representative units for two players, shot in CLASSIC mode, then re-shot
## after toggling GameSettings.enhanced_units live (exercising the same signal
## path the settings panel uses), plus close-ups and an attack-pose close-up.
##   CALIMA_SHOT_DIR=/tmp/calima-enhanced $GODOT --path project \
##     --resolution 1500x900 res://tools/check_enhanced_units.tscn

const UNIT_SCENES: Array[String] = [
	"res://scenes/units/villager.tscn",
	"res://scenes/units/militia.tscn",
	"res://scenes/units/archer.tscn",
	"res://scenes/units/pikeman.tscn",
	"res://scenes/units/knight.tscn",
	"res://scenes/units/harimaguada.tscn",
	"res://scenes/units/presa_canario.tscn",
]
const PLAYERS: Array[int] = [0, 1]
const COL_STEP: float = 120.0
const ROW_STEP: float = 130.0

var _shot_dir: String = ""
var _units: Array[Node2D] = []

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-enhanced"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.30, 0.36, 0.24))
	GameSettings.enhanced_units = false

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()

	var cols: int = UNIT_SCENES.size() + 1   # + hero column
	for row: int in range(PLAYERS.size()):
		for col: int in range(cols):
			var unit: Node2D = _make_unit(col, row)
			if unit == null:
				continue
			add_child(unit)
			unit.global_position = IsoProjection.screen_to_world(Vector2(
				(float(col) - float(cols - 1) * 0.5) * COL_STEP,
				(float(row) - float(PLAYERS.size() - 1) * 0.5) * ROW_STEP))
			unit.set_physics_process(false)
			_units.append(unit)
	_run(cam)

func _make_unit(col: int, row: int) -> Node2D:
	var unit: Node2D
	if col < UNIT_SCENES.size():
		var scene: PackedScene = load(UNIT_SCENES[col]) as PackedScene
		if scene == null:
			return null
		unit = scene.instantiate() as Node2D
	else:
		# Hero column, built the way WorldSetup spawns it.
		var data_path: String = WorldSetup.HERO_MALE_DATA["guanches"] as String
		unit = (load(HeroDress.scene_path_for(data_path)) as PackedScene).instantiate() as Node2D
		unit.set_script(load("res://scripts/units/hero_unit.gd"))
		unit.set("unit_data", load(data_path))
	unit.set("player_id", PLAYERS[row])
	unit.set("civ_id", "guanches")
	unit.set("is_female", col == 0 and row == 1)
	return unit

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.9).timeout
	await _shoot(cam, "classic_grid", 1.5, Vector2.ZERO)
	await _shoot(cam, "classic_close", 3.6, Vector2(-COL_STEP * 1.8, 0.0))

	# Flip the live toggle exactly like the settings panel does.
	GameSettings.enhanced_units = true
	await get_tree().create_timer(0.4).timeout
	await _shoot(cam, "enhanced_grid", 1.5, Vector2.ZERO)
	await _shoot(cam, "enhanced_close", 3.6, Vector2(-COL_STEP * 1.8, 0.0))
	await _shoot(cam, "enhanced_close_right", 3.6, Vector2(COL_STEP * 2.0, 0.0))

	# Attack pose: the enhanced snap composes over the base swing.
	for unit: Node2D in _units:
		unit.set("current_state", UnitBase.UnitState.ATTACKING)
	await get_tree().create_timer(0.35).timeout
	await _shoot(cam, "enhanced_attack", 3.6, Vector2(-COL_STEP * 1.8, 0.0))

	# And stripping restores the classic rig on the same living units.
	GameSettings.enhanced_units = false
	for unit: Node2D in _units:
		unit.set("current_state", UnitBase.UnitState.IDLE)
	await get_tree().create_timer(0.4).timeout
	await _shoot(cam, "stripped_close", 3.6, Vector2(-COL_STEP * 1.8, 0.0))
	get_tree().quit(0)

func _shoot(cam: Camera2D, shot_name: String, zoom: float, center: Vector2) -> void:
	IsoProjection.apply_to_camera(cam, zoom)
	cam.global_position = IsoProjection.screen_to_world(center)
	cam.reset_physics_interpolation()
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shot_dir, shot_name])
	print("CHECK_ENHANCED_UNITS: saved %s.png" % shot_name)

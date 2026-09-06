extends Node2D

## Visual review of the REDESIGNED unit style (real renderer): a grid of the
## chosen batch for two players shot in CLASSIC, re-shot after switching
## GameSettings.unit_style to REDESIGNED live (the same signal path the
## settings selector uses), plus close-ups and frozen walk/attack/work poses.
##   CALIMA_SHOT_DIR=/tmp/calima-redesign CALIMA_BATCH=a $GODOT --path project \
##     --resolution 1500x900 res://tools/check_redesigned_units.tscn

const BATCHES: Dictionary = {
	"a": [
		"res://scenes/units/villager.tscn",
		"res://scenes/units/villager.tscn",   # forced female column
		"res://scenes/units/militia.tscn",
		"res://scenes/units/man_at_arms.tscn",
		"res://scenes/units/long_swordsman.tscn",
		"res://scenes/units/pikeman.tscn",
		"res://scenes/units/archer.tscn",
	],
	"b": [
		"res://scenes/units/scout.tscn",
		"res://scenes/units/heavy_scout.tscn",
		"res://scenes/units/knight.tscn",
		"res://scenes/units/harimaguada.tscn",
		"res://scenes/units/presa_canario.tscn",
	],
	"c": [
		"res://scenes/units/battering_ram.tscn",
		"res://scenes/units/mangonel.tscn",
		"res://scenes/units/trebuchet.tscn",
	],
	"d": [
		"res://scenes/units/fishing_boat.tscn",
		"res://scenes/units/transport_ship.tscn",
		"res://scenes/units/war_galley.tscn",
	],
	"e": [
		"res://scenes/units/menceyes_guard.tscn",
		"res://scenes/units/ravine_archer.tscn",
		"res://scenes/units/sand_raider.tscn",
		"res://scenes/units/chevalier_normand.tscn",
		"res://scenes/units/longbowman.tscn",
		"res://scenes/units/conquistador.tscn",
		"res://scenes/units/tidecaller.tscn",
		"res://scenes/units/trireme.tscn",
	],
}
const HERO_CIVS: Array[String] = ["guanches", "canarii", "castellanos", "atlantes"]
const PLAYERS: Array[int] = [0, 1]
const COL_STEP: float = 110.0
const ROW_STEP: float = 130.0

var _shot_dir: String = ""
var _batch: String = "a"
var _units: Array[Node2D] = []

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-redesign"
	_batch = OS.get_environment("CALIMA_BATCH").to_lower()
	if _batch.is_empty():
		_batch = "a"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.30, 0.36, 0.24))
	GameSettings.unit_style = GameSettings.UnitStyle.CLASSIC

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()

	var cols: int = _col_count()
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

func _col_count() -> int:
	if _batch == "f":
		return HERO_CIVS.size()
	return (BATCHES.get(_batch, BATCHES["a"]) as Array).size()

func _make_unit(col: int, row: int) -> Node2D:
	var unit: Node2D
	if _batch == "f":
		var male: bool = row == 0
		var pool: Dictionary = WorldSetup.HERO_MALE_DATA if male else WorldSetup.HERO_FEMALE_DATA
		var data_path: String = pool[HERO_CIVS[col]] as String
		unit = (load(HeroDress.scene_path_for(data_path)) as PackedScene).instantiate() as Node2D
		unit.set_script(load("res://scripts/units/hero_unit.gd"))
		unit.set("unit_data", load(data_path))
		unit.set("civ_id", HERO_CIVS[col])
		unit.set("is_female", not male)
		unit.set("player_id", PLAYERS[row])
		return unit
	var scenes: Array = BATCHES.get(_batch, BATCHES["a"]) as Array
	var scene: PackedScene = load(scenes[col] as String) as PackedScene
	if scene == null:
		return null
	unit = scene.instantiate() as Node2D
	unit.set("player_id", PLAYERS[row])
	unit.set("civ_id", "guanches")
	# Column 1 of batch A is the forced-female villager; row 1 humans go female
	# elsewhere so both genders appear.
	unit.set("is_female", (col == 1) if _batch == "a" else row == 1)
	return unit

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.9).timeout
	await _shoot(cam, "1_classic_grid", 1.5, Vector2.ZERO)

	GameSettings.unit_style = GameSettings.UnitStyle.REDESIGNED
	await get_tree().create_timer(0.4).timeout
	await _shoot(cam, "2_redesigned_grid", 1.5, Vector2.ZERO)
	await _shoot(cam, "3_redesigned_close_left", 3.4, Vector2(-COL_STEP * 1.7, 0.0))
	await _shoot(cam, "4_redesigned_close_right", 3.4, Vector2(COL_STEP * 1.7, 0.0))

	for unit: Node2D in _units:
		unit.set("current_state", UnitBase.UnitState.MOVING)
	await get_tree().create_timer(0.31).timeout
	await _shoot(cam, "5_redesigned_walk", 3.4, Vector2(-COL_STEP * 1.7, 0.0))

	for unit: Node2D in _units:
		unit.set("current_state", UnitBase.UnitState.ATTACKING)
	await get_tree().create_timer(0.27).timeout
	await _shoot(cam, "6_redesigned_attack", 3.4, Vector2(-COL_STEP * 1.7, 0.0))

	if _batch == "a":
		for unit: Node2D in _units:
			unit.set("current_state", UnitBase.UnitState.GATHERING)
		await get_tree().create_timer(0.3).timeout
		await _shoot(cam, "7_redesigned_gather", 3.4, Vector2(-COL_STEP * 2.4, 0.0))

	# Stripping restores the classic rig on the same living units.
	GameSettings.unit_style = GameSettings.UnitStyle.CLASSIC
	for unit: Node2D in _units:
		unit.set("current_state", UnitBase.UnitState.IDLE)
	await get_tree().create_timer(0.4).timeout
	await _shoot(cam, "8_stripped_grid", 1.5, Vector2.ZERO)
	get_tree().quit(0)

func _shoot(cam: Camera2D, shot_name: String, zoom: float, center: Vector2) -> void:
	IsoProjection.apply_to_camera(cam, zoom)
	cam.global_position = IsoProjection.screen_to_world(center)
	cam.reset_physics_interpolation()
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_shot_dir, _batch, shot_name])
	print("CHECK_REDESIGNED_UNITS: saved %s_%s.png" % [_batch, shot_name])

extends Node2D

## Visual review of the Harimaguada priestess-healer (real renderer): close-up
## of her rig in idle / walking / tending poses, plus a lineup next to a female
## villager and a heroine — she must read as a priestess, distinct from both.
## A second row shows her in other player colours (team readability).
##   CALIMA_SHOT_DIR=/tmp/calima-hari $GODOT --path project \
##     --resolution 1400x900 res://tools/check_harimaguada_look.tscn

const HARI_SCENE: String = "res://scenes/units/harimaguada.tscn"
const VILLAGER_SCENE: String = "res://scenes/units/villager.tscn"
const HERO_DATA: String = "res://resources/units/hero_guayarmina.tres"
const COL_STEP: float = 110.0
const ROW_STEP: float = 130.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-hari"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.33, 0.42, 0.27))

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()

	# Row 0: villager(F) | harimaguada idle | harimaguada tending |
	#        harimaguada walking | heroine — all player 0 (blue).
	var villager: Node2D = _spawn(VILLAGER_SCENE, 0, Vector2(-2.0 * COL_STEP, -0.5 * ROW_STEP))
	villager.set("is_female", true)
	_spawn(HARI_SCENE, 0, Vector2(-1.0 * COL_STEP, -0.5 * ROW_STEP))
	var tending: Node2D = _spawn(HARI_SCENE, 0, Vector2(0.0, -0.5 * ROW_STEP))
	tending.set("current_state", 2)   # UnitState.ATTACKING — her tending pose
	var walking: Node2D = _spawn(HARI_SCENE, 0, Vector2(1.0 * COL_STEP, -0.5 * ROW_STEP))
	walking.set("current_state", 1)   # UnitState.MOVING — the walk sway
	_spawn_heroine(Vector2(2.0 * COL_STEP, -0.5 * ROW_STEP))

	# Row 1: her team readability in red / orange / green.
	var rivals: Array[int] = [1, 2, 4]
	for i: int in range(rivals.size()):
		_spawn(HARI_SCENE, rivals[i], Vector2((float(i) - 1.0) * COL_STEP, 0.5 * ROW_STEP))

	_run(cam)

func _spawn(path: String, player_id: int, screen_pos: Vector2) -> Node2D:
	var unit: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", "canarii")
	add_child(unit)
	unit.global_position = IsoProjection.screen_to_world(screen_pos)
	unit.set_physics_process(false)
	return unit

func _spawn_heroine(screen_pos: Vector2) -> void:
	var hero_data: UnitResource = load(HERO_DATA) as UnitResource
	var hero: Node2D = (load(HeroDress.scene_path_for(HERO_DATA)) as PackedScene).instantiate() as Node2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", hero_data)
	hero.set("player_id", 0)
	hero.set("civ_id", "canarii")
	hero.set("is_female", true)
	add_child(hero)
	hero.global_position = IsoProjection.screen_to_world(screen_pos)
	hero.set_physics_process(false)

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.8).timeout
	var shots: Array = [
		["hari_lineup", 1.7, Vector2(0.0, -0.5 * ROW_STEP)],
		["hari_close", 4.2, Vector2(-1.0 * COL_STEP, -0.5 * ROW_STEP)],
		["hari_poses", 3.2, Vector2(0.5 * COL_STEP, -0.5 * ROW_STEP)],
		["hari_teams", 3.0, Vector2(0.0, 0.5 * ROW_STEP)],
	]
	for shot: Array in shots:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(shot[2] as Vector2)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.25).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_HARIMAGUADA_LOOK: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

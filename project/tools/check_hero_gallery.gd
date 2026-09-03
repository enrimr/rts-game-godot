extends Node2D

## Visual review of the 16 hero signature dresses (real renderer): one row per
## civ — a plain civ-dressed militia for contrast, then the male and female
## hero — with name labels. Every hero must read apart from the militia and
## from every other hero at gameplay zoom.
##   CALIMA_SHOT_DIR=/tmp/calima-heroes $GODOT --path project \
##     --resolution 1600x1000 res://tools/check_hero_gallery.tscn

const CIVS: Array[String] = [
	"guanches", "canarii", "mahos", "franks",
	"britons", "castellanos", "atlantes", "fenicios",
]
const COL_STEP: float = 150.0
const ROW_STEP: float = 108.0
const GRID_LEFT: float = -140.0

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-heroes"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.30, 0.36, 0.24))

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()

	for row: int in range(CIVS.size()):
		var civ: String = CIVS[row]
		var y: float = (float(row) - float(CIVS.size() - 1) * 0.5) * ROW_STEP
		_label(civ.to_upper(), Vector2(GRID_LEFT - 160.0, y - 8.0))

		var militia: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
			.instantiate() as Node2D
		militia.set("player_id", 0)
		militia.set("civ_id", civ)
		add_child(militia)
		militia.global_position = IsoProjection.screen_to_world(Vector2(GRID_LEFT, y))
		militia.set_physics_process(false)

		var male_path: String = WorldSetup.HERO_MALE_DATA[civ] as String
		var female_path: String = WorldSetup.HERO_FEMALE_DATA[civ] as String
		_spawn_hero(male_path, civ, false, Vector2(GRID_LEFT + COL_STEP, y))
		_spawn_hero(female_path, civ, true, Vector2(GRID_LEFT + COL_STEP * 2.0, y))
		_label(_hero_name(male_path), Vector2(GRID_LEFT + COL_STEP - 34.0, y + 22.0))
		_label(_hero_name(female_path), Vector2(GRID_LEFT + COL_STEP * 2.0 - 34.0, y + 22.0))
	_spawn_duel()
	_run(cam)

## Two hostile heroes with physics ON below the grid: the attack swing must
## carry the signature gear with the Body rotation.
func _spawn_duel() -> void:
	var duel_y: float = float(CIVS.size()) * ROW_STEP * 0.5 + 130.0
	var a: Node2D = _make_hero(WorldSetup.HERO_MALE_DATA["guanches"] as String,
		"guanches", false, 0)
	var b: Node2D = _make_hero(WorldSetup.HERO_FEMALE_DATA["canarii"] as String,
		"canarii", true, 1)
	a.global_position = IsoProjection.screen_to_world(Vector2(-30.0, duel_y))
	b.global_position = IsoProjection.screen_to_world(Vector2(30.0, duel_y))
	_label("duel", Vector2(-10.0, duel_y + 24.0))

func _make_hero(data_path: String, civ: String, female: bool, pid: int) -> Node2D:
	var hero: CharacterBody2D = (load(HeroDress.scene_path_for(data_path)) as PackedScene)\
		.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", load(data_path))
	hero.set("player_id", pid)
	hero.set("civ_id", civ)
	hero.set("is_female", female)
	add_child(hero)
	return hero

func _hero_name(data_path: String) -> String:
	var data: UnitResource = load(data_path) as UnitResource
	return data.display_name if data != null else data_path.get_file()

func _spawn_hero(data_path: String, civ: String, female: bool, screen_pos: Vector2) -> void:
	var hero: CharacterBody2D = (load(HeroDress.scene_path_for(data_path)) as PackedScene)\
		.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", load(data_path))
	hero.set("player_id", 0)
	hero.set("civ_id", civ)
	hero.set("is_female", female)
	add_child(hero)
	hero.global_position = IsoProjection.screen_to_world(screen_pos)
	hero.set_physics_process(false)

func _label(text: String, screen_pos: Vector2) -> void:
	var label: Label = Label.new()
	label.text = text
	label.position = screen_pos
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.90))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 100
	add_child(label)
	IsoBillboard.make_upright(label)

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.9).timeout
	var heroes_x: float = GRID_LEFT + COL_STEP * 1.5
	var shots: Array = [
		["hero_gallery", 1.05, Vector2(-40.0, 0.0)],
		["hero_rows_top", 2.1, Vector2(10.0, -ROW_STEP * 2.5)],
		["hero_rows_bottom", 2.1, Vector2(10.0, ROW_STEP * 2.5)],
		["hero_close_01", 3.4, Vector2(heroes_x, -ROW_STEP * 3.0)],
		["hero_close_23", 3.4, Vector2(heroes_x, -ROW_STEP * 1.0)],
		["hero_close_45", 3.4, Vector2(heroes_x, ROW_STEP * 1.0)],
		["hero_close_67", 3.4, Vector2(heroes_x, ROW_STEP * 3.0)],
		["hero_duel", 4.0, Vector2(0.0, float(CIVS.size()) * ROW_STEP * 0.5 + 130.0)],
	]
	for shot: Array in shots:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(shot[2] as Vector2)
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.25).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_HERO_GALLERY: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

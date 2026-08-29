extends Node2D

## Visual review of the hero energy aura (real renderer, not headless):
## a hero and a heroine next to a plain militia for contrast, captured twice
## (the aura animates) at two zoom levels.
##   CALIMA_SHOT_DIR=/tmp/calima-aura $GODOT --path project --resolution 1000x700 \
##     res://tools/check_hero_aura.tscn

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("CHECK_HERO_AURA: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.26, 0.32, 0.20))

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()

	_spawn_hero("res://resources/units/hero_bencomo.tres", false, Vector2(-70.0, 0.0))
	_spawn_hero("res://resources/units/hero_dacil.tres", true, Vector2(0.0, 0.0))
	var militia: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	militia.set("player_id", 0)
	add_child(militia)
	militia.global_position = IsoProjection.screen_to_world(Vector2(70.0, 0.0))

	_run(cam)

func _spawn_hero(data_path: String, female: bool, screen_pos: Vector2) -> void:
	var hero: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", load(data_path))
	hero.set("player_id", 0)
	hero.set("civ_id", "guanches")
	hero.set("is_female", female)
	add_child(hero)
	hero.global_position = IsoProjection.screen_to_world(screen_pos)

func _run(cam: Camera2D) -> void:
	await get_tree().create_timer(0.8).timeout
	for shot: Array in [["aura_close", 5.0], ["aura_mid", 2.5]]:
		IsoProjection.apply_to_camera(cam, shot[1] as float)
		cam.global_position = IsoProjection.screen_to_world(Vector2(0.0, -8.0))
		cam.reset_physics_interpolation()
		await get_tree().create_timer(0.35).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, shot[0] as String])
		print("CHECK_HERO_AURA: saved %s.png" % (shot[0] as String))
	get_tree().quit(0)

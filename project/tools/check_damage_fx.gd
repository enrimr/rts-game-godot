extends Node2D

## Visual review of the building damage fire/smoke stages and the watch
## tower's arrow attack. Needs the real renderer (not --headless).
## Spawns four barracks at 100 / 70 / 45 / 15 % HP plus a tower shooting a
## target dummy, waits for the particles to develop and screenshots.
##   CALIMA_SHOT_DIR=/tmp/calima-fx $GODOT --path project --resolution 1400x900 \
##     res://tools/check_damage_fx.tscn

const COL_STEP: float = 240.0
const HP_RATIOS: Array[float] = [1.0, 0.7, 0.45, 0.15]

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("CHECK_DAMAGE_FX: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.24, 0.30, 0.18))

	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	IsoProjection.apply_to_camera(cam, 1.6)

	var packed: PackedScene = load("res://scenes/buildings/barracks.tscn") as PackedScene
	for i: int in range(HP_RATIOS.size()):
		var b: Node2D = packed.instantiate() as Node2D
		b.set("player_id", 0)
		add_child(b)
		b.global_position = IsoProjection.screen_to_world(Vector2(float(i) * COL_STEP, 0.0))
		b.call("force_complete")
		var max_hp: float = b.get("max_health") as float
		b.set("health", max_hp * HP_RATIOS[i])

	var tower: Node2D = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene).instantiate() as Node2D
	tower.set("player_id", 0)
	add_child(tower)
	tower.global_position = IsoProjection.screen_to_world(Vector2(1.0 * COL_STEP, 220.0))
	tower.call("force_complete")
	var dummy: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	dummy.set("player_id", 1)
	add_child(dummy)
	dummy.global_position = tower.global_position + Vector2(140.0, 40.0)

	cam.global_position = IsoProjection.screen_to_world(Vector2(COL_STEP * 1.5, 90.0))
	_run(cam)

func _run(cam: Camera2D) -> void:
	# Let the damage FX poll, ignite and develop a few plumes, and the tower
	# loose a couple of arrows.
	await get_tree().create_timer(2.5).timeout
	await get_tree().process_frame
	cam.reset_physics_interpolation()
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/damage_fx.png" % _shot_dir)
	print("CHECK_DAMAGE_FX: saved damage_fx.png")
	get_tree().quit(0)

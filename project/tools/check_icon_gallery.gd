extends Node2D

## Icon-bake gallery: runs IconBaker over EVERY unit and building scene the
## HUD can put on a button and saves each result to CALIMA_SHOT_DIR, flagging
## any icon that still equals the placeholder (the "rombo" bug) after the
## bake settles. Real renderer required.
##
##   CALIMA_SHOT_DIR=/tmp/calima-icons $GODOT --path project --resolution 800x600 \
##     res://tools/check_icon_gallery.tscn

const WAIT_FRAMES: int = 180

func _ready() -> void:
	var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if shot_dir.is_empty():
		shot_dir = "/tmp/calima-icons"
	DirAccess.make_dir_recursive_absolute(shot_dir)

	# CALIMA_ICONS_MATCH=1 reproduces the in-game bake: a real Islands match is
	# booted first, so TerrainManager has zones and the map centre — where the
	# bake viewport's local (0,0) lands — is very likely OCEAN. Any per-frame
	# unit logic that reads world state (terrain containment!) now fires on
	# the icon prop exactly like it does mid-match.
	if OS.get_environment("CALIMA_ICONS_MATCH") == "1":
		OS.set_environment("CALIMA_SEED", "4242")
		MatchConfig.map_type = MatchConfig.MapType.ISLANDS
		MatchConfig.weather_enabled = false
		MatchConfig.rival_count = 1
		var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene)\
			.instantiate() as Node2D
		add_child(world)
		for _i: int in range(30):
			await get_tree().physics_frame
		IconBaker.clear_cache()
		print("  match booted: centre terrain ocean=%s" % TerrainManager.is_ocean(Vector2.ZERO))

	var paths: Array[String] = []
	for dir_name: String in ["res://scenes/units", "res://scenes/buildings"]:
		for f: String in DirAccess.get_files_at(dir_name):
			if f.ends_with(".tscn"):
				paths.append(dir_name + "/" + f)

	# Never bake from inside _ready: the root is still assembling children.
	await get_tree().process_frame

	var placeholder: Image = null
	var failed: Array[String] = []
	for path: String in paths:
		var tex: Texture2D = IconBaker.get_icon(path, 0)
		if placeholder == null:
			placeholder = (tex as ImageTexture).get_image().duplicate()
		# Poll until the bake lands (slow tails under load) or give up.
		var img: Image = (tex as ImageTexture).get_image()
		for _i: int in range(WAIT_FRAMES):
			await get_tree().process_frame
			img = (tex as ImageTexture).get_image()
			if not _same_image(img, placeholder):
				break
		var name: String = path.get_file().get_basename()
		img.save_png("%s/icon_%s.png" % [shot_dir, name])
		if _same_image(img, placeholder):
			failed.append(name)
			print("  PLACEHOLDER (rombo): %s  [tree.paused=%s gm.state=%d]" % [
				path, get_tree().paused, GameManager.state])
		else:
			print("  ok: %s" % name)

	# Hero icons bake from configured mannequins, not their shared rig scene:
	# the miniature must show THE hero (dress, mount, gender), not a militia.
	for hero_cfg: Array in [["res://resources/units/hero_doramas.tres", false],
			["res://resources/units/hero_guayarmina.tres", true],
			["res://resources/units/hero_quijote.tres", false]]:
		var data_path: String = hero_cfg[0] as String
		var rig: Node2D = (load(HeroDress.scene_path_for(data_path)) as PackedScene)\
			.instantiate() as Node2D
		rig.set_script(load("res://scripts/units/hero_unit.gd"))
		rig.set("unit_data", load(data_path))
		rig.set("player_id", 0)
		rig.set("is_female", hero_cfg[1] as bool)
		add_child(rig)
		rig.position = Vector2(-4000, -4000)
		var htex: Texture2D = IconBaker.get_icon_for(rig, 0)
		var hname: String = data_path.get_file().get_basename()
		var himg: Image = (htex as ImageTexture).get_image()
		for _i: int in range(WAIT_FRAMES):
			await get_tree().process_frame
			himg = (htex as ImageTexture).get_image()
			if not _same_image(himg, placeholder):
				break
		himg.save_png("%s/icon_%s.png" % [shot_dir, hname])
		if _same_image(himg, placeholder):
			failed.append(hname)
			print("  PLACEHOLDER (rombo): %s" % hname)
		else:
			print("  ok: %s" % hname)
		rig.queue_free()

	print("ICON_GALLERY: %d scenes, %d stuck on the placeholder" % [paths.size(), failed.size()])
	if not failed.is_empty():
		print("ICON_GALLERY failed: %s" % ", ".join(failed))
	get_tree().quit(0 if failed.is_empty() else 1)

func _same_image(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	return a.save_png_to_buffer() == b.save_png_to_buffer()

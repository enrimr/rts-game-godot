extends Node

## Visual review of the main-menu replay browser (real renderer): seeds fake
## replay headers — one with an absurdly long roster — boots the real menu,
## opens the panel and screenshots it to CALIMA_SHOT_DIR (default
## /tmp/calima-replays). The seeded files are deleted before quitting.

const HARNESS_PREFIX: String = "replay_harness_"

func _ready() -> void:
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-replays"
	DirAccess.make_dir_recursive_absolute(dir)

	_seed_fake_replay("%s1%s" % [HARNESS_PREFIX, ReplayFile.EXT], ["castellanos"], 100)
	_seed_fake_replay("%s2%s" % [HARNESS_PREFIX, ReplayFile.EXT],
		["castellanos", "franks", "atlantes", "fenicios", "britons",
			"guanches", "mahos"], 200)

	var menu: Control = (load("res://scenes/game/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(0.6).timeout
	menu.call("_open_replays_panel")
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/replays_panel.png")

	_delete_seeded()
	print("REPLAYS_PANEL: saved 1 shot to %s" % dir)
	get_tree().quit(0)

func _seed_fake_replay(fname: String, rivals: Array, ts: int) -> void:
	DirAccess.make_dir_recursive_absolute(ReplayFile.DIR)
	var f: FileAccess = FileAccess.open_compressed(ReplayFile.DIR + fname,
		FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var({
		"format": ReplayFile.FORMAT_VERSION,
		"timestamp": ts,
		"config": {"player_civ_id": "atlantes", "rival_civ_ids": rivals},
	})
	f.close()

func _delete_seeded() -> void:
	var d: DirAccess = DirAccess.open(ReplayFile.DIR)
	if d == null:
		return
	d.list_dir_begin()
	var fname: String = d.get_next()
	while not fname.is_empty():
		if fname.begins_with(HARNESS_PREFIX):
			d.remove(fname)
		fname = d.get_next()
	d.list_dir_end()

extends Control

## Repro harness: prebakes every contextual cursor and cycles each one through
## Input.set_custom_mouse_cursor — the macOS DisplayServer rejects invalid
## cursor images with 'Parameter "imgrep" is null', so any bad bake shows up
## here deterministically.
## Run: $GODOT --path project --resolution 640x480 res://tools/check_cursor_cycle.tscn

func _ready() -> void:
	_run()

func _run() -> void:
	CursorManager.prebake()
	# Give the async bakes generous time to complete.
	await get_tree().create_timer(2.0).timeout
	var ids: Array = CursorManager.CONTEXT_IDS.duplicate()
	ids.append("default")
	for pass_n: int in range(2):
		for id: String in ids:
			print("CHECK_CURSOR_CYCLE: applying '", id, "' (baked=",
				CursorManager._textures.has(id), ")")
			CursorManager.set_context(id as String)
			await get_tree().process_frame
			await get_tree().process_frame
	# Also exercise the mid-bake path: clear and re-apply before bakes finish.
	CursorManager._textures.clear()
	CursorManager.current_id = "default"
	CursorManager.prebake()
	for id: String in ids:
		CursorManager.set_context(id as String)
		await get_tree().process_frame
	# Dump the baked cursor images for visual review when a dir is given.
	var dump_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if not dump_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dump_dir)
		await get_tree().create_timer(1.0).timeout
		for id: String in CursorManager._images.keys():
			var img: Image = CursorManager._images[id] as Image
			img.save_png(dump_dir.path_join("cursor_" + id + ".png"))
		print("CHECK_CURSOR_CYCLE: dumped ", CursorManager._images.size(), " cursors")
	print("CHECK_CURSOR_CYCLE: done")
	get_tree().quit(0)

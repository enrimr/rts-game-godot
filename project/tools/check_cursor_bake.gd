extends Node2D

## Visual check: dumps every baked contextual mouse cursor as a PNG so the
## 32 px glyph, dark outline backing and downscale quality can be reviewed 1:1.
## Run (real renderer):
##   CALIMA_SHOT_DIR=/tmp/calima-cursors $GODOT --path project \
##     --resolution 400x300 res://tools/check_cursor_bake.tscn

func _ready() -> void:
	var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if shot_dir.is_empty():
		push_error("CHECK_CURSOR_BAKE: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	_run(shot_dir)

func _run(shot_dir: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	CursorManager.prebake()
	# Bakes fill in asynchronously; give the deferred SubViewport chains headroom.
	await get_tree().create_timer(2.5).timeout
	var failed: bool = false
	for id: String in CursorManager.CONTEXT_IDS:
		var tex: Texture2D = CursorManager._textures.get(id) as Texture2D
		if tex == null:
			push_error("CHECK_CURSOR_BAKE: no texture baked for '%s'" % id)
			failed = true
			continue
		var out: String = shot_dir.path_join("cursor_" + id + ".png")
		tex.get_image().save_png(out)
		print("CHECK_CURSOR_BAKE: saved ", out)
	get_tree().quit(1 if failed else 0)

extends Control

## Visual check: renders the match-creation lobby and saves a PNG so layout
## fixes can be reviewed at any window size.
## Run (real renderer):
##   CALIMA_SHOT_DIR=/tmp/calima-lobby $GODOT --path project \
##     --resolution 1280x720 res://tools/check_lobby.tscn

func _ready() -> void:
	var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if shot_dir.is_empty():
		push_error("CHECK_LOBBY: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var rivals_env: String = OS.get_environment("CALIMA_RIVALS")
	if not rivals_env.is_empty():
		MatchConfig.rival_count = int(rivals_env)
	# The scene-root Control does not auto-size to the window in this headed
	# tool context — force the rect after layout settles (deferred, or the
	# anchor pass overrides it right back to zero).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport().get_visible_rect().size)
	var lobby: Control = LobbyScreen.new()
	add_child(lobby)
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run(shot_dir)

func _run(shot_dir: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var lobby: Control = get_child(0) as Control
	print("CHECK_LOBBY: self=", size, " lobby=", lobby.size,
		" children=", lobby.get_child_count(), " visible=", lobby.visible)
	for c: Node in lobby.get_children():
		if c is Control:
			print("CHECK_LOBBY:   child ", c.get_class(), " size=", (c as Control).size,
				" vis=", (c as Control).visible)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = shot_dir.path_join("lobby.png")
	if img.save_png(path) == OK:
		print("CHECK_LOBBY: saved ", path)
	get_tree().quit(0)

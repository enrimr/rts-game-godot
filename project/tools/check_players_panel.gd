extends Node2D

## Players-panel review harness (real renderer): boots a 3-player match,
## opens the minimap players overlay and screenshots it.
##   CALIMA_SHOT_DIR=/tmp/calima-players $GODOT --path project \
##     --resolution 1600x900 res://tools/check_players_panel.tscn

func _ready() -> void:
	var shot_dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if shot_dir.is_empty():
		shot_dir = "/tmp/calima-players"
	DirAccess.make_dir_recursive_absolute(shot_dir)
	OS.set_environment("CALIMA_SEED", "4242")
	MatchConfig.map_type = MatchConfig.MapType.STANDARD
	MatchConfig.rival_count = 2
	MatchConfig.weather_enabled = false
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene)\
		.instantiate() as Node2D
	add_child(world)
	for _i: int in range(90):
		await get_tree().process_frame
	var panel: HudPlayersPanel = _find_panel(world)
	if panel == null:
		print("CHECK_PLAYERS_PANEL: FAIL — panel not mounted")
		get_tree().quit(1)
		return
	(panel.get("_toggle") as Button).button_pressed = true
	for _i: int in range(30):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(shot_dir + "/players_panel.png")
	print("CHECK_PLAYERS_PANEL: saved %s/players_panel.png rows=%d" % [shot_dir,
		(panel.get("_rows_box") as VBoxContainer).get_child_count()])
	get_tree().quit(0)

func _find_panel(root: Node) -> HudPlayersPanel:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is HudPlayersPanel:
			return n as HudPlayersPanel
		for c: Node in n.get_children():
			stack.append(c)
	return null

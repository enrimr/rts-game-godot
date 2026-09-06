extends Node

func _ready() -> void:
	print("REPLAY_INTRO: watcher ready")
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-replay-intro"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.4).timeout
	print("REPLAY_INTRO: first shot")
	get_viewport().get_texture().get_image().save_png(dir + "/intro_card.png")
	# Select something recorded and prove the panel offers no commands.
	await get_tree().create_timer(3.0).timeout
	var world: Node = get_tree().get_first_node_in_group("world")
	if world != null:
		var hud: Node = world.get("hud")
		# Early replay: the player's only building is the TC (world.drop_off,
		# not a buildings_layer child).
		var target: Node = null
		for b: Node in (world.get("buildings_layer") as Node).get_children():
			if b.get("player_id") != null and (b.get("player_id") as int) == 0:
				target = b
				break
		if target == null:
			target = world.get("drop_off") as Node
		print("REPLAY_INTRO: selecting %s" % target.name)
		hud.call("_on_building_selected", target)
		await get_tree().create_timer(0.4).timeout
		var name_lbl: Label = (hud as Node).get_node("%UnitNameLabel") as Label
		print("REPLAY_INTRO: name_label='%s' visible=%s sel=%s" % [
			name_lbl.text, str(name_lbl.is_visible_in_tree()),
			str((hud as Node).get("_selected_building"))])
		get_viewport().get_texture().get_image().save_png(dir + "/selected_building.png")
	print("REPLAY_INTRO: saved shots")
	get_tree().quit(0)

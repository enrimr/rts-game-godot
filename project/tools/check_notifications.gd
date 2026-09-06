extends Node2D

## Visual review of notification toasts + their shortcut action buttons
## (real renderer): pushes one of each actionable kind and screenshots.
## CALIMA_SHOT_DIR=/tmp/calima-notifs (default)

func _ready() -> void:
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-notifs"
	DirAccess.make_dir_recursive_absolute(dir)
	var hud: CanvasLayer = (load("res://scenes/ui/hud/hud.tscn") as PackedScene)\
		.instantiate() as CanvasLayer
	add_child(hud)
	await get_tree().create_timer(0.4).timeout
	var nd: NotificationDisplay = null
	for child: Node in hud.get_node("HUDRoot").get_children():
		if child is NotificationDisplay:
			nd = child as NotificationDisplay
			break
	nd.push(tr("NOTIF_UNIT_ATTACK"), Color(1.0, 0.38, 0.28), 30.0, Vector2(100, 100))
	nd.push(tr("NOTIF_POP_CAP"), Color(1.0, 0.70, 0.25), 30.0, null, {
		"icon": "build", "tooltip": tr("NOTIF_ACTION_BUILD_HOUSE"),
		"callback": Callable()})
	nd.push(tr("NOTIF_HERO_LOW_HP"), Color(1.0, 0.20, 0.20), 30.0, null, {
		"icon": "locate_hero", "tooltip": tr("UI_LOCATE_HERO"),
		"callback": Callable()})
	nd.push(tr("NOTIF_AGE_COMPLETE") % "Feudal", Color(1.0, 0.92, 0.30), 30.0)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/notifications.png")
	print("NOTIFICATIONS: saved 1 shot to %s" % dir)
	get_tree().quit(0)

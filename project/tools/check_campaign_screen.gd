extends Node2D

## Visual review of the campaign selector + briefing (real renderer):
## screenshots to CALIMA_SHOT_DIR (default /tmp/calima-campaign).

func _ready() -> void:
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-campaign"
	DirAccess.make_dir_recursive_absolute(dir)
	var screen: CampaignScreen = CampaignScreen.new()
	add_child(screen)
	# Under a Node2D harness nothing sizes the Control; the real menu parents
	# it to a full-rect Control.
	screen.size = get_viewport().get_visible_rect().size
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/campaign_select.png")
	screen.call("_open_briefing", 0)
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/campaign_briefing.png")
	print("CAMPAIGN_SCREEN: saved 2 shots to %s" % dir)
	get_tree().quit(0)

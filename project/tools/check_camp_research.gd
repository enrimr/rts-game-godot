extends Node2D

## Visual review of the camp economy research buttons (real renderer): boots
## the HUD, selects a Lumber Camp / Mining Camp / Mill at the Imperial Age and
## screenshots the action panel — the three-step lines must show their glyphs.
## CALIMA_SHOT_DIR=/tmp/calima-camp-research (default)

const CAMPS: Array = [
	["lumber_camp", "res://scenes/buildings/lumber_camp.tscn"],
	["mining_camp", "res://scenes/buildings/mining_camp.tscn"],
	["mill", "res://scenes/buildings/mill.tscn"],
	["temple", "res://scenes/buildings/temple.tscn"],
	["barracks", "res://scenes/buildings/barracks.tscn"],
	["town_center", "res://scenes/buildings/town_center.tscn"],
]

func _ready() -> void:
	var dir: String = OS.get_environment("CALIMA_SHOT_DIR")
	if dir.is_empty():
		dir = "/tmp/calima-camp-research"
	DirAccess.make_dir_recursive_absolute(dir)

	ResourceManager.init_player(0,
		{"food": 9999, "wood": 9999, "gold": 9999, "stone": 9999})
	AgeManager.init_player(0, GameManager.Age.IMPERIAL)
	TechManager.init_player(0)
	CivBonusManager.init_player(0, "guanches")

	# The HudManager script sits on the HUD scene root itself.
	var mgr: CanvasLayer = (load("res://scenes/ui/hud/hud.tscn") as PackedScene)\
		.instantiate() as CanvasLayer
	add_child(mgr)
	await get_tree().create_timer(0.4).timeout

	for def: Array in CAMPS:
		var camp: Node2D = (load(def[1] as String) as PackedScene).instantiate() as Node2D
		camp.set("player_id", 0)
		camp.position = Vector2(320, 200)
		add_child(camp)
		camp.call("force_complete")
		await get_tree().process_frame
		mgr.call("_on_building_selected", camp)
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png(
			"%s/research_%s.png" % [dir, def[0] as String])
		camp.queue_free()
		await get_tree().process_frame

	print("CAMP_RESEARCH: saved %d shots to %s" % [CAMPS.size(), dir])
	get_tree().quit(0)

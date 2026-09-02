extends Node2D

## Campaign mission gate (headless): launches mission 1 for real — the
## deterministic world boots, the MissionDirector mounts with its objective
## panel, the first scripted wave spawns and marches, and a player victory
## marks the mission completed (unlocking mission 2). Progress on disk is
## backed up and restored, so the gate never touches real campaign saves.
## (Mission indices: 0 = tutorial prologue, 1 = La Vanguardia.)

var _backup: PackedByteArray = PackedByteArray()
var _had_progress: bool = false

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("CAMPAIGN: TIMEOUT")
		_restore_progress()
		get_tree().quit(1))
	_had_progress = FileAccess.file_exists(CampaignManager.SAVE_PATH)
	if _had_progress:
		_backup = FileAccess.get_file_as_bytes(CampaignManager.SAVE_PATH)
	CampaignManager.reset_progress()
	CampaignManager.auto_change_scene = false
	if not CampaignManager.launch_mission(1):
		return _fail("mission 1 refused to launch")
	MatchConfig.weather_enabled = false
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var director: MissionDirector = world.get_node_or_null("MissionDirector") as MissionDirector
	if director == null:
		return _fail("MissionDirector not mounted")
	print("CAMPAIGN: director mounted, %d objectives, %d waves pending" % [
		director.objectives().size(), director._pending_waves.size()])

	# Mission 1 authors its own pressure: the AI brain must hold its attacks.
	var held: bool = false
	for child: Node in world.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path.contains("ai_player"):
			held = child.get("offense_held") as bool
	if not held:
		return _fail("the AI's offense is not held on mission 1")
	print("CAMPAIGN: AI offense held (scripted waves are the only pressure)")

	# Fast-forward to the first wave and verify it marches.
	var before: int = _units_of_player(world, 1)
	director._elapsed = 299.0
	await get_tree().create_timer(1.5).timeout
	var after: int = _units_of_player(world, 1)
	if after <= before:
		return _fail("wave did not spawn (units %d -> %d)" % [before, after])
	print("CAMPAIGN: wave landed (+%d enemy units)" % (after - before))

	# Player victory must complete the mission and unlock the next one.
	GameManager.declare_winner(0)
	await get_tree().create_timer(0.5).timeout
	if not CampaignManager.is_completed(1) or not CampaignManager.is_unlocked(2):
		return _fail("victory did not record progress")
	print("CAMPAIGN: mission 1 completed, mission 2 unlocked")
	_restore_progress()
	print("CAMPAIGN: done")
	get_tree().quit(0)

func _units_of_player(world: Node2D, pid: int) -> int:
	var count: int = 0
	for unit: Node in (world.get("units_layer") as Node).get_children():
		if is_instance_valid(unit) and unit.get("player_id") != null \
				and (unit.get("player_id") as int) == pid:
			count += 1
	return count

func _fail(reason: String) -> void:
	print("CAMPAIGN: FAIL — %s" % reason)
	_restore_progress()
	get_tree().quit(1)

func _restore_progress() -> void:
	if _had_progress:
		var f: FileAccess = FileAccess.open(CampaignManager.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(CampaignManager.SAVE_PATH)
	CampaignManager._completed.clear()
	CampaignManager._load()

extends Node

## Visual review of the replay intro card (real renderer): boots the newest
## recorded replay via ReplayFile.launch; a ROOT-parented watcher survives the
## scene swap and screenshots the title card (~1.4 s) plus a later frame with
## an own building selected — info panel yes, action grid EMPTY (recorded
## history). CALIMA_SHOT_DIR=/tmp/calima-replay-intro (default)

func _ready() -> void:
	# Root is busy setting up this scene during _ready — defer the whole start.
	_start.call_deferred()

func _start() -> void:
	var replays: Array[Dictionary] = ReplayFile.list_replays()
	if replays.is_empty():
		print("REPLAY_INTRO: no replays on disk — SKIP")
		get_tree().quit(0)
		return
	var watcher: Node = Node.new()
	watcher.set_script(load("res://tools/check_replay_intro_watcher.gd"))
	get_tree().root.add_child(watcher)
	ReplayFile.launch(str(replays[0].get("path", "")), get_tree())

extends Node

## Marketing beauty shots (real renderer): boots a recorded replay in
## CINEMATIC mode (run with CALIMA_CINE=1 for clean fog-revealed frames),
## seeks through the match, auto-frames the camera on the ACTION (closest
## hostile contact, else touring each player's densest crowd) and screenshots
## each moment at the window resolution (use --resolution 1920x1080 for Steam).
## Scan mode (CALIMA_MKT_SCAN=1) samples the whole replay instead and prints
## one line per step — closest hostile distance, its midpoint, army sizes —
## to locate battle windows for clip export (CALIMA_CINE_CAM frames those).
## Env: CALIMA_MKT_REPLAY (path; default = newest replay on disk),
##      CALIMA_MKT_TIMES  (comma-separated seconds; default = spread),
##      CALIMA_MKT_ZOOM   (camera zoom, e.g. 1.6),
##      CALIMA_MKT_SCAN=1 + CALIMA_MKT_STEP (scan stride, default 120 s),
##      CALIMA_SHOT_DIR   (default /tmp/calima-marketing).
## Full asset pipeline: docs/marketing/steam_campaign.md

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	var path: String = OS.get_environment("CALIMA_MKT_REPLAY")
	if path.is_empty():
		var replays: Array[Dictionary] = ReplayFile.list_replays()
		if replays.is_empty():
			print("MARKETING_SHOTS: no replays — SKIP")
			get_tree().quit(0)
			return
		path = str(replays[0].get("path", ""))
	var watcher: Node = Node.new()
	watcher.set_script(load("res://tools/check_marketing_shots_watcher.gd"))
	get_tree().root.add_child(watcher)
	ReplayFile.launch(path, get_tree())

extends Node

## CampaignManager (autoload) — campaign progress and mission launching.
## Progress (which missions are completed) persists in user://campaign.cfg;
## a mission unlocks when the previous one is completed. Launching a mission
## writes its whole MatchConfig (fixed seed → deterministic world) and flags
## `MatchConfig.campaign_mission`, which makes GameWorld mount the
## MissionDirector. Campaign is single-player only: every multiplayer or
## skirmish start resets the flag.

const SAVE_PATH: String = "user://campaign.cfg"

signal progress_changed

var _completed: Dictionary = {}   # mission index -> true
## Harnesses flip this off to boot the world themselves.
var auto_change_scene: bool = true

func _ready() -> void:
	_load()

func is_completed(index: int) -> bool:
	return _completed.get(index, false) as bool

func is_unlocked(index: int) -> bool:
	return index == 0 or is_completed(index - 1)

func first_playable() -> int:
	for i: int in range(CampaignData.size()):
		if not is_completed(i):
			return i
	return CampaignData.size() - 1

func mark_completed(index: int) -> void:
	if index < 0 or is_completed(index):
		return
	_completed[index] = true
	_save()
	progress_changed.emit()

## Debug/testing helper — wipes the campaign progress.
func reset_progress() -> void:
	_completed.clear()
	_save()
	progress_changed.emit()

func launch_mission(index: int) -> bool:
	var m: Dictionary = CampaignData.mission(index)
	if m.is_empty() or not is_unlocked(index):
		return false
	MatchConfig.forced_seed = m["seed"] as int
	MatchConfig.map_type = m["map_type"] as int
	MatchConfig.map_size = m["map_size"] as int
	MatchConfig.resources = m["resources"] as int
	MatchConfig.player_civ_id = m["player_civ"] as String
	var civs: Array[String] = []
	for c: Variant in m["rival_civs"] as Array:
		civs.append(c as String)
	MatchConfig.rival_civ_ids = civs
	MatchConfig.rival_count = civs.size()
	MatchConfig.starting_age = m["starting_age"] as int
	MatchConfig.victory_mode = MatchConfig.VictoryMode.REGICIDE \
		if (m["victory"] as String) == "regicide" else MatchConfig.VictoryMode.CONQUEST
	MatchConfig.weather_enabled = m.get("weather", false) as bool
	MatchConfig.player_teams.clear()
	MatchConfig.launch_tutorial = false
	MatchConfig.campaign_mission = index
	if auto_change_scene:
		get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")
	return true

func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	for index: Variant in _completed:
		cfg.set_value("completed", str(index), true)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("completed"):
		return
	for key: String in cfg.get_section_keys("completed"):
		_completed[int(key)] = true

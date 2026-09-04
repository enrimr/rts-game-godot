extends Node

## GameSettings — persists audio volumes and AI difficulty across scenes.
## Saved to user://settings.cfg via ConfigFile.

const SAVE_PATH: String = "user://settings.cfg"

enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2, TUTORIAL = 3 }

var music_volume:        float  = 1.0    # 0.0 – 1.0 linear
var sfx_volume:          float  = 1.0    # 0.0 – 1.0 linear
var difficulty:          int    = Difficulty.NORMAL
## Record every authoritative match (SP and MP host) as a watchable replay.
var record_replays:      bool   = true
var language:            String = "en"
var tutorial_seen:       bool   = false
var show_dpad:           bool   = false
var edge_scroll_enabled: bool   = true
var fullscreen:          bool   = false
var vsync:               bool   = true
var show_fps:            bool   = false
## Custom camera-pan keys (action name -> keycode). Arrows always work too.
var pan_keys:            Dictionary = {}

const PAN_ACTIONS: Dictionary = {
	"camera_pan_left": KEY_A, "camera_pan_right": KEY_D,
	"camera_pan_up": KEY_W, "camera_pan_down": KEY_S,
}
const PAN_ARROWS: Dictionary = {
	"camera_pan_left": KEY_LEFT, "camera_pan_right": KEY_RIGHT,
	"camera_pan_up": KEY_UP, "camera_pan_down": KEY_DOWN,
}

func apply_video() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

## Rebinds the four pan actions: the letter key is replaceable, the arrow
## stays as a fixed secondary binding.
func apply_pan_keys() -> void:
	for action: String in PAN_ACTIONS:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = pan_keys.get(action, PAN_ACTIONS[action]) as Key
		InputMap.action_add_event(action, key_event)
		var arrow: InputEventKey = InputEventKey.new()
		arrow.physical_keycode = PAN_ARROWS[action] as Key
		InputMap.action_add_event(action, arrow)

func set_pan_key(action: String, keycode: int) -> void:
	pan_keys[action] = keycode
	apply_pan_keys()
	save_settings()

func pan_key_name(action: String) -> String:
	return OS.get_keycode_string(pan_keys.get(action, PAN_ACTIONS[action]) as Key)
var ai_debug:            bool   = false  # toggled with F2 in-game

func _ready() -> void:
	call_deferred("apply_video")
	call_deferred("apply_pan_keys")
	load_settings()
	apply_language()

# ---------------------------------------------------------------------------
# Difficulty helpers (read by AIPlayer)
# ---------------------------------------------------------------------------

func get_ai_villager_target() -> int:
	match difficulty:
		Difficulty.TUTORIAL: return 2
		Difficulty.EASY:     return 5
		Difficulty.HARD:     return 12
	return 8  # NORMAL

func get_ai_military_target_passive() -> int:
	match difficulty:
		Difficulty.TUTORIAL: return 1
		Difficulty.EASY:     return 3
		Difficulty.HARD:     return 8
	return 5

func get_ai_attack_interval() -> float:
	match difficulty:
		Difficulty.TUTORIAL: return 180.0
		Difficulty.EASY:     return 60.0
		Difficulty.HARD:     return 18.0
	return 30.0

func get_ai_min_attack_units() -> int:
	match difficulty:
		Difficulty.TUTORIAL: return 10
		Difficulty.EASY:     return 5
		Difficulty.HARD:     return 2
	return 3

func get_ai_tick_interval() -> float:
	match difficulty:
		Difficulty.TUTORIAL: return 8.0
		Difficulty.EASY:     return 4.0
		Difficulty.HARD:     return 1.5
	return 2.0

func get_ai_age_advance_min_military() -> int:
	match difficulty:
		Difficulty.TUTORIAL: return 6
		Difficulty.EASY:     return 5
		Difficulty.HARD:     return 2
	return 3

func get_ai_aggression_decay() -> float:
	match difficulty:
		Difficulty.TUTORIAL: return 8.0
		Difficulty.EASY:     return 12.0
		Difficulty.HARD:     return 30.0
	return 20.0

# ---------------------------------------------------------------------------
# Volume helpers (read by AudioManager)
# ---------------------------------------------------------------------------

func volume_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio",    "music_volume",        music_volume)
	cfg.set_value("audio",    "sfx_volume",          sfx_volume)
	# TUTORIAL is transient match state, never a preference: quitting the
	# tutorial mid-lesson left it active, any settings save persisted it,
	# and every later match ran with half-HP rivals forever.
	cfg.set_value("game", "difficulty",
		difficulty if difficulty != Difficulty.TUTORIAL else Difficulty.NORMAL)
	cfg.set_value("game",     "language",            language)
	cfg.set_value("game",     "record_replays",      record_replays)
	cfg.set_value("game",     "tutorial_seen",       tutorial_seen)
	cfg.set_value("controls", "show_dpad",           show_dpad)
	cfg.set_value("controls", "edge_scroll_enabled", edge_scroll_enabled)
	cfg.set_value("controls", "pan_keys",            pan_keys)
	cfg.set_value("video",    "fullscreen",          fullscreen)
	cfg.set_value("video",    "vsync",               vsync)
	cfg.set_value("video",    "show_fps",            show_fps)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	music_volume        = cfg.get_value("audio",    "music_volume",        1.0) as float
	sfx_volume          = cfg.get_value("audio",    "sfx_volume",          1.0) as float
	difficulty          = cfg.get_value("game",     "difficulty",          Difficulty.NORMAL) as int
	# Heal configs already poisoned by the persisted-TUTORIAL bug.
	if difficulty == Difficulty.TUTORIAL:
		difficulty = Difficulty.NORMAL
	language            = cfg.get_value("game",     "language",            "en") as String
	record_replays      = cfg.get_value("game",     "record_replays",      true) as bool
	tutorial_seen       = cfg.get_value("game",     "tutorial_seen",       false) as bool
	show_dpad           = cfg.get_value("controls", "show_dpad",           false) as bool
	edge_scroll_enabled = cfg.get_value("controls", "edge_scroll_enabled", true) as bool
	pan_keys            = cfg.get_value("controls", "pan_keys",            {}) as Dictionary
	fullscreen          = cfg.get_value("video",    "fullscreen",          false) as bool
	vsync               = cfg.get_value("video",    "vsync",               true) as bool
	show_fps            = cfg.get_value("video",    "show_fps",            false) as bool
	apply_language()

func apply_language() -> void:
	TranslationServer.set_locale(language)

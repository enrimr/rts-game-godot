extends Node

## GameSettings — persists audio volumes and AI difficulty across scenes.
## Saved to user://settings.cfg via ConfigFile.

const SAVE_PATH: String = "user://settings.cfg"

enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2, TUTORIAL = 3 }

var music_volume:   float = 1.0    # 0.0 – 1.0 linear
var sfx_volume:     float = 1.0    # 0.0 – 1.0 linear
var difficulty:     int   = Difficulty.NORMAL
var language:       String = "en"
var tutorial_seen:  bool  = false

func _ready() -> void:
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
	cfg.set_value("audio", "music_volume",  music_volume)
	cfg.set_value("audio", "sfx_volume",    sfx_volume)
	cfg.set_value("game",  "difficulty",    difficulty)
	cfg.set_value("game",  "language",      language)
	cfg.set_value("game",  "tutorial_seen", tutorial_seen)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	music_volume  = cfg.get_value("audio", "music_volume",  1.0) as float
	sfx_volume    = cfg.get_value("audio", "sfx_volume",    1.0) as float
	difficulty    = cfg.get_value("game",  "difficulty",    Difficulty.NORMAL) as int
	language      = cfg.get_value("game",  "language",      "en") as String
	tutorial_seen = cfg.get_value("game",  "tutorial_seen", false) as bool
	apply_language()

func apply_language() -> void:
	TranslationServer.set_locale(language)

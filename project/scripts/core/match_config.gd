extends Node

## MatchConfig — holds the settings chosen in the lobby screen.
## Written before loading game_world, read during _ready().

enum MapSize      { SMALL = 0, MEDIUM = 1, LARGE = 2 }
enum Resources    { SCARCE = 0, NORMAL = 1, ABUNDANT = 2, FULL_COMBAT = 3, TUTORIAL = 4 }
enum MapType      { PLAINS = 0, STANDARD = 1, VOLCANIC_COAST = 2, DESERT_COAST = 3, ISLANDS = 4 }
enum VictoryMode  { CONQUEST = 0, REGICIDE = 1, WONDER = 2 }

# Chosen by the player in the lobby
var map_size:          int    = MapSize.MEDIUM
var resources:         int    = Resources.NORMAL
var map_type:          int    = MapType.PLAINS
var player_civ_id:     String = "guanches"
var starting_age:      int    = 0           # GameManager.Age
var victory_mode:      int    = VictoryMode.CONQUEST
var launch_tutorial:   bool   = false

# Multi-rival support: rival_civ_ids[0] = first rival, etc.
var rival_count:    int            = 1
var rival_civ_ids:  Array[String]  = ["castellanos"]

# Compatibility accessor — first rival's civ id
var rival_civ_id: String:
	get:
		return rival_civ_ids[0] if rival_civ_ids.size() > 0 else "castellanos"
	set(v):
		if rival_civ_ids.is_empty():
			rival_civ_ids.append(v)
		else:
			rival_civ_ids[0] = v

# Map size → MAP_HALF px
const MAP_HALF_BY_SIZE: Array[float] = [1200.0, 1800.0, 2600.0]

# Resources multiplier on deposit count and amount (FULL_COMBAT uses same as ABUNDANT; TUTORIAL is very sparse)
const RES_MULT_BY_LEVEL: Array[float] = [0.65, 1.0, 1.5, 1.5, 0.35]

# Starting stockpile for FULL_COMBAT — enough to train and build immediately
const FULL_COMBAT_STARTING: Dictionary = {
	"food": 9999,
	"wood": 9999,
	"gold": 9999,
	"stone": 9999,
}

func get_map_half() -> float:
	return MAP_HALF_BY_SIZE[clampi(map_size, 0, 2)]

func get_resource_multiplier() -> float:
	return RES_MULT_BY_LEVEL[clampi(resources, 0, 4)]

const TUTORIAL_STARTING: Dictionary = {"wood": 125}

func get_starting_resources() -> Dictionary:
	if resources == Resources.FULL_COMBAT:
		return FULL_COMBAT_STARTING
	if resources == Resources.TUTORIAL:
		return TUTORIAL_STARTING
	return {}  # use ResourceManager defaults

# Returns player_id list for all rival AIs: [1, 2, 3, ...]
func get_rival_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for i: int in range(rival_count):
		ids.append(i + 1)
	return ids

# Returns the civ_id for a given rival player_id (1-based)
func get_rival_civ_id(rival_player_id: int) -> String:
	var idx: int = rival_player_id - 1
	if idx >= 0 and idx < rival_civ_ids.size():
		return rival_civ_ids[idx]
	return "castellanos"

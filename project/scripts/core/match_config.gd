extends Node

## MatchConfig — holds the settings chosen in the lobby screen.
## Written before loading game_world, read during _ready().

enum MapSize   { SMALL = 0, MEDIUM = 1, LARGE = 2 }
enum Resources { SCARCE = 0, NORMAL = 1, ABUNDANT = 2 }

# Chosen by the player in the lobby
var map_size:        int    = MapSize.MEDIUM
var resources:       int    = Resources.NORMAL
var player_civ_id:   String = "britons"   # matches CivilizationResource.id
var starting_age:    int    = 0           # GameManager.Age

# Map size → MAP_HALF px
const MAP_HALF_BY_SIZE: Array[float] = [1200.0, 1800.0, 2600.0]

# Resources multiplier on deposit count and amount
const RES_MULT_BY_LEVEL: Array[float] = [0.65, 1.0, 1.5]

func get_map_half() -> float:
	return MAP_HALF_BY_SIZE[clampi(map_size, 0, 2)]

func get_resource_multiplier() -> float:
	return RES_MULT_BY_LEVEL[clampi(resources, 0, 2)]

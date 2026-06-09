extends Resource

class_name CivilizationResource

## Defines a civilization's identity and bonuses.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var unique_unit_ids: Array[String] = []
@export var unique_technology_ids: Array[String] = []

## Flat bonuses applied at game start.
@export var starting_bonuses: Dictionary = {}

## Multipliers applied to stats (e.g. {"villager_carry_capacity": 1.15}).
@export var stat_multipliers: Dictionary = {}

## Weather affinity: weather_id -> resistance factor in [0.0, 1.0] applied to that
## weather's penalties. 1.0 (or absent) = affected like everyone else; 0.5 = half
## the penalty; 0.0 = immune. Keys match WeatherManager weather ids, e.g.
## {"calima": 0.0, "volcanic_ash": 0.5}.
@export var weather_affinity: Dictionary = {}

## Which unit lines are unavailable for this civilization.
@export var missing_units: Array[String] = []
@export var missing_technologies: Array[String] = []

## Terrain traversal flags — replace hardcoded civ_id string checks in TerrainManager.
@export var can_traverse_malpais: bool = false   # volcanic rock (default: impassable)
@export var can_traverse_dune: bool = false      # desert dunes at full speed
@export var can_traverse_ocean: bool = false     # ocean tiles (ships set this via civ_id="atlantes")

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

## Which unit lines are unavailable for this civilization.
@export var missing_units: Array[String] = []
@export var missing_technologies: Array[String] = []

## Terrain traversal flags — replace hardcoded civ_id string checks in TerrainManager.
@export var can_traverse_malpais: bool = false   # volcanic rock (default: impassable)
@export var can_traverse_dune: bool = false      # desert dunes at full speed
@export var can_traverse_ocean: bool = false     # ocean tiles (ships set this via civ_id="atlantes")

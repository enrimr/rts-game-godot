extends Resource

class_name TechnologyResource

## Defines a researchable technology and its effects.

enum ResearchBuilding { BLACKSMITH, UNIVERSITY, MONASTERY, TOWN_CENTER, MARKET, BARRACKS, STABLE, LUMBER_CAMP, MINING_CAMP, MILL }

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export var required_age: int = 1  # GameManager.Age value
@export var research_building: ResearchBuilding = ResearchBuilding.BLACKSMITH
@export var research_time: float = 40.0

@export var cost_food: int = 0
@export var cost_wood: int = 0
@export var cost_gold: int = 0

## Effects as key-value pairs. Keys match stat_multipliers convention.
@export var effects: Dictionary = {}

## Technologies that must be researched first.
@export var prerequisites: Array[String] = []

## When non-empty, this tech upgrades all existing units of this id to upgrade_to_unit_id.
@export var upgrade_from_unit_id: String = ""
@export var upgrade_to_unit_id: String = ""

@export var icon: Texture2D

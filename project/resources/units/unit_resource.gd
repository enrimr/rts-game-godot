extends Resource

class_name UnitResource

## Static data for a unit type — loaded once, shared across instances.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export_group("Stats")
@export var max_health: float = 50.0
@export var move_speed: float = 100.0
@export var line_of_sight: float = 5.0
@export var population_cost: int = 1

@export_group("Combat")
@export var attack: float = 3.0
@export var attack_range: float = 0.5
@export var attack_speed: float = 1.5  # attacks per second
@export var armor_melee: float = 0.0
@export var armor_pierce: float = 0.0

@export_group("Production")
@export var train_time: float = 30.0
@export var cost_food: int = 0
@export var cost_wood: int = 0
@export var cost_gold: int = 0

@export_group("Visuals")
@export var icon: Texture2D
@export var scene: PackedScene

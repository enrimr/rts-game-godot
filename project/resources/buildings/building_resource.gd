extends Resource

class_name BuildingResource

## Static data for a building type.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export_group("Stats")
@export var max_health: float = 500.0
@export var line_of_sight: float = 8.0
@export var garrison_capacity: int = 0

@export_group("Cost")
@export var cost_wood: int = 0
@export var cost_stone: int = 0
@export var cost_gold: int = 0
@export var build_time: float = 60.0

@export_group("Visuals")
@export var icon: Texture2D
@export var scene: PackedScene
@export var footprint: Vector2i = Vector2i(2, 2)  # in tiles

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
@export var cost_food: int = 0
@export var build_time: float = 60.0

## Returns a {resource: amount} dict compatible with ResourceManager.can_afford / spend_resource.
## Only includes resources with a non-zero cost.
func get_cost_dict() -> Dictionary:
	var d: Dictionary = {}
	if cost_wood  > 0: d["wood"]  = cost_wood
	if cost_stone > 0: d["stone"] = cost_stone
	if cost_gold  > 0: d["gold"]  = cost_gold
	if cost_food  > 0: d["food"]  = cost_food
	return d

@export_group("Visuals")
@export var icon: Texture2D
@export var scene: PackedScene
@export var footprint: Vector2i = Vector2i(2, 2)  # in tiles

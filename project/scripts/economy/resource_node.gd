extends Node2D

class_name ResourceNode

enum ResourceType { WOOD, GOLD, STONE, FOOD_HUNT, FOOD_FISH, FOOD_BERRY }

const RESOURCE_NAMES: Dictionary = {
	ResourceType.WOOD:       "wood",
	ResourceType.GOLD:       "gold",
	ResourceType.STONE:      "stone",
	ResourceType.FOOD_HUNT:  "food",
	ResourceType.FOOD_FISH:  "food",
	ResourceType.FOOD_BERRY: "food",
}

@export var resource_type: ResourceType = ResourceType.WOOD
@export var initial_amount: float = 100.0

var remaining_amount: float = 0.0

signal depleted(node: Node)

func _ready() -> void:
	remaining_amount = initial_amount

func get_resource_name() -> String:
	return RESOURCE_NAMES.get(resource_type, "food") as String

func gather(amount: float) -> float:
	var gathered: float = minf(amount, remaining_amount)
	remaining_amount -= gathered
	if remaining_amount <= 0.0:
		depleted.emit(self)
		queue_free()
	return gathered

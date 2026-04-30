extends Node2D

class_name ResourceNode

## A gatherable resource on the map (tree, gold mine, stone quarry, etc.).

enum ResourceType { WOOD, GOLD, STONE, FOOD_HUNT, FOOD_FISH, FOOD_BERRY }

@export var resource_type: ResourceType = ResourceType.WOOD
@export var initial_amount: float = 100.0

var remaining_amount: float = 0.0

signal depleted(node: Node)

func _ready() -> void:
	remaining_amount = initial_amount

func gather(amount: float) -> float:
	var gathered: float = minf(amount, remaining_amount)
	remaining_amount -= gathered
	if remaining_amount <= 0.0:
		depleted.emit(self)
		queue_free()
	return gathered

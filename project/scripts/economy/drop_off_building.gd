extends Node2D

class_name DropOffBuilding

## Marks a building as a valid drop-off point for villagers.

@export var player_id: int = 0

func _ready() -> void:
	add_to_group("drop_off_buildings")

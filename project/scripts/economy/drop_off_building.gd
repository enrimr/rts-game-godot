extends Node2D

class_name DropOffBuilding

## Marks a building as a valid drop-off point for villagers.

@export var player_id: int = 0

func _ready() -> void:
	# A scene default can never know its runtime owner: town_center_ai.tscn
	# shipped with player_id = 1 baked in, so rivals 2+ had no valid drop-off
	# and their villagers held a full load forever. Owners set their player_id
	# before add_child on every spawn path, so the parent is authoritative here.
	var parent_pid: Variant = get_parent().get("player_id") if get_parent() != null else null
	if parent_pid != null:
		player_id = parent_pid as int
	add_to_group("drop_off_buildings")

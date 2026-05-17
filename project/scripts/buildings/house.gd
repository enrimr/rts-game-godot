extends BuildingBase

class_name House

const POP_BONUS: int = 5

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)
	building_destroyed.connect(_on_house_destroyed)

func _on_construction_complete() -> void:
	PopulationManager.add_cap(player_id, POP_BONUS)

func _on_house_destroyed() -> void:
	if state == BuildingState.COMPLETE:
		PopulationManager.reduce_cap(player_id, POP_BONUS)

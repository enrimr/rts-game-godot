extends BuildingBase

class_name House

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)

func _on_construction_complete() -> void:
	PopulationManager.add_cap(player_id, 5)

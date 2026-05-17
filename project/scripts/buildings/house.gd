extends BuildingBase

class_name House

const POP_BONUS: int = 5

var _cap_granted: bool = false

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)
	tree_exiting.connect(_on_tree_exiting)

func _on_construction_complete() -> void:
	_cap_granted = true
	PopulationManager.add_cap(player_id, POP_BONUS)

func _on_tree_exiting() -> void:
	if not _cap_granted:
		return
	_cap_granted = false
	PopulationManager.reduce_cap(player_id, POP_BONUS)

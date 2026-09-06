extends BuildingBase

class_name House

const POP_BONUS: int = 5

var _cap_granted: bool = false

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)
	tree_exiting.connect(_on_tree_exiting)
	if state == BuildingState.COMPLETE:
		_maybe_register_drop_off()

func _on_construction_complete() -> void:
	_cap_granted = true
	PopulationManager.add_cap(player_id, POP_BONUS)
	_maybe_register_drop_off()

## Canarii civ bonus: their houses double as drop-off points, so villagers
## unload wherever the town has grown (the .tres description promised this
## for months while nothing read the flag).
func _maybe_register_drop_off() -> void:
	if not CivBonusManager.has_bonus(player_id, "house_drop_off"):
		return
	if get_node_or_null("DropOffBuilding") != null:
		return
	var drop_off := DropOffBuilding.new()
	drop_off.name = "DropOffBuilding"
	drop_off.player_id = player_id
	add_child(drop_off)

func _on_tree_exiting() -> void:
	if not _cap_granted:
		return
	_cap_granted = false
	PopulationManager.reduce_cap(player_id, POP_BONUS)

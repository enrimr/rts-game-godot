extends BuildingBase

class_name MiningCamp

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)
	if state == BuildingState.COMPLETE:
		_register_drop_off()

func _on_construction_complete() -> void:
	_register_drop_off()

func _register_drop_off() -> void:
	var drop_off := DropOffBuilding.new()
	drop_off.player_id = player_id
	add_child(drop_off)

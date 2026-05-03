extends BuildingBase

class_name Farm

@export var gather_rate: float = 1.0

func _ready() -> void:
	super._ready()

func gather(amount: float) -> float:
	if state != BuildingState.COMPLETE:
		return 0.0
	return amount

func get_resource_name() -> String:
	return "food"

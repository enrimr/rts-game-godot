extends BuildingBase

class_name Farm

@export var max_food: float = 250.0
@export var gather_rate: float = 1.0

var _remaining: float = 0.0

signal depleted

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)

func _on_construction_complete() -> void:
	_remaining = max_food

func gather(amount: float) -> float:
	if state != BuildingState.COMPLETE or _remaining <= 0.0:
		return 0.0
	var taken: float = minf(amount, _remaining)
	_remaining -= taken
	if _remaining <= 0.0:
		depleted.emit()
		queue_free()
	return taken

func get_resource_name() -> String:
	return "food"

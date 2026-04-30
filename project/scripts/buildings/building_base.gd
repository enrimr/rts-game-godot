extends StaticBody2D

class_name BuildingBase

## Base class for all buildings.

enum BuildingState { BLUEPRINT, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

@export var building_data: BuildingResource

var player_id: int = 0
var state: BuildingState = BuildingState.BLUEPRINT
var health: float = 0.0
var construction_progress: float = 0.0

signal construction_complete
signal building_destroyed(building: Node)

func _ready() -> void:
	if building_data:
		health = building_data.max_health

func add_construction(amount: float) -> void:
	construction_progress = minf(construction_progress + amount, 100.0)
	if construction_progress >= 100.0:
		_complete_construction()

func _complete_construction() -> void:
	state = BuildingState.COMPLETE
	construction_complete.emit()
	EventBus.building_construction_complete.emit(self)

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	if health <= 0.0:
		_destroy()

func _destroy() -> void:
	state = BuildingState.DESTROYED
	EventBus.building_destroyed.emit(self, player_id)
	building_destroyed.emit(self)
	queue_free()

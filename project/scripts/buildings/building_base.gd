extends StaticBody2D

class_name BuildingBase

enum BuildingState { BLUEPRINT, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

@export var building_data: BuildingResource

var player_id: int = 0
var state: BuildingState = BuildingState.BLUEPRINT
var health: float = 0.0
var construction_progress: float = 0.0

signal construction_complete
signal building_destroyed(building: Node)

@onready var _progress_bar: ProgressBar = get_node_or_null("ConstructionBar")
@onready var _body_rect: ColorRect   = get_node_or_null("Body")

func _ready() -> void:
	if building_data:
		health = building_data.max_health
	_refresh_visuals()

func add_construction(amount: float) -> void:
	construction_progress = minf(construction_progress + amount, 100.0)
	_refresh_visuals()
	if construction_progress >= 100.0:
		_complete_construction()

func _complete_construction() -> void:
	state = BuildingState.COMPLETE
	if is_instance_valid(_progress_bar):
		_progress_bar.visible = false
	if is_instance_valid(_body_rect):
		_body_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
	construction_complete.emit()
	EventBus.building_construction_complete.emit(self)

func _refresh_visuals() -> void:
	if is_instance_valid(_progress_bar):
		_progress_bar.value = construction_progress
		_progress_bar.visible = state == BuildingState.UNDER_CONSTRUCTION or construction_progress < 100.0
	# Blueprint/under-construction tint: semi-transparent
	if is_instance_valid(_body_rect):
		var alpha: float = 0.4 + construction_progress / 100.0 * 0.6
		_body_rect.modulate = Color(1.0, 1.0, 1.0, alpha)

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	if health <= 0.0:
		_destroy()

func _destroy() -> void:
	state = BuildingState.DESTROYED
	EventBus.building_destroyed.emit(self, player_id)
	building_destroyed.emit(self)
	queue_free()

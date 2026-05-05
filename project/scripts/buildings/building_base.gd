extends StaticBody2D

class_name BuildingBase

enum BuildingState { BLUEPRINT, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

@export var building_data: BuildingResource

const MAX_BUILD_SPEED_MULTIPLIER: float = 3.0

var player_id: int = 0
var state: BuildingState = BuildingState.BLUEPRINT
var health: float = 0.0
var construction_progress: float = 0.0
var _active_builders: int = 0

signal construction_complete
signal building_destroyed(building: Node)

@onready var _progress_bar: ProgressBar = get_node_or_null("ConstructionBar")
@onready var _body_rect: ColorRect   = get_node_or_null("Body")

func _ready() -> void:
	add_to_group("buildings")
	if building_data:
		health = building_data.max_health
	_refresh_visuals()
	call_deferred("_apply_player_color_stripe")

func register_builder() -> void:
	_active_builders += 1

func unregister_builder() -> void:
	_active_builders = maxi(0, _active_builders - 1)

func add_construction(base_amount: float) -> void:
	var multiplier: float = minf(float(_active_builders), MAX_BUILD_SPEED_MULTIPLIER)
	if multiplier < 1.0:
		multiplier = 1.0
	construction_progress = minf(construction_progress + base_amount * multiplier, 100.0)
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

func _apply_player_color_stripe() -> void:
	if not is_instance_valid(_body_rect):
		PlayerColors.apply_color_stripe(self, player_id, 48.0, 36.0)
		return
	var w: float = _body_rect.offset_right - _body_rect.offset_left
	var b: float = _body_rect.offset_bottom
	PlayerColors.apply_color_stripe(self, player_id, w, b)

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	if health <= 0.0:
		_destroy()

func _destroy() -> void:
	state = BuildingState.DESTROYED
	EventBus.building_destroyed.emit(self, player_id)
	building_destroyed.emit(self)
	queue_free()

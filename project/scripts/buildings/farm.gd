extends BuildingBase

class_name Farm

@export var food_rate: float = 1.0

const TICK_INTERVAL: float = 5.0

var _tick_timer: float = 0.0

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if state != BuildingState.COMPLETE:
		return
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		ResourceManager.add_resource(player_id, "food", food_rate * TICK_INTERVAL)

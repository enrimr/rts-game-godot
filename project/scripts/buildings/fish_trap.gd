extends BuildingBase

class_name FishTrap

## Fish Trap — ocean building constructed and harvested by Fishing Boats.
## Generates food passively; fishing boats gather from it just like a ResourceNode.

const MAX_FOOD: float = 400.0
const REPLENISH_RATE: float = 0.25   # food/sec replenishment when depleted
const RESTORE_COST: Dictionary = {"wood": 50}

var _remaining: float = 0.0
var _is_depleted: bool = false

@onready var _food_bar: ProgressBar = get_node_or_null("FoodBar")

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)

func _process(delta: float) -> void:
	if state != BuildingState.COMPLETE:
		return
	if _is_depleted and _remaining < MAX_FOOD:
		_remaining = minf(_remaining + REPLENISH_RATE * delta, MAX_FOOD)
		if _remaining >= MAX_FOOD * 0.1:
			_is_depleted = false
		_refresh_visuals()

func _on_construction_complete() -> void:
	_remaining = MAX_FOOD
	_is_depleted = false
	_refresh_visuals()

func gather(amount: float) -> float:
	if state != BuildingState.COMPLETE or _is_depleted:
		return 0.0
	var taken: float = minf(amount, _remaining)
	_remaining -= taken
	_refresh_visuals()
	if _remaining <= 0.0:
		_is_depleted = true
	return taken

func get_resource_name() -> String:
	return "food"

func is_depleted() -> bool:
	return _is_depleted

func restore() -> void:
	_remaining = MAX_FOOD
	_is_depleted = false
	_refresh_visuals()

func get_restore_cost() -> Dictionary:
	return RESTORE_COST

func _refresh_visuals() -> void:
	if is_instance_valid(_food_bar):
		_food_bar.visible = state == BuildingState.COMPLETE
		_food_bar.value = (_remaining / MAX_FOOD) * 100.0 if MAX_FOOD > 0.0 else 0.0

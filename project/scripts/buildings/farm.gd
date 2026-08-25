extends BuildingBase

class_name Farm

@export var max_food: float = 250.0
@export var gather_rate: float = 1.0
@export var restore_cost: Dictionary = {"wood": 40}

var _remaining: float = 0.0
var _is_depleted: bool = false

@onready var _body: CanvasItem = get_node_or_null("Body")
@onready var _food_bar: ProgressBar = get_node_or_null("FoodBar")

const COLOR_ACTIVE:   Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DEPLETED: Color = Color(0.55, 0.45, 0.35, 1.0)

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)

# A farm is a ground feature: its field plots must stay projected flat on the
# diamond instead of standing upright like walled buildings.
func _iso_upright_children() -> Array:
	return ["NameLabel", "HealthBar", "ConstructionBar", "FoodBar"]

func _on_construction_complete() -> void:
	_remaining = max_food
	_is_depleted = false
	_refresh_farm_visuals()

func gather(amount: float) -> float:
	if state != BuildingState.COMPLETE or _is_depleted:
		return 0.0
	var taken: float = minf(amount, _remaining)
	_remaining -= taken
	_refresh_farm_visuals()
	if _remaining <= 0.0:
		_deplete()
	return taken

func get_resource_name() -> String:
	return "food"

func is_depleted() -> bool:
	return _is_depleted

func restore() -> void:
	_remaining = max_food
	_is_depleted = false
	_refresh_farm_visuals()

func get_restore_cost() -> Dictionary:
	return restore_cost

func _deplete() -> void:
	_is_depleted = true
	_refresh_farm_visuals()

func _refresh_farm_visuals() -> void:
	if is_instance_valid(_body):
		_body.modulate = COLOR_ACTIVE if not _is_depleted else COLOR_DEPLETED
	if is_instance_valid(_food_bar):
		_food_bar.visible = state == BuildingState.COMPLETE
		_food_bar.value = (_remaining / max_food) * 100.0 if max_food > 0.0 else 0.0

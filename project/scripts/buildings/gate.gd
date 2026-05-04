extends BuildingBase

class_name Gate

signal gate_toggled(is_open: bool)

var is_open: bool = false

@onready var _collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var _obstacle: NavigationObstacle2D = get_node_or_null("NavigationObstacle2D")
@onready var _body: ColorRect = get_node_or_null("Body")
@onready var _open_label: Label = get_node_or_null("StateLabel")

const COLOR_CLOSED: Color = Color(0.45, 0.32, 0.14, 1.0)
const COLOR_OPEN: Color = Color(0.60, 0.50, 0.28, 0.55)

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)

func _on_construction_complete() -> void:
	_apply_state()

func toggle() -> void:
	is_open = not is_open
	_apply_state()
	gate_toggled.emit(is_open)
	EventBus.building_selected.emit(self)

func open_for_unit() -> void:
	if is_open:
		return
	is_open = true
	_apply_state()
	gate_toggled.emit(true)

func close_after_unit() -> void:
	if not is_open:
		return
	is_open = false
	_apply_state()
	gate_toggled.emit(false)

func can_pass(unit_player_id: int) -> bool:
	return is_open or unit_player_id == player_id

func _apply_state() -> void:
	if is_instance_valid(_collision):
		_collision.disabled = is_open
	if is_instance_valid(_obstacle):
		_obstacle.avoidance_enabled = not is_open
	if is_instance_valid(_body):
		_body.color = COLOR_OPEN if is_open else COLOR_CLOSED
	if is_instance_valid(_open_label):
		_open_label.text = "OPEN" if is_open else "GATE"


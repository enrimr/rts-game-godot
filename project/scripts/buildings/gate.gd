extends BuildingBase

class_name Gate

signal gate_toggled(is_open: bool)

var is_open: bool = false
var locked: bool = false  # when true, auto-open is suppressed

@onready var _collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var _obstacle: NavigationObstacle2D = get_node_or_null("NavigationObstacle2D")
@onready var _body: ColorRect = get_node_or_null("Body")
@onready var _open_label: Label = get_node_or_null("StateLabel")
@onready var _detect_area: Area2D = get_node_or_null("DetectArea")

const COLOR_CLOSED: Color = Color(0.45, 0.32, 0.14, 1.0)
const COLOR_OPEN: Color = Color(0.60, 0.50, 0.28, 0.55)
const COLOR_LOCKED: Color = Color(0.30, 0.10, 0.10, 1.0)

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)

func _on_construction_complete() -> void:
	if is_instance_valid(_detect_area):
		_detect_area.body_entered.connect(_on_body_entered)
		_detect_area.body_exited.connect(_on_body_exited)
	_apply_state()

# Called from HUD button — toggles the locked flag.
# If locked: force-closes and holds. If unlocked: auto-logic resumes.
func toggle_lock() -> void:
	locked = not locked
	if locked and is_open:
		_set_open(false)
	elif not locked:
		_recheck_area()
	gate_toggled.emit(is_open)
	EventBus.building_selected.emit(self)

func _on_body_entered(body: Node) -> void:
	if state != BuildingState.COMPLETE or locked:
		return
	if _is_allied(body) and not is_open:
		_set_open(true)
		gate_toggled.emit(true)

func _on_body_exited(_body: Node) -> void:
	if state != BuildingState.COMPLETE or locked:
		return
	if not _has_allied_units_inside():
		if is_open:
			_set_open(false)
			gate_toggled.emit(false)

func _recheck_area() -> void:
	if not is_instance_valid(_detect_area):
		return
	if _has_allied_units_inside():
		if not is_open:
			_set_open(true)
			gate_toggled.emit(true)
	else:
		if is_open:
			_set_open(false)
			gate_toggled.emit(false)

func _has_allied_units_inside() -> bool:
	if not is_instance_valid(_detect_area):
		return false
	for body: Node in _detect_area.get_overlapping_bodies():
		if _is_allied(body):
			return true
	return false

func _is_allied(body: Node) -> bool:
	var pid: Variant = body.get("player_id")
	return pid != null and (pid as int) == player_id

func get_nav_obstacle_polygon() -> PackedVector2Array:
	if is_open:
		return PackedVector2Array()
	return super.get_nav_obstacle_polygon()

func _set_open(value: bool) -> void:
	is_open = value
	_apply_state()
	EventBus.gate_state_changed.emit(self)

func _apply_state() -> void:
	# Toggled from Area2D body_entered/exited callbacks, which run while the
	# physics server is flushing queries — mutating a collision shape's disabled
	# state then is illegal, so defer it.
	if is_instance_valid(_collision):
		_collision.set_deferred("disabled", is_open)
	if is_instance_valid(_obstacle):
		_obstacle.set_deferred("avoidance_enabled", not is_open)
	if is_instance_valid(_body):
		if locked:
			_body.color = COLOR_LOCKED
		else:
			_body.color = COLOR_OPEN if is_open else COLOR_CLOSED
	if is_instance_valid(_open_label):
		if locked:
			_open_label.text = "LOCKED"
		elif is_open:
			_open_label.text = "OPEN"
		else:
			_open_label.text = "GATE"

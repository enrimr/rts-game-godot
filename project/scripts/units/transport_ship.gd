extends ShipBase

class_name TransportShip

## Transport Ship — carries land units across water.
## Garrisoning/ungarrisoning is click-based (future milestone).
## For now behaves as a mobile unit that can be ordered to move.

var attack_target: Node = null
var _attack_timer: float = 0.0

func _ready() -> void:
	super._ready()
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_velocity_computed(safe_vel: Vector2) -> void:
	velocity = safe_vel
	move_and_slide()

func _on_auto_attack_target(_target: Node) -> void:
	pass  # Transport ships don't attack

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)

func order_move(destination: Vector2) -> void:
	attack_target = null
	nav_agent.target_position = _safe_destination(destination)
	current_state = UnitState.MOVING

func _handle_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = UnitState.IDLE
		return
	if _advance_stuck(delta):
		current_state = UnitState.IDLE
	nav_agent.set_velocity(_nav_velocity())

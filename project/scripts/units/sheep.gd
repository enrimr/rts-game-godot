extends Animal

class_name Sheep

const RECONVERT_INTERVAL: float = 1.5

var _reconvert_timer: float = 0.0

func _ready() -> void:
	animal_name = "Sheep"
	convertible = true
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if current_state == AnimalState.DEAD:
		return
	_reconvert_timer += delta
	if _reconvert_timer >= RECONVERT_INTERVAL:
		_reconvert_timer = 0.0
		_check_nearest_owner()

# Every tick find the closest unit/building body inside the convert area.
# If it belongs to a different team than the current owner, switch.
func _check_nearest_owner() -> void:
	var bodies: Array[Node2D] = _convert_area.get_overlapping_bodies()
	if bodies.is_empty():
		return
	var best_body: Node = null
	var best_dist: float = INF
	for body: Node2D in bodies:
		var pid: Variant = body.get("player_id")
		if pid == null or (pid as int) < 0:
			continue
		var d: float = global_position.distance_to(body.global_position)
		if d < best_dist:
			best_dist = d
			best_body = body
	if best_body == null:
		return
	var nearest_pid: int = best_body.get("player_id") as int
	_try_convert(nearest_pid)

func _on_converted() -> void:
	# Tint by team color
	_body_rect.color = PlayerColors.get_color(player_id)

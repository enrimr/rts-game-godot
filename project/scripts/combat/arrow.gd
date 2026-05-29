extends Node2D

class_name Arrow

var damage: float = 0.0
var shooter: Node = null
var target_pos: Vector2 = Vector2.ZERO   # fixed at launch — arrow flies to this point
var _original_target: Node = null        # only used to check if it's still there at impact
var _speed: float = 520.0
var _hit_radius: float = 28.0
var _lifetime: float = 0.0
const MAX_LIFETIME: float = 3.0

func _ready() -> void:
	var shaft: Polygon2D = Polygon2D.new()
	shaft.color = Color(0.72, 0.60, 0.28, 1.0)
	shaft.polygon = PackedVector2Array([Vector2(-8, -1), Vector2(6, -1), Vector2(6, 1), Vector2(-8, 1)])
	add_child(shaft)
	var tip: Polygon2D = Polygon2D.new()
	tip.color = Color(0.85, 0.82, 0.75, 1.0)
	tip.polygon = PackedVector2Array([Vector2(6, -2), Vector2(11, 0), Vector2(6, 2)])
	add_child(tip)
	var fletching: Polygon2D = Polygon2D.new()
	fletching.color = Color(0.88, 0.25, 0.10, 1.0)
	fletching.polygon = PackedVector2Array([Vector2(-8, -1), Vector2(-12, -4), Vector2(-11, -1), Vector2(-12, 4), Vector2(-8, 1)])
	add_child(fletching)

func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		queue_free()
		return
	var dir: Vector2 = (target_pos - global_position)
	var dist: float = dir.length()
	if dist < 8.0:
		_on_impact()
		return
	var move: float = _speed * delta
	global_position += dir.normalized() * minf(move, dist)
	rotation = dir.angle()

func _on_impact() -> void:
	if is_instance_valid(_original_target):
		var target_dist: float = global_position.distance_to((_original_target as Node2D).global_position)
		if target_dist <= _hit_radius and _original_target.has_method("take_damage"):
			_original_target.take_damage(damage, shooter)
			AudioManager.play_if_visible("hit_ranged", global_position, -4.0)
			if is_instance_valid(shooter):
				EventBus.unit_attacked.emit(shooter, _original_target)
	queue_free()

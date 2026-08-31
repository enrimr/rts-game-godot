extends Node2D

class_name Arrow

var damage: float = 0.0
var shooter: Node = null
var target_pos: Vector2 = Vector2.ZERO   # fixed at launch — arrow flies to this point
var _original_target: Node = null        # only used to check if it's still there at impact
var _speed: float = 520.0
var _hit_radius: float = 28.0
var _lifetime: float = 0.0
## True on a client-side replication echo: purely visual, never reported back.
var echo: bool = false
var _reported: bool = false
const MAX_LIFETIME: float = 3.0

func _ready() -> void:
	z_index = IsoBillboard.Z_AIRBORNE
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
	# Deferred to the first frame: global_position is set AFTER add_child.
	if not _reported and not echo:
		_reported = true
		if NetworkSession.is_host():
			EventBus.projectile_spawned.emit(global_position, target_pos, SiegeFx.KIND_ARROW)
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
			# The shooter may have died while the arrow was in flight; pass a live
			# reference or null (take_damage handles null) — never a freed Object,
			# which fails take_damage's typed `source` argument.
			var live_shooter: Node = shooter if is_instance_valid(shooter) else null
			_original_target.take_damage(damage, live_shooter)
			AudioManager.play_if_visible("hit_ranged", global_position, -4.0)
			if live_shooter != null:
				EventBus.unit_attacked.emit(live_shooter, _original_target)
	queue_free()

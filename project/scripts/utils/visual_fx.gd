class_name VisualFx

## Shared procedural visual helpers: ground shadows that "seat" units and
## buildings on the terrain, giving the flat-polygon art a sense of depth.

const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.22)
const SHADOW_Z: int = -1   # below the Body, above the terrain (terrain is z <= -6)

## Adds a soft elliptical shadow under `parent`, sized `rx` × `ry`, nudged down
## by `offset_y`. Call after `parent` is inside the tree. Idempotent: skips if a
## shadow already exists.
static func add_ground_shadow(parent: Node2D, rx: float, ry: float, offset_y: float = 4.0) -> void:
	if parent.get_node_or_null("GroundShadow") != null:
		return
	var shadow: Polygon2D = Polygon2D.new()
	shadow.name = "GroundShadow"
	shadow.color = SHADOW_COLOR
	shadow.z_index = SHADOW_Z
	shadow.position = Vector2(0.0, offset_y)
	shadow.polygon = _ellipse_points(rx, ry, 16)
	# Keep the shadow flat on the ground even when the body rotates/scales.
	shadow.set_meta("static_shadow", true)
	parent.add_child(shadow)
	parent.move_child(shadow, 0)

static func _ellipse_points(rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps):
		var a: float = TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

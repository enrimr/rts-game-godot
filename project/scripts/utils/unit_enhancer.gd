class_name UnitEnhancer
extends RefCounted

## Optional "enhanced unit detail" visual layer (GameSettings.enhanced_units).
## Applied on top of the finished rig — AFTER UnitDress/TeamDress/gender have
## painted — and fully reversible: every node it adds carries META_ENHANCED,
## every polygon it shades carries META_SHADED, so strip() restores the exact
## classic look. It never touches Polygon2D.color (the TeamDress contract) —
## shading lives in vertex_colors, which REPLACE the flat fill per vertex and
## are simply cleared on strip.
##
## Three generic improvements, valid for every rig without editing scenes:
##  - Ink outline: a grown dark copy of each polygon, added as a CHILD at
##    z_index -1 so all outlines merge into one silhouette contour BEHIND the
##    whole figure and follow any sub-node animation (Head/Tool pivots) free.
##  - Volume shading: per-polygon vertical gradient baked from the polygon's
##    current colour — brighter toward the figure's top (sky/rim light),
##    darker toward the feet (grounding).
##  - Life animation (animate_extras, called from UnitBase._process when the
##    mode is on): idle breathing, walk lean + squash&stretch bounce, attack
##    anticipation/overshoot snap. Only figures with a head (humanoids,
##    animals) animate — ships and siege get outline+shading only.

const META_ENHANCED: StringName = &"enhanced_part"
const META_SHADED: StringName = &"enhanced_shaded"
const META_APPLIED: StringName = &"enhanced_applied"
const META_BASE_SCALE: StringName = &"enhanced_base_scale"
const META_BREATHES: StringName = &"enhanced_breathes"

const OUTLINE_COLOR: Color = Color(0.09, 0.07, 0.06, 0.85)
const OUTLINE_GROW: float = 1.2
## Vertical shading gains at the figure's top / bottom.
const TOP_GAIN: float = 1.14
const BOTTOM_GAIN: float = 0.78

## Animation amplitudes (radians / scale fractions). Small on purpose: the
## goal is life, not cartoons.
const BREATH_RATE: float = 0.5
const BREATH_AMP: float = 0.012
const WALK_BOUNCE_AMP: float = 0.04
const WALK_LEAN: float = 0.05
const ATTACK_SNAP: float = 0.12
const ATTACK_CRUNCH: float = 0.03

static func is_applied(unit: Node2D) -> bool:
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	return body != null and body.has_meta(META_APPLIED)

static func apply(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null or body.has_meta(META_APPLIED):
		return
	var polys: Array[Polygon2D] = []
	_collect_polygons(body, polys)
	if polys.is_empty():
		return
	# Vertical extent of the whole figure in Body space, so the gradient runs
	# head-to-feet across parts, not per part.
	var min_y: float = INF
	var max_y: float = -INF
	var xfs: Array[Transform2D] = []
	for poly: Polygon2D in polys:
		var xf: Transform2D = _xf_to_body(body, poly)
		xfs.append(xf)
		for p: Vector2 in poly.polygon:
			var y: float = (xf * p).y
			min_y = minf(min_y, y)
			max_y = maxf(max_y, y)
	var span: float = maxf(max_y - min_y, 1.0)
	for i: int in range(polys.size()):
		_shade(polys[i], xfs[i], min_y, span)
		_add_outline(polys[i])
	body.set_meta(META_APPLIED, true)
	body.set_meta(META_BASE_SCALE, Vector2(absf(body.scale.x), absf(body.scale.y)))
	body.set_meta(META_BREATHES, VisualFx.find_head(unit) != null)

static func strip(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null or not body.has_meta(META_APPLIED):
		return
	var base: Vector2 = body.get_meta(META_BASE_SCALE, Vector2.ONE) as Vector2
	body.scale = Vector2(signf(body.scale.x) * base.x, base.y)
	_strip_node(body)
	body.remove_meta(META_APPLIED)
	body.remove_meta(META_BASE_SCALE)
	body.remove_meta(META_BREATHES)

static func _strip_node(node: Node) -> void:
	for child: Node in node.get_children():
		if child.has_meta(META_ENHANCED):
			child.get_parent().remove_child(child)
			child.queue_free()
			continue
		_strip_node(child)
	if node is Polygon2D and node.has_meta(META_SHADED):
		(node as Polygon2D).vertex_colors = PackedColorArray()
		node.remove_meta(META_SHADED)

## Post-step over the base procedural animation — UnitBase._process calls it
## right after _animate_body when the mode is on. Adds offsets ON TOP of
## whatever the state machine set this frame (rotation/scale are re-set by the
## rig every frame, so nothing drifts). O(1) per unit per frame.
static func animate_extras(unit: UnitBase) -> void:
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null or not body.has_meta(META_APPLIED):
		return
	if not body.get_meta(META_BREATHES, false):
		return   # ships/siege: outline+shading only, no organic motion
	var base: Vector2 = body.get_meta(META_BASE_SCALE, Vector2.ONE) as Vector2
	var t: float = unit._anim_time
	var stretch: float = 0.0
	var rot_add: float = 0.0
	match unit.current_state:
		UnitBase.UnitState.IDLE:
			stretch = sin(t * TAU * BREATH_RATE) * BREATH_AMP
		UnitBase.UnitState.MOVING, UnitBase.UnitState.RETURNING:
			# Double the walk cadence (2.8 Hz shuffle): one bounce per footfall.
			stretch = absf(sin(t * TAU * 5.6)) * WALK_BOUNCE_AMP - WALK_BOUNCE_AMP * 0.5
			rot_add = WALK_LEAN * signf(body.scale.x)
		UnitBase.UnitState.ATTACKING:
			var s: float = sin(t * TAU * 3.5)
			rot_add = s * s * s * ATTACK_SNAP   # cubed sine: wind-up, snap, overshoot
			stretch = -s * ATTACK_CRUNCH
	body.scale.y = base.y * (1.0 + stretch)
	body.scale.x = signf(body.scale.x) * base.x * (1.0 - stretch * 0.6)
	body.rotation += rot_add

# ---------------------------------------------------------------------------

static func _collect_polygons(node: Node, out: Array[Polygon2D]) -> void:
	for child: Node in node.get_children():
		if child.has_meta(META_ENHANCED):
			continue
		if child is Polygon2D:
			out.append(child as Polygon2D)
		_collect_polygons(child, out)

## Accumulated transform from a rig part up to (excluding) the Body node —
## computed from local transforms so it works out of tree (tests, icon bakes).
static func _xf_to_body(body: Node2D, node: Node2D) -> Transform2D:
	var xf: Transform2D = Transform2D.IDENTITY
	var n: Node = node
	while n != null and n != body:
		if n is Node2D:
			xf = (n as Node2D).transform * xf
		n = n.get_parent()
	return xf if n == body else node.transform

static func _shade(poly: Polygon2D, xf: Transform2D, min_y: float, span: float) -> void:
	if not poly.vertex_colors.is_empty():
		return   # authored gradient: leave it alone
	var base: Color = poly.color
	var cols: PackedColorArray = PackedColorArray()
	for p: Vector2 in poly.polygon:
		var f: float = clampf(((xf * p).y - min_y) / span, 0.0, 1.0)
		var g: float = lerpf(TOP_GAIN, BOTTOM_GAIN, f)
		cols.append(Color(minf(base.r * g, 1.0), minf(base.g * g, 1.0),
			minf(base.b * g, 1.0), base.a))
	poly.vertex_colors = cols
	poly.set_meta(META_SHADED, true)

## Grown dark copy of the polygon, CHILD of it (follows Head/Tool animation)
## at relative z -1: all outlines render behind the entire figure and merge
## into a single contour silhouette.
static func _add_outline(poly: Polygon2D) -> void:
	var pts: PackedVector2Array = poly.polygon
	if pts.size() < 3:
		return
	var c: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		c += p
	c /= float(pts.size())
	var grown: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		var d: Vector2 = p - c
		var l: float = d.length()
		grown.append(p + d / l * OUTLINE_GROW if l > 0.01 else p)
	var o: Polygon2D = Polygon2D.new()
	o.name = "EnhanceOutline"
	o.polygon = grown
	o.color = OUTLINE_COLOR
	o.z_index = -1
	o.set_meta(META_ENHANCED, true)
	poly.add_child(o)

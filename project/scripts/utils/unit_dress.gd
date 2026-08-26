class_name UnitDress

## Civilization dress pass for shared human units (villager, militia line,
## archer, pikeman, scout line, knight).
##
## Adds the civ headgear (CivStyle.style.headgear) as 1-2 small Polygon2Ds
## anchored to the head polygon, plus a thin sash across the torso tinted
## style.trim, so two armies of different civs read apart at a glance while
## the PlayerColors plinth keeps marking ownership. Purely cosmetic: no
## physics, no gameplay fields, nothing outside the Body rig.
##
## Skips units without a head polygon (ships, siege, animals) and heroes /
## civ-unique units, which carry their own identity.

const META_APPLIED: StringName = &"civ_dress_applied"

## Headwear the gear sits on top of; scanned for the crown height so a cap or
## wrap wraps OVER a helmet instead of hiding inside it. HelmetCrest/Plume are
## thin decorations, not shell, and are deliberately excluded.
const _CROWN_NODES: Array = ["Hat", "Helmet", "Cap", "Hood"]
const _TORSO_NODES: Array = ["Torso", "RiderBody"]
## Crown-covering gear replaces the villager straw hat instead of stacking on
## its wide brim (helmets are kept — gear decorates them).
const _HAT_REPLACING: Array = ["wrap", "cap", "hood"]

const _CLOTH: Color = Color(0.93, 0.90, 0.83)
const _BRONZE: Color = Color(0.84, 0.70, 0.36)

# unit_ref is untyped because the call is deferred from _ready: a unit freed
# in the same frame (tests, instant deaths) can no longer convert to a typed
# Node2D argument and would error inside the message queue.
static func apply(unit_ref: Variant, player_id: int) -> void:
	if not is_instance_valid(unit_ref) or not (unit_ref is Node2D):
		return
	var unit: Node2D = unit_ref as Node2D
	if unit.has_meta(META_APPLIED):
		return
	# Heroes style themselves (HeroUnit extends Militia, so the militia call
	# reaches them); detected by their ability signal to avoid a class-name
	# dependency cycle (HeroUnit -> Militia -> UnitDress).
	if unit.has_signal("ability_used"):
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null:
		return
	var head: Polygon2D = VisualFx.find_head(unit)
	if head == null:
		return
	unit.set_meta(META_APPLIED, true)

	var style: Dictionary = CivStyle.style_for_civ(_civ_id(unit, player_id))
	var trim: Color = style.trim as Color
	var gear: String = style.headgear as String

	var hat: Polygon2D = body.get_node_or_null("Hat") as Polygon2D
	if hat != null and gear in _HAT_REPLACING:
		hat.visible = false

	var b: Rect2 = _poly_bounds(head.polygon)
	var crown_y: float = b.position.y
	for n: String in _CROWN_NODES:
		var hw: Polygon2D = body.get_node_or_null(n) as Polygon2D
		if hw == null or not hw.visible:
			continue
		crown_y = minf(crown_y, _poly_bounds(hw.polygon).position.y)

	match gear:
		"band":
			_add_band(head, b, trim)
		"wrap":
			_add_wrap(head, b, crown_y, trim)
		"cap":
			_add_cap(head, b, crown_y, trim)
		"hood":
			_add_hood(head, b, crown_y, trim)
		"crest":
			_add_crest(head, b, crown_y, style.roof_color as Color)
		"circlet":
			_add_circlet(head, b, trim)
		_:
			pass  # "none": identity carried by the sash alone

	_add_sash(body, trim)

static func _civ_id(unit: Node2D, player_id: int) -> String:
	var cv: Variant = unit.get("civ_id")
	var cid: String = (cv as String) if cv is String else ""
	if cid.is_empty():
		cid = CivStyle.civ_id_for_player(player_id)
	return cid

static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(p)
	return r

## Gear polygons live under the head node so they inherit its animation
## (villager head bob/tilt) and the Body flip. z_index 1 lifts them above
## later Body siblings (Helmet/Hat/female hair fringe) drawn at z 0.
static func _add_gear(head: Polygon2D, points: PackedVector2Array, color: Color,
		suffix: String = "") -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.name = "CivHeadgear" + suffix
	poly.color = color
	poly.polygon = points
	poly.z_index = 1
	head.add_child(poly)

## Forehead cloth band with a short knotted tail at the back (Guanches).
static func _add_band(head: Polygon2D, b: Rect2, trim: Color) -> void:
	var lx: float = b.position.x
	var rx: float = b.end.x
	var ty: float = b.position.y
	var col: Color = trim.darkened(0.3)
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 0.6, ty + 1.2), Vector2(rx + 0.6, ty + 1.2),
		Vector2(rx + 0.6, ty + 2.6), Vector2(lx - 0.6, ty + 2.6),
	]), col)
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 0.4, ty + 1.6), Vector2(lx - 2.2, ty + 4.6),
		Vector2(lx - 1.2, ty + 5.0), Vector2(lx + 0.2, ty + 2.6),
	]), col, "B")

## Pale head cloth over the crown with a trim-coloured tail (Mahos/Fenicios —
## told apart by the tail tint).
static func _add_wrap(head: Polygon2D, b: Rect2, crown_y: float, trim: Color) -> void:
	var lx: float = b.position.x
	var rx: float = b.end.x
	var cx: float = (lx + rx) * 0.5
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 1.4, crown_y + 3.0), Vector2(lx - 1.0, crown_y + 0.6),
		Vector2(cx, crown_y - 1.0), Vector2(rx + 1.0, crown_y + 0.6),
		Vector2(rx + 1.4, crown_y + 3.0),
	]), _CLOTH)
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 1.0, crown_y + 2.2), Vector2(lx - 2.4, crown_y + 7.0),
		Vector2(lx - 1.2, crown_y + 7.4), Vector2(lx + 0.2, crown_y + 3.0),
	]), trim, "B")

## Small peaked cap with a front brim (Franks). Front is local +x; the Body
## flip mirrors it with the facing.
static func _add_cap(head: Polygon2D, b: Rect2, crown_y: float, trim: Color) -> void:
	var lx: float = b.position.x
	var rx: float = b.end.x
	var cx: float = (lx + rx) * 0.5
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 0.8, crown_y + 1.4), Vector2(lx - 0.4, crown_y - 0.8),
		Vector2(cx + 0.4, crown_y - 1.8), Vector2(rx + 0.4, crown_y - 0.6),
		Vector2(rx + 2.4, crown_y + 0.6), Vector2(rx + 0.6, crown_y + 1.4),
	]), trim)

## Hood rim framing the face down past the chin (Britons).
static func _add_hood(head: Polygon2D, b: Rect2, crown_y: float, trim: Color) -> void:
	var lx: float = b.position.x
	var rx: float = b.end.x
	var cx: float = (lx + rx) * 0.5
	var by: float = b.end.y
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 1.6, by - 0.5), Vector2(lx - 1.2, crown_y + 0.4),
		Vector2(cx, crown_y - 1.6), Vector2(rx + 1.2, crown_y + 0.4),
		Vector2(rx + 1.6, by - 0.5), Vector2(rx + 0.4, by - 0.5),
		Vector2(rx + 0.4, crown_y + 1.6), Vector2(cx, crown_y + 0.2),
		Vector2(lx - 0.4, crown_y + 1.6), Vector2(lx - 0.4, by - 0.5),
	]), trim.darkened(0.25))

## Thin comb crest on the crown, terracotta material tint (Castellanos).
static func _add_crest(head: Polygon2D, b: Rect2, crown_y: float, col: Color) -> void:
	var cx: float = (b.position.x + b.end.x) * 0.5
	_add_gear(head, PackedVector2Array([
		Vector2(cx - 0.9, crown_y + 0.8), Vector2(cx - 0.4, crown_y - 2.6),
		Vector2(cx + 0.6, crown_y - 2.8), Vector2(cx + 0.9, crown_y + 0.8),
	]), col)

## Thin bronze brow band with a small trim gem at the centre (Atlantes).
static func _add_circlet(head: Polygon2D, b: Rect2, trim: Color) -> void:
	var lx: float = b.position.x
	var rx: float = b.end.x
	var cx: float = (lx + rx) * 0.5
	var ty: float = b.position.y
	_add_gear(head, PackedVector2Array([
		Vector2(lx - 0.5, ty + 0.6), Vector2(rx + 0.5, ty + 0.6),
		Vector2(rx + 0.5, ty + 1.6), Vector2(lx - 0.5, ty + 1.6),
	]), _BRONZE)
	_add_gear(head, PackedVector2Array([
		Vector2(cx, ty - 0.6), Vector2(cx + 0.9, ty + 1.1),
		Vector2(cx, ty + 2.0), Vector2(cx - 0.9, ty + 1.1),
	]), trim, "B")

## Thin diagonal sash shoulder-to-hip across the torso, tinted style.trim.
static func _add_sash(body: Node2D, trim: Color) -> void:
	var torso: Polygon2D = null
	for n: String in _TORSO_NODES:
		torso = body.get_node_or_null(n) as Polygon2D
		if torso != null:
			break
	if torso == null:
		return
	var t: Rect2 = _poly_bounds(torso.polygon)
	var sash: Polygon2D = Polygon2D.new()
	sash.name = "CivSash"
	sash.color = trim
	sash.z_index = 1
	sash.polygon = PackedVector2Array([
		Vector2(t.position.x + 0.4, t.position.y + 1.0),
		Vector2(t.position.x + 2.2, t.position.y + 1.0),
		Vector2(t.end.x - 0.4, t.end.y - 1.0),
		Vector2(t.end.x - 2.2, t.end.y - 1.0),
	])
	torso.add_child(sash)

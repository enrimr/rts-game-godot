class_name ShipDress

## Civilization dress pass for the shared hulls (fishing boat, transport ship,
## war galley), the naval counterpart of UnitDress.
##
## Land units hang their civ identity on a head (headgear + sash); a ship has
## none, so the hull planking carries the material and the sail carries the
## colour, plus a small prow ornament for the two civs whose identity IS the sea
## (Atlantes bronze fin, Fenicios painted eye). Purely cosmetic: only Polygon2D
## colours inside the Body rig, no gameplay fields.
##
## Civ-unique ships (Trireme) stamp META_APPLIED in their own _ready and keep the
## bespoke art they were drawn with.

const META_APPLIED: StringName = &"ship_dress_applied"

## Hull-material nodes: gunwales, planks, bulwarks and rowing benches all read as
## the same timber as the hull, one step darker.
const _PLANK_NODES: Array = [
	"Gunwale", "Plank1", "Plank2", "LeftBulwark", "RightBulwark",
	"RowBench1", "RowBench2",
]
const _OAR_PREFIX: String = "OarBlade"

# ship_ref is untyped because the call is deferred from _ready: a ship freed in
# the same frame (tests, instant deaths) can no longer convert to a typed Node2D
# argument and would error inside the message queue.
static func apply(ship_ref: Variant, player_id: int) -> void:
	if not is_instance_valid(ship_ref) or not (ship_ref is Node2D):
		return
	var ship: Node2D = ship_ref as Node2D
	if ship.has_meta(META_APPLIED):
		return
	var body: Node2D = ship.get_node_or_null("Body") as Node2D
	if body == null:
		return
	var hull: Polygon2D = body.get_node_or_null("Hull") as Polygon2D
	if hull == null:
		return
	ship.set_meta(META_APPLIED, true)

	var naval: Dictionary = CivStyle.naval_for_civ(_civ_id(ship, player_id))
	var hull_color: Color = naval.hull as Color
	var deck_color: Color = naval.deck as Color
	var sail_color: Color = naval.sail as Color
	var accent: Color = naval.accent as Color

	hull.color = hull_color
	_tint(body, "HullShadow", hull_color.darkened(0.32))
	_tint(body, "Deck", deck_color)
	_tint(body, "Cabin", deck_color.lightened(0.1))
	# The ram is the bow's metal fitting: it must match the prow ornament that
	# lands on top of it, or the bow reads as two unrelated pieces.
	_tint(body, "Ram", accent.darkened(0.1))
	for n: String in _PLANK_NODES:
		_tint(body, n, hull_color.darkened(0.16))
	for child: Node in body.get_children():
		if child is Polygon2D and String(child.name).begins_with(_OAR_PREFIX):
			(child as Polygon2D).color = accent

	var sail: Polygon2D = body.get_node_or_null("Sail") as Polygon2D
	if sail != null:
		sail.color = sail_color
		var stripe: Polygon2D = body.get_node_or_null("SailStripe") as Polygon2D
		if stripe != null:
			stripe.color = accent
		else:
			_add_sail_band(sail, accent)

	_add_prow_ornament(hull, naval.motif as String, accent)

static func _civ_id(ship: Node2D, player_id: int) -> String:
	var cv: Variant = ship.get("civ_id")
	var cid: String = (cv as String) if cv is String else ""
	if cid.is_empty():
		cid = CivStyle.civ_id_for_player(player_id)
	return cid

static func _tint(body: Node2D, node_name: String, color: Color) -> void:
	var poly: Polygon2D = body.get_node_or_null(node_name) as Polygon2D
	if poly != null:
		poly.color = color

static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(p)
	return r

## Horizontal band across the middle of a plain sail, so hulls without a
## SailStripe of their own still fly the civ colour.
static func _add_sail_band(sail: Polygon2D, accent: Color) -> void:
	var b: Rect2 = _poly_bounds(sail.polygon)
	var mid: float = b.position.y + b.size.y * 0.45
	var band: Polygon2D = Polygon2D.new()
	band.name = "CivSailBand"
	band.color = accent
	band.z_index = 1
	band.polygon = PackedVector2Array([
		Vector2(b.position.x + 0.4, mid), Vector2(b.end.x - 0.4, mid),
		Vector2(b.end.x - 0.4, mid + 2.0), Vector2(b.position.x + 0.4, mid + 2.0),
	])
	sail.add_child(band)

## Ornaments hang off the hull node so they follow the ship's rotation, and sit
## at the bow — local -y, the direction every hull polygon points.
static func _add_prow_ornament(hull: Polygon2D, motif: String, accent: Color) -> void:
	var b: Rect2 = _poly_bounds(hull.polygon)
	var cx: float = (b.position.x + b.end.x) * 0.5
	var bow: float = b.position.y
	match motif:
		"fin":
			# Tall bronze dorsal fin plus a waterline stripe: the Atlantes
			# silhouette has to read as "the naval civ" at gameplay zoom.
			_add_ornament(hull, PackedVector2Array([
				Vector2(cx - 2.2, bow + 6.0), Vector2(cx - 0.8, bow - 3.0),
				Vector2(cx + 1.0, bow - 3.0), Vector2(cx + 2.4, bow + 6.0),
			]), accent)
			_add_ornament(hull, PackedVector2Array([
				Vector2(b.position.x + 0.6, b.end.y - 3.4),
				Vector2(b.end.x - 0.6, b.end.y - 3.4),
				Vector2(b.end.x - 0.6, b.end.y - 1.8),
				Vector2(b.position.x + 0.6, b.end.y - 1.8),
			]), accent, "B")
		"eye":
			_add_ornament(hull, PackedVector2Array([
				Vector2(b.position.x + 1.0, bow + 5.0),
				Vector2(b.position.x + 4.6, bow + 4.0),
				Vector2(b.position.x + 4.6, bow + 6.8),
				Vector2(b.position.x + 1.0, bow + 6.2),
			]), accent)
		"beak":
			_add_ornament(hull, PackedVector2Array([
				Vector2(cx - 1.8, bow + 1.2), Vector2(cx, bow - 3.6),
				Vector2(cx + 1.8, bow + 1.2),
			]), accent)
		_:
			pass  # "none": hull and sail carry the identity alone

static func _add_ornament(hull: Polygon2D, points: PackedVector2Array, color: Color,
		suffix: String = "") -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.name = "CivProw" + suffix
	poly.color = color
	poly.polygon = points
	poly.z_index = 1
	hull.add_child(poly)

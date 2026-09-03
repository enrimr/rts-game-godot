class_name IsoBuildingMassing
extends Object

## Procedural isometric massing for buildings.
##
## Buildings' `Body` nodes are uprighted billboards (see IsoBillboard): art
## authored inside Body is rendered 1:1 in screen space, anchored at the
## building's cartesian ground position. This module replaces the old flat
## front-facing facades with true isometric volumes authored in that screen
## space: a 2:1 diamond ground footprint matching the collision rect, two
## visible shaded wall faces (front-left and front-right), and a roof plane.
##
## Every generated polygon is a plain Polygon2D child of Body, so the existing
## team-accent pass in building_base (`Team*` name prefix) keeps recolouring
## flags, awnings and merlons, and the construction alpha fade keeps working.
##
## Civ identity: walls, trim and the ROOF SILHOUETTE come from CivStyle
## (per-civilization material + one of five roof shapes via Builder.civ_roof),
## so the same building type reads differently per civ at a glance. Ownership
## stays exclusively on the player-coloured Team* accents and stripes — the
## roof itself is civ material, never player colour.
##
## Geometry: a world-local point (x, y) at height h projects to screen
##   ((x - y) * K, (x + y) * K * 0.5 - h)      with K = sqrt(2) / 2,
## which is IsoProjection.world_to_screen plus an upright height offset.

const K: float = 0.7071067811865476

# Shared material tones (civ-agnostic details; walls/roofs come from CivStyle).
const C_STONE_DARK: Color = Color(0.52, 0.49, 0.44)
const C_WOOD_DARK: Color = Color(0.42, 0.30, 0.16)
const C_DOOR: Color = Color(0.28, 0.17, 0.08)
const C_WINDOW: Color = Color(0.92, 0.86, 0.55)
const C_APRON: Color = Color(0.47, 0.40, 0.28, 0.85)
const C_APRON_STONE: Color = Color(0.50, 0.48, 0.44, 0.85)
const C_POLE: Color = Color(0.32, 0.23, 0.12)
const C_SCAFFOLD: Color = Color(0.58, 0.44, 0.24)
const C_BASALT: Color = Color(0.37, 0.35, 0.34)
const C_BASALT_DARK: Color = Color(0.26, 0.245, 0.24)
const C_EARTH_SACRED: Color = Color(0.61, 0.49, 0.31, 0.96)
const C_BONE: Color = Color(0.91, 0.87, 0.77)
const C_EMBER: Color = Color(0.93, 0.47, 0.15)
const C_SMOKE: Color = Color(0.78, 0.77, 0.75)

const WALL_L_DARKEN: float = 0.34
const WALL_R_DARKEN: float = 0.12

## Screen-space point for world-local ground (x, y) lifted `h` pixels.
static func gp(x: float, y: float, h: float = 0.0) -> Vector2:
	return Vector2((x - y) * K, (x + y) * K * 0.5 - h)


class Builder extends RefCounted:
	var body: Node2D
	var style: Dictionary = CivStyle.DEFAULT_STYLE
	var top_y: float = INF
	var bot_y: float = -INF
	var _n: int = 0

	func _init(body_node: Node2D, style_dict: Dictionary = {}) -> void:
		body = body_node
		if not style_dict.is_empty():
			style = style_dict

	func wall() -> Color:
		return style.wall as Color

	func wall2() -> Color:
		return style.wall_shade as Color

	func trim() -> Color:
		return style.trim as Color

	func roof() -> Color:
		return style.roof_color as Color

	func poly(base_name: String, color: Color, pts: PackedVector2Array) -> Polygon2D:
		var p: Polygon2D = Polygon2D.new()
		_n += 1
		p.name = "%s_%d" % [base_name, _n]
		p.color = color
		p.polygon = pts
		for v: Vector2 in pts:
			top_y = minf(top_y, v.y)
			bot_y = maxf(bot_y, v.y)
		body.add_child(p)
		return p

	## Ground diamond matching a world rect centred (cx, cy), half (hx, hy).
	func footprint(cx: float, cy: float, hx: float, hy: float, color: Color) -> void:
		poly("Footprint", color, PackedVector2Array([
			IsoBuildingMassing.gp(cx - hx, cy - hy),
			IsoBuildingMassing.gp(cx + hx, cy - hy),
			IsoBuildingMassing.gp(cx + hx, cy + hy),
			IsoBuildingMassing.gp(cx - hx, cy + hy),
		]))

	## Two visible wall faces of a box: front-left (+y face) and
	## front-right (+x face), auto-shaded from the base wall colour.
	func walls(cx: float, cy: float, hx: float, hy: float,
			h0: float, h1: float, c: Color) -> void:
		var w: Vector2 = Vector2(cx - hx, cy + hy)
		var s: Vector2 = Vector2(cx + hx, cy + hy)
		var e: Vector2 = Vector2(cx + hx, cy - hy)
		poly("WallL", c.darkened(WALL_L_DARKEN), PackedVector2Array([
			IsoBuildingMassing.gp(w.x, w.y, h0), IsoBuildingMassing.gp(s.x, s.y, h0),
			IsoBuildingMassing.gp(s.x, s.y, h1), IsoBuildingMassing.gp(w.x, w.y, h1),
		]))
		poly("WallR", c.darkened(WALL_R_DARKEN), PackedVector2Array([
			IsoBuildingMassing.gp(s.x, s.y, h0), IsoBuildingMassing.gp(e.x, e.y, h0),
			IsoBuildingMassing.gp(e.x, e.y, h1), IsoBuildingMassing.gp(s.x, s.y, h1),
		]))

	func flat_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, c: Color, base_name: String = "Roof") -> void:
		poly(base_name, c, PackedVector2Array([
			IsoBuildingMassing.gp(cx - hx, cy - hy, h),
			IsoBuildingMassing.gp(cx + hx, cy - hy, h),
			IsoBuildingMassing.gp(cx + hx, cy + hy, h),
			IsoBuildingMassing.gp(cx - hx, cy + hy, h),
		]))

	## Hipped roof with a ridge inset along one axis. When `team` is true the
	## sunlit planes are named TeamRoof* so the accent pass recolours them.
	func hip_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, along_x: bool, team: bool = true,
			c: Color = Color(0.55, 0.30, 0.20)) -> void:
		var light_name: String = "TeamRoof" if team else "RoofLight"
		var dark_name: String = "TeamRoofDark" if team else "RoofDark"
		var cl: Color = c
		var cd: Color = c.darkened(0.30)
		var n: Vector2 = Vector2(cx - hx, cy - hy)
		var e: Vector2 = Vector2(cx + hx, cy - hy)
		var s: Vector2 = Vector2(cx + hx, cy + hy)
		var w: Vector2 = Vector2(cx - hx, cy + hy)
		var ht: float = h + rise
		if along_x:
			var r1: Vector2 = Vector2(cx - hx * 0.45, cy)
			var r2: Vector2 = Vector2(cx + hx * 0.45, cy)
			poly(dark_name, cd, _quad(n, e, r2, r1, h, ht))
			poly(dark_name, cd, _tri(w, n, r1, h, ht))
			poly(light_name, cl, _tri(e, s, r2, h, ht))
			poly(light_name, cl, _quad(w, s, r2, r1, h, ht))
		else:
			var r1: Vector2 = Vector2(cx, cy - hy * 0.45)
			var r2: Vector2 = Vector2(cx, cy + hy * 0.45)
			poly(dark_name, cd, _quad(n, w, r2, r1, h, ht))
			poly(dark_name, cd, _tri(n, e, r1, h, ht))
			poly(light_name, cl.darkened(0.10), _tri(w, s, r2, h, ht))
			poly(light_name, cl, _quad(e, s, r2, r1, h, ht))

	## Gable roof: full-length ridge plus a wall-coloured gable triangle on
	## the visible end face.
	func gable_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, along_x: bool, wall_c: Color,
			team: bool = true, c: Color = Color(0.55, 0.30, 0.20)) -> void:
		var light_name: String = "TeamRoof" if team else "RoofLight"
		var dark_name: String = "TeamRoofDark" if team else "RoofDark"
		var cl: Color = c
		var cd: Color = c.darkened(0.30)
		var n: Vector2 = Vector2(cx - hx, cy - hy)
		var e: Vector2 = Vector2(cx + hx, cy - hy)
		var s: Vector2 = Vector2(cx + hx, cy + hy)
		var w: Vector2 = Vector2(cx - hx, cy + hy)
		var ht: float = h + rise
		if along_x:
			var r1: Vector2 = Vector2(cx - hx, cy)
			var r2: Vector2 = Vector2(cx + hx, cy)
			poly(dark_name, cd, _quad(n, e, r2, r1, h, ht))
			poly("Gable", wall_c.darkened(WALL_R_DARKEN + 0.05), _tri(s, e, r2, h, ht))
			poly(light_name, cl, _quad(w, s, r2, r1, h, ht))
		else:
			var r1: Vector2 = Vector2(cx, cy - hy)
			var r2: Vector2 = Vector2(cx, cy + hy)
			poly(dark_name, cd, _quad(n, w, r2, r1, h, ht))
			poly("Gable", wall_c.darkened(WALL_L_DARKEN + 0.03), _tri(w, s, r2, h, ht))
			poly(light_name, cl, _quad(e, s, r2, r1, h, ht))

	## Pyramid roof to a central apex (towers, temple dome stand-in).
	func pyramid_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, team: bool = true,
			c: Color = Color(0.55, 0.30, 0.20)) -> void:
		var light_name: String = "TeamRoof" if team else "RoofLight"
		var dark_name: String = "TeamRoofDark" if team else "RoofDark"
		var cl: Color = c
		var cd: Color = c.darkened(0.30)
		var n: Vector2 = Vector2(cx - hx, cy - hy)
		var e: Vector2 = Vector2(cx + hx, cy - hy)
		var s: Vector2 = Vector2(cx + hx, cy + hy)
		var w: Vector2 = Vector2(cx - hx, cy + hy)
		var a: Vector2 = Vector2(cx, cy)
		var ht: float = h + rise
		poly(dark_name, cd.darkened(0.15), _tri(n, e, a, h, ht))
		poly(dark_name, cd.darkened(0.15), _tri(w, n, a, h, ht))
		poly(dark_name, cd, _tri(w, s, a, h, ht))
		poly(light_name, cl, _tri(s, e, a, h, ht))

	## Civilization-identity roof: dispatches on the owner civ's Roof silhouette
	## and tints it with the civ roof material colour. Ownership never rides on
	## the roof — it stays on the Team* accents (flags, awnings, merlons).
	## `gable_wall` overrides the gable-triangle colour when the walls below are
	## not the civ's base wall tone (alpha 0 = use style.wall).
	func civ_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, along_x: bool = true,
			gable_wall: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
		var rc: Color = roof()
		var wc: Color = wall() if gable_wall.a == 0.0 else gable_wall
		match int(style.roof):
			CivStyle.Roof.FLAT:
				_flat_parapet_roof(cx, cy, hx, hy, h, rise, rc)
			CivStyle.Roof.DOMED:
				_dome_roof(cx, cy, hx, hy, h, rise, rc)
			CivStyle.Roof.STEPPED:
				_stepped_roof(cx, cy, hx, hy, h, rise, rc)
			CivStyle.Roof.GABLED:
				gable_roof(cx, cy, hx, hy, h, rise * 1.75, along_x, wc, false, rc)
				_ridge_cap(cx, cy, hx, hy, h + rise * 1.75, along_x, 1.0)
			_:
				hip_roof(cx, cy, hx, hy, h, rise, along_x, false, rc)
				_ridge_cap(cx, cy, hx, hy, h + rise, along_x, 0.45)

	## Trim-coloured beam capping a roof ridge.
	func _ridge_cap(cx: float, cy: float, hx: float, hy: float,
			ht: float, along_x: bool, span: float) -> void:
		var p0: Vector2 = Vector2(cx - hx * span, cy) if along_x else Vector2(cx, cy - hy * span)
		var p1: Vector2 = Vector2(cx + hx * span, cy) if along_x else Vector2(cx, cy + hy * span)
		poly("RidgeBeam", trim(), Builder._quad(p0, p1, p1, p0, ht - 0.2, ht + 1.5))

	## FLAT: low slab enclosed by a parapet with a trim course — squat profile.
	func _flat_parapet_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, rc: Color) -> void:
		var lip: float = clampf(rise * 0.35, 3.0, 6.0)
		walls(cx, cy, hx, hy, h, h + lip, rc)
		walls(cx, cy, hx, hy, h + lip - 1.5, h + lip, trim())
		flat_roof(cx, cy, hx, hy, h + lip, rc.lightened(0.14), "Parapet")
		flat_roof(cx, cy, maxf(hx - 4.0, hx * 0.55), maxf(hy - 4.0, hy * 0.55),
			h + lip - 1.5, rc.darkened(0.10), "RoofTerrace")

	## DOMED: low rounded dome on a short drum, trim finial at the apex.
	func _dome_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, rc: Color) -> void:
		var deck_h: float = 2.5
		walls(cx, cy, hx, hy, h, h + deck_h, wall())
		flat_roof(cx, cy, hx, hy, h + deck_h, wall().lightened(0.10), "RoofDeck")
		var c0: Vector2 = IsoBuildingMassing.gp(cx, cy, h + deck_h)
		var r: float = (hx + hy) * IsoBuildingMassing.K * 0.55
		var dh: float = maxf(rise, r * 0.55)
		poly("Dome", rc.darkened(0.18), Builder._dome_pts(c0, r, dh))
		poly("DomeLight", rc.lightened(0.05),
			Builder._dome_pts(c0 + Vector2(r * 0.22, 0.0), r * 0.6, dh * 0.8))
		poly("Finial", trim(), PackedVector2Array([
			c0 + Vector2(-1.2, -dh + 1.0), c0 + Vector2(1.2, -dh + 1.0),
			c0 + Vector2(1.2, -dh - 3.5), c0 + Vector2(-1.2, -dh - 3.5),
		]))

	## STEPPED: two stacked slabs, ziggurat-like, trim band on the upper edge.
	func _stepped_roof(cx: float, cy: float, hx: float, hy: float,
			h: float, rise: float, rc: Color) -> void:
		var h1: float = h + rise * 0.5
		walls(cx, cy, hx, hy, h, h1, rc)
		flat_roof(cx, cy, hx, hy, h1, rc.lightened(0.10), "StepLow")
		var ix: float = maxf(hx * 0.58, minf(hx, 6.0))
		var iy: float = maxf(hy * 0.58, minf(hy, 6.0))
		var h2: float = h1 + rise * 0.55
		walls(cx, cy, ix, iy, h1, h2, rc.darkened(0.05))
		walls(cx, cy, ix, iy, h2 - 1.4, h2, trim())
		flat_roof(cx, cy, ix, iy, h2, rc.lightened(0.20), "StepTop")

	## Door/window opening on the front-right (+x) wall face; t runs 0..1 from
	## the bottom corner (S) to the right corner (E).
	func opening_right(cx: float, cy: float, hx: float, hy: float,
			t0: float, t1: float, h0: float, h1: float, c: Color,
			base_name: String = "Door") -> void:
		var s: Vector2 = Vector2(cx + hx, cy + hy)
		var e: Vector2 = Vector2(cx + hx, cy - hy)
		_opening(s, e, t0, t1, h0, h1, c, base_name)

	## Same on the front-left (+y) wall face; t runs from left corner (W) to
	## bottom corner (S).
	func opening_left(cx: float, cy: float, hx: float, hy: float,
			t0: float, t1: float, h0: float, h1: float, c: Color,
			base_name: String = "Door") -> void:
		var w: Vector2 = Vector2(cx - hx, cy + hy)
		var s: Vector2 = Vector2(cx + hx, cy + hy)
		_opening(w, s, t0, t1, h0, h1, c, base_name)

	func _opening(a: Vector2, b: Vector2, t0: float, t1: float,
			h0: float, h1: float, c: Color, base_name: String) -> void:
		var p0: Vector2 = a.lerp(b, t0)
		var p1: Vector2 = a.lerp(b, t1)
		poly(base_name, c, PackedVector2Array([
			IsoBuildingMassing.gp(p0.x, p0.y, h0), IsoBuildingMassing.gp(p1.x, p1.y, h0),
			IsoBuildingMassing.gp(p1.x, p1.y, h1), IsoBuildingMassing.gp(p0.x, p0.y, h1),
		]))

	## Upright post standing on ground point (x, y): fences, stilts, scaffolds.
	func post(x: float, y: float, h: float, w: float, c: Color,
			base_name: String = "Post") -> void:
		var base: Vector2 = IsoBuildingMassing.gp(x, y)
		poly(base_name, c, PackedVector2Array([
			base + Vector2(-w * 0.5, 0.0), base + Vector2(w * 0.5, 0.0),
			base + Vector2(w * 0.5, -h), base + Vector2(-w * 0.5, -h),
		]))

	## Flag pole + team pennant standing on ground point (x, y).
	func flag(x: float, y: float, h0: float, h1: float, mirror: bool = false) -> void:
		var b: Vector2 = IsoBuildingMassing.gp(x, y, h0)
		var t: Vector2 = IsoBuildingMassing.gp(x, y, h1)
		poly("FlagPole", C_POLE, PackedVector2Array([
			b + Vector2(-0.7, 0.0), b + Vector2(0.7, 0.0),
			t + Vector2(0.7, 0.0), t + Vector2(-0.7, 0.0),
		]))
		var dx: float = -9.0 if mirror else 9.0
		poly("TeamFlag", Color.WHITE, PackedVector2Array([
			t, t + Vector2(dx, 2.5), t + Vector2(0.0, 5.5),
		]))

	## Flat ground ellipse (screen-space 2:1) around ground point (x, y).
	func ground_ellipse(x: float, y: float, rx: float, c: Color,
			base_name: String = "GroundDisc") -> void:
		var centre: Vector2 = IsoBuildingMassing.gp(x, y)
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(12):
			var a: float = TAU * float(i) / 12.0
			pts.append(centre + Vector2(cos(a) * rx, sin(a) * rx * 0.5))
		poly(base_name, c, pts)

	static func _quad(a: Vector2, b: Vector2, c2: Vector2, d: Vector2,
			h_ab: float, h_cd: float) -> PackedVector2Array:
		return PackedVector2Array([
			IsoBuildingMassing.gp(a.x, a.y, h_ab), IsoBuildingMassing.gp(b.x, b.y, h_ab),
			IsoBuildingMassing.gp(c2.x, c2.y, h_cd), IsoBuildingMassing.gp(d.x, d.y, h_cd),
		])

	static func _tri(a: Vector2, b: Vector2, c2: Vector2,
			h_ab: float, h_c: float) -> PackedVector2Array:
		return PackedVector2Array([
			IsoBuildingMassing.gp(a.x, a.y, h_ab), IsoBuildingMassing.gp(b.x, b.y, h_ab),
			IsoBuildingMassing.gp(c2.x, c2.y, h_c),
		])

	## Screen-space dome silhouette: top arc rising `dh` above centre `c0`,
	## closed by a shallow elliptical bulge along the bottom.
	static func _dome_pts(c0: Vector2, r: float, dh: float) -> PackedVector2Array:
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(13):
			var a: float = PI * float(i) / 12.0
			pts.append(c0 + Vector2(cos(a) * r, -sin(a) * dh))
		for i: int in range(1, 12):
			var a: float = PI + PI * float(i) / 12.0
			pts.append(c0 + Vector2(cos(a) * r, -sin(a) * r * 0.18))
		return pts


## Entry point: rebuilds `building`'s Body with isometric massing if a recipe
## exists for it. Returns false (leaving authored art untouched) for
## ground-plane buildings like Farm and Fish Trap.
static func apply(building: Node2D) -> bool:
	var key: String = _massing_key(building)
	if not _has_recipe(key):
		return false
	var body: Node2D = building.get_node_or_null("Body") as Node2D
	if body == null:
		return false
	var half: Vector2 = _half_extents(building)
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var pid_v: Variant = building.get("player_id")
	var style: Dictionary = CivStyle.style_for_player((pid_v as int) if pid_v is int else 0)
	var b: Builder = Builder.new(body, style)
	_build(key, b, half.x, half.y)
	_add_scaffold_rig(building, b, half.x, half.y)
	_add_contact_shadow(building, half)
	_place_overlays(building, b, half)
	building.set_meta("massing_top_y", b.top_y)
	building.set_meta("massing_bot_y", b.bot_y)
	return true

## Ground-contact shadow matching the iso footprint: the collision rect grown
## a few px, authored in WORLD space on the building root so the camera
## projection lays it flat as a diamond hugging the footprint — this seats the
## volume on the terrain instead of the old detached ellipse. Idempotent.
static func _add_contact_shadow(building: Node2D, half: Vector2) -> void:
	if building.get_node_or_null("FootprintShadow") != null:
		return
	var grow: float = 7.0
	var shadow: Polygon2D = Polygon2D.new()
	shadow.name = "FootprintShadow"
	shadow.color = Color(0.0, 0.0, 0.0, 0.22)
	shadow.z_index = -2
	shadow.polygon = PackedVector2Array([
		Vector2(-half.x - grow, -half.y - grow),
		Vector2(half.x + grow, -half.y - grow),
		Vector2(half.x + grow, half.y + grow),
		Vector2(-half.x - grow, half.y + grow),
	])
	shadow.set_meta(IsoBillboard.META_GROUND, true)
	building.add_child(shadow)

static func _massing_key(building: Node2D) -> String:
	var data: Resource = building.get("building_data") as Resource
	if data != null:
		var id: Variant = data.get("id")
		if id is String and not (id as String).is_empty():
			return id as String
	var base: String = building.scene_file_path.get_file().get_basename()
	return "town_center" if base == "town_center_ai" else base

static func _has_recipe(key: String) -> bool:
	return key in ["house", "town_center", "barracks", "archery_range", "stable",
		"blacksmith", "university", "temple", "market", "siege_workshop",
		"lumber_camp", "mining_camp", "mill", "dock", "watch_tower", "wonder",
		"wall_segment", "gate", "fish_trap"]

static func _half_extents(building: Node2D) -> Vector2:
	var cs: CollisionShape2D = building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).size * 0.5
	return Vector2(24.0, 24.0)

## Repositions the upright overlays (name label above the massing silhouette,
## progress bars below the footprint diamond) so they never cross the volume.
static func _place_overlays(building: Node2D, b: Builder, half: Vector2) -> void:
	var bar_w: float = maxf(24.0, (half.x + half.y) * K * 0.75)
	for label_name: String in ["NameLabel", "StateLabel", "Label"]:
		var label: Label = building.get_node_or_null(label_name) as Label
		if label != null:
			label.offset_top = b.top_y - 15.0
			label.offset_bottom = b.top_y - 3.0
	var slot: int = 0
	for bar_name: String in ["ConstructionBar", "TrainingBar", "FoodBar", "HealthBar"]:
		var bar: ProgressBar = building.get_node_or_null(bar_name) as ProgressBar
		if bar == null:
			continue
		var y: float = b.bot_y + 4.0 + float(slot) * 10.0
		bar.offset_left = -bar_w
		bar.offset_right = bar_w
		bar.offset_top = y
		bar.offset_bottom = y + 7.0
		slot += 1

## Wooden scaffold rig shown while the building is under construction: corner
## poles with rails and braces hugging the footprint. Added as an upright
## sibling of Body so it stays opaque while the massing fades in.
static func _add_scaffold_rig(building: Node2D, b: Builder, hx: float, hy: float) -> void:
	if building.get_node_or_null("ScaffoldRig") != null:
		return
	var rig: Node2D = Node2D.new()
	rig.name = "ScaffoldRig"
	rig.visible = false
	building.add_child(rig)
	var rb: Builder = Builder.new(rig)
	var h: float = maxf(14.0, (b.bot_y - b.top_y) * 0.5)
	var m: float = 1.10
	var corners: Array[Vector2] = [
		Vector2(-hx * m, hy * m), Vector2(hx * m, hy * m), Vector2(hx * m, -hy * m),
	]
	for c: Vector2 in corners:
		rb.post(c.x, c.y, h, 1.6, C_SCAFFOLD, "ScafPole")
	for rail_h: float in [h * 0.45, h * 0.9]:
		rb.poly("ScafRail", C_SCAFFOLD.darkened(0.15), Builder._quad(
			corners[0], corners[1], corners[1], corners[0], rail_h, rail_h + 1.4))
		rb.poly("ScafRail", C_SCAFFOLD.darkened(0.25), Builder._quad(
			corners[1], corners[2], corners[2], corners[1], rail_h, rail_h + 1.4))
	rb.poly("ScafBrace", C_SCAFFOLD.darkened(0.35), PackedVector2Array([
		gp(corners[0].x, corners[0].y, 1.0), gp(corners[1].x, corners[1].y, h * 0.85),
		gp(corners[1].x, corners[1].y, h * 0.85 + 1.4), gp(corners[0].x, corners[0].y, 2.4),
	]))
	rb.poly("ScafBrace", C_SCAFFOLD.darkened(0.4), PackedVector2Array([
		gp(corners[2].x, corners[2].y, 1.0), gp(corners[1].x, corners[1].y, h * 0.85),
		gp(corners[1].x, corners[1].y, h * 0.85 + 1.4), gp(corners[2].x, corners[2].y, 2.4),
	]))

static func _build(key: String, b: Builder, hx: float, hy: float) -> void:
	match key:
		"house": _house(b, hx, hy)
		"town_center": _town_center(b, hx, hy)
		"barracks": _barracks(b, hx, hy)
		"archery_range": _archery_range(b, hx, hy)
		"stable": _stable(b, hx, hy)
		"blacksmith": _blacksmith(b, hx, hy)
		"university": _university(b, hx, hy)
		"temple": _temple(b, hx, hy)
		"market": _market(b, hx, hy)
		"siege_workshop": _siege_workshop(b, hx, hy)
		"lumber_camp": _lumber_camp(b, hx, hy)
		"mining_camp": _mining_camp(b, hx, hy)
		"mill": _mill(b, hx, hy)
		"dock": _dock(b, hx, hy)
		"watch_tower": _watch_tower(b, hx, hy)
		"wonder": _wonder(b, hx, hy)
		"wall_segment": _wall_segment(b, hx, hy)
		"gate": _gate(b, hx, hy)
		"fish_trap": _fish_trap(b, hx, hy)

# --- Recipes -----------------------------------------------------------------

static func _house(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 3.0
	var wy: float = hy - 3.0
	b.walls(0, 0, wx, wy, 0.0, 17.0, b.wall())
	b.civ_roof(0, 0, wx + 3.0, wy + 3.0, 16.0, 12.0, true)
	b.opening_right(0, 0, wx, wy, 0.25, 0.5, 0.0, 11.0, C_DOOR, "Door")
	b.opening_left(0, 0, wx, wy, 0.3, 0.55, 5.0, 11.0, C_WINDOW, "Window")

static func _town_center(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	# Foundation plinth: a low stone course wider than the keep walls that
	# seats the volume on the ground diamond instead of floating on it.
	b.walls(0, 0, hx - 1.0, hy - 1.0, 0.0, 3.5, b.wall2().lightened(0.06))
	b.flat_roof(0, 0, hx - 1.0, hy - 1.0, 3.5, b.wall2().lightened(0.22), "PlinthTop")
	b.walls(0, 0, hx - 4.0, hy - 4.0, 3.5, 20.0, b.wall())
	b.flat_roof(0, 0, hx - 2.0, hy - 2.0, 20.0, b.wall().lightened(0.10), "WalkTop")
	b.opening_right(0, 0, hx - 4.0, hy - 4.0, 0.32, 0.58, 0.0, 14.0, C_DOOR, "Gatehouse")
	b.opening_left(0, 0, hx - 4.0, hy - 4.0, 0.34, 0.5, 6.0, 13.0, C_WINDOW, "Window")
	b.walls(0, 0, 22.0, 22.0, 20.0, 38.0, b.wall().lightened(0.06))
	b.civ_roof(0, 0, 26.0, 26.0, 37.0, 14.0, true)
	for t: Vector2 in [Vector2(-hx + 10.0, hy - 10.0), Vector2(hx - 10.0, -hy + 10.0)]:
		b.walls(t.x, t.y, 9.0, 9.0, 0.0, 32.0, b.wall2())
		b.flat_roof(t.x, t.y, 10.5, 10.5, 32.0, b.wall2().lightened(0.18), "TowerCap")
		b.pyramid_roof(t.x, t.y, 10.5, 10.5, 33.0, 9.0, false, b.roof())
	b.flag(-hx + 10.0, hy - 10.0, 42.0, 56.0, true)
	b.flag(hx - 10.0, -hy + 10.0, 42.0, 56.0)

static func _barracks(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 4.0
	var wy: float = hy - 4.0
	b.walls(0, 0, wx, wy, 0.0, 20.0, b.wall())
	b.civ_roof(0, 0, wx + 3.0, wy + 3.0, 19.0, 13.0, true)
	b.opening_right(0, 0, wx, wy, 0.28, 0.6, 0.0, 15.0, C_DOOR, "Door")
	b.opening_left(0, 0, wx, wy, 0.2, 0.32, 6.0, 13.0, Color(0.2, 0.18, 0.16), "Slit")
	b.opening_left(0, 0, wx, wy, 0.55, 0.67, 6.0, 13.0, Color(0.2, 0.18, 0.16), "Slit")
	b.flag(-wx * 0.4, wy, 20.0, 40.0, true)

static func _archery_range(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 12.0
	b.ground_ellipse(hx - 16.0, hy - 16.0, 9.0, Color(0.9, 0.88, 0.8), "TargetOuter")
	b.ground_ellipse(hx - 16.0, hy - 16.0, 5.5, Color(0.75, 0.2, 0.15), "TargetMid")
	b.ground_ellipse(hx - 16.0, hy - 16.0, 2.2, Color(0.95, 0.9, 0.5), "TargetPin")
	b.walls(-6.0, -6.0, wx, wx, 0.0, 17.0, b.wall())
	b.civ_roof(-6.0, -6.0, wx + 3.0, wx + 3.0, 16.0, 11.0, false)
	b.opening_left(-6.0, -6.0, wx, wx, 0.3, 0.6, 0.0, 12.0, C_DOOR, "Door")
	b.flag(-6.0, -6.0 - wx, 27.0, 44.0)

static func _stable(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 10.0
	var wy: float = hy - 16.0
	b.walls(-4.0, -8.0, wx, wy, 0.0, 16.0, b.wall())
	b.civ_roof(-4.0, -8.0, wx + 4.0, wy + 4.0, 15.0, 11.0, true)
	b.opening_right(-4.0, -8.0, wx, wy, 0.2, 0.75, 0.0, 13.0, C_WOOD_DARK, "BarnDoor")
	var fy: float = hy - 5.0
	for i: int in range(5):
		var fx: float = -hx + 6.0 + float(i) * (hx * 2.0 - 12.0) / 4.0
		b.post(fx, fy, 8.0, 1.6, C_WOOD_DARK, "FencePost")
	b.poly("FenceRail", C_WOOD_DARK.lightened(0.15), Builder._quad(
		Vector2(-hx + 6.0, fy), Vector2(hx - 6.0, fy),
		Vector2(hx - 6.0, fy), Vector2(-hx + 6.0, fy), 5.0, 6.4))

static func _blacksmith(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 6.0
	var wy: float = hy - 6.0
	b.walls(0, 0, wx, wy, 0.0, 16.0, b.wall2())
	b.civ_roof(0, 0, wx + 3.0, wy + 3.0, 15.0, 10.0, true, b.wall2())
	b.opening_right(0, 0, wx, wy, 0.3, 0.62, 0.0, 12.0, Color(0.95, 0.5, 0.15), "ForgeGlow")
	b.walls(-wx + 8.0, -wy + 8.0, 4.5, 4.5, 15.0, 36.0, Color(0.36, 0.32, 0.28))
	b.flat_roof(-wx + 8.0, -wy + 8.0, 5.5, 5.5, 36.0, Color(0.25, 0.22, 0.20), "ChimneyCap")
	b.ground_ellipse(hx - 14.0, hy - 20.0, 6.0, Color(0.35, 0.33, 0.3), "Anvil")

static func _university(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 5.0
	var wy: float = hy - 5.0
	b.walls(0, 0, wx, wy, 0.0, 24.0, b.wall().lightened(0.05))
	b.civ_roof(0, 0, wx + 3.0, wy + 3.0, 23.0, 13.0, false)
	for t: Array in [[0.2, 0.32], [0.44, 0.56], [0.68, 0.8]]:
		b.opening_right(0, 0, wx, wy, t[0], t[1], 9.0, 18.0, C_WINDOW, "Window")
	b.opening_left(0, 0, wx, wy, 0.35, 0.6, 0.0, 15.0, C_DOOR, "Portal")
	b.flag(0, wy, 36.0, 52.0, true)

## Almogarén: an open pre-conquest mountain shrine — dry-stone precinct with
## a stone cairn, a standing monolith and ritual dressings instead of a roofed
## hall. The sanctuary is Canarian whichever banner flies over it
## (docs/lore/harimaguada.md), so civ identity rides only on the monolith's
## painted band and ownership only on the Team* flag by the entrance.
static func _temple(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_EARTH_SACRED)
	_temple_ring_wall(b, 0.0, -hy + 4.5, hx - 2.0, 2.5)
	_temple_ring_wall(b, -hx + 4.5, 0.0, 2.5, hy - 2.0)
	_temple_monolith(b, Vector2(3.0, -hy + 11.0), b.trim())
	_temple_cairn(b, Vector2(-13.0, -11.0))
	b.ground_ellipse(-3.0, 4.0, 2.4, C_BONE, "Bowl")
	b.ground_ellipse(2.5, 9.0, 2.0, C_BONE.darkened(0.12), "Bowl")
	_temple_fire(b, Vector2(13.0, 11.0))
	_temple_tunics(b, hx)
	_temple_ring_wall(b, hx - 4.5, 0.0, 2.5, hy - 2.0)
	var seg: float = (hx - 11.0) * 0.5
	_temple_ring_wall(b, -9.0 - seg, hy - 4.5, seg, 2.5)
	_temple_ring_wall(b, 9.0 + seg, hy - 4.5, seg, 2.5)
	_temple_idol(b, Vector2(-11.5, hy - 4.5))
	_temple_idol(b, Vector2(11.5, hy - 4.5))
	b.flag(-hx + 9.0, hy - 9.0, 0.0, 26.0, true)

## Low dry-stone course with a lighter walk top and irregular capstones.
static func _temple_ring_wall(b: Builder, cx: float, cy: float,
		sx: float, sy: float) -> void:
	b.walls(cx, cy, sx, sy, 0.0, 6.0, C_BASALT)
	b.flat_roof(cx, cy, sx, sy, 6.0, C_BASALT.lightened(0.16), "RingTop")
	var axis: Vector2 = Vector2(1.0, 0.0) if sx > sy else Vector2(0.0, 1.0)
	var span: float = maxf(sx, sy) - 2.0
	for t: float in [-0.6, 0.05, 0.65]:
		var p: Vector2 = Vector2(cx, cy) + axis * span * t
		var e: Vector2 = axis * 1.8
		b.poly("CapStone", C_BASALT.darkened(0.12 - 0.1 * t),
			Builder._quad(p - e, p + e, p + e, p - e, 6.0, 8.6))

## Tall standing stone, slightly tapered and leaning, with the civ-trim
## painted band — the shrine's landmark silhouette.
static func _temple_monolith(b: Builder, at: Vector2, band: Color) -> void:
	var warm: Color = Color(0.47, 0.43, 0.38)
	var m: Vector2 = IsoBuildingMassing.gp(at.x, at.y)
	b.poly("MonolithBack", warm.darkened(0.30), PackedVector2Array([
		m + Vector2(1.6, -0.4), m + Vector2(7.0, -1.6),
		m + Vector2(2.6, -23.5), m + Vector2(-0.4, -27.0)]))
	b.poly("Monolith", warm.lightened(0.08), PackedVector2Array([
		m + Vector2(-7.0, 0.4), m + Vector2(2.6, -0.7), m + Vector2(1.4, -20.0),
		m + Vector2(-1.8, -27.6), m + Vector2(-5.4, -22.0), m + Vector2(-6.4, -12.0)]))
	b.poly("MonolithBand", band, PackedVector2Array([
		m + Vector2(-6.1, -14.5), m + Vector2(1.75, -14.2),
		m + Vector2(1.55, -17.4), m + Vector2(-5.85, -17.8)]))
	b.post(at.x + 6.0, at.y + 2.5, 4.5, 3.6, warm.darkened(0.22), "BaseStone")
	b.post(at.x - 6.0, at.y + 3.5, 3.2, 3.0, C_BASALT_DARK, "BaseStone")

## Rounded stacked-stone cairn with a dark chamber mouth facing the entrance.
static func _temple_cairn(b: Builder, at: Vector2) -> void:
	b.ground_ellipse(at.x, at.y, 16.0, C_BASALT_DARK, "CairnBase")
	var c0: Vector2 = IsoBuildingMassing.gp(at.x, at.y, 0.5)
	b.poly("Cairn", C_BASALT, Builder._dome_pts(c0, 14.5, 12.5))
	b.poly("CairnLight", C_BASALT.lightened(0.13),
		Builder._dome_pts(c0 + Vector2(4.0, 0.0), 8.0, 9.5))
	for s: Vector2 in [Vector2(-11.0, 5.0), Vector2(-2.0, 9.5), Vector2(9.0, 3.0)]:
		b.post(at.x + s.x, at.y + s.y, 3.4, 3.0, C_BASALT_DARK.lightened(0.06), "CairnStone")
	b.poly("CaveMouth", Color(0.13, 0.11, 0.10),
		Builder._dome_pts(IsoBuildingMassing.gp(at.x + 6.5, at.y + 6.5), 5.0, 6.5))

## Offering fire: stone ring, embers, one flame lick and a rising smoke wisp.
static func _temple_fire(b: Builder, at: Vector2) -> void:
	b.ground_ellipse(at.x, at.y, 6.0, C_BASALT_DARK, "FireRing")
	b.ground_ellipse(at.x, at.y, 3.4, C_EMBER, "Embers")
	var f: Vector2 = IsoBuildingMassing.gp(at.x, at.y)
	b.poly("Flame", Color(0.98, 0.74, 0.28), PackedVector2Array([
		f + Vector2(-2.2, 0.5), f + Vector2(2.2, 0.5), f + Vector2(0.4, -6.5)]))
	for i: int in range(3):
		var k: float = float(i)
		var c: Vector2 = f + Vector2(1.5 + k * 1.8, -9.0 - k * 7.5)
		var r: float = 2.6 + k * 1.1
		var pts: PackedVector2Array = PackedVector2Array()
		for j: int in range(10):
			var a: float = TAU * float(j) / 10.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.8))
		b.poly("Smoke", Color(C_SMOKE.r, C_SMOKE.g, C_SMOKE.b, 0.40 - k * 0.09), pts)

## The harimaguadas' white leather tunics drying on a cord between two posts.
static func _temple_tunics(b: Builder, hx: float) -> void:
	var a: Vector2 = Vector2(hx - 16.0, -12.0)
	var c: Vector2 = Vector2(hx - 16.0, 14.0)
	b.post(a.x, a.y, 15.0, 2.2, C_WOOD_DARK, "CordPost")
	b.post(c.x, c.y, 15.0, 2.2, C_WOOD_DARK, "CordPost")
	b.poly("Cord", C_POLE, Builder._quad(a, c, c, a, 13.6, 14.3))
	for t: float in [0.22, 0.5, 0.78]:
		var p: Vector2 = a.lerp(c, t)
		var drop: float = 4.5 if t == 0.5 else 6.5
		b.poly("Tunic", C_BONE.darkened(absf(t - 0.5) * 0.20), Builder._quad(
			Vector2(p.x, p.y - 2.8), Vector2(p.x, p.y + 2.8),
			Vector2(p.x, p.y + 2.8), Vector2(p.x, p.y - 2.8), drop, 13.8))

## Carved wooden idol post flanking the precinct entrance.
static func _temple_idol(b: Builder, at: Vector2) -> void:
	b.post(at.x, at.y, 12.0, 2.6, C_WOOD_DARK, "IdolPost")
	var t: Vector2 = IsoBuildingMassing.gp(at.x, at.y, 12.0)
	b.poly("IdolHead", C_WOOD_DARK.lightened(0.22), PackedVector2Array([
		t + Vector2(-2.2, 0.0), t + Vector2(2.2, 0.0),
		t + Vector2(1.6, -4.2), t + Vector2(-1.6, -4.2)]))
	b.poly("IdolNotch", C_WOOD_DARK.darkened(0.2), PackedVector2Array([
		t + Vector2(-1.6, -1.2), t + Vector2(1.6, -1.2),
		t + Vector2(1.6, -2.0), t + Vector2(-1.6, -2.0)]))

static func _market(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 14.0
	var wy: float = hy - 14.0
	b.walls(-6.0, -6.0, wx, wy, 0.0, 13.0, b.wall())
	b.civ_roof(-6.0, -6.0, wx + 4.0, wy + 4.0, 12.0, 9.0, true)
	var s: Vector2 = Vector2(-6.0 + wx, -6.0 + wy)
	var e: Vector2 = Vector2(-6.0 + wx, -6.0 - wy)
	b.poly("TeamAwning", Color.WHITE, PackedVector2Array([
		gp(s.x, s.y, 13.0), gp(e.x, e.y, 13.0),
		gp(e.x + 9.0, e.y, 8.0), gp(s.x + 9.0, s.y, 8.0),
	]))
	for st: Vector2 in [Vector2(hx - 12.0, hy - 24.0), Vector2(hx - 26.0, hy - 10.0)]:
		b.walls(st.x, st.y, 6.0, 6.0, 0.0, 7.0, C_WOOD_DARK.lightened(0.2))
		b.hip_roof(st.x, st.y, 8.0, 8.0, 7.0, 4.0, true, false, b.roof())
	b.flag(-6.0, -6.0 - wy, 22.0, 38.0)

static func _siege_workshop(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 5.0
	var wy: float = hy - 5.0
	b.walls(0, 0, wx, wy, 0.0, 19.0, b.wall2())
	b.civ_roof(0, 0, wx + 3.0, wy + 3.0, 18.0, 12.0, false, b.wall2())
	b.opening_left(0, 0, wx, wy, 0.22, 0.72, 0.0, 15.0, Color(0.16, 0.12, 0.08), "Bay")
	b.opening_right(0, 0, wx, wy, 0.4, 0.52, 7.0, 14.0, C_WINDOW, "Window")
	b.post(hx - 8.0, hy - 8.0, 12.0, 2.2, C_WOOD_DARK, "Crane")
	b.flag(0, -wy, 30.0, 46.0)

## Screen-space ellipse (small discs: log ends, wheels, ore lumps).
static func _disc(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(12):
		var a: float = TAU * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## Open-air logging yard, not a house: pole lean-to under a team tarp,
## stacked log pile with pale cut ends, a saw-horse trunk mid-cut, a
## chopping block with an axe planted in it and fresh stumps.
static func _lumber_camp(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	b.ground_ellipse(1.0, 8.0, 9.0, Color(0.68, 0.56, 0.36, 0.45), "ChipFloor")
	_lc_lean_to(b, -hx + 13.0, -hy + 12.0)
	_lc_log_pile(b, hx - 13.0, -hy + 14.0)
	_lc_stump(b, hx - 7.0, hy - 6.0)
	_lc_saw_horse(b, -1.0, hy - 10.0)
	_lc_chop_block(b, -hx + 9.0, hy - 8.0)
	b.flag(hx - 4.0, -hy + 4.0, 0.0, 30.0, true)

## Pole shelter with a mono-pitch tarp (high back, low front) over a
## firewood row — the crew's only "roof".
static func _lc_lean_to(b: Builder, cx: float, cy: float) -> void:
	var sx: float = 10.0
	var sy: float = 8.0
	var back_h: float = 17.0
	var front_h: float = 10.0
	b.poly("FireWood", C_WOOD_DARK.lightened(0.10), Builder._quad(
		Vector2(cx - sx + 2.0, cy), Vector2(cx + sx - 2.0, cy),
		Vector2(cx + sx - 2.0, cy), Vector2(cx - sx + 2.0, cy), 0.0, 5.5))
	b.poly("FireWoodEnd", Color(0.82, 0.68, 0.42),
		_disc(gp(cx + sx - 2.0, cy, 2.7), 2.2, 2.5))
	b.post(cx - sx, cy - sy, back_h, 1.8, C_POLE, "LeanPost")
	b.post(cx - sx, cy + sy, back_h, 1.8, C_POLE, "LeanPost")
	b.post(cx + sx, cy - sy, front_h, 1.8, C_POLE, "LeanPost")
	b.post(cx + sx, cy + sy, front_h, 1.8, C_POLE, "LeanPost")
	b.poly("TeamRoof", Color.WHITE, PackedVector2Array([
		gp(cx - sx - 2.0, cy - sy - 2.0, back_h + 1.0),
		gp(cx - sx - 2.0, cy + sy + 2.0, back_h + 1.0),
		gp(cx + sx + 2.5, cy + sy + 2.0, front_h + 1.0),
		gp(cx + sx + 2.5, cy - sy - 2.0, front_h + 1.0)]))
	b.poly("TeamRoofDark", Color.WHITE, Builder._quad(
		Vector2(cx + sx + 2.5, cy - sy - 2.0), Vector2(cx + sx + 2.5, cy + sy + 2.0),
		Vector2(cx + sx + 2.5, cy + sy + 2.0), Vector2(cx + sx + 2.5, cy - sy - 2.0),
		front_h - 2.2, front_h + 1.0))

## One felled trunk lying along x with a pale sawn end + growth ring.
static func _lc_log(b: Builder, cx: float, y: float, half: float,
		h: float, c: Color) -> void:
	b.poly("Log", c, Builder._quad(
		Vector2(cx - half, y), Vector2(cx + half, y),
		Vector2(cx + half, y), Vector2(cx - half, y), h - 2.4, h + 2.4))
	var e: Vector2 = gp(cx + half, y, h)
	b.poly("LogEnd", Color(0.85, 0.72, 0.46), _disc(e, 2.5, 2.9))
	b.poly("LogRing", Color(0.62, 0.47, 0.26), _disc(e, 1.2, 1.4))

static func _lc_log_pile(b: Builder, cx: float, cy: float) -> void:
	b.post(cx - 10.5, cy + 5.0, 10.0, 1.7, C_POLE, "PileStake")
	_lc_log(b, cx, cy + 3.5, 9.0, 2.4, Color(0.47, 0.33, 0.18))
	_lc_log(b, cx, cy - 3.5, 9.0, 2.4, Color(0.52, 0.38, 0.20))
	_lc_log(b, cx, cy, 9.0, 6.9, Color(0.57, 0.43, 0.24))
	b.post(cx + 10.5, cy + 5.0, 10.0, 1.7, C_POLE, "PileStake")

## Trunk up on two splayed trestles with a two-man saw standing in the kerf.
static func _lc_saw_horse(b: Builder, cx: float, cy: float) -> void:
	for tx: float in [cx - 7.0, cx + 7.0]:
		var t: Vector2 = gp(tx, cy, 8.0)
		var g: Vector2 = gp(tx, cy)
		b.poly("Trestle", C_WOOD_DARK, PackedVector2Array([
			t + Vector2(-1.0, 0.0), t + Vector2(1.0, 0.0),
			g + Vector2(4.5, 0.5), g + Vector2(2.3, 0.5)]))
		b.poly("Trestle", C_WOOD_DARK.darkened(0.12), PackedVector2Array([
			t + Vector2(-1.0, 0.0), t + Vector2(1.0, 0.0),
			g + Vector2(-2.3, 0.5), g + Vector2(-4.5, 0.5)]))
	_lc_log(b, cx, cy, 11.0, 8.0, Color(0.55, 0.40, 0.22))
	var k: Vector2 = gp(cx + 2.0, cy, 10.0)
	b.poly("SawBlade", Color(0.74, 0.76, 0.80), PackedVector2Array([
		k + Vector2(-0.7, 0.5), k + Vector2(0.7, 0.5),
		k + Vector2(1.5, -8.0), k + Vector2(-1.5, -8.0)]))
	b.poly("SawHandle", C_WOOD_DARK, PackedVector2Array([
		k + Vector2(-2.8, -8.0), k + Vector2(2.8, -8.0),
		k + Vector2(2.8, -9.6), k + Vector2(-2.8, -9.6)]))

static func _lc_chop_block(b: Builder, cx: float, cy: float) -> void:
	b.walls(cx, cy, 3.2, 3.2, 0.0, 6.0, Color(0.46, 0.33, 0.18))
	b.flat_roof(cx, cy, 3.2, 3.2, 6.0, Color(0.80, 0.66, 0.42), "BlockTop")
	var t: Vector2 = gp(cx, cy, 6.0)
	b.poly("AxeHandle", C_WOOD_DARK.lightened(0.18), PackedVector2Array([
		t + Vector2(0.2, -1.2), t + Vector2(1.6, -0.6),
		t + Vector2(6.6, -9.0), t + Vector2(5.2, -9.7)]))
	b.poly("AxeHead", Color(0.74, 0.76, 0.80), PackedVector2Array([
		t + Vector2(-1.8, -1.4), t + Vector2(1.8, -0.2),
		t + Vector2(2.6, -2.5), t + Vector2(-0.8, -3.6)]))

static func _lc_stump(b: Builder, cx: float, cy: float) -> void:
	b.walls(cx, cy, 2.6, 2.6, 0.0, 3.4, Color(0.42, 0.30, 0.16))
	b.flat_roof(cx, cy, 2.6, 2.6, 3.4, Color(0.78, 0.64, 0.40), "StumpTop")

## Timber-framed mine adit cut into a rock knoll, not a house: dark tunnel
## mouth under posts and a lintel, a rail track out to an ore cart, a grey
## tailings heap with a gold fleck and a pick left against a prop rock.
static func _mining_camp(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	_mc_knoll(b, -hx + 15.0, -hy + 14.0)
	_mc_rails(b, Vector2(-2.0, -2.0), Vector2(hx - 9.0, hy - 15.0))
	_mc_tailings(b, hx - 12.0, -hy + 12.0)
	_mc_cart(b, hx - 11.0, hy - 16.5)
	_mc_pick(b, -hx + 8.0, hy - 8.0)
	for s: Vector2 in [Vector2(2.0, hy - 7.0), Vector2(7.5, hy - 5.0)]:
		b.poly("OreBasket", Color(0.66, 0.52, 0.30),
			Builder._dome_pts(gp(s.x, s.y), 3.2, 3.4))
	b.flag(-hx + 5.0, hy - 5.0, 0.0, 30.0, true)

static func _mc_knoll(b: Builder, cx: float, cy: float) -> void:
	b.ground_ellipse(cx, cy, 18.0, C_BASALT_DARK, "KnollBase")
	var c0: Vector2 = gp(cx, cy, 0.5)
	b.poly("Knoll", C_BASALT, Builder._dome_pts(c0, 17.0, 15.0))
	b.poly("KnollLight", C_BASALT.lightened(0.12),
		Builder._dome_pts(c0 + Vector2(5.0, -1.0), 9.5, 11.0))
	var m: Vector2 = c0 + Vector2(1.0, 4.0)
	b.poly("AditMouth", Color(0.10, 0.09, 0.08),
		Builder._dome_pts(m + Vector2(0.0, 1.0), 6.0, 8.5))
	for dx: float in [-6.8, 6.8]:
		b.poly("AditPost", C_WOOD_DARK, PackedVector2Array([
			m + Vector2(dx - 1.2, 1.6), m + Vector2(dx + 1.2, 1.6),
			m + Vector2(dx + 1.2, -7.6), m + Vector2(dx - 1.2, -7.6)]))
	b.poly("AditLintel", C_WOOD_DARK.lightened(0.14), PackedVector2Array([
		m + Vector2(-8.6, -7.0), m + Vector2(8.6, -7.0),
		m + Vector2(8.6, -9.8), m + Vector2(-8.6, -9.8)]))

static func _mc_rails(b: Builder, a: Vector2, c: Vector2) -> void:
	var dir: Vector2 = (c - a).normalized()
	var n: Vector2 = Vector2(-dir.y, dir.x) * 2.2
	for t: float in [0.12, 0.4, 0.68, 0.92]:
		var p: Vector2 = a.lerp(c, t)
		b.poly("Sleeper", C_WOOD_DARK.darkened(0.10), Builder._quad(
			p - n * 1.5, p + n * 1.5, p + n * 1.5, p - n * 1.5, 0.0, 0.8))
	for s: float in [-1.0, 1.0]:
		b.poly("Rail", Color(0.42, 0.36, 0.28), Builder._quad(
			a + n * s, c + n * s, c + n * s, a + n * s, 0.0, 1.0))

static func _mc_cart(b: Builder, cx: float, cy: float) -> void:
	var c0: Vector2 = gp(cx, cy)
	for dx: float in [-4.2, 4.2]:
		b.poly("CartWheel", Color(0.20, 0.18, 0.16), _disc(c0 + Vector2(dx, 0.2), 2.2, 2.4))
	b.walls(cx, cy, 5.0, 4.0, 2.0, 9.0, Color(0.50, 0.36, 0.20))
	b.flat_roof(cx, cy, 5.0, 4.0, 9.0, Color(0.34, 0.25, 0.13), "CartRim")
	b.poly("CartOre", Color(0.85, 0.68, 0.22),
		Builder._dome_pts(gp(cx, cy, 9.0), 4.6, 3.6))
	b.poly("OreGlint", Color(0.98, 0.87, 0.42), _disc(gp(cx, cy, 11.0) + Vector2(-1.2, 0.0), 1.3, 1.0))

static func _mc_tailings(b: Builder, cx: float, cy: float) -> void:
	b.ground_ellipse(cx, cy, 11.5, Color(0.38, 0.36, 0.34), "TailingsBase")
	b.poly("Tailings", Color(0.55, 0.52, 0.49), Builder._dome_pts(gp(cx, cy), 10.0, 7.5))
	b.poly("TailingsLight", Color(0.66, 0.63, 0.59),
		Builder._dome_pts(gp(cx + 2.5, cy - 1.0), 5.5, 4.8))
	b.poly("GoldFleck", Color(0.90, 0.75, 0.30), _disc(gp(cx + 3.0, cy + 4.0), 1.3, 1.0))
	b.poly("StoneChunk", C_BASALT.lightened(0.05), _disc(gp(cx - 6.0, cy + 6.0), 2.0, 1.5))

static func _mc_pick(b: Builder, cx: float, cy: float) -> void:
	b.post(cx, cy, 4.5, 4.2, C_BASALT, "PropRock")
	var t: Vector2 = gp(cx, cy, 4.0)
	b.poly("PickHandle", C_WOOD_DARK.lightened(0.22), PackedVector2Array([
		t + Vector2(-5.6, 3.6), t + Vector2(-4.4, 4.3),
		t + Vector2(2.0, -5.0), t + Vector2(0.8, -5.7)]))
	b.poly("PickHead", Color(0.62, 0.64, 0.68), PackedVector2Array([
		t + Vector2(-2.0, -6.6), t + Vector2(1.2, -7.6), t + Vector2(4.6, -4.4),
		t + Vector2(3.6, -3.5), t + Vector2(1.0, -5.6), t + Vector2(-1.4, -4.9)]))

## Rustic island gofio windmill: tapered stone tower under a conical civ
## roof, four canvas sails facing the viewer, millstone and grain sacks.
static func _mill(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	b.ground_ellipse(hx - 12.0, hy - 14.0, 8.0, Color(0.74, 0.66, 0.48, 0.55), "ThreshFloor")
	b.ground_ellipse(16.0, 19.0, 6.0, Color(0.70, 0.68, 0.63), "MillStone")
	b.ground_ellipse(16.0, 19.0, 2.0, Color(0.42, 0.40, 0.37), "MillStoneEye")
	b.walls(0, 0, 13.0, 13.0, 0.0, 4.0, b.wall2())
	b.flat_roof(0, 0, 13.0, 13.0, 4.0, b.wall2().lightened(0.15), "FootingTop")
	b.walls(0, 0, 11.5, 11.5, 4.0, 28.0, b.wall())
	b.opening_right(0, 0, 11.5, 11.5, 0.30, 0.62, 0.0, 12.0, C_DOOR, "Door")
	b.opening_left(0, 0, 11.5, 11.5, 0.36, 0.56, 16.0, 22.0, C_WINDOW, "Window")
	b.pyramid_roof(0, 0, 13.0, 13.0, 28.0, 11.0, false, b.roof())
	for s: Vector2 in [Vector2(-13.0, 17.0), Vector2(-8.0, 21.0), Vector2(-16.0, 22.0)]:
		b.poly("GrainSack", Color(0.80, 0.66, 0.42),
			Builder._dome_pts(gp(s.x, s.y), 3.2, 4.4))
		b.poly("SackTie", Color(0.55, 0.42, 0.24),
			_disc(gp(s.x, s.y) + Vector2(0.0, -4.2), 1.1, 0.8))
	b.flag(13.0, -13.0, 0.0, 30.0, true)
	var hub: Vector2 = Vector2(0.0, -31.0)
	for i: int in range(4):
		var a: float = TAU * 0.125 + TAU * float(i) / 4.0
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var pn: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = hub + dir * 19.0
		b.poly("SailCanvas", Color(0.93, 0.90, 0.80), PackedVector2Array([
			hub + dir * 4.0, tip, tip + pn * 5.5, hub + dir * 4.0 + pn * 3.0]))
		b.poly("SailSeam", Color(0.78, 0.73, 0.60), PackedVector2Array([
			hub + dir * 11.0, tip, tip + pn * 5.5, hub + dir * 11.0 + pn * 4.2]))
		b.poly("SailSpar", C_WOOD_DARK, PackedVector2Array([
			hub + pn * 0.8, tip + pn * 0.8, tip - pn * 0.8, hub - pn * 0.8]))
	b.poly("SailHub", C_WOOD_DARK.darkened(0.15), _disc(hub, 2.7, 2.7))

static func _dock(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, Color(0.55, 0.42, 0.26, 0.95))
	for i: int in range(1, 4):
		var px: float = -hx + float(i) * hx * 0.5
		b.poly("PlankSeam", Color(0.45, 0.33, 0.19, 0.9), PackedVector2Array([
			gp(px - 0.8, hy), gp(px + 0.8, hy), gp(px + 0.8, -hy), gp(px - 0.8, -hy),
		]))
	for t: float in [0.1, 0.5, 0.9]:
		b.post(-hx + t * hx * 2.0, hy - 1.0, 6.0, 2.0, C_WOOD_DARK, "Mooring")
		b.post(hx - 1.0, hy - t * hy * 2.0, 6.0, 2.0, C_WOOD_DARK, "Mooring")
	var cx: float = -hx + 16.0
	var cy: float = -hy + 13.0
	b.walls(cx, cy, 13.0, 11.0, 0.0, 13.0, b.wall())
	b.civ_roof(cx, cy, 16.0, 14.0, 12.0, 9.0, true)
	b.opening_right(cx, cy, 13.0, 11.0, 0.3, 0.62, 0.0, 10.0, C_DOOR, "Door")
	b.flag(cx, cy + 11.0, 23.0, 40.0, true)

static func _watch_tower(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 3.0
	b.walls(0, 0, wx, wx, 0.0, 42.0, b.wall2())
	b.opening_right(0, 0, wx, wx, 0.35, 0.55, 24.0, 34.0, Color(0.15, 0.13, 0.11), "Slit")
	b.opening_left(0, 0, wx, wx, 0.38, 0.52, 24.0, 34.0, Color(0.12, 0.1, 0.09), "Slit")
	b.walls(0, 0, wx + 2.5, wx + 2.5, 42.0, 50.0, b.wall())
	b.walls(0, 0, wx + 2.5, wx + 2.5, 42.0, 43.6, b.trim())
	b.flat_roof(0, 0, wx + 2.5, wx + 2.5, 50.0, b.wall().lightened(0.15), "Deck")
	var pw: float = wx + 2.5
	for t: float in [0.08, 0.42, 0.76]:
		b.opening_left(0, 0, pw, pw, t, t + 0.16, 50.0, 55.0, C_STONE_DARK, "TeamMerlon")
		b.opening_right(0, 0, pw, pw, t, t + 0.16, 50.0, 55.0, C_STONE_DARK.lightened(0.1), "TeamMerlon")
	b.flag(0, 0, 50.0, 68.0)

static func _wonder(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, Color(0.72, 0.68, 0.58, 0.95))
	b.walls(0, 0, hx - 3.0, hy - 3.0, 0.0, 10.0, b.wall().lightened(0.18))
	b.flat_roof(0, 0, hx - 3.0, hy - 3.0, 10.0, b.wall().lightened(0.28), "Terrace")
	var t2: float = 26.0
	b.walls(0, 0, t2, t2, 10.0, 34.0, b.wall().lightened(0.12))
	for t: Array in [[0.1, 0.18], [0.3, 0.38], [0.5, 0.58], [0.7, 0.78]]:
		b.opening_right(0, 0, t2, t2, t[0], t[1], 10.0, 32.0, b.wall().lightened(0.30), "Column")
		b.opening_left(0, 0, t2, t2, t[0], t[1], 10.0, 32.0, b.wall().lightened(0.04), "Column")
	b.flat_roof(0, 0, t2 + 3.0, t2 + 3.0, 34.0, Color(0.85, 0.72, 0.35), "GoldBand")
	b.pyramid_roof(0, 0, t2 + 1.0, t2 + 1.0, 35.0, 22.0)
	for c: Vector2 in [Vector2(-hx + 8.0, hy - 8.0), Vector2(hx - 8.0, -hy + 8.0),
			Vector2(hx - 8.0, hy - 8.0)]:
		b.walls(c.x, c.y, 3.5, 3.5, 10.0, 30.0, b.wall().lightened(0.22))
		b.pyramid_roof(c.x, c.y, 4.5, 4.5, 30.0, 6.0, false, Color(0.85, 0.72, 0.35))
	b.flag(0, 0, 58.0, 76.0)

static func _wall_segment(b: Builder, hx: float, hy: float) -> void:
	b.walls(0, 0, hx, hy, 0.0, 13.0, b.wall())
	b.flat_roof(0, 0, hx, hy, 13.0, b.wall().lightened(0.12), "Walk")
	b.opening_left(0, 0, hx, hy, 0.05, 0.45, 13.0, 16.5, Color.WHITE, "TeamMerlon")
	b.opening_right(0, 0, hx, hy, 0.55, 0.95, 13.0, 16.5, Color.WHITE, "TeamMerlonDark")

## Floating net enclosure: flat netted water plot with upright stake posts —
## it sits on the ocean, so there is no walled volume to raise.
static func _fish_trap(b: Builder, hx: float, hy: float) -> void:
	var nx: float = hx - 3.0
	var ny: float = hy - 3.0
	b.footprint(0, 0, nx, ny, Color(0.13, 0.34, 0.44, 0.85))
	for i: int in range(1, 4):
		var o: float = -nx + float(i) * nx * 0.5
		b.poly("NetSeam", Color(0.72, 0.66, 0.5, 0.5), PackedVector2Array([
			gp(o - 0.7, ny), gp(o + 0.7, ny), gp(o + 0.7, -ny), gp(o - 0.7, -ny),
		]))
		b.poly("NetSeam", Color(0.72, 0.66, 0.5, 0.5), PackedVector2Array([
			gp(nx, o - 0.7), gp(nx, o + 0.7), gp(-nx, o + 0.7), gp(-nx, o - 0.7),
		]))
	for c: Vector2 in [Vector2(-nx, ny), Vector2(nx, ny), Vector2(nx, -ny), Vector2(-nx, -ny)]:
		b.post(c.x, c.y, 9.0, 1.8, C_WOOD_DARK, "Stake")
	b.flag(-nx, ny, 9.0, 20.0, true)

static func _gate(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var leaf_x: float = hx - 15.0
	b.poly("GateLeaf", Color(0.45, 0.32, 0.14), Builder._quad(
		Vector2(-leaf_x, hy - 2.0), Vector2(leaf_x, hy - 2.0),
		Vector2(leaf_x, hy - 2.0), Vector2(-leaf_x, hy - 2.0), 0.0, 18.0))
	for i: int in range(1, 4):
		var px: float = -leaf_x + float(i) * leaf_x * 0.5
		b.poly("GateLeafPlank", Color(0.36, 0.25, 0.10), Builder._quad(
			Vector2(px - 0.8, hy - 2.0), Vector2(px + 0.8, hy - 2.0),
			Vector2(px + 0.8, hy - 2.0), Vector2(px - 0.8, hy - 2.0), 0.0, 18.0))
	b.poly("GateLeafBrace", Color(0.30, 0.21, 0.09), Builder._quad(
		Vector2(-leaf_x, hy - 2.0), Vector2(leaf_x, hy - 2.0),
		Vector2(leaf_x, hy - 2.0), Vector2(-leaf_x, hy - 2.0), 8.0, 10.5))
	for tx: float in [-hx + 7.0, hx - 7.0]:
		b.walls(tx, 0, 7.0, hy, 0.0, 26.0, b.wall2())
		b.flat_roof(tx, 0, 8.5, hy + 1.5, 26.0, b.wall2().lightened(0.18), "TowerCap")
		b.pyramid_roof(tx, 0, 8.5, hy + 1.5, 27.0, 7.0, false, b.roof())
	b.flag(-hx + 7.0, 0, 34.0, 48.0, true)
	b.flag(hx - 7.0, 0, 34.0, 48.0)

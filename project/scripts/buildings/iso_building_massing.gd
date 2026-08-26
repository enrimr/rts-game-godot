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
## roofs, flags and awnings, and the construction alpha fade keeps working.
##
## Geometry: a world-local point (x, y) at height h projects to screen
##   ((x - y) * K, (x + y) * K * 0.5 - h)      with K = sqrt(2) / 2,
## which is IsoProjection.world_to_screen plus an upright height offset.

const K: float = 0.7071067811865476

# Shared material tones.
const C_TIMBER: Color = Color(0.76, 0.62, 0.42)
const C_STONE: Color = Color(0.66, 0.62, 0.55)
const C_STONE_DARK: Color = Color(0.52, 0.49, 0.44)
const C_WOOD_DARK: Color = Color(0.42, 0.30, 0.16)
const C_DOOR: Color = Color(0.28, 0.17, 0.08)
const C_WINDOW: Color = Color(0.92, 0.86, 0.55)
const C_APRON: Color = Color(0.47, 0.40, 0.28, 0.85)
const C_APRON_STONE: Color = Color(0.50, 0.48, 0.44, 0.85)
const C_POLE: Color = Color(0.32, 0.23, 0.12)
const C_SCAFFOLD: Color = Color(0.58, 0.44, 0.24)

const WALL_L_DARKEN: float = 0.34
const WALL_R_DARKEN: float = 0.12

## Screen-space point for world-local ground (x, y) lifted `h` pixels.
static func gp(x: float, y: float, h: float = 0.0) -> Vector2:
	return Vector2((x - y) * K, (x + y) * K * 0.5 - h)


class Builder extends RefCounted:
	var body: Node2D
	var top_y: float = INF
	var bot_y: float = -INF
	var _n: int = 0

	func _init(body_node: Node2D) -> void:
		body = body_node

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
	var b: Builder = Builder.new(body)
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
		"lumber_camp", "mining_camp", "dock", "watch_tower", "wonder",
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
		"lumber_camp": _camp(b, hx, hy, C_TIMBER, true)
		"mining_camp": _camp(b, hx, hy, C_STONE, false)
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
	b.walls(0, 0, wx, wy, 0.0, 17.0, C_TIMBER)
	b.hip_roof(0, 0, wx + 3.0, wy + 3.0, 16.0, 12.0, true)
	b.opening_right(0, 0, wx, wy, 0.25, 0.5, 0.0, 11.0, C_DOOR, "Door")
	b.opening_left(0, 0, wx, wy, 0.3, 0.55, 5.0, 11.0, C_WINDOW, "Window")

static func _town_center(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	# Foundation plinth: a low stone course wider than the keep walls that
	# seats the volume on the ground diamond instead of floating on it.
	b.walls(0, 0, hx - 1.0, hy - 1.0, 0.0, 3.5, C_STONE_DARK.lightened(0.06))
	b.flat_roof(0, 0, hx - 1.0, hy - 1.0, 3.5, C_STONE_DARK.lightened(0.22), "PlinthTop")
	b.walls(0, 0, hx - 4.0, hy - 4.0, 3.5, 20.0, C_STONE)
	b.flat_roof(0, 0, hx - 2.0, hy - 2.0, 20.0, C_STONE.lightened(0.10), "Parapet")
	b.opening_right(0, 0, hx - 4.0, hy - 4.0, 0.32, 0.58, 0.0, 14.0, C_DOOR, "Gatehouse")
	b.opening_left(0, 0, hx - 4.0, hy - 4.0, 0.34, 0.5, 6.0, 13.0, C_WINDOW, "Window")
	b.walls(0, 0, 22.0, 22.0, 20.0, 38.0, C_STONE.lightened(0.06))
	b.hip_roof(0, 0, 26.0, 26.0, 37.0, 14.0, true)
	for t: Vector2 in [Vector2(-hx + 10.0, hy - 10.0), Vector2(hx - 10.0, -hy + 10.0)]:
		b.walls(t.x, t.y, 9.0, 9.0, 0.0, 32.0, C_STONE_DARK)
		b.flat_roof(t.x, t.y, 10.5, 10.5, 32.0, C_STONE_DARK.lightened(0.18), "TowerCap")
		b.pyramid_roof(t.x, t.y, 10.5, 10.5, 33.0, 9.0)
	b.flag(-hx + 10.0, hy - 10.0, 42.0, 56.0, true)
	b.flag(hx - 10.0, -hy + 10.0, 42.0, 56.0)

static func _barracks(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 4.0
	var wy: float = hy - 4.0
	b.walls(0, 0, wx, wy, 0.0, 20.0, C_STONE)
	b.gable_roof(0, 0, wx + 3.0, wy + 3.0, 19.0, 13.0, true, C_STONE)
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
	b.walls(-6.0, -6.0, wx, wx, 0.0, 17.0, C_TIMBER)
	b.gable_roof(-6.0, -6.0, wx + 3.0, wx + 3.0, 16.0, 11.0, false, C_TIMBER)
	b.opening_left(-6.0, -6.0, wx, wx, 0.3, 0.6, 0.0, 12.0, C_DOOR, "Door")
	b.flag(-6.0, -6.0 - wx, 27.0, 44.0)

static func _stable(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 10.0
	var wy: float = hy - 16.0
	b.walls(-4.0, -8.0, wx, wy, 0.0, 16.0, C_TIMBER)
	b.hip_roof(-4.0, -8.0, wx + 4.0, wy + 4.0, 15.0, 11.0, true)
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
	b.walls(0, 0, wx, wy, 0.0, 16.0, C_STONE_DARK)
	b.gable_roof(0, 0, wx + 3.0, wy + 3.0, 15.0, 10.0, true, C_STONE_DARK)
	b.opening_right(0, 0, wx, wy, 0.3, 0.62, 0.0, 12.0, Color(0.95, 0.5, 0.15), "ForgeGlow")
	b.walls(-wx + 8.0, -wy + 8.0, 4.5, 4.5, 15.0, 36.0, Color(0.36, 0.32, 0.28))
	b.flat_roof(-wx + 8.0, -wy + 8.0, 5.5, 5.5, 36.0, Color(0.25, 0.22, 0.20), "ChimneyCap")
	b.ground_ellipse(hx - 14.0, hy - 20.0, 6.0, Color(0.35, 0.33, 0.3), "Anvil")

static func _university(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 5.0
	var wy: float = hy - 5.0
	b.walls(0, 0, wx, wy, 0.0, 24.0, C_STONE.lightened(0.08))
	b.hip_roof(0, 0, wx + 3.0, wy + 3.0, 23.0, 13.0, false)
	for t: Array in [[0.2, 0.32], [0.44, 0.56], [0.68, 0.8]]:
		b.opening_right(0, 0, wx, wy, t[0], t[1], 9.0, 18.0, C_WINDOW, "Window")
	b.opening_left(0, 0, wx, wy, 0.35, 0.6, 0.0, 15.0, C_DOOR, "Portal")
	b.flag(0, wy, 36.0, 52.0, true)

static func _temple(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 5.0
	var wy: float = hy - 5.0
	b.walls(0, 0, wx, wy, 0.0, 18.0, C_STONE.lightened(0.12))
	b.flat_roof(0, 0, wx + 2.0, wy + 2.0, 18.0, C_STONE.lightened(0.2), "Cornice")
	for t: Array in [[0.14, 0.2], [0.36, 0.42], [0.58, 0.64], [0.8, 0.86]]:
		b.opening_right(0, 0, wx, wy, t[0], t[1], 0.0, 16.0, C_STONE.lightened(0.28), "Column")
	b.opening_left(0, 0, wx, wy, 0.38, 0.62, 0.0, 14.0, C_DOOR, "Portal")
	b.walls(0, 0, 17.0, 17.0, 18.0, 26.0, C_STONE.lightened(0.05))
	b.pyramid_roof(0, 0, 19.0, 19.0, 26.0, 16.0)
	b.flag(0, 0, 42.0, 54.0)

static func _market(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 14.0
	var wy: float = hy - 14.0
	b.walls(-6.0, -6.0, wx, wy, 0.0, 13.0, C_TIMBER)
	b.hip_roof(-6.0, -6.0, wx + 4.0, wy + 4.0, 12.0, 9.0, true)
	var s: Vector2 = Vector2(-6.0 + wx, -6.0 + wy)
	var e: Vector2 = Vector2(-6.0 + wx, -6.0 - wy)
	b.poly("TeamAwning", Color.WHITE, PackedVector2Array([
		gp(s.x, s.y, 13.0), gp(e.x, e.y, 13.0),
		gp(e.x + 9.0, e.y, 8.0), gp(s.x + 9.0, s.y, 8.0),
	]))
	for st: Vector2 in [Vector2(hx - 12.0, hy - 24.0), Vector2(hx - 26.0, hy - 10.0)]:
		b.walls(st.x, st.y, 6.0, 6.0, 0.0, 7.0, C_WOOD_DARK.lightened(0.2))
		b.hip_roof(st.x, st.y, 8.0, 8.0, 7.0, 4.0, true)
	b.flag(-6.0, -6.0 - wy, 22.0, 38.0)

static func _siege_workshop(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 5.0
	var wy: float = hy - 5.0
	b.walls(0, 0, wx, wy, 0.0, 19.0, C_WOOD_DARK.lightened(0.25))
	b.gable_roof(0, 0, wx + 3.0, wy + 3.0, 18.0, 12.0, false, C_WOOD_DARK.lightened(0.25))
	b.opening_left(0, 0, wx, wy, 0.22, 0.72, 0.0, 15.0, Color(0.16, 0.12, 0.08), "Bay")
	b.opening_right(0, 0, wx, wy, 0.4, 0.52, 7.0, 14.0, C_WINDOW, "Window")
	b.post(hx - 8.0, hy - 8.0, 12.0, 2.2, C_WOOD_DARK, "Crane")
	b.flag(0, -wy, 30.0, 46.0)

static func _camp(b: Builder, hx: float, hy: float, wall_c: Color, is_lumber: bool) -> void:
	b.footprint(0, 0, hx, hy, C_APRON)
	var wx: float = hx - 9.0
	var wy: float = hy - 9.0
	b.walls(-4.0, -4.0, wx, wy, 0.0, 13.0, wall_c)
	b.gable_roof(-4.0, -4.0, wx + 3.0, wy + 3.0, 12.0, 9.0, true, wall_c)
	b.opening_right(-4.0, -4.0, wx, wy, 0.28, 0.6, 0.0, 10.0, C_DOOR, "Door")
	if is_lumber:
		for i: int in range(3):
			var lh: float = 1.5 + float(i) * 3.0
			b.poly("Log", Color(0.5, 0.36, 0.2).darkened(float(i) * 0.08), Builder._quad(
				Vector2(hx - 20.0, hy - 7.0), Vector2(hx - 6.0, hy - 7.0),
				Vector2(hx - 6.0, hy - 7.0), Vector2(hx - 20.0, hy - 7.0), lh - 1.5, lh + 1.5))
	else:
		b.ground_ellipse(hx - 13.0, hy - 9.0, 7.0, Color(0.45, 0.43, 0.4), "OrePile")
		b.poly("OreTop", Color(0.55, 0.53, 0.5), PackedVector2Array([
			gp(hx - 18.0, hy - 9.0), gp(hx - 8.0, hy - 9.0), gp(hx - 13.0, hy - 9.0, 6.0),
		]))
	b.flag(-4.0, -4.0 - wy, 17.0, 32.0)

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
	b.walls(cx, cy, 13.0, 11.0, 0.0, 13.0, C_TIMBER)
	b.gable_roof(cx, cy, 16.0, 14.0, 12.0, 9.0, true, C_TIMBER)
	b.opening_right(cx, cy, 13.0, 11.0, 0.3, 0.62, 0.0, 10.0, C_DOOR, "Door")
	b.flag(cx, cy + 11.0, 23.0, 40.0, true)

static func _watch_tower(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, C_APRON_STONE)
	var wx: float = hx - 3.0
	b.walls(0, 0, wx, wx, 0.0, 42.0, C_STONE_DARK)
	b.opening_right(0, 0, wx, wx, 0.35, 0.55, 24.0, 34.0, Color(0.15, 0.13, 0.11), "Slit")
	b.opening_left(0, 0, wx, wx, 0.38, 0.52, 24.0, 34.0, Color(0.12, 0.1, 0.09), "Slit")
	b.walls(0, 0, wx + 2.5, wx + 2.5, 42.0, 50.0, C_STONE)
	b.flat_roof(0, 0, wx + 2.5, wx + 2.5, 50.0, C_STONE.lightened(0.15), "Deck")
	var pw: float = wx + 2.5
	for t: float in [0.08, 0.42, 0.76]:
		b.opening_left(0, 0, pw, pw, t, t + 0.16, 50.0, 55.0, C_STONE_DARK, "TeamMerlon")
		b.opening_right(0, 0, pw, pw, t, t + 0.16, 50.0, 55.0, C_STONE_DARK.lightened(0.1), "TeamMerlon")
	b.flag(0, 0, 50.0, 68.0)

static func _wonder(b: Builder, hx: float, hy: float) -> void:
	b.footprint(0, 0, hx, hy, Color(0.72, 0.68, 0.58, 0.95))
	b.walls(0, 0, hx - 3.0, hy - 3.0, 0.0, 10.0, C_STONE.lightened(0.2))
	b.flat_roof(0, 0, hx - 3.0, hy - 3.0, 10.0, C_STONE.lightened(0.3), "Terrace")
	var t2: float = 26.0
	b.walls(0, 0, t2, t2, 10.0, 34.0, C_STONE.lightened(0.15))
	for t: Array in [[0.1, 0.18], [0.3, 0.38], [0.5, 0.58], [0.7, 0.78]]:
		b.opening_right(0, 0, t2, t2, t[0], t[1], 10.0, 32.0, C_STONE.lightened(0.32), "Column")
		b.opening_left(0, 0, t2, t2, t[0], t[1], 10.0, 32.0, C_STONE.lightened(0.05), "Column")
	b.flat_roof(0, 0, t2 + 3.0, t2 + 3.0, 34.0, Color(0.85, 0.72, 0.35), "GoldBand")
	b.pyramid_roof(0, 0, t2 + 1.0, t2 + 1.0, 35.0, 22.0)
	for c: Vector2 in [Vector2(-hx + 8.0, hy - 8.0), Vector2(hx - 8.0, -hy + 8.0),
			Vector2(hx - 8.0, hy - 8.0)]:
		b.walls(c.x, c.y, 3.5, 3.5, 10.0, 30.0, C_STONE.lightened(0.25))
		b.pyramid_roof(c.x, c.y, 4.5, 4.5, 30.0, 6.0, false, Color(0.85, 0.72, 0.35))
	b.flag(0, 0, 58.0, 76.0)

static func _wall_segment(b: Builder, hx: float, hy: float) -> void:
	b.walls(0, 0, hx, hy, 0.0, 13.0, C_STONE)
	b.flat_roof(0, 0, hx, hy, 13.0, C_STONE.lightened(0.12), "Walk")
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
		b.walls(tx, 0, 7.0, hy, 0.0, 26.0, C_STONE_DARK)
		b.flat_roof(tx, 0, 8.5, hy + 1.5, 26.0, C_STONE_DARK.lightened(0.18), "TowerCap")
		b.pyramid_roof(tx, 0, 8.5, hy + 1.5, 27.0, 7.0)
	b.flag(-hx + 7.0, 0, 34.0, 48.0, true)
	b.flag(hx - 7.0, 0, 34.0, 48.0)

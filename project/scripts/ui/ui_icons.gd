class_name UiIcons
extends Object

## Procedural command-glyph library for the HUD.
##
## Every command button glyph is drawn from Polygon2D/Line2D geometry in a
## 64x64 design space and rendered ONCE into a cached ImageTexture via a
## hidden SubViewport (same async pattern as IconBaker). The game ships no
## image assets, so the icons stay coherent with the flat low-poly art style:
## 2-3 flat fills per glyph plus a darker outline shade.
##
## get_icon() is synchronous: it returns the cached ImageTexture immediately
## (transparent until the offscreen render lands a few frames later). Headless
## runs (tests, CI) keep the transparent placeholder.

const SIZE: int = 64

## Glyph ids drawable by _build(). Anything else falls back to the caller's
## text abbreviation.
const GLYPHS: Array[String] = [
	"gather_wood", "gather_gold", "gather_stone", "gather_food",
	"build", "repair", "destroy", "destroy_unit",
	"move", "stop", "attack", "attack_ground", "cover_fire", "patrol_route",
	"follow", "age_up", "gate_lock", "gate_unlock", "ability", "unload",
	"close", "menu", "speed1", "speed2", "speed3",
	"idle_villager", "idle_military", "locate_hero", "garrison_into", "town_bell",
	"stance_aggressive", "stance_defensive", "stance_stand_ground", "stance_passive",
	"formation_line", "formation_box", "formation_spread", "formation_rings",
	"page_prev", "page_next",
	"res_food", "res_wood", "res_gold", "res_stone",
	"stat_attack", "stat_armor", "stat_range", "stat_speed",
]

## Stockpile display order shared by every cost row.
const RES_ORDER: Array[String] = ["food", "wood", "gold", "stone"]

## Technology ids with a dedicated research glyph (drawn by _build_tech).
## Unknown ids fall back to the generic "tech_research" scroll-and-book.
const TECH_GLYPHS: Array[String] = [
	"loom", "forging", "iron_casting", "blast_furnace",
	"scale_barding", "chain_barding", "plate_barding",
	"fletching", "bodkin_arrow", "padded_archer_armor", "shipwright",
	"ballistics", "chemistry", "siege_engineering",
	"fervor", "sanctity", "atonement",
	"upgrade_man_at_arms", "upgrade_long_swordsman",
	"upgrade_heavy_scout", "upgrade_knight",
	"carreta_canaria", "carreton_isleno",
	"double_bit_axe", "bow_saw", "two_man_saw",
	"reinforced_picks", "shaft_mining", "deep_galleries",
	"horse_collar", "heavy_plow", "crop_rotation",
]

# ── Palette (flat fills; outlines derive as darkened shades) ──────────────────
const C_WOOD: Color = Color(0.56, 0.38, 0.19)
const C_WOOD_DARK: Color = Color(0.36, 0.23, 0.10)
const C_LOG: Color = Color(0.47, 0.30, 0.14)
const C_LOG_END: Color = Color(0.78, 0.62, 0.38)
const C_STEEL: Color = Color(0.78, 0.80, 0.86)
const C_STEEL_DARK: Color = Color(0.42, 0.45, 0.53)
const C_GOLD: Color = Color(0.93, 0.75, 0.20)
const C_STONE: Color = Color(0.64, 0.64, 0.67)
const C_RED: Color = Color(0.78, 0.20, 0.16)
const C_BONE: Color = Color(0.93, 0.90, 0.83)
const C_PALE: Color = Color(0.90, 0.87, 0.80)
const C_BLUE: Color = Color(0.55, 0.74, 0.94)
const C_VIOLET: Color = Color(0.68, 0.44, 0.84)
const C_BODY: Color = Color(0.47, 0.50, 0.58)
const C_PARCH: Color = Color(0.88, 0.79, 0.60)
const C_SAND: Color = Color(0.81, 0.67, 0.43)
const C_DARK: Color = Color(0.14, 0.12, 0.10)
const C_FLAME: Color = Color(0.93, 0.45, 0.12)
const C_FLAME_HOT: Color = Color(1.0, 0.82, 0.30)
const C_GREEN: Color = Color(0.35, 0.62, 0.30)
const C_HORSE: Color = Color(0.55, 0.38, 0.22)

## id -> ImageTexture (shared instance, filled async once).
static var _cache: Dictionary = {}

static func has_glyph(id: String) -> bool:
	return id in GLYPHS

## Research icon for a technology id; unknown ids get the generic scroll so
## future techs never break the HUD.
static func tech_glyph(tech_id: String) -> Texture2D:
	if tech_id in TECH_GLYPHS:
		return get_icon("tech_" + tech_id)
	return get_icon("tech_research")

static func get_icon(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id] as Texture2D
	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	_cache[id] = texture
	_bake_async(texture, id)
	return texture

## Convenience: a mouse-transparent TextureRect showing a glyph at px size,
## centered over its parent. Used by the misc HUD icon buttons (menu, speed,
## idle, follow) so they match the action-grid look.
static func icon_rect(id: String, inset: float = 5.0) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = get_icon(id)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = inset
	rect.offset_top = inset
	rect.offset_right = -inset
	rect.offset_bottom = -inset
	return rect

## One "icon + text" cell (e.g. a resource amount or a unit stat), mouse
## transparent so it never steals hover from the control it annotates.
static func amount_chip(glyph_id: String, text: String, icon_px: float = 15.0,
		font_size: int = 13) -> HBoxContainer:
	var chip: HBoxContainer = HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", 3)
	var icon: TextureRect = TextureRect.new()
	icon.texture = get_icon(glyph_id)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(icon_px, icon_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip

## Renders a cost dictionary ({"food": 50, ...}) as a row of mini resource
## glyphs with amounts, in stockpile order. Reusable anywhere the HUD shows
## a price.
static func cost_row(costs: Dictionary, icon_px: float = 15.0,
		font_size: int = 13) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	for res: String in RES_ORDER:
		var amount: int = int(costs.get(res, 0) as float)
		if amount <= 0:
			continue
		row.add_child(amount_chip("res_" + res, str(amount), icon_px, font_size))
	return row

static func _bake_async(target: ImageTexture, id: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	# The dummy renderer has no render-target textures: headless runs keep the
	# transparent placeholder (tests never inspect the pixels).
	if DisplayServer.get_name() == "headless":
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var root: Node2D = Node2D.new()
	viewport.add_child(root)
	_build(id, root)
	# Deferred: icons are typically requested from _ready while the scene root
	# is still setting up its children (add_child would fail there).
	tree.root.add_child.call_deferred(viewport)
	await tree.process_frame
	await tree.process_frame
	await RenderingServer.frame_post_draw
	if not is_instance_valid(viewport):
		return
	var img: Image = viewport.get_texture().get_image()
	if img != null and not img.is_empty():
		target.set_image(img)
	viewport.free()

# ── Geometry helpers ──────────────────────────────────────────────────────────

static func _poly(parent: Node2D, pts: PackedVector2Array, fill: Color,
		outline: Color = Color(0.0, 0.0, 0.0, 0.0), outline_w: float = 3.0) -> void:
	var p: Polygon2D = Polygon2D.new()
	p.polygon = pts
	p.color = fill
	p.antialiased = true
	parent.add_child(p)
	var oc: Color = outline if outline.a > 0.0 else fill.darkened(0.55)
	var l: Line2D = Line2D.new()
	l.points = pts
	l.closed = true
	l.width = outline_w
	l.default_color = oc
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.antialiased = true
	parent.add_child(l)

static func _stroke(parent: Node2D, pts: PackedVector2Array, color: Color,
		width: float) -> void:
	var l: Line2D = Line2D.new()
	l.points = pts
	l.width = width
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.antialiased = true
	parent.add_child(l)

static func _bar(parent: Node2D, from: Vector2, to: Vector2, width: float,
		fill: Color, outline: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var dir: Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x) * width * 0.5
	_poly(parent, PackedVector2Array([from + perp, to + perp, to - perp, from - perp]),
		fill, outline)

static func _rect(parent: Node2D, x: float, y: float, w: float, h: float,
		fill: Color, outline: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	_poly(parent, PackedVector2Array([Vector2(x, y), Vector2(x + w, y),
		Vector2(x + w, y + h), Vector2(x, y + h)]), fill, outline)

static func _circle_pts(c: Vector2, r: float, n: int = 20) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

static func _circle(parent: Node2D, c: Vector2, r: float, fill: Color,
		outline: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	_poly(parent, _circle_pts(c, r), fill, outline)

static func _ellipse_pts(c: Vector2, rx: float, ry: float, rot_deg: float,
		n: int = 20) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var rot: float = deg_to_rad(rot_deg)
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts

static func _group(parent: Node2D, at: Vector2, rot_deg: float) -> Node2D:
	var g: Node2D = Node2D.new()
	g.position = at
	g.rotation_degrees = rot_deg
	parent.add_child(g)
	return g

# ── Shared sub-figures ────────────────────────────────────────────────────────

## Sword pointing up, centered on the pivot origin (tip y=-27, pommel y=+25).
static func _sword(parent: Node2D) -> void:
	_poly(parent, PackedVector2Array([Vector2(0, -27), Vector2(3.5, -21),
		Vector2(3.5, 7), Vector2(-3.5, 7), Vector2(-3.5, -21)]), C_STEEL)
	_rect(parent, -9.0, 7.0, 18.0, 5.0, C_GOLD)
	_rect(parent, -2.5, 12.0, 5.0, 10.0, C_WOOD_DARK)
	_circle(parent, Vector2(0, 25), 3.5, C_GOLD)

## Pickaxe: wooden handle + bent steel head, drawn in glyph space.
static func _pickaxe(parent: Node2D) -> void:
	_bar(parent, Vector2(16, 54), Vector2(40, 14), 6.0, C_WOOD)
	_bar(parent, Vector2(12, 28), Vector2(34, 8), 8.0, C_STEEL)
	_bar(parent, Vector2(34, 8), Vector2(58, 26), 8.0, C_STEEL)

## Small arrow pointing up, centered on the pivot origin.
static func _arrow(parent: Node2D) -> void:
	_bar(parent, Vector2(0, 14), Vector2(0, -6), 3.0, C_PALE)
	_poly(parent, PackedVector2Array([Vector2(0, -16), Vector2(-5.5, -5),
		Vector2(5.5, -5)]), C_STEEL)
	_bar(parent, Vector2(0, 9), Vector2(-5, 15), 2.5, C_PALE)
	_bar(parent, Vector2(0, 9), Vector2(5, 15), 2.5, C_PALE)

## Blocky "Z" (sleep mark), top-left corner at pos, 14x14.
static func _z_mark(parent: Node2D, pos: Vector2) -> void:
	var p: Vector2 = pos
	_poly(parent, PackedVector2Array([
		p + Vector2(0, 0), p + Vector2(14, 0), p + Vector2(14, 4.5),
		p + Vector2(6, 9.5), p + Vector2(14, 9.5), p + Vector2(14, 14),
		p + Vector2(0, 14), p + Vector2(0, 9.5), p + Vector2(8, 4.5),
		p + Vector2(0, 4.5)]), C_GOLD)

## Upright hammer centered on the pivot origin (head up).
static func _hammer(parent: Node2D) -> void:
	_bar(parent, Vector2(0, 28), Vector2(0, -12), 7.0, C_WOOD)
	_rect(parent, -17.0, -26.0, 34.0, 15.0, C_STEEL)
	_rect(parent, -17.0, -14.5, 34.0, 3.5, C_STEEL_DARK)

## Right-pointing chevron centered on the pivot origin.
static func _chevron(parent: Node2D) -> void:
	_poly(parent, PackedVector2Array([Vector2(-5, -14), Vector2(7, 0),
		Vector2(-5, 14), Vector2(-12, 14), Vector2(0, 0), Vector2(-12, -14)]),
		C_PALE)

# ── Glyph builders ────────────────────────────────────────────────────────────

static func _build(id: String, root: Node2D) -> void:
	if id.begins_with("tech_"):
		_build_tech(id.trim_prefix("tech_"), root)
		return
	match id:
		"gather_wood":
			_rect(root, 10.0, 42.0, 44.0, 14.0, C_LOG)
			_circle(root, Vector2(54, 49), 7.0, C_LOG_END)
			_bar(root, Vector2(50, 8), Vector2(24, 36), 6.0, C_WOOD)
			_poly(root, PackedVector2Array([Vector2(14, 32), Vector2(30, 29),
				Vector2(33, 44), Vector2(17, 48)]), C_STEEL)
		"gather_gold":
			_pickaxe(root)
			_circle(root, Vector2(44, 43), 4.5, C_GOLD)
			_circle(root, Vector2(38, 52), 6.0, C_GOLD)
			_circle(root, Vector2(51, 51), 5.0, C_GOLD)
		"gather_stone":
			_pickaxe(root)
			_rect(root, 36.0, 36.0, 11.0, 10.0, C_STONE)
			_rect(root, 32.0, 46.0, 17.0, 12.0, C_STONE)
		"gather_food":
			# Wheat sheaf: fanned stalks, grain heads, tie band.
			_bar(root, Vector2(32, 56), Vector2(19, 18), 3.0, Color(0.80, 0.63, 0.24))
			_bar(root, Vector2(32, 56), Vector2(32, 12), 3.0, Color(0.80, 0.63, 0.24))
			_bar(root, Vector2(32, 56), Vector2(45, 18), 3.0, Color(0.80, 0.63, 0.24))
			_poly(root, _ellipse_pts(Vector2(18, 14), 5.0, 9.5, -16.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(32, 9), 5.0, 9.5, 0.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(46, 14), 5.0, 9.5, 16.0), C_GOLD)
			_bar(root, Vector2(23, 43), Vector2(41, 46), 6.0, C_WOOD)
		"build":
			_hammer(_group(root, Vector2(32, 33), -35.0))
		"repair":
			var h: Node2D = _group(root, Vector2(27, 38), -35.0)
			h.scale = Vector2(0.85, 0.85)
			_hammer(h)
			_poly(root, PackedVector2Array([Vector2(48, 5), Vector2(50.5, 11.5),
				Vector2(57, 14), Vector2(50.5, 16.5), Vector2(48, 23),
				Vector2(45.5, 16.5), Vector2(39, 14), Vector2(45.5, 11.5)]), C_GOLD)
		"destroy":
			_rect(root, 12.0, 26.0, 34.0, 30.0, C_STONE)
			_poly(root, PackedVector2Array([Vector2(8, 28), Vector2(29, 10),
				Vector2(50, 28)]), Color(0.52, 0.28, 0.20))
			# Bold lightning crack splitting the wall top to bottom.
			_poly(root, PackedVector2Array([Vector2(27, 26), Vector2(34, 26),
				Vector2(28, 36), Vector2(36, 36), Vector2(27, 49), Vector2(33, 49),
				Vector2(29, 56), Vector2(23, 56), Vector2(29, 45), Vector2(22, 45),
				Vector2(30, 33), Vector2(24, 33)]), C_DARK, C_DARK)
			_poly(root, PackedVector2Array([Vector2(50, 34), Vector2(59, 38),
				Vector2(55, 46), Vector2(48, 41)]), C_STONE)
			_poly(root, PackedVector2Array([Vector2(53, 51), Vector2(60, 53),
				Vector2(56, 59), Vector2(51, 56)]), C_STONE)
		"destroy_unit":
			_circle(root, Vector2(32, 26), 16.0, C_BONE)
			_rect(root, 24.0, 38.0, 16.0, 11.0, C_BONE)
			_circle(root, Vector2(25.5, 25), 4.5, C_DARK)
			_circle(root, Vector2(38.5, 25), 4.5, C_DARK)
			_poly(root, PackedVector2Array([Vector2(32, 30), Vector2(29, 36),
				Vector2(35, 36)]), C_DARK)
			_stroke(root, PackedVector2Array([Vector2(28, 41), Vector2(28, 47)]), C_DARK, 2.0)
			_stroke(root, PackedVector2Array([Vector2(32, 41), Vector2(32, 47)]), C_DARK, 2.0)
			_stroke(root, PackedVector2Array([Vector2(36, 41), Vector2(36, 47)]), C_DARK, 2.0)
		"move":
			_bar(root, Vector2(15, 49), Vector2(37, 27), 10.0, C_PALE)
			_poly(root, PackedVector2Array([Vector2(28, 10), Vector2(54, 10),
				Vector2(54, 36)]), C_PALE)
		"stop":
			var oct: PackedVector2Array = PackedVector2Array()
			for i: int in range(8):
				var a: float = TAU * (float(i) + 0.5) / 8.0
				oct.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * 23.0)
			_poly(root, oct, C_RED)
			var inner: PackedVector2Array = PackedVector2Array()
			for i: int in range(8):
				var a: float = TAU * (float(i) + 0.5) / 8.0
				inner.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * 17.0)
			var l: Line2D = Line2D.new()
			l.points = inner
			l.closed = true
			l.width = 3.0
			l.default_color = C_PALE
			l.joint_mode = Line2D.LINE_JOINT_ROUND
			l.antialiased = true
			root.add_child(l)
		"attack":
			_sword(_group(root, Vector2(32, 32), -42.0))
			_sword(_group(root, Vector2(32, 32), 42.0))
		"attack_ground":
			_bar(root, Vector2(12, 52), Vector2(52, 52), 5.0, C_WOOD_DARK)
			_poly(root, PackedVector2Array([Vector2(20, 50), Vector2(10, 42),
				Vector2(22, 44)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(44, 50), Vector2(54, 42),
				Vector2(42, 44)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(25, 42), Vector2(18, 32),
				Vector2(28, 37)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(39, 42), Vector2(46, 32),
				Vector2(36, 37)]), C_GOLD)
			_sword(_group(root, Vector2(32, 24), 180.0))
		"cover_fire":
			_arrow(_group(root, Vector2(16, 27), 200.0))
			_arrow(_group(root, Vector2(32, 20), 180.0))
			_arrow(_group(root, Vector2(48, 27), 160.0))
		"patrol_route":
			for i: int in range(1, 8):
				var a: float = TAU * float(i) / 8.0
				_circle(root, Vector2(32, 34) + Vector2(cos(a) * 18.0, sin(a) * 13.0),
					3.6, C_PALE)
			# Arrowhead on the loop's right side, pointing along travel.
			_poly(root, PackedVector2Array([Vector2(50, 47), Vector2(43, 28),
				Vector2(57, 28)]), C_BLUE)
		"follow":
			# Binoculars, front view: two capsule barrels + bridge + lenses.
			for cx: float in [21.0, 43.0]:
				_poly(root, PackedVector2Array([
					Vector2(cx - 7, 22), Vector2(cx - 4, 14), Vector2(cx + 4, 14),
					Vector2(cx + 7, 22), Vector2(cx + 7, 42), Vector2(cx + 4, 50),
					Vector2(cx - 4, 50), Vector2(cx - 7, 42)]), C_BODY)
			_rect(root, 27.0, 24.0, 10.0, 11.0, C_BODY)
			_circle(root, Vector2(21, 44), 5.5, C_BLUE)
			_circle(root, Vector2(43, 44), 5.5, C_BLUE)
			_circle(root, Vector2(21, 16), 4.0, C_DARK)
			_circle(root, Vector2(43, 16), 4.0, C_DARK)
		"age_up":
			_rect(root, 10.0, 50.0, 44.0, 8.0, C_SAND)
			_rect(root, 18.0, 40.0, 28.0, 10.0, C_SAND)
			_rect(root, 25.0, 31.0, 14.0, 9.0, C_SAND)
			_rect(root, 27.0, 20.0, 10.0, 11.0, C_GOLD)
			_poly(root, PackedVector2Array([Vector2(32, 5), Vector2(19, 20),
				Vector2(45, 20)]), C_GOLD)
		"gate_lock":
			_stroke(root, PackedVector2Array([Vector2(24, 30), Vector2(24.5, 23),
				Vector2(28, 18), Vector2(32, 17), Vector2(36, 18),
				Vector2(39.5, 23), Vector2(40, 30)]), C_STEEL, 5.0)
			_poly(root, PackedVector2Array([Vector2(20, 29), Vector2(44, 29),
				Vector2(46, 31), Vector2(46, 52), Vector2(44, 54), Vector2(20, 54),
				Vector2(18, 52), Vector2(18, 31)]), C_GOLD)
			_circle(root, Vector2(32, 38), 3.5, C_DARK)
			_bar(root, Vector2(32, 40), Vector2(32, 47), 3.0, C_DARK)
		"gate_unlock":
			# Shackle swung wide open: only the left leg enters the body, the
			# free end hangs past the body's right edge.
			_stroke(root, PackedVector2Array([Vector2(24, 29), Vector2(23, 18),
				Vector2(27, 10), Vector2(35, 7), Vector2(44, 9),
				Vector2(51, 16), Vector2(53, 24)]), C_STEEL, 5.0)
			_poly(root, PackedVector2Array([Vector2(20, 29), Vector2(44, 29),
				Vector2(46, 31), Vector2(46, 52), Vector2(44, 54), Vector2(20, 54),
				Vector2(18, 52), Vector2(18, 31)]), C_GOLD)
			_circle(root, Vector2(32, 38), 3.5, C_DARK)
			_bar(root, Vector2(32, 40), Vector2(32, 47), 3.0, C_DARK)
		"ability":
			_poly(root, PackedVector2Array([Vector2(32, 7), Vector2(39, 25),
				Vector2(57, 32), Vector2(39, 39), Vector2(32, 57), Vector2(25, 39),
				Vector2(7, 32), Vector2(25, 25)]), C_VIOLET)
			_poly(root, PackedVector2Array([Vector2(32, 21), Vector2(43, 32),
				Vector2(32, 43), Vector2(21, 32)]), C_VIOLET.lightened(0.35))
		"unload":
			_rect(root, 16.0, 8.0, 32.0, 26.0, C_WOOD)
			_stroke(root, PackedVector2Array([Vector2(16, 8), Vector2(48, 34)]),
				C_WOOD_DARK, 3.0)
			_stroke(root, PackedVector2Array([Vector2(48, 8), Vector2(16, 34)]),
				C_WOOD_DARK, 3.0)
			_bar(root, Vector2(32, 38), Vector2(32, 47), 9.0, C_PALE)
			_poly(root, PackedVector2Array([Vector2(32, 58), Vector2(22, 46),
				Vector2(42, 46)]), C_PALE)
		"close":
			_poly(root, PackedVector2Array([Vector2(12, 20), Vector2(20, 12),
				Vector2(32, 24), Vector2(44, 12), Vector2(52, 20), Vector2(40, 32),
				Vector2(52, 44), Vector2(44, 52), Vector2(32, 40), Vector2(20, 52),
				Vector2(12, 44), Vector2(24, 32)]), C_PALE)
		"menu":
			_rect(root, 12.0, 10.0, 40.0, 8.0, Color(0.72, 0.62, 0.42))
			_rect(root, 16.0, 18.0, 32.0, 30.0, C_PARCH)
			_rect(root, 12.0, 48.0, 40.0, 8.0, Color(0.72, 0.62, 0.42))
			_stroke(root, PackedVector2Array([Vector2(22, 26), Vector2(42, 26)]),
				C_WOOD_DARK, 2.5)
			_stroke(root, PackedVector2Array([Vector2(22, 33), Vector2(42, 33)]),
				C_WOOD_DARK, 2.5)
			_stroke(root, PackedVector2Array([Vector2(22, 40), Vector2(37, 40)]),
				C_WOOD_DARK, 2.5)
		"speed1":
			_chevron(_group(root, Vector2(35, 32), 0.0))
		"speed2":
			_chevron(_group(root, Vector2(27, 32), 0.0))
			_chevron(_group(root, Vector2(42, 32), 0.0))
		"speed3":
			_chevron(_group(root, Vector2(20, 32), 0.0))
			_chevron(_group(root, Vector2(34, 32), 0.0))
			_chevron(_group(root, Vector2(48, 32), 0.0))
		"idle_villager":
			# Figure sitting on a rock, legs bent forward, sleep mark above.
			var skin: Color = Color(0.85, 0.72, 0.55)
			var tunic: Color = Color(0.55, 0.48, 0.36)
			_rect(root, 12.0, 44.0, 18.0, 12.0, C_STONE)
			_circle(root, Vector2(23, 17), 7.5, skin)
			_poly(root, PackedVector2Array([Vector2(15, 26), Vector2(30, 26),
				Vector2(32, 44), Vector2(15, 44)]), tunic)
			_bar(root, Vector2(29, 40), Vector2(45, 42), 8.0, tunic)
			_bar(root, Vector2(43, 43), Vector2(43, 57), 5.5, skin)
			_z_mark(root, Vector2(40, 6))
		"idle_military":
			_poly(root, PackedVector2Array([Vector2(12, 14), Vector2(44, 14),
				Vector2(44, 32), Vector2(40, 42), Vector2(28, 52), Vector2(16, 42),
				Vector2(12, 32)]), C_RED)
			_circle(root, Vector2(28, 28), 5.0, C_GOLD)
			_z_mark(root, Vector2(46, 8))
		"stance_aggressive":
			# Two crossed blades: chase anything that comes close.
			var blade: Color = Color(0.82, 0.84, 0.88)
			_bar(root, Vector2(18, 46), Vector2(46, 14), 5.0, blade)
			_bar(root, Vector2(18, 14), Vector2(46, 46), 5.0, blade)
			_bar(root, Vector2(14, 50), Vector2(22, 42), 6.0, C_RED)
			_bar(root, Vector2(50, 50), Vector2(42, 42), 6.0, C_RED)
		"stance_defensive":
			# A shield: fight back, return to post.
			_poly(root, PackedVector2Array([Vector2(16, 14), Vector2(48, 14),
				Vector2(48, 32), Vector2(44, 42), Vector2(32, 52), Vector2(20, 42),
				Vector2(16, 32)]), Color(0.20, 0.42, 0.66))
			_circle(root, Vector2(32, 28), 5.0, Color(0.75, 0.85, 0.95))
		"stance_stand_ground":
			# Shield planted on the ground: strike in reach, never move.
			_poly(root, PackedVector2Array([Vector2(20, 10), Vector2(44, 10),
				Vector2(44, 26), Vector2(41, 34), Vector2(32, 42), Vector2(23, 34),
				Vector2(20, 26)]), Color(0.45, 0.42, 0.30))
			_circle(root, Vector2(32, 22), 4.0, C_GOLD)
			_bar(root, Vector2(12, 50), Vector2(52, 50), 6.0, Color(0.35, 0.28, 0.18))
			_bar(root, Vector2(32, 42), Vector2(32, 50), 4.0, Color(0.45, 0.42, 0.30))
		"stance_passive":
			# Sword under a prohibition stroke: never attack on its own.
			var pale: Color = Color(0.62, 0.64, 0.68)
			_bar(root, Vector2(20, 44), Vector2(44, 20), 5.0, pale)
			_bar(root, Vector2(18, 46), Vector2(24, 40), 6.0, Color(0.45, 0.35, 0.25))
			_stroke(root, PackedVector2Array([Vector2(14, 14), Vector2(50, 50)]),
				Color(0.85, 0.20, 0.15), 5.5)
		"formation_line":
			# Two ranks facing up: melee front (red), ranged behind (gold).
			for i: int in range(4):
				_circle(root, Vector2(14.0 + i * 12.0, 24.0), 5.0, C_RED)
				_circle(root, Vector2(14.0 + i * 12.0, 42.0), 5.0, C_GOLD)
		"formation_box":
			# A solid square block.
			for gx: int in range(3):
				for gy: int in range(3):
					_circle(root, Vector2(18.0 + gx * 14.0, 18.0 + gy * 14.0), 5.0,
						C_RED if gx == 0 or gx == 2 or gy == 0 or gy == 2 else C_GOLD)
		"formation_spread":
			# Wide spacing against splash damage.
			for p: Vector2 in [Vector2(12, 14), Vector2(50, 12), Vector2(30, 28),
					Vector2(14, 46), Vector2(48, 44), Vector2(34, 54)]:
				_circle(root, p, 5.0, C_RED)
		"formation_rings":
			# The classic concentric blob around the click.
			_circle(root, Vector2(32, 32), 5.5, C_GOLD)
			for i: int in range(6):
				var a: float = TAU * float(i) / 6.0
				_circle(root, Vector2(32, 32) + Vector2(cos(a), sin(a)) * 17.0, 4.5, C_RED)
		"garrison_into":
			# Sheltering: a stout keep with a figure slipping in through the door.
			var keep: Color = Color(0.55, 0.52, 0.48)
			_poly(root, PackedVector2Array([Vector2(14, 22), Vector2(50, 22),
				Vector2(50, 54), Vector2(14, 54)]), keep)
			_poly(root, PackedVector2Array([Vector2(10, 22), Vector2(54, 22),
				Vector2(54, 14), Vector2(10, 14)]), keep.darkened(0.2))
			_poly(root, PackedVector2Array([Vector2(26, 54), Vector2(38, 54),
				Vector2(38, 34), Vector2(32, 28), Vector2(26, 34)]), Color(0.12, 0.10, 0.08))
			_circle(root, Vector2(32, 40), 4.0, Color(0.85, 0.72, 0.55))
			_stroke(root, PackedVector2Array([Vector2(32, 44), Vector2(32, 50)]),
				Color(0.55, 0.48, 0.36), 4.0)
		"town_bell":
			# Alarm bell with sound arcs.
			_poly(root, PackedVector2Array([Vector2(26, 12), Vector2(38, 12),
				Vector2(40, 18), Vector2(44, 36), Vector2(20, 36), Vector2(24, 18)]), C_GOLD)
			_bar(root, Vector2(18, 38), Vector2(46, 38), 5.0, C_GOLD.darkened(0.25))
			_circle(root, Vector2(32, 44), 4.5, C_GOLD.darkened(0.35))
			_stroke(root, PackedVector2Array([Vector2(14, 20), Vector2(10, 28)]),
				Color(1.0, 0.9, 0.5, 0.9), 2.5)
			_stroke(root, PackedVector2Array([Vector2(50, 20), Vector2(54, 28)]),
				Color(1.0, 0.9, 0.5, 0.9), 2.5)
		"locate_hero":
			# Golden crown over a head — the hero locator.
			var hero_skin: Color = Color(0.85, 0.72, 0.55)
			_circle(root, Vector2(32, 36), 11.0, hero_skin)
			_poly(root, PackedVector2Array([Vector2(16, 24), Vector2(22, 12),
				Vector2(28, 21), Vector2(32, 8), Vector2(36, 21), Vector2(42, 12),
				Vector2(48, 24), Vector2(46, 28), Vector2(18, 28)]), C_GOLD)
			_circle(root, Vector2(32, 10), 2.6, Color(1.0, 0.95, 0.7))
		"res_food":
			# Wheat ear: bold kernel pairs on a single stalk (readable at 14 px).
			_bar(root, Vector2(32, 58), Vector2(32, 24), 4.0, Color(0.80, 0.63, 0.24))
			_poly(root, _ellipse_pts(Vector2(22, 38), 6.5, 10.0, -35.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(42, 38), 6.5, 10.0, 35.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(23, 22), 6.5, 10.0, -35.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(41, 22), 6.5, 10.0, 35.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(32, 10), 6.0, 9.0, 0.0), C_GOLD)
		"res_wood":
			# Single log, cut end facing right.
			_rect(root, 6.0, 22.0, 42.0, 20.0, C_LOG)
			_circle(root, Vector2(48, 32), 10.0, C_LOG_END)
			_circle(root, Vector2(48, 32), 4.5, C_LOG)
		"res_gold":
			# Faceted nugget with a light glint.
			_poly(root, PackedVector2Array([Vector2(20, 14), Vector2(44, 12),
				Vector2(56, 30), Vector2(48, 50), Vector2(22, 52),
				Vector2(8, 32)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(24, 20), Vector2(40, 18),
				Vector2(34, 34), Vector2(20, 32)]), C_GOLD.lightened(0.35))
		"res_stone":
			# Cut block: lit top face, shaded side face.
			_poly(root, PackedVector2Array([Vector2(10, 28), Vector2(20, 16),
				Vector2(58, 16), Vector2(48, 28)]), C_STONE.lightened(0.25))
			_poly(root, PackedVector2Array([Vector2(48, 28), Vector2(58, 16),
				Vector2(58, 42), Vector2(48, 54)]), C_STONE.darkened(0.20))
			_rect(root, 10.0, 28.0, 38.0, 26.0, C_STONE)
		"stat_attack":
			var sg: Node2D = _group(root, Vector2(32, 32), 45.0)
			sg.scale = Vector2(1.15, 1.15)
			_sword(sg)
		"stat_armor":
			_poly(root, PackedVector2Array([Vector2(12, 12), Vector2(52, 12),
				Vector2(52, 32), Vector2(48, 42), Vector2(32, 54),
				Vector2(16, 42), Vector2(12, 32)]), C_STEEL)
			_circle(root, Vector2(32, 28), 6.0, C_GOLD)
		"stat_range":
			# Bow limb arc + string, arrow nocked and pointing right.
			var arc: PackedVector2Array = PackedVector2Array()
			for i: int in range(13):
				var a: float = deg_to_rad(-70.0 + 140.0 * float(i) / 12.0)
				arc.append(Vector2(20, 32) + Vector2(cos(a), sin(a)) * 26.0)
			_stroke(root, arc, C_WOOD, 5.0)
			_stroke(root, PackedVector2Array([arc[0], arc[12]]), C_PALE, 2.5)
			_bar(root, Vector2(18, 32), Vector2(44, 32), 3.0, C_PALE)
			_poly(root, PackedVector2Array([Vector2(56, 32), Vector2(43, 25),
				Vector2(43, 39)]), C_STEEL)
		"stat_speed":
			# Boot facing right with motion dashes trailing behind.
			_poly(root, PackedVector2Array([Vector2(24, 12), Vector2(38, 12),
				Vector2(38, 32), Vector2(54, 40), Vector2(54, 48),
				Vector2(24, 48)]), C_WOOD)
			_rect(root, 22.0, 46.0, 34.0, 7.0, C_WOOD_DARK)
			_stroke(root, PackedVector2Array([Vector2(8, 22), Vector2(18, 22)]), C_PALE, 3.5)
			_stroke(root, PackedVector2Array([Vector2(6, 32), Vector2(16, 32)]), C_PALE, 3.5)
			_stroke(root, PackedVector2Array([Vector2(8, 42), Vector2(18, 42)]), C_PALE, 3.5)
		"page_prev":
			_poly(root, PackedVector2Array([Vector2(43, 13), Vector2(43, 51),
				Vector2(17, 32)]), C_PALE)
		"page_next":
			_poly(root, PackedVector2Array([Vector2(21, 13), Vector2(21, 51),
				Vector2(47, 32)]), C_PALE)
		_:
			# Unknown id: leave the texture transparent (caller falls back to text).
			pass

# ── Tech-glyph sub-figures ────────────────────────────────────────────────────

## Gold double up-chevron, the shared "unit upgrade" motif (top-right corner).
static func _up_chevron(parent: Node2D, at: Vector2) -> void:
	var g: Node2D = _group(parent, at, 0.0)
	_poly(g, PackedVector2Array([Vector2(-9, 2), Vector2(0, -7), Vector2(9, 2),
		Vector2(9, 8), Vector2(0, -1), Vector2(-9, 8)]), C_GOLD)
	_poly(g, PackedVector2Array([Vector2(-9, 13), Vector2(0, 4), Vector2(9, 13),
		Vector2(9, 19), Vector2(0, 10), Vector2(-9, 19)]), C_GOLD)

## Horse head + neck profile facing left, full glyph space. Bardings overlay
## armour on it; cavalry upgrades mirror it to face right.
static func _horse_head(parent: Node2D) -> void:
	_poly(parent, PackedVector2Array([Vector2(6, 30), Vector2(18, 18),
		Vector2(30, 14), Vector2(44, 26), Vector2(54, 58), Vector2(30, 58),
		Vector2(24, 44), Vector2(16, 42), Vector2(6, 38)]), C_HORSE)
	_poly(parent, PackedVector2Array([Vector2(28, 15), Vector2(33, 4),
		Vector2(38, 17)]), C_HORSE.darkened(0.25))
	_stroke(parent, PackedVector2Array([Vector2(33, 15), Vector2(44, 28),
		Vector2(52, 55)]), C_HORSE.darkened(0.40), 5.0)
	_circle(parent, Vector2(21, 26), 2.6, C_DARK)
	_circle(parent, Vector2(10, 34), 1.8, C_DARK)

## Spoked wooden cart wheel.
static func _cart_wheel(parent: Node2D, c: Vector2, r: float,
		rim: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	_circle(parent, c, r, C_WOOD if rim.a <= 0.0 else rim)
	_circle(parent, c, r * 0.72, C_LOG_END)
	_stroke(parent, PackedVector2Array([c + Vector2(-r * 0.6, 0), c + Vector2(r * 0.6, 0)]),
		C_WOOD_DARK, 2.5)
	_stroke(parent, PackedVector2Array([c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.6)]),
		C_WOOD_DARK, 2.5)
	_circle(parent, c, r * 0.18, C_WOOD_DARK)

## Two-tongued flame (outer hot orange, inner gold core), tip up, base at origin.
static func _flame(parent: Node2D, at: Vector2, s: float = 1.0) -> void:
	var g: Node2D = _group(parent, at, 0.0)
	g.scale = Vector2(s, s)
	_poly(g, PackedVector2Array([Vector2(-8, 0), Vector2(-6, -10), Vector2(-2, -6),
		Vector2(0, -18), Vector2(4, -8), Vector2(8, -13), Vector2(8, 0)]), C_FLAME)
	_poly(g, PackedVector2Array([Vector2(-3, 0), Vector2(0, -9), Vector2(3, 0)]),
		C_FLAME_HOT)

# ── Technology glyph builders ─────────────────────────────────────────────────

static func _build_tech(id: String, root: Node2D) -> void:
	match id:
		"loom":
			_rect(root, 8.0, 6.0, 48.0, 6.0, C_WOOD_DARK)
			_rect(root, 10.0, 10.0, 6.0, 46.0, C_WOOD)
			_rect(root, 48.0, 10.0, 6.0, 46.0, C_WOOD)
			for i: int in range(5):
				_stroke(root, PackedVector2Array([Vector2(20.0 + i * 6.0, 12.0),
					Vector2(20.0 + i * 6.0, 38.0)]), C_PALE, 2.0)
			_rect(root, 16.0, 38.0, 32.0, 16.0, C_RED)
			_stroke(root, PackedVector2Array([Vector2(17, 43), Vector2(47, 43)]),
				C_RED.darkened(0.35), 2.0)
			_stroke(root, PackedVector2Array([Vector2(17, 49), Vector2(47, 49)]),
				C_RED.darkened(0.35), 2.0)
			_poly(root, _ellipse_pts(Vector2(32, 34), 9.0, 4.0, 0.0), C_GOLD)
		"forging":
			_poly(root, PackedVector2Array([Vector2(4, 27), Vector2(14, 20),
				Vector2(52, 20), Vector2(52, 32), Vector2(14, 32)]), C_STEEL)
			_poly(root, PackedVector2Array([Vector2(24, 32), Vector2(44, 32),
				Vector2(40, 44), Vector2(28, 44)]), C_STEEL_DARK)
			_poly(root, PackedVector2Array([Vector2(20, 44), Vector2(48, 44),
				Vector2(52, 54), Vector2(16, 54)]), C_STEEL)
			for p: Vector2 in [Vector2(22, 11), Vector2(34, 6), Vector2(45, 12)]:
				_poly(root, PackedVector2Array([p + Vector2(0, -4), p + Vector2(3, 0),
					p + Vector2(0, 4), p + Vector2(-3, 0)]), C_GOLD)
		"iron_casting":
			_poly(root, PackedVector2Array([Vector2(8, 44), Vector2(28, 44),
				Vector2(31, 55), Vector2(4, 55)]), C_STEEL_DARK)
			_poly(root, PackedVector2Array([Vector2(35, 44), Vector2(55, 44),
				Vector2(59, 55), Vector2(31, 55)]), C_STEEL_DARK)
			_poly(root, PackedVector2Array([Vector2(19, 28), Vector2(43, 28),
				Vector2(47, 42), Vector2(15, 42)]), C_FLAME)
			_poly(root, PackedVector2Array([Vector2(21, 23), Vector2(41, 23),
				Vector2(43, 28), Vector2(19, 28)]), C_FLAME_HOT)
			_stroke(root, PackedVector2Array([Vector2(23, 17), Vector2(26, 12),
				Vector2(23, 7)]), C_FLAME_HOT, 2.5)
			_stroke(root, PackedVector2Array([Vector2(38, 17), Vector2(41, 12),
				Vector2(38, 7)]), C_FLAME_HOT, 2.5)
		"blast_furnace":
			_poly(root, PackedVector2Array([Vector2(14, 58), Vector2(19, 22),
				Vector2(26, 14), Vector2(38, 14), Vector2(45, 22),
				Vector2(50, 58)]), C_STONE)
			_stroke(root, PackedVector2Array([Vector2(19, 32), Vector2(45, 32)]),
				C_STONE.darkened(0.30), 2.2)
			_stroke(root, PackedVector2Array([Vector2(17, 44), Vector2(47, 44)]),
				C_STONE.darkened(0.30), 2.2)
			_poly(root, PackedVector2Array([Vector2(25, 58), Vector2(25, 48),
				Vector2(32, 42), Vector2(39, 48), Vector2(39, 58)]), C_DARK)
			_poly(root, PackedVector2Array([Vector2(29, 58), Vector2(29, 51),
				Vector2(32, 48), Vector2(35, 51), Vector2(35, 58)]), C_FLAME)
			_flame(root, Vector2(32, 14), 1.6)
		"scale_barding":
			_horse_head(root)
			_poly(root, PackedVector2Array([Vector2(33, 17), Vector2(46, 27),
				Vector2(56, 58), Vector2(28, 58), Vector2(26, 34)]), C_STEEL)
			for row: int in range(3):
				for k: int in range(3):
					_circle(root, Vector2(34.0 + k * 8.0 + (row % 2) * 4.0,
						28.0 + row * 10.0), 3.4, C_STEEL_DARK if (k + row) % 2 == 0
						else C_STEEL.darkened(0.25))
		"chain_barding":
			_horse_head(root)
			_poly(root, PackedVector2Array([Vector2(33, 17), Vector2(46, 27),
				Vector2(56, 58), Vector2(22, 58), Vector2(24, 40),
				Vector2(26, 30)]), C_STEEL_DARK)
			for row: int in range(4):
				for k: int in range(3):
					_circle(root, Vector2(31.0 + k * 8.0 + (row % 2) * 4.0,
						27.0 + row * 8.5), 2.2, C_PALE)
		"plate_barding":
			_horse_head(root)
			_poly(root, PackedVector2Array([Vector2(6, 30), Vector2(18, 18),
				Vector2(30, 14), Vector2(42, 24), Vector2(32, 36), Vector2(14, 40),
				Vector2(6, 38)]), C_STEEL)
			_poly(root, PackedVector2Array([Vector2(33, 17), Vector2(46, 27),
				Vector2(56, 58), Vector2(24, 58), Vector2(26, 32)]), C_STEEL)
			_stroke(root, PackedVector2Array([Vector2(30, 40), Vector2(52, 40)]),
				C_STEEL_DARK, 2.5)
			_stroke(root, PackedVector2Array([Vector2(28, 50), Vector2(54, 50)]),
				C_STEEL_DARK, 2.5)
			_circle(root, Vector2(21, 26), 2.6, C_DARK)
			for p: Vector2 in [Vector2(38, 26), Vector2(42, 35), Vector2(40, 45)]:
				_circle(root, p, 1.8, C_GOLD)
		"fletching":
			var g: Node2D = _group(root, Vector2(32, 32), 45.0)
			_bar(g, Vector2(0, 28), Vector2(0, -24), 3.0, C_WOOD)
			_poly(g, PackedVector2Array([Vector2(0, -30), Vector2(-5, -20),
				Vector2(5, -20)]), C_STEEL)
			for fy: float in [8.0, 17.0]:
				_poly(g, PackedVector2Array([Vector2(1, fy), Vector2(11, fy + 7),
					Vector2(11, fy + 13), Vector2(1, fy + 6)]), C_RED)
				_poly(g, PackedVector2Array([Vector2(-1, fy), Vector2(-11, fy + 7),
					Vector2(-11, fy + 13), Vector2(-1, fy + 6)]), C_RED)
		"bodkin_arrow":
			_poly(root, PackedVector2Array([Vector2(32, 2), Vector2(38, 24),
				Vector2(26, 24)]), C_STEEL)
			_stroke(root, PackedVector2Array([Vector2(32, 5), Vector2(32, 22)]),
				C_PALE, 2.2)
			_rect(root, 29.0, 24.0, 6.0, 6.0, C_STEEL_DARK)
			_bar(root, Vector2(32, 30), Vector2(32, 54), 3.5, C_WOOD)
			_bar(root, Vector2(32, 48), Vector2(26, 56), 2.5, C_PALE)
			_bar(root, Vector2(32, 48), Vector2(38, 56), 2.5, C_PALE)
		"padded_archer_armor":
			_poly(root, PackedVector2Array([Vector2(22, 10), Vector2(42, 10),
				Vector2(48, 18), Vector2(46, 54), Vector2(18, 54),
				Vector2(16, 18)]), C_SAND)
			_poly(root, PackedVector2Array([Vector2(27, 10), Vector2(37, 10),
				Vector2(32, 20)]), C_DARK)
			for i: int in range(4):
				_stroke(root, PackedVector2Array([Vector2(16.0, 14.0 + i * 11.0),
					Vector2(48.0, 25.0 + i * 11.0)]), C_SAND.darkened(0.35), 1.8)
				_stroke(root, PackedVector2Array([Vector2(48.0, 14.0 + i * 11.0),
					Vector2(16.0, 25.0 + i * 11.0)]), C_SAND.darkened(0.35), 1.8)
		"shipwright":
			for rib: Array in [[Vector2(14, 40), Vector2(8, 18)],
					[Vector2(23, 45), Vector2(20, 14)], [Vector2(32, 47), Vector2(32, 12)],
					[Vector2(41, 45), Vector2(44, 14)], [Vector2(50, 40), Vector2(56, 18)]]:
				_stroke(root, PackedVector2Array([rib[0] as Vector2, rib[1] as Vector2]),
					C_WOOD, 3.5)
			_poly(root, PackedVector2Array([Vector2(4, 30), Vector2(14, 30),
				Vector2(22, 34), Vector2(42, 34), Vector2(50, 30), Vector2(60, 30),
				Vector2(52, 44), Vector2(40, 50), Vector2(24, 50),
				Vector2(12, 44)]), C_LOG)
			_stroke(root, PackedVector2Array([Vector2(10, 36), Vector2(32, 44),
				Vector2(54, 36)]), C_WOOD_DARK, 2.5)
			_stroke(root, PackedVector2Array([Vector2(6, 31), Vector2(32, 36),
				Vector2(58, 31)]), C_LOG_END, 2.5)
			_stroke(root, PackedVector2Array([Vector2(16, 56), Vector2(48, 56)]),
				C_STONE.darkened(0.2), 4.0)
		"ballistics":
			_circle(root, Vector2(46, 44), 14.0, C_PALE)
			_circle(root, Vector2(46, 44), 9.5, C_RED)
			_circle(root, Vector2(46, 44), 5.0, C_PALE)
			_circle(root, Vector2(46, 44), 2.2, C_RED)
			for t: float in [0.0, 0.16, 0.32, 0.48, 0.64, 0.8]:
				var p: Vector2 = Vector2(8, 52).bezier_interpolate(
					Vector2(14, 2), Vector2(38, 2), Vector2(46, 40), t)
				_circle(root, p, 2.4, C_GOLD)
			_poly(root, PackedVector2Array([Vector2(46, 40), Vector2(41, 28),
				Vector2(51, 28)]), C_STEEL)
		"chemistry":
			_rect(root, 27.0, 8.0, 10.0, 4.0, C_STEEL_DARK)
			_poly(root, PackedVector2Array([Vector2(28, 12), Vector2(36, 12),
				Vector2(38, 30), Vector2(50, 52), Vector2(14, 52),
				Vector2(26, 30)]), C_BLUE.lightened(0.25))
			_poly(root, PackedVector2Array([Vector2(24, 38), Vector2(40, 38),
				Vector2(47, 50), Vector2(17, 50)]), C_GREEN)
			_circle(root, Vector2(29, 30), 2.4, C_PALE)
			_circle(root, Vector2(35, 22), 2.0, C_PALE)
		"siege_engineering":
			_bar(root, Vector2(8, 54), Vector2(56, 54), 5.0, C_WOOD_DARK)
			_stroke(root, PackedVector2Array([Vector2(18, 53), Vector2(31, 33)]), C_WOOD, 5.0)
			_stroke(root, PackedVector2Array([Vector2(44, 53), Vector2(31, 33)]), C_WOOD, 5.0)
			_stroke(root, PackedVector2Array([Vector2(46, 48), Vector2(12, 12)]), C_LOG, 4.5)
			_rect(root, 42.0, 44.0, 9.0, 8.0, C_STEEL_DARK)
			_circle(root, Vector2(31, 33), 3.0, C_STEEL_DARK)
			_circle(root, Vector2(11, 8), 5.5, C_STONE)
		"fervor":
			_poly(root, PackedVector2Array([Vector2(32, 58), Vector2(12, 38),
				Vector2(10, 29), Vector2(16, 22), Vector2(25, 23), Vector2(32, 31),
				Vector2(39, 23), Vector2(48, 22), Vector2(54, 29), Vector2(52, 38)]),
				C_RED)
			_flame(root, Vector2(32, 27), 1.35)
		"sanctity":
			var ring: Line2D = Line2D.new()
			ring.points = _circle_pts(Vector2(32, 27), 13.5)
			ring.closed = true
			ring.width = 4.0
			ring.default_color = C_PALE
			ring.antialiased = true
			root.add_child(ring)
			_bar(root, Vector2(32, 8), Vector2(32, 56), 7.0, C_GOLD)
			_bar(root, Vector2(18, 27), Vector2(46, 27), 7.0, C_GOLD)
		"atonement":
			_stroke(root, PackedVector2Array([Vector2(9, 34), Vector2(4, 44)]),
				C_GREEN.darkened(0.2), 2.2)
			_poly(root, _ellipse_pts(Vector2(6, 38), 4.5, 2.2, -60.0), C_GREEN)
			_poly(root, _ellipse_pts(Vector2(8, 42), 4.5, 2.2, -20.0), C_GREEN)
			_poly(root, _ellipse_pts(Vector2(29, 36), 15.0, 8.5, -8.0), C_BONE)
			_circle(root, Vector2(14, 30), 5.5, C_BONE)
			_poly(root, PackedVector2Array([Vector2(9, 29), Vector2(4, 32),
				Vector2(9, 33)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(26, 33), Vector2(38, 8),
				Vector2(48, 14), Vector2(36, 36)]), C_BONE.darkened(0.08))
			_poly(root, PackedVector2Array([Vector2(41, 38), Vector2(58, 32),
				Vector2(58, 45), Vector2(43, 44)]), C_BONE.darkened(0.08))
			_circle(root, Vector2(13, 29), 1.5, C_DARK)
		"upgrade_man_at_arms":
			_circle(root, Vector2(38, 40), 13.0, C_RED)
			_circle(root, Vector2(38, 40), 4.5, C_GOLD)
			var sg: Node2D = _group(root, Vector2(24, 30), -32.0)
			sg.scale = Vector2(1.05, 1.05)
			_sword(sg)
			_up_chevron(root, Vector2(51, 12))
		"upgrade_long_swordsman":
			_poly(root, PackedVector2Array([Vector2(30, 2), Vector2(34, 2),
				Vector2(36, 10), Vector2(36, 38), Vector2(28, 38),
				Vector2(28, 10)]), C_STEEL)
			_stroke(root, PackedVector2Array([Vector2(32, 6), Vector2(32, 36)]),
				C_PALE, 1.8)
			_rect(root, 17.0, 38.0, 30.0, 5.5, C_GOLD)
			_rect(root, 29.0, 43.5, 6.0, 12.0, C_WOOD_DARK)
			_circle(root, Vector2(32, 58), 3.8, C_GOLD)
			_up_chevron(root, Vector2(52, 12))
		"upgrade_heavy_scout":
			var hg: Node2D = _group(root, Vector2(64, 0), 0.0)
			hg.scale = Vector2(-1, 1)
			_horse_head(hg)
			_up_chevron(root, Vector2(13, 12))
		"upgrade_knight":
			var kg: Node2D = _group(root, Vector2(64, 0), 0.0)
			kg.scale = Vector2(-1, 1)
			_horse_head(kg)
			_stroke(root, PackedVector2Array([Vector2(16, 56), Vector2(46, 14)]),
				C_WOOD_DARK, 3.5)
			_poly(root, PackedVector2Array([Vector2(46, 14), Vector2(51, 4),
				Vector2(54, 15)]), C_STEEL)
			_poly(root, PackedVector2Array([Vector2(44, 19), Vector2(24, 9),
				Vector2(44, 8)]), C_RED)
			_up_chevron(root, Vector2(13, 12))
		"carreta_canaria":
			_rect(root, 10.0, 26.0, 42.0, 7.0, C_WOOD)
			_stroke(root, PackedVector2Array([Vector2(48, 28), Vector2(60, 21)]),
				C_WOOD_DARK, 3.5)
			_stroke(root, PackedVector2Array([Vector2(48, 33), Vector2(60, 29)]),
				C_WOOD_DARK, 3.5)
			_cart_wheel(root, Vector2(26, 44), 12.0)
			_circle(root, Vector2(24, 18), 8.0, C_SAND)
			_stroke(root, PackedVector2Array([Vector2(22, 11), Vector2(27, 9)]),
				C_WOOD_DARK, 2.5)
		"carreton_isleno":
			_rect(root, 8.0, 20.0, 48.0, 16.0, C_WOOD)
			_stroke(root, PackedVector2Array([Vector2(9, 21), Vector2(55, 21)]), C_GOLD, 2.5)
			for i: int in range(3):
				_stroke(root, PackedVector2Array([Vector2(19.0 + i * 13.0, 22.0),
					Vector2(19.0 + i * 13.0, 35.0)]), C_WOOD_DARK, 2.5)
			_rect(root, 14.0, 10.0, 12.0, 10.0, C_STONE)
			_circle(root, Vector2(38, 13), 7.0, C_SAND)
			_cart_wheel(root, Vector2(20, 46), 10.0, C_STEEL_DARK)
			_cart_wheel(root, Vector2(44, 46), 10.0, C_STEEL_DARK)
		"double_bit_axe":
			# Twin-bladed axe on a vertical haft.
			_bar(root, Vector2(32, 58), Vector2(32, 12), 4.5, C_WOOD)
			_poly(root, PackedVector2Array([Vector2(28, 10), Vector2(14, 6),
				Vector2(8, 17), Vector2(14, 28), Vector2(28, 24)]), C_STEEL)
			_poly(root, PackedVector2Array([Vector2(36, 10), Vector2(50, 6),
				Vector2(56, 17), Vector2(50, 28), Vector2(36, 24)]), C_STEEL)
			_stroke(root, PackedVector2Array([Vector2(11, 10), Vector2(9, 17),
				Vector2(11, 24)]), C_PALE, 2.2)
			_stroke(root, PackedVector2Array([Vector2(53, 10), Vector2(55, 17),
				Vector2(53, 24)]), C_PALE, 2.2)
		"bow_saw":
			# D-frame bow saw over a half-cut log.
			_rect(root, 8.0, 44.0, 48.0, 14.0, C_LOG)
			_circle(root, Vector2(56, 51), 7.0, C_LOG_END)
			_stroke(root, PackedVector2Array([Vector2(32, 58), Vector2(32, 46)]),
				C_DARK, 2.5)
			var bow: PackedVector2Array = PackedVector2Array()
			for i: int in range(11):
				var a: float = deg_to_rad(180.0 + 180.0 * float(i) / 10.0)
				bow.append(Vector2(32, 40) + Vector2(cos(a) * 22.0, sin(a) * 32.0))
			_stroke(root, bow, C_WOOD, 5.0)
			_bar(root, Vector2(10, 40), Vector2(54, 40), 3.0, C_STEEL)
			for k: int in range(6):
				_poly(root, PackedVector2Array([Vector2(12.0 + k * 7.0, 41.0),
					Vector2(15.0 + k * 7.0, 41.0), Vector2(13.5 + k * 7.0, 45.0)]),
					C_STEEL_DARK)
		"two_man_saw":
			# Long crosscut blade, one upright handle at each end.
			_bar(root, Vector2(10, 22), Vector2(10, 36), 5.0, C_WOOD_DARK)
			_bar(root, Vector2(54, 22), Vector2(54, 36), 5.0, C_WOOD_DARK)
			_poly(root, PackedVector2Array([Vector2(8, 34), Vector2(56, 34),
				Vector2(56, 42), Vector2(8, 42)]), C_STEEL)
			for k: int in range(8):
				_poly(root, PackedVector2Array([Vector2(9.0 + k * 6.0, 42.0),
					Vector2(14.0 + k * 6.0, 42.0), Vector2(11.5 + k * 6.0, 47.0)]),
					C_STEEL_DARK)
			_rect(root, 16.0, 50.0, 32.0, 8.0, C_LOG)
			_circle(root, Vector2(48, 54), 4.0, C_LOG_END)
		"reinforced_picks":
			# Pickaxe striking a gold nugget.
			_bar(root, Vector2(36, 12), Vector2(20, 50), 4.5, C_WOOD)
			var pick: PackedVector2Array = PackedVector2Array()
			for i: int in range(9):
				var a: float = deg_to_rad(-35.0 + 90.0 * float(i) / 8.0)
				pick.append(Vector2(28, 34) + Vector2(cos(a), sin(a)) * 26.0)
			_stroke(root, pick, C_STEEL, 6.0)
			_poly(root, PackedVector2Array([Vector2(38, 44), Vector2(54, 40),
				Vector2(60, 50), Vector2(52, 58), Vector2(40, 56)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(42, 46), Vector2(52, 44),
				Vector2(48, 52)]), C_GOLD.lightened(0.35))
		"shaft_mining":
			# Timbered mine portal, rails running into the dark.
			_rect(root, 12.0, 18.0, 40.0, 36.0, C_STONE)
			_rect(root, 20.0, 26.0, 24.0, 28.0, C_DARK)
			_rect(root, 14.0, 20.0, 6.0, 34.0, C_WOOD)
			_rect(root, 44.0, 20.0, 6.0, 34.0, C_WOOD)
			_rect(root, 10.0, 14.0, 44.0, 8.0, C_WOOD_DARK)
			_stroke(root, PackedVector2Array([Vector2(24, 54), Vector2(30, 38)]),
				C_STEEL_DARK, 2.2)
			_stroke(root, PackedVector2Array([Vector2(40, 54), Vector2(34, 38)]),
				C_STEEL_DARK, 2.2)
			_circle(root, Vector2(32, 32), 2.4, C_GOLD)
		"deep_galleries":
			# Rock cross-section: a shaft feeding two galleries, gold seams below.
			_rect(root, 8.0, 10.0, 48.0, 46.0, C_STONE)
			_rect(root, 29.0, 10.0, 7.0, 22.0, C_DARK)
			_rect(root, 16.0, 28.0, 33.0, 7.0, C_DARK)
			_rect(root, 22.0, 44.0, 26.0, 7.0, C_DARK)
			_rect(root, 29.0, 32.0, 7.0, 14.0, C_DARK)
			for p: Vector2 in [Vector2(20, 31), Vector2(44, 48), Vector2(27, 48)]:
				_circle(root, p, 2.4, C_GOLD)
			_stroke(root, PackedVector2Array([Vector2(12, 20), Vector2(24, 14)]),
				C_STONE.darkened(0.25), 2.0)
			_stroke(root, PackedVector2Array([Vector2(40, 16), Vector2(52, 22)]),
				C_STONE.darkened(0.25), 2.0)
		"horse_collar":
			# The plough horse in its padded leather collar.
			_horse_head(root)
			var collar: PackedVector2Array = PackedVector2Array()
			for i: int in range(9):
				var a: float = deg_to_rad(-60.0 + 160.0 * float(i) / 8.0)
				collar.append(Vector2(36, 36) + Vector2(cos(a) * 16.0, sin(a) * 20.0))
			_stroke(root, collar, C_WOOD, 7.0)
			for i: int in [1, 4, 7]:
				_circle(root, collar[i], 2.0, C_GOLD)
		"heavy_plow":
			# Wooden beam and steel share carving a furrow.
			_bar(root, Vector2(6, 52), Vector2(58, 52), 5.0, C_WOOD_DARK)
			_poly(root, PackedVector2Array([Vector2(4, 58), Vector2(16, 46),
				Vector2(24, 52), Vector2(14, 58)]), C_SAND)
			_stroke(root, PackedVector2Array([Vector2(52, 12), Vector2(34, 26),
				Vector2(26, 42)]), C_WOOD, 5.0)
			_stroke(root, PackedVector2Array([Vector2(52, 12), Vector2(58, 20)]),
				C_WOOD, 4.0)
			_poly(root, PackedVector2Array([Vector2(22, 38), Vector2(34, 44),
				Vector2(30, 54), Vector2(16, 52)]), C_STEEL)
		"crop_rotation":
			# Wheat ear inside the cycle arrows.
			for arc_start: float in [20.0, 200.0]:
				var arrow: PackedVector2Array = PackedVector2Array()
				for i: int in range(9):
					var a: float = deg_to_rad(arc_start + 120.0 * float(i) / 8.0)
					arrow.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * 24.0)
				_stroke(root, arrow, C_GREEN, 4.0)
				var tip: float = deg_to_rad(arc_start + 120.0)
				var tp: Vector2 = Vector2(32, 32) + Vector2(cos(tip), sin(tip)) * 24.0
				var tangent: Vector2 = Vector2(-sin(tip), cos(tip))
				var out: Vector2 = Vector2(cos(tip), sin(tip))
				_poly(root, PackedVector2Array([tp + tangent * 9.0,
					tp + out * 7.0, tp - out * 7.0]), C_GREEN)
			_bar(root, Vector2(32, 46), Vector2(32, 24), 3.0,
				Color(0.80, 0.63, 0.24))
			_poly(root, _ellipse_pts(Vector2(26, 32), 4.5, 7.0, -35.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(38, 32), 4.5, 7.0, 35.0), C_GOLD)
			_poly(root, _ellipse_pts(Vector2(32, 20), 4.2, 6.5, 0.0), C_GOLD)
		_:
			_rect(root, 14.0, 14.0, 36.0, 40.0, C_PARCH)
			_rect(root, 10.0, 10.0, 36.0, 40.0, C_PARCH.lightened(0.08))
			_stroke(root, PackedVector2Array([Vector2(16, 20), Vector2(40, 20)]),
				C_WOOD_DARK, 2.2)
			_stroke(root, PackedVector2Array([Vector2(16, 27), Vector2(40, 27)]),
				C_WOOD_DARK, 2.2)
			_stroke(root, PackedVector2Array([Vector2(16, 34), Vector2(33, 34)]),
				C_WOOD_DARK, 2.2)
			_poly(root, PackedVector2Array([Vector2(36, 38), Vector2(52, 54),
				Vector2(47, 58), Vector2(33, 42)]), C_GOLD)
			_poly(root, PackedVector2Array([Vector2(52, 54), Vector2(58, 60),
				Vector2(47, 58)]), C_STEEL_DARK)

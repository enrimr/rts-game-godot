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
	"idle_villager", "idle_military", "locate_hero", "page_prev", "page_next",
	"res_food", "res_wood", "res_gold", "res_stone",
	"stat_attack", "stat_armor", "stat_range", "stat_speed",
]

## Stockpile display order shared by every cost row.
const RES_ORDER: Array[String] = ["food", "wood", "gold", "stone"]

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

## id -> ImageTexture (shared instance, filled async once).
static var _cache: Dictionary = {}

static func has_glyph(id: String) -> bool:
	return id in GLYPHS

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

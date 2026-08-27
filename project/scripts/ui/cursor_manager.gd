class_name CursorManager
extends Object

## Contextual mouse cursors: the pointer previews what a right-click would do
## (attack, gather, build/repair, board), like classic RTS games.
##
## Cursor textures are baked ONCE from the UiIcons glyph geometry via the same
## hidden-SubViewport pattern UiIcons uses, then downscaled to 32 px with a
## 1 px dark outline backing so the glyph reads over any terrain. Headless runs
## bake nothing; set_context() still tracks current_id so tests can assert it.
##
## resolve_context() is a pure function (selection flags + target kind →
## cursor id) so the mapping is unit-testable without a mouse or a scene tree.

const BAKE_SIZE: int = 64
const CURSOR_SIZE: int = 32
# Hotspot on the pointer-arrow tip: the composite cursor (small arrow
# top-left + context glyph bottom-right) clicks exactly where the arrow points.
const HOTSPOT: Vector2 = Vector2(2.0, 2.0)
const OUTLINE_COLOR: Color = Color(0.08, 0.07, 0.06)
const OUTLINE_ALPHA: float = 0.7

## Cursor ids with a baked texture. "default" (OS arrow) is implicit.
const CONTEXT_IDS: Array[String] = [
	"attack", "gather_wood", "gather_gold", "gather_stone", "gather_food",
	"build", "repair", "board",
]

const GATHER_RESOURCES: Array[String] = ["wood", "gold", "stone", "food"]

static var current_id: String = "default"
static var _textures: Dictionary = {}   # id -> ImageTexture (kept for tooling)
# id -> Image (CPU copy). The cursor is applied from this image directly:
# Input.set_custom_mouse_cursor(texture) re-reads the texture from VRAM, and
# that readback can transiently fail on macOS (occluded window, display
# switch), which surfaces as 'Parameter "imgrep" is null' in the DisplayServer.
# Feeding the CPU image to DisplayServer.cursor_set_custom_image avoids the
# readback entirely.
static var _images: Dictionary = {}
static var _baking: Dictionary = {}     # id -> true while the bake is in flight

## Pure mapping: what would a right-click do with this selection on this target?
## target_kind: "transport" | "enemy" | "animal" | "resource" | "construction"
## | "damaged" | "none".
static func resolve_context(has_villagers: bool, has_military: bool,
		has_land_units: bool, target_kind: String,
		target_resource: String = "") -> String:
	match target_kind:
		"transport":
			if has_land_units:
				return "board"
		"enemy":
			if has_military or has_villagers:
				return "attack"
		"animal":
			if has_villagers:
				return "gather_food"
			if has_military:
				return "attack"
		"resource":
			if has_villagers and target_resource in GATHER_RESOURCES:
				return "gather_" + target_resource
		"construction":
			if has_villagers:
				return "build"
		"damaged":
			if has_villagers:
				return "repair"
	return "default"

static func set_context(id: String) -> void:
	if id == current_id:
		return
	current_id = id
	_apply(id)

static func prebake() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_bake("default")
	for id: String in CONTEXT_IDS:
		_bake(id)

static func _apply(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Escape hatch while diagnosing platform cursor issues.
	if OS.get_environment("CALIMA_NO_CURSORS") == "1":
		return
	var texture: ImageTexture = _textures.get(id) as ImageTexture
	if id == "default":
		texture = _textures.get("default") as ImageTexture
	if texture == null:
		# Default not baked yet (or unknown id): fall back to the OS arrow.
		if OS.get_environment("CALIMA_CURSOR_DEBUG") == "1":
			printerr("CURSOR_APPLY reset (id='", id, "', baked=false)")
		Input.set_custom_mouse_cursor(null)
		return
	# Probe the VRAM readback ourselves first: on macOS it can transiently
	# fail (occluded window, display switch) and passing the texture then
	# raises 'Parameter "imgrep" is null' inside the DisplayServer. If the
	# probe fails we skip this transition; the next context change retries.
	# (Applying a raw Image via DisplayServer.cursor_set_custom_image avoids
	# the readback but silently no-ops on macOS, so the texture path stays.)
	var probe: Image = texture.get_image()
	if probe == null or probe.is_empty():
		if OS.get_environment("CALIMA_CURSOR_DEBUG") == "1":
			printerr("CURSOR_APPLY skipped '", id, "': VRAM readback empty")
		return
	# Debug diagnostic: if the macOS 'imgrep is null' error ever fires, the
	# line right before it in the log identifies the exact cursor and state.
	if OS.get_environment("CALIMA_CURSOR_DEBUG") == "1":
		printerr("CURSOR_APPLY '", id, "' img=", probe.get_width(), "x",
			probe.get_height(), " fmt=", probe.get_format(),
			" win_mode=", DisplayServer.window_get_mode())
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, HOTSPOT)

static func _bake(id: String) -> void:
	if _textures.has(id) or _baking.get(id, false):
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_baking[id] = true
	var viewport: SubViewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(BAKE_SIZE, BAKE_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var root: Node2D = Node2D.new()
	viewport.add_child(root)
	# Composite cursor: the context glyph shrinks to the bottom-right and a
	# small pointer arrow sits top-left, so the cursor still reads as "the
	# cursor" and marks the exact click point.
	if id == "default":
		# The signature tabona alone, larger — Calima's default pointer.
		_add_pointer_arrow(root, 1.15)
	else:
		var glyph_root: Node2D = Node2D.new()
		glyph_root.scale = Vector2(0.62, 0.62)
		glyph_root.position = Vector2(BAKE_SIZE * 0.36, BAKE_SIZE * 0.36)
		root.add_child(glyph_root)
		if id == "board":
			_build_board(glyph_root)
		else:
			UiIcons._build(id, glyph_root)
		_add_pointer_arrow(root)
	tree.root.add_child.call_deferred(viewport)
	await tree.process_frame
	await tree.process_frame
	await RenderingServer.frame_post_draw
	_baking.erase(id)
	if not is_instance_valid(viewport):
		return
	var img: Image = viewport.get_texture().get_image()
	viewport.free()
	if img == null or img.is_empty():
		return
	img.resize(CURSOR_SIZE, CURSOR_SIZE, Image.INTERPOLATE_LANCZOS)
	var outlined: Image = _with_outline(img)
	_images[id] = outlined
	_textures[id] = ImageTexture.create_from_image(outlined)
	if current_id == id:
		# This resume point sits right after `await frame_post_draw`, i.e. at
		# the renderer sync — calling the OS cursor API (AppKit on macOS)
		# there fails intermittently ('Parameter "imgrep" is null'). Defer
		# the re-apply to the next main-loop iteration.
		var apply_id: String = id
		(func() -> void:
			if current_id == apply_id:
				_apply(apply_id)).call_deferred()

## Calima's signature pointer: an original slender knife-pointer blending the
## tabona (Guanche volcanic-glass blade) with the naife canario silhouette —
## steel blade with a bone edge, brass ferrule, and the naife's iconic ringed
## handle (alternating bone / horn / brass bands). Authored tip-up in local
## space, rotated to the pointer diagonal; the blade tip lands on HOTSPOT.
static func _add_pointer_arrow(root: Node2D, pointer_scale: float = 1.0) -> void:
	var holder: Node2D = Node2D.new()
	holder.position = Vector2(3.0, 3.0)
	holder.rotation = -PI / 4.0
	holder.scale = Vector2(pointer_scale, pointer_scale)
	root.add_child(holder)

	var silhouette: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0), Vector2(5, 15), Vector2(5.5, 24.5),
		Vector2(4.2, 39), Vector2(-4.2, 39), Vector2(-5.5, 24.5), Vector2(-5, 15),
	])
	var backing: Polygon2D = Polygon2D.new()
	var back_pts: PackedVector2Array = PackedVector2Array()
	for pt: Vector2 in silhouette:
		back_pts.append(pt * 1.08 + Vector2(0, -0.5))
	backing.polygon = back_pts
	backing.color = Color(0.07, 0.06, 0.06, 0.85)
	holder.add_child(backing)

	# Blade: steel with a darker right facet and a bone-bright cutting edge.
	var blade: Polygon2D = Polygon2D.new()
	blade.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(5, 15), Vector2(5.3, 22), Vector2(-5.3, 22), Vector2(-5, 15),
	])
	blade.color = Color(0.70, 0.72, 0.76)
	holder.add_child(blade)

	var facet: Polygon2D = Polygon2D.new()
	facet.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(5, 15), Vector2(5.3, 22), Vector2(0, 22),
	])
	facet.color = Color(0.52, 0.55, 0.60)
	holder.add_child(facet)

	var edge: Polygon2D = Polygon2D.new()
	edge.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(-5, 15), Vector2(-3.4, 16.5), Vector2(-0.6, 3.2),
	])
	edge.color = Color(0.93, 0.92, 0.87)
	holder.add_child(edge)

	# Brass ferrule between blade and handle.
	var ferrule: Polygon2D = Polygon2D.new()
	ferrule.polygon = PackedVector2Array([
		Vector2(-5.3, 22), Vector2(5.3, 22), Vector2(5.1, 25), Vector2(-5.1, 25),
	])
	ferrule.color = Color(0.74, 0.57, 0.24)
	holder.add_child(ferrule)

	# Naife handle: alternating bone / dark horn rings, brass mid-band,
	# tapering slightly toward a dark pommel.
	var ring_colors: Array[Color] = [
		Color(0.85, 0.78, 0.62), Color(0.24, 0.19, 0.15),
		Color(0.74, 0.57, 0.24), Color(0.85, 0.78, 0.62),
	]
	var y0: float = 25.0
	var ring_h: float = 3.0
	for i: int in range(ring_colors.size()):
		var top_w: float = 5.0 - 0.25 * float(i)
		var bot_w: float = 5.0 - 0.25 * float(i + 1)
		var ring: Polygon2D = Polygon2D.new()
		ring.polygon = PackedVector2Array([
			Vector2(-top_w, y0), Vector2(top_w, y0),
			Vector2(bot_w, y0 + ring_h), Vector2(-bot_w, y0 + ring_h),
		])
		ring.color = ring_colors[i]
		holder.add_child(ring)
		y0 += ring_h
	var pommel: Polygon2D = Polygon2D.new()
	pommel.polygon = PackedVector2Array([
		Vector2(-4.0, y0), Vector2(4.0, y0), Vector2(3.0, y0 + 2.2), Vector2(-3.0, y0 + 2.2),
	])
	pommel.color = Color(0.20, 0.16, 0.13)
	holder.add_child(pommel)

## Embark counterpart of the UiIcons "unload" glyph: same raft, arrow rising
## into it. Drawn here (not in ui_icons.gd) with the shared geometry helpers.
static func _build_board(root: Node2D) -> void:
	UiIcons._rect(root, 16.0, 8.0, 32.0, 26.0, UiIcons.C_WOOD)
	UiIcons._stroke(root, PackedVector2Array([Vector2(16, 8), Vector2(48, 34)]),
		UiIcons.C_WOOD_DARK, 3.0)
	UiIcons._stroke(root, PackedVector2Array([Vector2(48, 8), Vector2(16, 34)]),
		UiIcons.C_WOOD_DARK, 3.0)
	UiIcons._bar(root, Vector2(32, 58), Vector2(32, 49), 9.0, UiIcons.C_PALE)
	UiIcons._poly(root, PackedVector2Array([Vector2(32, 38), Vector2(22, 50),
		Vector2(42, 50)]), UiIcons.C_PALE)

## Composites the glyph over a 1 px dilated dark silhouette so the cursor
## stays readable over bright sand and dark lava alike.
static func _with_outline(glyph: Image) -> Image:
	var size: int = glyph.get_width()
	var out: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var max_alpha: float = 0.0
			# Cross kernel (no diagonals): a finer rim without corner bulges.
			for off: Vector2i in [Vector2i(0, 0), Vector2i(1, 0),
					Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					continue
				max_alpha = maxf(max_alpha, glyph.get_pixel(nx, ny).a)
			if max_alpha > 0.0:
				out.set_pixel(x, y, Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g,
					OUTLINE_COLOR.b, max_alpha * OUTLINE_ALPHA))
	out.blend_rect(glyph, Rect2i(0, 0, size, size), Vector2i.ZERO)
	return out

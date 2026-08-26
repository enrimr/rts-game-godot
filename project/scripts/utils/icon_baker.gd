class_name IconBaker
extends Object

## Runtime entity-icon baker for the HUD.
##
## All art in the game is procedural (Polygon2D + CivStyle + UnitDress), so
## instead of hand-drawn icon assets the HUD renders the REAL entity scene into
## an offscreen SubViewport under the same isometric camera projection used in
## game. Icons therefore automatically match the owning player's civilization
## style. Results are cached per (scene, civilization).
##
## get_icon() is synchronous: it returns a cached ImageTexture immediately
## (initially a civ-tinted placeholder) and fills it in a few frames later when
## the offscreen render completes, so callers never need to await. Headless
## runs (tests, CI) keep the placeholder — the full instantiate/free lifecycle
## still executes so group hygiene stays testable.

const ICON_SIZE: int = 96
## Fraction of the icon square the entity's screen bounds are scaled to fill.
const FRAME_FILL: float = 0.94
const MIN_ZOOM: float = 0.05
const MAX_ZOOM: float = 8.0
const FALLBACK_BOUNDS: Rect2 = Rect2(-24.0, -40.0, 48.0, 56.0)

## key "scene_path|civ_id" -> ImageTexture (shared instance, filled async).
static var _cache: Dictionary = {}

static func get_icon(scene_path: String, player_id: int) -> Texture2D:
	var key: String = "%s|%s" % [scene_path, CivStyle.civ_id_for_player(player_id)]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var texture: ImageTexture = ImageTexture.create_from_image(_placeholder_image(player_id))
	_cache[key] = texture
	_bake_async(texture, scene_path, player_id)
	return texture

## Call on match (re)start: players may pick different civilizations.
static func clear_cache() -> void:
	_cache.clear()

static func _bake_async(target: ImageTexture, scene_path: String, player_id: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var entity: Node2D = packed.instantiate() as Node2D
	if entity == null:
		return

	var viewport: SubViewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# One-shot render: project-wide physics interpolation would only smear the
	# grab across physics ticks (and force the camera into physics mode).
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var camera: Camera2D = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	viewport.add_child(camera)

	# player_id must be assigned before _ready so civ style/HP passes see it.
	entity.set("player_id", player_id)
	# Deterministic icon: skip the 50/50 random visual gender roll.
	if "is_female" in entity:
		entity.set("is_female", false)
	viewport.add_child(entity)
	tree.root.add_child(viewport)
	# The entity's _ready joined gameplay groups ("buildings", "animals", ...);
	# leave them immediately so victory checks and queries never see the prop.
	_strip_groups(entity)
	if entity.has_method("force_complete"):
		entity.call("force_complete")

	# Four frames flush the call_deferred visual passes (massing, billboard,
	# dress, team accents): the chains re-defer internally, so two frames
	# measured bounds before late polygons (foundation, contact shadow)
	# existed — icons framed low and buildings visually spilled the frame.
	for _i: int in range(4):
		await tree.process_frame
	if not is_instance_valid(viewport) or not is_instance_valid(entity):
		return
	_strip_groups(entity)
	# Icons show only the art: hide UI overlays (HP/food/construction bars,
	# nameplates) so they neither render nor stretch the measured bounds —
	# a baked-in bar under the entity read as art spilling out of the button.
	_hide_ui_overlays(entity)

	var bounds: Rect2 = _screen_bounds(entity)
	var zoom: float = clampf(FRAME_FILL * float(ICON_SIZE) / maxf(bounds.size.x, bounds.size.y),
		MIN_ZOOM, MAX_ZOOM)
	camera.global_position = IsoProjection.screen_to_world(bounds.get_center())
	IsoProjection.apply_to_camera(camera, zoom)

	await tree.process_frame
	await tree.process_frame
	# The dummy renderer has no render-target textures: headless runs keep the
	# placeholder (tests only exercise the lifecycle, never the pixels).
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not is_instance_valid(viewport):
			return
		var img: Image = viewport.get_texture().get_image()
		if img != null and not img.is_empty() and img.get_used_rect().has_area():
			target.set_image(img)
	# free (not queue_free) so no zombie nodes linger past the bake.
	if is_instance_valid(viewport):
		viewport.free()

## Removes the node subtree from every non-internal scene group.
static func _hide_ui_overlays(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is ProgressBar or node is Label \
				or node.name.begins_with("PlayerColorStripe"):
			(node as CanvasItem).visible = false
		for child: Node in node.get_children():
			stack.append(child)

static func _strip_groups(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		for group: StringName in node.get_groups():
			if not String(group).begins_with("_"):
				node.remove_from_group(group)

## Merged screen-space bounds (zoom 1, camera math mirrored via IsoProjection)
## of every visible drawn point, so the camera frames head-to-feet rigs and
## full building massings alike.
static func _screen_bounds(entity: Node2D) -> Rect2:
	var rect: Rect2 = Rect2()
	var has_any: bool = false
	var stack: Array[Node] = [entity]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not (node is CanvasItem) or not (node as CanvasItem).is_visible_in_tree():
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		if node is Polygon2D:
			pts = (node as Polygon2D).polygon
		elif node is Line2D:
			pts = (node as Line2D).points
		if pts.is_empty():
			continue
		var to_world: Transform2D = (node as Node2D).get_global_transform()
		for p: Vector2 in pts:
			var screen_pt: Vector2 = IsoProjection.world_to_screen(to_world * p)
			if has_any:
				rect = rect.expand(screen_pt)
			else:
				rect = Rect2(screen_pt, Vector2.ZERO)
				has_any = true
	if not has_any or rect.size.x < 4.0 or rect.size.y < 4.0:
		return FALLBACK_BOUNDS
	return rect

## Civ-tinted diamond shown until the bake lands (or forever when headless).
static func _placeholder_image(player_id: int) -> Image:
	var img: Image = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var style: Dictionary = CivStyle.style_for_player(player_id)
	var wall: Color = style["wall"] as Color
	var trim: Color = style["trim"] as Color
	var center: float = ICON_SIZE * 0.5
	var radius: float = ICON_SIZE * 0.34
	for y: int in range(ICON_SIZE):
		for x: int in range(ICON_SIZE):
			var d: float = absf(float(x) - center) + absf(float(y) - center)
			if d <= radius:
				img.set_pixel(x, y, wall)
			elif d <= radius + 3.0:
				img.set_pixel(x, y, trim)
	return img

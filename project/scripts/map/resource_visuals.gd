class_name ResourceVisuals extends RefCounted

## Procedural visuals for resource nodes: the node factory (Node2D + script +
## collision + nav obstacle) and the Polygon2D drawing library for every
## resource type. Everything here is static — MapGenerator calls it while
## generating a map, SaveManager while restoring one, and ResourceNode itself
## when a tree turns into a stump.

## Public static factory — call this from SaveManager when restoring nodes.
## Pass a seeded RNG (or null for fixed-size defaults).
static func create_resource_node(parent: Node2D, pos: Vector2,
		rtype: ResourceNode.ResourceType, amount: float,
		rng: RandomNumberGenerator = null,
		res_script: Script = null) -> void:
	var node: Node2D = Node2D.new()
	if res_script == null:
		res_script = load("res://scripts/economy/resource_node.gd") as Script
	node.set_script(res_script)
	node.set("resource_type", rtype)
	node.set("initial_amount", amount)
	parent.add_child(node)
	node.global_position = pos

	var jitter: float = rng.randf_range(0.85, 1.15) if rng != null else 1.0
	var collision_r: float = build_visual(node, rtype, jitter, amount)

	var area: Area2D = Area2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = collision_r + 4.0
	shape.shape = circle
	area.add_child(shape)
	node.add_child(area)

	# Fish nodes live in the ocean — only land resources need physics blocking.
	if rtype != ResourceNode.ResourceType.FOOD_FISH:
		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var body_shape: CollisionShape2D = CollisionShape2D.new()
		var body_circle: CircleShape2D = CircleShape2D.new()
		body_circle.radius = maxf(collision_r * 0.7, 8.0)
		body_shape.shape = body_circle
		body.add_child(body_shape)
		node.add_child(body)

		var obstacle: NavigationObstacle2D = NavigationObstacle2D.new()
		obstacle.radius = collision_r + 4.0
		obstacle.avoidance_enabled = true
		node.add_child(obstacle)

	IsoBillboard.setup_drawn_node(node)

# Builds the visual Polygon2D children for a resource node.
# Returns the effective collision radius.
static func build_visual(node: Node2D,
		rtype: ResourceNode.ResourceType, scale: float, amount: float = 0.0) -> float:
	match rtype:
		ResourceNode.ResourceType.WOOD:
			return _draw_tree(node, scale)
		ResourceNode.ResourceType.GOLD:
			return _draw_gold(node, scale, amount)
		ResourceNode.ResourceType.STONE:
			return _draw_stone(node, scale, amount)
		ResourceNode.ResourceType.FOOD_BERRY:
			return _draw_berry_bush(node, scale, amount)
		ResourceNode.ResourceType.FOOD_HUNT:
			return _draw_deer(node, scale)
		ResourceNode.ResourceType.FOOD_FISH:
			return _draw_fish(node, scale)
		ResourceNode.ResourceType.OLIVINA:
			return _draw_olivina(node, scale, amount)
	return 12.0

# ── Tree (wood) ──────────────────────────────────────────────────────────────
static func _draw_tree(node: Node2D, s: float) -> float:
	# Trunk
	var trunk: Polygon2D = Polygon2D.new()
	trunk.color = Color(0.38, 0.24, 0.12)
	var tw: float = 3.0 * s
	var th: float = 10.0 * s
	trunk.polygon = PackedVector2Array([
		Vector2(-tw, 0.0), Vector2(tw, 0.0),
		Vector2(tw * 0.7, -th), Vector2(-tw * 0.7, -th),
	])
	node.add_child(trunk)
	# Three layered canopy circles using Polygon2D octagons
	const LAYERS: Array = [
		[0.0,  -8.0,  13.0, Color(0.10, 0.48, 0.12)],
		[0.0,  -16.0, 11.0, Color(0.14, 0.58, 0.16)],
		[0.0,  -23.0,  8.0, Color(0.18, 0.65, 0.20)],
	]
	for layer: Variant in LAYERS:
		var la: Array = layer as Array
		var cx: float = (la[0] as float) * s
		var cy: float = (la[1] as float) * s
		var r: float  = (la[2] as float) * s
		var col: Color = la[3] as Color
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(8):
			var a: float = TAU * i / 8.0 - PI / 8.0
			pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
		var canopy: Polygon2D = Polygon2D.new()
		canopy.color = col
		canopy.polygon = pts
		node.add_child(canopy)
	# Shadow ellipse under the tree
	var shadow: Polygon2D = Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	var sw: float = 11.0 * s
	var sh: float = 4.0 * s
	var spts: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var a: float = TAU * i / 10.0
		spts.append(Vector2(cos(a) * sw, sin(a) * sh))
	shadow.polygon = spts
	shadow.z_index = -1
	node.add_child(shadow)
	return 13.0 * s

# ── Tree stump (shown while a villager is actively chopping) ─────────────────
static func draw_tree_stump(node: Node2D, s: float) -> void:
	# Shadow ellipse — keep same footprint so it still reads as a ground object
	var shadow: Polygon2D = Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	var sw: float = 11.0 * s
	var sh: float = 4.0 * s
	var spts: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var a: float = TAU * i / 10.0
		spts.append(Vector2(cos(a) * sw, sin(a) * sh))
	shadow.polygon = spts
	shadow.z_index = -1
	node.add_child(shadow)
	# Short wide stump
	var stump: Polygon2D = Polygon2D.new()
	stump.color = Color(0.38, 0.24, 0.12)
	var sw2: float = 5.0 * s
	var sh2: float = 4.0 * s
	stump.polygon = PackedVector2Array([
		Vector2(-sw2, 0.0), Vector2(sw2, 0.0),
		Vector2(sw2 * 0.8, -sh2), Vector2(-sw2 * 0.8, -sh2),
	])
	node.add_child(stump)
	# Horizontal log lying to the right, rotated slightly
	var log: Polygon2D = Polygon2D.new()
	log.color = Color(0.42, 0.27, 0.14)
	var lw: float = 10.0 * s
	var lh: float = 2.0 * s
	log.polygon = PackedVector2Array([
		Vector2(-lw, -lh), Vector2(lw, -lh),
		Vector2(lw,  lh),  Vector2(-lw,  lh),
	])
	log.position = Vector2(12.0 * s, -2.0 * s)
	log.rotation = deg_to_rad(15.0)
	node.add_child(log)

# ── Gold rocks ───────────────────────────────────────────────────────────────
static func _draw_gold(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int = 2 if amount <= 160.0 else 3
	const LAYOUTS_2: Array = [[-7.0, 2.0, 1.00], [ 6.0, 0.0, 0.90]]
	const LAYOUTS_3: Array = [[-9.0, 2.0, 1.00], [ 4.0, 0.0, 0.88], [ 0.0,-7.0, 0.75]]
	var layout: Array = LAYOUTS_2 if count == 2 else LAYOUTS_3
	for entry: Variant in layout:
		var e: Array = entry as Array
		var container: Node2D = Node2D.new()
		container.position = Vector2((e[0] as float) * s, (e[1] as float) * s)
		node.add_child(container)
		_draw_single_gold_rock(container, s * (e[2] as float))
	return (14.0 if count == 3 else 11.0) * s

static func _draw_single_gold_rock(node: Node2D, s: float) -> void:
	# Ground shadow ellipse
	var ground: Polygon2D = Polygon2D.new()
	ground.color = Color(0.40, 0.32, 0.08, 0.5)
	var gpts: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var a: float = TAU * i / 10.0
		gpts.append(Vector2(cos(a) * 9.0 * s, sin(a) * 4.0 * s))
	ground.polygon = gpts
	ground.z_index = -1
	node.add_child(ground)
	# Rock blob — dark earthy brown
	var rpts: PackedVector2Array = PackedVector2Array()
	const RANGLES: Array = [0.0, 0.9, 1.8, 2.7, 3.6, 4.5, 5.4]
	const RRADII:  Array = [8.0, 6.5, 9.0, 7.5, 6.0, 8.5, 7.0]
	for i: int in range(7):
		var a: float = (RANGLES[i] as float)
		var rr: float = (RRADII[i] as float) * s
		rpts.append(Vector2(cos(a) * rr, sin(a) * rr * 0.62))
	var rock_poly: Polygon2D = Polygon2D.new()
	rock_poly.color = Color(0.40, 0.33, 0.16)
	rock_poly.polygon = rpts
	node.add_child(rock_poly)
	# Top highlight — lighter warm stone
	var hi: Polygon2D = Polygon2D.new()
	hi.color = Color(0.60, 0.50, 0.26, 0.55)
	hi.polygon = PackedVector2Array([rpts[6], rpts[0], rpts[1], rpts[2]])
	node.add_child(hi)
	# Gold vein streaks
	const VEINS: Array = [[-5.0,-2.5, 1.0,-1.0, 4.5, 0.5], [-1.0, 0.5, 3.5,-0.8, 2.0, 2.0]]
	for v: Variant in VEINS:
		var vd: Array = v as Array
		var vein: Line2D = Line2D.new()
		vein.default_color = Color(0.95, 0.80, 0.10, 0.85)
		vein.width = 1.5 * s
		vein.add_point(Vector2((vd[0] as float) * s, (vd[1] as float) * s))
		vein.add_point(Vector2((vd[2] as float) * s, (vd[3] as float) * s))
		vein.add_point(Vector2((vd[4] as float) * s, (vd[5] as float) * s))
		node.add_child(vein)

# ── Olivina crystals ──────────────────────────────────────────────────────────
static func _draw_olivina(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int
	if amount <= 100.0:
		count = 2
	elif amount <= 180.0:
		count = 3
	else:
		count = 4
	# [offset_x, offset_y, half_width, height, angle, Color]
	const CRYSTAL_2: Array = [
		[-4.0,  0.0, 3.2, 11.0, -0.25, Color(0.35, 0.82, 0.28)],
		[ 4.0, -1.0, 2.8, 10.0,  0.30, Color(0.28, 0.70, 0.20)],
	]
	const CRYSTAL_3: Array = [
		[-5.0,  0.0, 3.5, 12.0, -0.25, Color(0.35, 0.82, 0.28)],
		[ 1.0,  1.0, 3.0, 14.0,  0.10, Color(0.45, 0.92, 0.35)],
		[ 5.0, -1.0, 2.5, 10.0,  0.35, Color(0.28, 0.70, 0.20)],
	]
	const CRYSTAL_4: Array = [
		[-7.0,  1.0, 3.5, 13.0, -0.30, Color(0.35, 0.82, 0.28)],
		[ 0.0,  0.0, 3.2, 15.0,  0.08, Color(0.45, 0.92, 0.35)],
		[ 5.0, -1.0, 2.5, 10.0,  0.32, Color(0.28, 0.70, 0.20)],
		[-2.0, -5.0, 2.2,  9.0, -0.15, Color(0.38, 0.78, 0.26)],
	]
	var crystals: Array
	match count:
		2: crystals = CRYSTAL_2
		4: crystals = CRYSTAL_4
		_: crystals = CRYSTAL_3

	# Ground patch scales with count
	var ground: Polygon2D = Polygon2D.new()
	ground.color = Color(0.12, 0.38, 0.10, 0.6)
	var gw: float = (7.0 + float(count) * 2.0) * s
	ground.polygon = PackedVector2Array([
		Vector2(-gw, 0.0), Vector2(gw, 0.0),
		Vector2(gw * 0.72, 4.0 * s), Vector2(-gw * 0.72, 4.0 * s),
	])
	node.add_child(ground)

	for c: Variant in crystals:
		var ca: Array = c as Array
		var bx: float = (ca[0] as float) * s
		var by: float = (ca[1] as float) * s
		var hw: float = (ca[2] as float) * s
		var ht: float = (ca[3] as float) * s
		var angle: float = ca[4] as float
		var col: Color = ca[5] as Color
		var raw: PackedVector2Array = PackedVector2Array([
			Vector2(0.0, -ht),
			Vector2(hw, -ht * 0.35),
			Vector2(hw * 0.6, 0.0),
			Vector2(-hw * 0.6, 0.0),
			Vector2(-hw, -ht * 0.35),
		])
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in raw:
			pts.append(Vector2(
				bx + p.x * cos(angle) - p.y * sin(angle),
				by + p.x * sin(angle) + p.y * cos(angle)
			))
		var shard: Polygon2D = Polygon2D.new()
		shard.color = col
		shard.polygon = pts
		node.add_child(shard)
		var face_bright: Polygon2D = Polygon2D.new()
		face_bright.color = Color(0.75, 1.0, 0.65, 0.50)
		face_bright.polygon = PackedVector2Array([pts[0], pts[1], pts[2]])
		node.add_child(face_bright)
	return (10.0 + float(count) * 2.0) * s

# ── Stone rocks ──────────────────────────────────────────────────────────────
static func _draw_stone(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int = 2 if amount <= 180.0 else 3
	const LAYOUTS_2: Array = [[-6.0, 1.0, 1.00], [ 5.0, 0.0, 0.92]]
	const LAYOUTS_3: Array = [[-8.0, 1.0, 1.00], [ 4.0, 0.0, 0.90], [-1.0,-7.0, 0.78]]
	var layout: Array = LAYOUTS_2 if count == 2 else LAYOUTS_3
	for entry: Variant in layout:
		var e: Array = entry as Array
		var container: Node2D = Node2D.new()
		container.position = Vector2((e[0] as float) * s, (e[1] as float) * s)
		node.add_child(container)
		_draw_single_stone_rock(container, s * (e[2] as float))
	return (14.0 if count == 3 else 11.0) * s

static func _draw_single_stone_rock(node: Node2D, s: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	const ANGLES: Array = [0.0, 0.9, 1.8, 2.7, 3.6, 4.5, 5.4]
	const RADII:  Array = [9.0, 7.5, 10.0, 8.0, 6.5, 9.5, 7.0]
	for i: int in range(7):
		var a: float = (ANGLES[i] as float)
		var rr: float = (RADII[i] as float) * s
		pts.append(Vector2(cos(a) * rr, sin(a) * rr * 0.6))
	var rock_poly: Polygon2D = Polygon2D.new()
	rock_poly.color = Color(0.52, 0.50, 0.47)
	rock_poly.polygon = pts
	node.add_child(rock_poly)
	var hi: Polygon2D = Polygon2D.new()
	hi.color = Color(0.75, 0.73, 0.70, 0.55)
	hi.polygon = PackedVector2Array([pts[6], pts[0], pts[1], pts[2]])
	node.add_child(hi)

# ── Berry bush (food) ────────────────────────────────────────────────────────
static func _draw_berry_bush(node: Node2D, s: float, amount: float = 0.0) -> float:
	var count: int
	if amount <= 88.0:
		count = 2
	elif amount <= 132.0:
		count = 3
	else:
		count = 4
	const LAYOUTS_2: Array = [[-7.0, 0.0, 1.00], [ 6.0, 0.0, 0.88]]
	const LAYOUTS_3: Array = [[-8.0, 0.0, 1.00], [ 4.0, 0.0, 0.88], [-1.0,-8.0, 0.80]]
	const LAYOUTS_4: Array = [[-9.0, 0.0, 1.00], [ 5.0,-1.0, 0.88], [-2.0,-8.0, 0.82], [ 7.0,-6.0, 0.75]]
	var layout: Array
	match count:
		2: layout = LAYOUTS_2
		4: layout = LAYOUTS_4
		_: layout = LAYOUTS_3
	for entry: Variant in layout:
		var e: Array = entry as Array
		var container: Node2D = Node2D.new()
		container.position = Vector2((e[0] as float) * s, (e[1] as float) * s)
		node.add_child(container)
		_draw_single_berry_bush(container, s * (e[2] as float))
	return (12.0 + float(count) * 2.5) * s

static func _draw_single_berry_bush(node: Node2D, s: float) -> void:
	const BLOBS: Array = [
		[-4.0, -2.0, 9.0, Color(0.15, 0.48, 0.12)],
		[ 4.0, -1.0, 8.0, Color(0.18, 0.55, 0.15)],
		[ 0.0, -7.0, 7.0, Color(0.20, 0.52, 0.14)],
	]
	for bl: Variant in BLOBS:
		var bla: Array = bl as Array
		var bx: float = (bla[0] as float) * s
		var by: float = (bla[1] as float) * s
		var br: float = (bla[2] as float) * s
		var col: Color = bla[3] as Color
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(9):
			var a: float = TAU * i / 9.0
			pts.append(Vector2(bx + cos(a) * br, by + sin(a) * br * 0.85))
		var blob: Polygon2D = Polygon2D.new()
		blob.color = col
		blob.polygon = pts
		node.add_child(blob)
	const BERRIES: Array = [
		[-5.0, -4.0], [0.0, -9.0], [5.0, -5.0],
		[-3.0, -1.0], [4.0, -2.0], [1.0, -6.0],
	]
	for bpos: Variant in BERRIES:
		var bp: Array = bpos as Array
		var bx: float = (bp[0] as float) * s
		var by: float = (bp[1] as float) * s
		var br: float = 1.8 * s
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(6):
			var a: float = TAU * i / 6.0
			pts.append(Vector2(bx + cos(a) * br, by + sin(a) * br))
		var berry: Polygon2D = Polygon2D.new()
		berry.color = Color(0.85, 0.15, 0.10)
		berry.polygon = pts
		node.add_child(berry)

# ── Deer (hunt food) ─────────────────────────────────────────────────────────
static func _draw_deer(node: Node2D, s: float) -> float:
	# Body — oval
	var body: Polygon2D = Polygon2D.new()
	body.color = Color(0.65, 0.38, 0.15)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(12):
		var a: float = TAU * i / 12.0
		pts.append(Vector2(cos(a) * 9.0 * s, sin(a) * 5.5 * s - 2.0 * s))
	body.polygon = pts
	node.add_child(body)
	# Head
	var head: Polygon2D = Polygon2D.new()
	head.color = Color(0.60, 0.34, 0.13)
	var hpts: PackedVector2Array = PackedVector2Array()
	for i: int in range(8):
		var a: float = TAU * i / 8.0
		hpts.append(Vector2(8.0 * s + cos(a) * 4.0 * s, -4.0 * s + sin(a) * 3.0 * s))
	head.polygon = hpts
	node.add_child(head)
	# Antlers — two small lines as thin polygons
	const ANTLERS: Array = [
		[8.0, -7.0, 10.0, -13.0],
		[10.0, -7.0, 13.0, -13.0],
	]
	for ant: Variant in ANTLERS:
		var aa: Array = ant as Array
		var ax1: float = (aa[0] as float) * s
		var ay1: float = (aa[1] as float) * s
		var ax2: float = (aa[2] as float) * s
		var ay2: float = (aa[3] as float) * s
		var dir: Vector2 = (Vector2(ax2, ay2) - Vector2(ax1, ay1)).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x) * 0.8 * s
		var antler: Polygon2D = Polygon2D.new()
		antler.color = Color(0.35, 0.20, 0.08)
		antler.polygon = PackedVector2Array([
			Vector2(ax1, ay1) - perp, Vector2(ax1, ay1) + perp,
			Vector2(ax2, ay2) + perp, Vector2(ax2, ay2) - perp,
		])
		node.add_child(antler)
	# Legs — four thin rectangles
	const LEGS: Array = [-6.0, -2.0, 2.0, 6.0]
	for lx: Variant in LEGS:
		var leg: Polygon2D = Polygon2D.new()
		leg.color = Color(0.50, 0.28, 0.10)
		var lxf: float = (lx as float) * s
		leg.polygon = PackedVector2Array([
			Vector2(lxf - 1.2 * s, 3.0 * s), Vector2(lxf + 1.2 * s, 3.0 * s),
			Vector2(lxf + 1.0 * s, 9.0 * s), Vector2(lxf - 1.0 * s, 9.0 * s),
		])
		node.add_child(leg)
	return 11.0 * s

# ── Fish ─────────────────────────────────────────────────────────────────────
static func _draw_fish(node: Node2D, s: float) -> float:
	# School layout: [offset_x, offset_y, angle_deg, size_mult]
	# Fish are spread in a loose shoal formation around the resource point.
	const SCHOOL: Array = [
		[ 0.0,   0.0,   0.0,  1.00],
		[22.0, -14.0,  20.0,  0.80],
		[26.0,  13.0, -14.0,  0.85],
		[-18.0, -10.0,  8.0,  0.75],
		[ 12.0,  22.0, -24.0, 0.72],
	]
	for entry: Array in SCHOOL:
		var container: Node2D = Node2D.new()
		container.position = Vector2((entry[0] as float) * s, (entry[1] as float) * s)
		container.rotation = deg_to_rad(entry[2] as float)
		node.add_child(container)
		_draw_single_fish(container, s * (entry[3] as float))
	return 38.0 * s

static func _draw_single_fish(node: Node2D, s: float) -> void:
	# Body
	var body: Polygon2D = Polygon2D.new()
	body.color = Color(0.25, 0.55, 0.75)
	body.polygon = PackedVector2Array([
		Vector2(-9.0 * s, 0.0),
		Vector2(-4.0 * s, -3.5 * s),
		Vector2(6.0 * s, -2.5 * s),
		Vector2(9.0 * s, 0.0),
		Vector2(6.0 * s, 2.5 * s),
		Vector2(-4.0 * s, 3.5 * s),
	])
	node.add_child(body)
	# Tail fin
	var tail: Polygon2D = Polygon2D.new()
	tail.color = Color(0.20, 0.45, 0.65)
	tail.polygon = PackedVector2Array([
		Vector2(-9.0 * s, 0.0),
		Vector2(-14.0 * s, -4.0 * s),
		Vector2(-12.0 * s, 0.0),
		Vector2(-14.0 * s, 4.0 * s),
	])
	node.add_child(tail)
	# Eye
	var eye: Polygon2D = Polygon2D.new()
	eye.color = Color(0.05, 0.05, 0.05)
	var epts: PackedVector2Array = PackedVector2Array()
	for i: int in range(6):
		var a: float = TAU * i / 6.0
		epts.append(Vector2(6.0 * s + cos(a) * 1.5 * s, sin(a) * 1.5 * s))
	eye.polygon = epts
	node.add_child(eye)
	# Shimmer stripe
	var shimmer: Polygon2D = Polygon2D.new()
	shimmer.color = Color(0.7, 0.9, 1.0, 0.35)
	shimmer.polygon = PackedVector2Array([
		Vector2(0.0, -1.5 * s), Vector2(5.0 * s, -2.0 * s),
		Vector2(5.5 * s, -0.5 * s), Vector2(0.0, 0.5 * s),
	])
	node.add_child(shimmer)

class_name VisualFx

## Shared procedural visual helpers: ground shadows that "seat" units and
## buildings on the terrain, giving the flat-polygon art a sense of depth.

const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.22)
const SHADOW_Z: int = -1   # below the Body, above the terrain (terrain is z <= -6)

## Shows/hides a building's floating "NameLabel" nameplate. Nameplates appear
## only while selected — a permanently floating name reads as debug UI.
static func set_nameplate_visible(parent: Node2D, nameplate_visible: bool) -> void:
	var label: Label = parent.get_node_or_null("NameLabel") as Label
	if label != null:
		label.visible = nameplate_visible

## Adds a soft elliptical shadow under `parent`, sized `rx` × `ry`, nudged down
## by `offset_y`. All three are SCREEN-space pixels: the shadow is a ground
## decal, so its polygon is authored as the world-space preimage of the wanted
## on-screen ellipse (see IsoProjection) — after the camera projection it reads
## as a horizontal ellipse sitting directly below the upright art's feet.
## Call after `parent` is inside the tree. Idempotent: skips if a shadow exists.
static func add_ground_shadow(parent: Node2D, rx: float, ry: float, offset_y: float = 4.0) -> void:
	if parent.get_node_or_null("GroundShadow") != null:
		return
	var shadow: Polygon2D = Polygon2D.new()
	shadow.name = "GroundShadow"
	shadow.color = SHADOW_COLOR
	shadow.z_index = SHADOW_Z
	shadow.position = IsoProjection.screen_to_world(Vector2(0.0, offset_y))
	shadow.polygon = _projected_ellipse_points(rx, ry, 16)
	# Ground decal: must stay flat (projected), never uprighted.
	shadow.set_meta(IsoBillboard.META_GROUND, true)
	# Keep the shadow flat on the ground even when the body rotates/scales.
	shadow.set_meta("static_shadow", true)
	parent.add_child(shadow)
	parent.move_child(shadow, 0)

static func _projected_ellipse_points(rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps):
		var a: float = TAU * float(i) / float(steps)
		pts.append(IsoProjection.screen_to_world(Vector2(cos(a) * rx, sin(a) * ry)))
	return pts

## Adds a ground-aligned ellipse OUTLINE under `parent` — the genre-classic
## selection/status ring. `rx`/`ry` and `offset_y` are SCREEN-space pixels
## (the ring is a ground decal: points are the world-space preimage of the
## wanted on-screen ellipse, so the camera projection lays it flat on the
## ground plane). Idempotent per `ring_name`: an existing ring is restyled.
static func add_ground_ring(parent: Node2D, ring_name: String, rx: float, ry: float,
		color: Color, width: float, offset_y: float, z: int = 0) -> Line2D:
	var existing: Line2D = parent.get_node_or_null(ring_name) as Line2D
	if existing != null:
		existing.default_color = color
		return existing
	var ring: Line2D = Line2D.new()
	ring.name = ring_name
	ring.closed = true
	ring.width = width
	ring.default_color = color
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	ring.z_index = z
	ring.position = IsoProjection.screen_to_world(Vector2(0.0, offset_y))
	ring.points = _projected_ellipse_points(rx, ry, 28)
	ring.set_meta(IsoBillboard.META_GROUND, true)
	parent.add_child(ring)
	return ring

## Player-colour ownership marker: a thin ground-aligned ellipse OUTLINE under
## the unit's feet, visible ONLY while the unit is selected. The old always-on
## filled disc made every unit look like it stood in a pond and drowned the
## selection state; unselected units now keep just their soft ground shadow.
## `rx` and `offset_y` are SCREEN-space pixels. Idempotent: re-calling
## recolours the existing ring (used when a unit changes owner).
static func add_ground_plinth(parent: Node2D, player_id: int, rx: float, offset_y: float) -> void:
	var color: Color = PlayerColors.get_color(player_id)
	# Always visible but deliberately faint — team readability without the old
	# "every unit stands in a pond" effect; selection brightens it.
	color.a = 0.55
	var existing: Node = parent.get_node_or_null("PlayerColorStripe")
	if existing != null and not (existing is Line2D):
		# Legacy filled plinth or ColorRect stripe from an older save — replace.
		existing.name = "PlayerColorStripeOld"
		existing.queue_free()
	var ring: Line2D = add_ground_ring(parent, "PlayerColorStripe", rx, rx * 0.5,
		color, 1.5, offset_y, SHADOW_Z)
	ring.visible = true

## Owner tint: blends the unit's LARGEST body polygon (torso/tunic on human
## rigs) toward the player colour, so the team reads on the figure itself —
## also while moving, where ground markers get lost in the crowd. Original
## colours are stashed in metadata, so a change of owner (Mercenary Pact,
## sheep conversion) re-tints from the true base.
const OWNER_TINT: float = 0.45

static func apply_owner_tint(unit: Node, player_id: int) -> void:
	var body: Node = unit.get_node_or_null("Body")
	if body == null:
		return
	var best: Polygon2D = null
	var best_area: float = 0.0
	for poly: Polygon2D in _all_polygons(body):
		var a: float = _polygon_area(poly.polygon)
		if a > best_area:
			best_area = a
			best = poly
	if best == null:
		return
	if not best.has_meta(&"owner_tint_base"):
		best.set_meta(&"owner_tint_base", best.color)
	var base: Color = best.get_meta(&"owner_tint_base") as Color
	best.color = base.lerp(PlayerColors.get_color(player_id), OWNER_TINT)

## Owner pennant for units whose body must keep its art untouched (ships,
## siege): a small player-coloured flag on a pole above the figure.
static func add_owner_pennant(unit: Node, player_id: int, top_y: float) -> void:
	var color: Color = PlayerColors.get_color(player_id)
	# Inside the Body: the billboard keeps it upright over the figure —
	# parented to the unit root it would lie flat on the ground plane.
	var holder: Node = unit.get_node_or_null("Body")
	if holder == null:
		holder = unit
	var existing: Node = holder.get_node_or_null("OwnerPennant")
	if existing != null:
		for child: Node in existing.get_children():
			if child is Polygon2D and (child.name as String) == "Flag":
				(child as Polygon2D).color = color
		return
	var pennant: Node2D = Node2D.new()
	pennant.name = "OwnerPennant"
	pennant.position = Vector2(0.0, top_y)
	var pole: Polygon2D = Polygon2D.new()
	pole.name = "Pole"
	pole.color = Color(0.30, 0.24, 0.18)
	pole.polygon = PackedVector2Array([
		Vector2(-0.6, 0.0), Vector2(0.6, 0.0), Vector2(0.6, -10.0), Vector2(-0.6, -10.0)])
	pennant.add_child(pole)
	var flag: Polygon2D = Polygon2D.new()
	flag.name = "Flag"
	flag.color = color
	flag.polygon = PackedVector2Array([
		Vector2(0.6, -10.0), Vector2(9.0, -8.0), Vector2(0.6, -5.5)])
	pennant.add_child(flag)
	holder.add_child(pennant)

static func _all_polygons(node: Node) -> Array[Polygon2D]:
	var out: Array[Polygon2D] = []
	if node is Polygon2D:
		out.append(node as Polygon2D)
	for child: Node in node.get_children():
		out.append_array(_all_polygons(child))
	return out

static func _polygon_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for i: int in range(points.size()):
		var j: int = (i + 1) % points.size()
		area += points[i].x * points[j].y - points[j].x * points[i].y
	return absf(area) * 0.5

## Converts a scene-authored filled SelectionCircle (a flat world-space disc
## that shears into a blob under the projection) into a ground-aligned ellipse
## ring under the feet. Radius and colour are taken from the authored polygon;
## `foot_y` is the SCREEN-space distance from the anchor down to the feet.
## Idempotent (skips once the ring exists).
static func make_ground_selection_ring(indicator: Node2D, foot_y: float) -> void:
	if indicator == null or indicator.get_node_or_null("SelectionCircle") is Line2D:
		return
	var poly: Polygon2D = indicator.get_node_or_null("SelectionCircle") as Polygon2D
	if poly == null:
		return
	var radius: float = 0.0
	for p: Vector2 in poly.polygon:
		radius = maxf(radius, absf(p.x))
	var color: Color = poly.color
	poly.name = "SelectionCircleOld"
	poly.queue_free()
	add_ground_ring(indicator, "SelectionCircle", radius, radius * 0.5, color, 2.2, foot_y)

# Names a human unit's head polygon goes by across the unit scenes. The first
# one found marks the unit as "human" (ships/siege/animals have none).
const _HEAD_NODES: Array = ["Head", "RiderHead"]
# Headgear that should stay ON when adding hair (hats/helmets a woman can wear);
# only loose hair-replacing pieces are nudged. We keep all headgear and just add
# hair behind it, which reads fine at this scale.

## Returns the unit's head Polygon2D (searching the Body subtree), or null if the
## unit has no head — i.e. it isn't a human figure. Used both to decide whether a
## unit can be gendered and to anchor the hair.
static func find_head(unit: Node) -> Polygon2D:
	var body: Node = unit.get_node_or_null("Body")
	if body == null:
		return null
	for n: String in _HEAD_NODES:
		var h: Polygon2D = body.get_node_or_null(n) as Polygon2D
		if h != null:
			return h
	return null

## Adds long hair framing the head so the unit reads as female. Idempotent.
## `unit` must have a Body with a head polygon (check with find_head first).
static func add_female_hair(unit: Node2D) -> void:
	var head: Polygon2D = find_head(unit)
	if head == null:
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null or body.get_node_or_null("FemaleHair") != null:
		return

	# Derive head bounds from its polygon so hair fits any unit's proportions.
	var min_x: float = INF
	var max_x: float = -INF
	var top_y: float = INF
	var bot_y: float = -INF
	for p: Vector2 in head.polygon:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		top_y = minf(top_y, p.y)
		bot_y = maxf(bot_y, p.y)
	var hair_col: Color = Color(0.34, 0.20, 0.09, 1.0)

	# Back hair: a curtain behind the head falling just below the chin, framing
	# both sides. Drawn behind the head (added first, moved to front of list).
	var back: Polygon2D = Polygon2D.new()
	back.name = "FemaleHair"
	back.color = hair_col
	var fall: float = bot_y + 4.0   # how far the hair falls past the head
	back.polygon = PackedVector2Array([
		Vector2(min_x - 1.0, top_y - 1.0),
		Vector2(min_x - 1.5, fall),
		Vector2(min_x + 1.0, fall),
		Vector2(min_x + 1.0, top_y + 1.0),
		Vector2(max_x - 1.0, top_y + 1.0),
		Vector2(max_x - 1.0, fall),
		Vector2(max_x + 1.5, fall),
		Vector2(max_x + 1.0, top_y - 1.0),
	])
	body.add_child(back)
	body.move_child(back, 0)

	# A small fringe across the top of the forehead, drawn above the head.
	var fringe: Polygon2D = Polygon2D.new()
	fringe.name = "FemaleFringe"
	fringe.color = hair_col
	fringe.polygon = PackedVector2Array([
		Vector2(min_x - 1.0, top_y - 1.0),
		Vector2(max_x + 1.0, top_y - 1.0),
		Vector2(max_x + 1.0, top_y + 1.5),
		Vector2(0.0, top_y + 0.5),
		Vector2(min_x - 1.0, top_y + 1.5),
	])
	body.add_child(fringe)

class_name IsoBillboard
extends Object

## Billboard counter-transform for the camera-level isometric projection.
##
## The camera renders screen = Scale(1, Y_SQUASH) x Rotate(WORLD_ROTATION) x world
## (see IsoProjection), which on its own skews every sprite flat onto the
## ground plane. World entities instead stand upright: their visual roots get
## the inverse basis Rotate(-WORLD_ROTATION) x Scale(1, 1/Y_SQUASH), so the
## projection cancels and the authored art renders 1:1 in screen space while
## staying anchored to the entity's cartesian ground position. Ground decals
## (shadows, selection rings, footprints, blood pools) keep the projection so
## they read as flat on the diamond.
##
## The counter-scale is non-uniform, so it must only ever be applied to pure
## visual nodes — never to CharacterBody2D/StaticBody2D roots or any ancestor
## of a CollisionShape2D (it would corrupt the physics shapes).

const UPRIGHT_ROTATION: float = -IsoProjection.WORLD_ROTATION
const UPRIGHT_SCALE: Vector2 = Vector2(1.0, 1.0 / IsoProjection.Y_SQUASH)

## Painter-sort depth band for world entities. Under the 45-degree rotation the
## screen depth of a point grows with world (x + y), so entities are sorted by
## that sum via z_index. Godot's y_sort compares pre-camera world Y — the wrong
## axis once the camera rotates — hence explicit z. The band leaves room below
## for terrain and ground markers (z <= 10) and above for airborne/overlay
## layers (z_index hard limit is 4096).
const DEPTH_Z_BASE: int = 2048
const DEPTH_Z_PER_PX: float = 1.0 / 3.0
const DEPTH_Z_MIN: int = 16
const DEPTH_Z_MAX: int = 4064

## World-space layers that must always render above the entity depth band.
const Z_AIRBORNE: int = 4070      # arrows, siege boulders, ability clouds
const Z_FOG: int = 4090
const Z_WEATHER: int = 4093
const Z_DRAG_SELECT: int = 4094

## Meta flag: a node already carries the upright counter-transform.
const META_UPRIGHT: StringName = &"iso_upright"
## Meta flag: a node is a ground decal and must never be made upright.
const META_GROUND: StringName = &"iso_ground"

static func depth_z(world_pos: Vector2) -> int:
	return clampi(DEPTH_Z_BASE + roundi((world_pos.x + world_pos.y) * DEPTH_Z_PER_PX),
		DEPTH_Z_MIN, DEPTH_Z_MAX)

static func update_depth(entity: Node2D) -> void:
	entity.z_index = depth_z(entity.global_position)

## Re-bases a visual node so its authored transform is interpreted in screen
## space: the node renders exactly as authored (upright, unsquashed) and its
## authored position becomes the equivalent screen offset from the parent's
## anchor. Idempotent. The node itself must not own physics shapes.
static func make_upright(item: CanvasItem) -> void:
	if item == null or item.has_meta(META_UPRIGHT) or item.has_meta(META_GROUND):
		return
	item.set_meta(META_UPRIGHT, true)
	if item is Node2D:
		var n: Node2D = item as Node2D
		n.transform = Transform2D(UPRIGHT_ROTATION, UPRIGHT_SCALE, 0.0,
			IsoProjection.screen_to_world(n.position)) \
			* Transform2D(n.rotation, n.scale, n.skew, Vector2.ZERO)
	elif item is Control:
		var c: Control = item as Control
		c.position = IsoProjection.screen_to_world(c.position)
		c.rotation = UPRIGHT_ROTATION
		c.scale = UPRIGHT_SCALE

## Uprights an entity's named visual children (missing names are skipped) and
## seats the entity into the depth band. Ground decals must not be listed.
static func setup_entity(root: Node2D, upright_children: Array) -> void:
	for child_name: Variant in upright_children:
		var child: CanvasItem = root.get_node_or_null(NodePath(child_name as String)) as CanvasItem
		if child != null:
			make_upright(child)
	update_depth(root)

## Uprights the drawable children of a procedurally-drawn node (resource
## nodes, carcasses): direct Polygon2D/Line2D parts and plain Node2D part
## containers. Children at z_index < 0 are ground decals (shadows, blood
## pools) and stay projected flat, as does anything tagged META_GROUND.
## Safe to call again after a redraw (e.g. tree -> stump).
static func setup_drawn_node(root: Node2D) -> void:
	for child: Node in root.get_children():
		if not (child is CanvasItem):
			continue
		var item: CanvasItem = child as CanvasItem
		if item.z_index < 0:
			continue
		if item is Polygon2D or item is Line2D or item.get_class() == "Node2D":
			make_upright(item)
	update_depth(root)

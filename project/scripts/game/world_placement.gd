class_name WorldPlacement extends RefCounted

## Building placement for the human player: the ghost/footprint preview, grid
## snapping, terrain/overlap validation, wall drag runs, and the debounced
## async navmesh rebake that follows any building change.

const BUILDING_SCENES: Dictionary = {
	"house":         "res://scenes/buildings/house.tscn",
	"barracks":      "res://scenes/buildings/barracks.tscn",
	"archery_range": "res://scenes/buildings/archery_range.tscn",
	"blacksmith":    "res://scenes/buildings/blacksmith.tscn",
	"stable":        "res://scenes/buildings/stable.tscn",
	"lumber_camp":   "res://scenes/buildings/lumber_camp.tscn",
	"mining_camp":   "res://scenes/buildings/mining_camp.tscn",
	"farm":          "res://scenes/buildings/farm.tscn",
	"wall_segment":  "res://scenes/buildings/wall_segment.tscn",
	"gate":          "res://scenes/buildings/gate.tscn",
	"dock":          "res://scenes/buildings/dock.tscn",
	"fish_trap":     "res://scenes/buildings/fish_trap.tscn",
	"university":    "res://scenes/buildings/university.tscn",
	"market":        "res://scenes/buildings/market.tscn",
	"temple":          "res://scenes/buildings/temple.tscn",
	"siege_workshop":  "res://scenes/buildings/siege_workshop.tscn",
	"town_center":     "res://scenes/buildings/town_center.tscn",
	"wonder":          "res://scenes/buildings/wonder.tscn",
	"watch_tower":     "res://scenes/buildings/watch_tower.tscn",
}

## Single cost source shared by the player and the AI: loaded lazily from each
## building's BuildingResource .tres, so placement can never charge a price
## different from the design data. The old hand-written table silently missed
## university/market/temple — the player built them for FREE while the HUD
## showed a cost and the AI paid it.
static var _costs_cache: Dictionary = {}

static func building_costs(building_id: String) -> Dictionary:
	if _costs_cache.is_empty():
		for id: String in BUILDING_SCENES.keys():
			var res_path: String = "res://resources/buildings/%s.tres" % id
			if not ResourceLoader.exists(res_path):
				continue
			var res: BuildingResource = load(res_path) as BuildingResource
			if res != null:
				_costs_cache[id] = res.get_cost_dict()
		# The AI's rebuilt TC shares the buildable town center's price.
		_costs_cache["town_center_ai"] = _costs_cache.get("town_center", {})
	return _costs_cache.get(building_id, {}) as Dictionary

# Buildings that must be placed adjacent to water (at least one edge in ocean terrain).
const COASTAL_BUILDINGS: Array = ["dock"]

# Buildings that must be placed fully in ocean (all footprint probes in ocean terrain).
const OCEAN_BUILDINGS: Array = ["fish_trap"]

const PLACEMENT_OK_FILL: Color = Color(0.35, 1.0, 0.45, 0.22)
const PLACEMENT_OK_LINE: Color = Color(0.45, 1.0, 0.55, 0.9)
const PLACEMENT_BAD_FILL: Color = Color(1.0, 0.25, 0.2, 0.28)
const PLACEMENT_BAD_LINE: Color = Color(1.0, 0.35, 0.3, 0.9)
const PLACEMENT_GRID_LINE: Color = Color(1.0, 1.0, 1.0, 0.18)

const WALL_STEP: float = 16.0
const NAV_REBAKE_DELAY: float = 1.0

var _world  # GameWorld — untyped so dynamic access works

var _placing_building: bool = false
var _placing_id: String = ""
var _ghost: Node2D = null
var _ghost_rotation: float = 0.0
var _ghost_shape_cached: RectangleShape2D = null
var _ghost_params_cached: PhysicsShapeQueryParameters2D = null
var _ghost_footprint: Node2D = null

# Wall drag placement state
var _wall_drag_active: bool = false
var _wall_drag_start: Vector2 = Vector2.ZERO
var _wall_ghosts: Array[Node2D] = []
var _wall_cost_layer: CanvasLayer = null
var _wall_cost_label: Label = null

var _nav_rebake_timer: float = 0.0
var _nav_rebake_pending: bool = false
var _nav_bake_failed: Dictionary = {}            # region name → empty bake already warned

func setup(world) -> void:
	_world = world

## Per-frame nav-rebake countdown; called from GameWorld._process.
func tick_nav_rebake(delta: float) -> void:
	if _nav_rebake_pending:
		_nav_rebake_timer -= delta
		if _nav_rebake_timer <= 0.0:
			_nav_rebake_pending = false
			_do_nav_rebake()

## Ghost/wall preview refresh; called from GameWorld._process AFTER the camera
## handlers so the snap uses the post-pan mouse world position.
func update_previews() -> void:
	if _placing_building and is_instance_valid(_ghost):
		var mouse_pos: Vector2 = _snap_placement(_world.get_global_mouse_position())
		_ghost.visible = not _wall_drag_active
		_ghost.global_position = mouse_pos
		_ghost.rotation = _ghost_rotation
		var terrain_ok: bool = not TerrainManager.is_ocean(mouse_pos) and not _placement_overlaps(mouse_pos)
		if _placing_id in OCEAN_BUILDINGS:
			terrain_ok = TerrainManager.is_ocean(mouse_pos) and not _placement_overlaps(mouse_pos)
		_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5) if terrain_ok else Color(1.0, 0.2, 0.2, 0.5)
		if is_instance_valid(_ghost_footprint):
			_ghost_footprint.visible = _ghost.visible
			_ghost_footprint.global_position = mouse_pos
			_ghost_footprint.rotation = _ghost_rotation
			_tint_placement_footprint(terrain_ok)
	if _wall_drag_active:
		_update_wall_drag_preview(_snap_wall(_world.get_global_mouse_position()))

## Placement-mode keys (R rotate, ESC cancel); routed from GameWorld._unhandled_input.
## Returns true when the event is consumed (any pressed key while placing).
func handle_placement_key(ke: InputEventKey) -> bool:
	if not (_placing_building and ke.pressed and not ke.echo):
		return false
	if ke.physical_keycode == KEY_R:
		_ghost_rotation += PI / 2.0
		_world.get_viewport().set_input_as_handled()
	elif ke.physical_keycode == KEY_ESCAPE:
		_cancel_placement()
		_world.get_viewport().set_input_as_handled()
	return true

## Placement-mode mouse clicks (confirm/wall-drag/cancel); routed from
## GameWorld._unhandled_input. Returns true when placement mode is active.
func handle_placement_mouse(mb: InputEventMouseButton) -> bool:
	if not _placing_building:
		return false
	var is_wall_drag: bool = _placing_id == "wall_segment"
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if is_wall_drag and not _wall_drag_active:
			_wall_drag_start = _snap_wall(_world.get_global_mouse_position())
			_wall_drag_active = true
		elif is_wall_drag and _wall_drag_active:
			_confirm_wall_drag(_world.get_global_mouse_position())
		else:
			_confirm_placement(_world.get_global_mouse_position())
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_placement()
	return true

func _start_placement(building_id: String) -> void:
	if not BUILDING_SCENES.has(building_id):
		return
	if not ResourceManager.can_afford(0, WorldPlacement.building_costs(building_id)):
		return

	_cancel_placement()
	_placing_building = true
	_placing_id = building_id
	_ghost_rotation = 0.0

	var scene: PackedScene = load(BUILDING_SCENES[building_id]) as PackedScene
	_ghost = scene.instantiate() as Node2D
	_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5)
	for child: Node in _ghost.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			(child as CollisionShape2D).disabled = true
	_world.buildings_layer.add_child(_ghost)

	_ghost_shape_cached = _get_ghost_shape()
	_ghost_params_cached = PhysicsShapeQueryParameters2D.new()
	_ghost_params_cached.shape = _ghost_shape_cached
	_ghost_params_cached.collision_mask = 1

	# Sibling of the ghost so its validity colours are not multiplied by the
	# ghost's red/white modulate. World-space geometry: the camera projection
	# renders it as the footprint ground diamond plus the 16 px snap lattice.
	_ghost_footprint = _make_placement_footprint(
		_ghost_shape_cached.size if _ghost_shape_cached != null
		else Vector2(PlacementGrid.CELL_SIZE, PlacementGrid.CELL_SIZE))
	_world.buildings_layer.add_child(_ghost_footprint)

# Ground footprint indicator for the placement ghost: a filled rect with an
# outline and internal grid lines every placement cell, all in world space so
# they project onto the terrain as 2:1 diamonds.
func _make_placement_footprint(size: Vector2) -> Node2D:
	var root: Node2D = Node2D.new()
	root.name = "PlacementFootprint"
	root.z_index = 5
	var half: Vector2 = size * 0.5
	var fill: Polygon2D = Polygon2D.new()
	fill.name = "Fill"
	fill.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	fill.color = PLACEMENT_OK_FILL
	root.add_child(fill)
	var cell: float = PlacementGrid.CELL_SIZE
	var gx: float = -half.x + cell
	while gx < half.x - 0.5:
		root.add_child(_grid_line(Vector2(gx, -half.y), Vector2(gx, half.y)))
		gx += cell
	var gy: float = -half.y + cell
	while gy < half.y - 0.5:
		root.add_child(_grid_line(Vector2(-half.x, gy), Vector2(half.x, gy)))
		gy += cell
	var outline: Line2D = Line2D.new()
	outline.name = "Outline"
	outline.width = 1.5
	outline.default_color = PLACEMENT_OK_LINE
	outline.closed = true
	outline.points = fill.polygon
	root.add_child(outline)
	return root

func _grid_line(from: Vector2, to: Vector2) -> Line2D:
	var line: Line2D = Line2D.new()
	line.width = 1.0
	line.default_color = PLACEMENT_GRID_LINE
	line.points = PackedVector2Array([from, to])
	return line

func _tint_placement_footprint(ok: bool) -> void:
	var fill: Polygon2D = _ghost_footprint.get_node_or_null("Fill") as Polygon2D
	if fill != null:
		fill.color = PLACEMENT_OK_FILL if ok else PLACEMENT_BAD_FILL
	var outline: Line2D = _ghost_footprint.get_node_or_null("Outline") as Line2D
	if outline != null:
		outline.default_color = PLACEMENT_OK_LINE if ok else PLACEMENT_BAD_LINE

# Snap a placement position to the building grid, sized to the ghost footprint
# so edges stay flush with the lattice. Hold Alt for free (continuous) placement.
func _snap_placement(world_pos: Vector2) -> Vector2:
	if Input.is_key_pressed(KEY_ALT):
		return world_pos
	var size: Vector2 = _ghost_shape_cached.size if _ghost_shape_cached != null else Vector2(PlacementGrid.CELL_SIZE, PlacementGrid.CELL_SIZE)
	return PlacementGrid.snap_footprint(world_pos, size)

# Snap a wall endpoint to a cell centre so wall runs and gates share one grid.
func _snap_wall(world_pos: Vector2) -> Vector2:
	if Input.is_key_pressed(KEY_ALT):
		return world_pos
	return PlacementGrid.snap(world_pos)

func _placement_overlaps(world_pos: Vector2) -> bool:
	if _ghost_params_cached == null or _ghost_shape_cached == null:
		return false
	var space: PhysicsDirectSpaceState2D = _world.get_world_2d().direct_space_state
	_ghost_params_cached.transform = Transform2D(_ghost_rotation, world_pos)
	var results: Array[Dictionary] = space.intersect_shape(_ghost_params_cached, 1)
	if results.size() > 0:
		return true
	if _placing_id in COASTAL_BUILDINGS and not _is_coastal(world_pos, _ghost_shape_cached):
		return true
	if _placing_id in OCEAN_BUILDINGS and not _is_fully_ocean(world_pos, _ghost_shape_cached):
		return true
	return false

# Returns true if the dock footprint touches both ocean and land —
# at least one cardinal probe is ocean AND at least one is non-ocean.
func _is_coastal(world_pos: Vector2, shape: RectangleShape2D) -> bool:
	var half: Vector2 = shape.size * 0.5 + Vector2(8.0, 8.0)
	var probes: Array[Vector2] = [
		world_pos + Vector2(0.0,  half.y),
		world_pos + Vector2(0.0, -half.y),
		world_pos + Vector2( half.x, 0.0),
		world_pos + Vector2(-half.x, 0.0),
	]
	var has_ocean: bool = false
	var has_land:  bool = false
	for p: Vector2 in probes:
		if TerrainManager.is_ocean(p):
			has_ocean = true
		else:
			has_land = true
	return has_ocean and has_land

func _is_fully_ocean(world_pos: Vector2, shape: RectangleShape2D) -> bool:
	var half: Vector2 = shape.size * 0.5
	var probes: Array[Vector2] = [
		world_pos,
		world_pos + Vector2(half.x,  half.y),
		world_pos + Vector2(-half.x, half.y),
		world_pos + Vector2(half.x, -half.y),
		world_pos + Vector2(-half.x, -half.y),
	]
	for p: Vector2 in probes:
		if not TerrainManager.is_ocean(p):
			return false
	return true

func _get_ghost_shape() -> RectangleShape2D:
	for child: Node in _ghost.get_children():
		if child is CollisionShape2D:
			var cs: CollisionShape2D = child as CollisionShape2D
			if cs.shape is RectangleShape2D:
				return cs.shape as RectangleShape2D
	return null

func _confirm_placement(raw_world_pos: Vector2) -> void:
	var world_pos: Vector2 = _snap_placement(raw_world_pos)
	if _placement_overlaps(world_pos):
		return
	if not ResourceManager.can_afford(0, WorldPlacement.building_costs(_placing_id)):
		_cancel_placement()
		return

	CommandBus.submit(PlaceBuildingCommand.make(NetworkSession.local_player_id, _placing_id,
		[world_pos] as Array[Vector2], _ghost_rotation,
		EntityRegistry.ids_of(_world.live_selection())))

	if Input.is_key_pressed(KEY_SHIFT):
		# Keep placement mode active for the same building type.
		var keep_id: String = _placing_id
		_cancel_placement()
		_start_placement(keep_id)
	else:
		_cancel_placement()

func _cancel_placement() -> void:
	_placing_building = false
	_placing_id = ""
	_ghost_rotation = 0.0
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if is_instance_valid(_ghost_footprint):
		_ghost_footprint.queue_free()
	_ghost_footprint = null
	_ghost_shape_cached = null
	_ghost_params_cached = null
	_wall_drag_active = false
	_wall_drag_start = Vector2.ZERO
	for g: Node2D in _wall_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_wall_ghosts.clear()
	if is_instance_valid(_wall_cost_label):
		_wall_cost_label.queue_free()
	_wall_cost_label = null
	if is_instance_valid(_wall_cost_layer):
		_wall_cost_layer.queue_free()
	_wall_cost_layer = null

func _wall_segment_positions(start: Vector2, end: Vector2, step: float) -> Array[Vector2]:
	return PlacementGrid.segment_positions(start, end, step)

func _update_wall_drag_preview(end_pos: Vector2) -> void:
	for g: Node2D in _wall_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_wall_ghosts.clear()

	var positions: Array[Vector2] = _wall_segment_positions(_wall_drag_start, end_pos, WALL_STEP)

	# World-space cell squares: the camera projection renders each one as a
	# 16 px ground diamond of the snap lattice.
	var cell_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-8.0, -8.0), Vector2(8.0, -8.0), Vector2(8.0, 8.0), Vector2(-8.0, 8.0),
	])
	for pos: Vector2 in positions:
		var ghost: Node2D = Node2D.new()
		ghost.global_position = pos
		var cell: Polygon2D = Polygon2D.new()
		cell.polygon = cell_pts
		cell.color = Color(0.4, 0.7, 1.0, 0.4)
		ghost.add_child(cell)
		var rim: Line2D = Line2D.new()
		rim.width = 1.0
		rim.closed = true
		rim.default_color = Color(0.6, 0.85, 1.0, 0.8)
		rim.points = cell_pts
		ghost.add_child(rim)
		ghost.z_index = 5
		_world.buildings_layer.add_child(ghost)
		_wall_ghosts.append(ghost)

	var cost_per: int = WorldPlacement.building_costs("wall_segment").get("stone", 0) as int
	var total_cost: int = positions.size() * cost_per

	if not is_instance_valid(_wall_cost_layer):
		_wall_cost_layer = CanvasLayer.new()
		_wall_cost_layer.layer = 10
		_world.add_child(_wall_cost_layer)
		_wall_cost_label = Label.new()
		_wall_cost_label.add_theme_font_size_override("font_size", 14)
		_wall_cost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 1.0))
		_wall_cost_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		_wall_cost_label.add_theme_constant_override("shadow_offset_x", 1)
		_wall_cost_label.add_theme_constant_override("shadow_offset_y", 1)
		_wall_cost_layer.add_child(_wall_cost_label)

	_wall_cost_label.text = "Stone: %d" % total_cost
	var vp_mouse: Vector2 = _world.get_viewport().get_mouse_position()
	_wall_cost_label.position = vp_mouse + Vector2(16.0, -24.0)

func _confirm_wall_drag(raw_end_pos: Vector2) -> void:
	var end_pos: Vector2 = _snap_wall(raw_end_pos)
	var positions: Array[Vector2] = _wall_segment_positions(_wall_drag_start, end_pos, WALL_STEP)
	if positions.is_empty():
		_cancel_placement()
		return

	# One command for the whole run; it pays per segment and stops when the
	# stockpile runs out, exactly like the old inline loop.
	CommandBus.submit(PlaceBuildingCommand.make(NetworkSession.local_player_id, "wall_segment",
		positions, 0.0, EntityRegistry.ids_of(_world.live_selection())))

	var keep_id: String = _placing_id
	_cancel_placement()
	if Input.is_key_pressed(KEY_SHIFT):
		_start_placement(keep_id)

func _request_nav_rebake() -> void:
	_nav_rebake_pending = true
	_nav_rebake_timer = NAV_REBAKE_DELAY

# Walkable surface handed to the rebake: on Islands maps only the land polygons
# NavMeshBuilder carved, otherwise the whole board. Baking the full rect on an
# Islands map would erase the carving and hand land units a route across open sea.
func _traversable_outlines() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for lp: Variant in TerrainManager.get_land_polys():
		out.append(lp as PackedVector2Array)
	if out.is_empty():
		out.append(PackedVector2Array([
			Vector2(-3000.0, -3000.0), Vector2(3000.0, -3000.0),
			Vector2(3000.0,  3000.0), Vector2(-3000.0,  3000.0),
		]))
	return out

## The amphibious mesh spans land and water alike, so a building rebake must not
## carve it back to the islands — only the buildings standing on it matter.
func _amphibious_outlines() -> Array[PackedVector2Array]:
	return [PackedVector2Array([
		Vector2(-3000.0, -3000.0), Vector2(3000.0, -3000.0),
		Vector2(3000.0,  3000.0), Vector2(-3000.0,  3000.0),
	])]

func _do_nav_rebake() -> void:
	# Impassable terrain zones must survive every rebake or the carve from map
	# generation would vanish with the first building placed.
	_rebake_region(_world._nav_region, _traversable_outlines(),
		NavMeshBuilder.zone_obstructions(true))
	_rebake_region(
		_world.get_node_or_null("MalpaisNavigationRegion2D") as NavigationRegion2D,
		_traversable_outlines(), NavMeshBuilder.zone_obstructions(false))
	# Keep the amphibious surface in step: without this a Tidecaller would path
	# straight through buildings that the land mesh already routes around.
	_rebake_region(
		_world.get_node_or_null("AmphibiousNavigationRegion2D") as NavigationRegion2D,
		_amphibious_outlines(), NavMeshBuilder.zone_obstructions(true))

func _rebake_region(region: NavigationRegion2D, traversable: Array[PackedVector2Array],
		extra_obstructions: Array[PackedVector2Array] = [], attempt: int = 0) -> void:
	if not is_instance_valid(region):
		return
	var current: NavigationPolygon = region.navigation_polygon
	if current == null:
		return
	# Bake into a FRESH polygon (copying agent settings, widened by the attempt's
	# NavMeshBuilder nudge) rather than the live one. If the convex partition
	# still fails the result is empty; _on_nav_bake_done then walks the rest of
	# the nudge ladder and, failing that, keeps the previous mesh instead of
	# leaving units with no walkable navmesh.
	var nav_poly: NavigationPolygon = NavMeshBuilder.bake_target(current, attempt)
	var source: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	for outline: PackedVector2Array in traversable:
		source.add_traversable_outline(outline)
	for zone: PackedVector2Array in extra_obstructions:
		source.add_obstruction_outline(zone)
	for b: Node in _world.buildings_layer.get_children():
		if not is_instance_valid(b) or not b.has_method("get_nav_obstacle_polygon"):
			continue
		var sv: Variant = b.get("state")
		if sv != null and (sv as int) == BuildingBase.BuildingState.DESTROYED:
			continue
		var bpoly: PackedVector2Array = b.call("get_nav_obstacle_polygon") as PackedVector2Array
		if bpoly.size() >= 3:
			source.add_obstruction_outline(bpoly)
	if is_instance_valid(_world.drop_off) and _world.drop_off.has_method("get_nav_obstacle_polygon"):
		var dpoly: PackedVector2Array = _world.drop_off.call("get_nav_obstacle_polygon") as PackedVector2Array
		if dpoly.size() >= 3:
			source.add_obstruction_outline(dpoly)
	for rn: Node in _world.get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(rn) or not rn.has_method("get_nav_obstacle_polygon"):
			continue
		var rpoly: PackedVector2Array = rn.call("get_nav_obstacle_polygon") as PackedVector2Array
		if rpoly.size() >= 3:
			source.add_obstruction_outline(rpoly)
	NavigationServer2D.bake_from_source_geometry_data_async(
		nav_poly, source, Callable(self, "_on_nav_bake_done").bind(
			region, nav_poly, traversable, extra_obstructions, attempt))

func _on_nav_bake_done(region: NavigationRegion2D, baked: NavigationPolygon,
		traversable: Array[PackedVector2Array],
		extra_obstructions: Array[PackedVector2Array], attempt: int) -> void:
	if not is_instance_valid(_world) or not is_instance_valid(region) or baked == null:
		return
	# Only swap in the freshly baked mesh if the partition succeeded (non-empty).
	# An empty result means Godot's convex partition choked on a degenerate
	# contact between obstruction outlines; the next nudge of the ladder offsets
	# them differently and normally clears it (see NavMeshBuilder.RADIUS_NUDGE).
	if baked.get_polygon_count() > 0:
		region.navigation_polygon = baked
		_nav_bake_failed.erase(region.name)
		return
	if attempt + 1 < NavMeshBuilder.nudge_attempts():
		_rebake_region(region, traversable, extra_obstructions, attempt + 1)
		return
	# Ladder exhausted: keep the existing navmesh so units never lose their
	# walkable surface, and warn once per region — re-requesting the bake here
	# would spin on identical geometry forever. The next building change
	# rebakes anyway.
	if not _nav_bake_failed.has(region.name):
		push_warning("Nav rebake produced an empty mesh for %s after %d attempts; keeping the previous polygon."
			% [region.name, NavMeshBuilder.nudge_attempts()])
		_nav_bake_failed[region.name] = true

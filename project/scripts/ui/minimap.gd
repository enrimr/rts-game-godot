extends Control

class_name MinimapRenderer

var _world_min: Vector2 = Vector2(-1800.0, -1800.0)
var _world_size: float = 3600.0

const COLOR_BG:             Color = Color(0.08, 0.18, 0.08, 1.0)
const COLOR_BORDER:         Color = Color(0.0,  0.0,  0.0,  1.0)
const COLOR_RESOURCE_WOOD:  Color = Color(0.15, 0.65, 0.15, 1.0)
const COLOR_RESOURCE_GOLD:  Color = Color(0.95, 0.8,  0.1,  1.0)
const COLOR_RESOURCE_STONE: Color = Color(0.75, 0.75, 0.75, 1.0)
const COLOR_ANIMAL:         Color = Color(0.85, 0.65, 0.25, 1.0)
const COLOR_CAMERA_RECT:    Color = Color(1.0,  1.0,  1.0,  0.75)
const COLOR_GRID:           Color = Color(1.0,  1.0,  1.0,  0.06)

const FLASH_DURATION:   float = 1.5
const FLASH_RADIUS_MAX: float = 14.0

# Entities (fog, resources, buildings, units) redraw on this decoupled tick
# instead of every frame — a minimap dot moving at 5 Hz is imperceptible, but
# iterating every unit/resource per frame is not.
const CONTENT_REDRAW_INTERVAL: float = 0.2

# Each entry: {world_pos: Vector2, timer: float, color: Color}
var _flashes: Array[Dictionary] = []

var world_node: Node2D = null
var camera_node: Camera2D = null
var fog: FogOfWar = null

# Resource nodes appear on the minimap only when an own unit is within this
# fraction of its normal line-of-sight radius. Keeps partial forests hidden
# until the unit is close enough to actually "see" the individual trees.
const MINIMAP_RESOURCE_SIGHT_FRACTION: float = 0.30

# Cached per content tick: own units with (position, sight_radius_px)
var _own_unit_sights: Array[Dictionary] = []

# Enemy buildings the player has seen at least once, drawn dimmed at their
# last known position while fogged (AoE2-style). Keyed by instance id;
# entries are forgotten only when the spot is re-observed and the building
# is gone. Value: {pos: Vector2, pid: int}
var _known_enemy_buildings: Dictionary = {}

# Content (entities) draws at CONTENT_REDRAW_INTERVAL; the overlay (camera
# rect + flashes) draws only while something on it is actually changing.
var _content: Control = null
var _overlay: Control = null
var _content_timer: float = CONTENT_REDRAW_INTERVAL
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: Vector2 = Vector2.INF
var _last_vp_size: Vector2 = Vector2.INF

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_content = _make_layer("ContentLayer")
	_content.draw.connect(_draw_content)
	_overlay = _make_layer("OverlayLayer")
	_overlay.clip_contents = true
	_overlay.draw.connect(_draw_overlay)
	EventBus.player_entity_under_attack.connect(_on_player_entity_under_attack)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.minimap_move_order.connect(_on_minimap_move_order)
	EventBus.hero_low_hp.connect(_on_hero_low_hp)

func _make_layer(layer_name: String) -> Control:
	var layer: Control = Control.new()
	layer.name = layer_name
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer

func _process(delta: float) -> void:
	var overlay_dirty: bool = not _flashes.is_empty()
	var i: int = _flashes.size() - 1
	while i >= 0:
		_flashes[i]["timer"] -= delta
		if _flashes[i]["timer"] <= 0.0:
			_flashes.remove_at(i)
		i -= 1
	if _camera_view_changed():
		overlay_dirty = true
	if overlay_dirty:
		_overlay.queue_redraw()
	_content_timer += delta
	if _content_timer >= CONTENT_REDRAW_INTERVAL:
		_content_timer = 0.0
		_cache_own_unit_sights()
		_update_enemy_building_memory()
		_content.queue_redraw()

# True when the camera rect drawn on the overlay would differ from the last
# drawn one (camera moved/zoomed or the viewport was resized).
func _camera_view_changed() -> bool:
	if camera_node == null:
		return false
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if camera_node.global_position == _last_cam_pos \
			and camera_node.zoom == _last_cam_zoom and vp == _last_vp_size:
		return false
	_last_cam_pos = camera_node.global_position
	_last_cam_zoom = camera_node.zoom
	_last_vp_size = vp
	return true

func _cache_own_unit_sights() -> void:
	_own_unit_sights.clear()
	if world_node == null:
		return
	var ul: Node = world_node.get_node_or_null("UnitsLayer")
	if ul == null:
		return
	for u: Node in ul.get_children():
		if not is_instance_valid(u):
			continue
		var upid: Variant = u.get("player_id")
		if upid == null or (upid as int) != 0:
			continue
		var udata: Variant = u.get("unit_data")
		var los_px: float = 5.0 * 64.0
		if udata is UnitResource:
			los_px = (udata as UnitResource).line_of_sight * 64.0
		_own_unit_sights.append({"pos": (u as Node2D).global_position, "r": los_px * MINIMAP_RESOURCE_SIGHT_FRACTION})

func add_flash(world_pos: Vector2, color: Color) -> void:
	_flashes.append({"world_pos": world_pos, "timer": FLASH_DURATION, "color": color})

func _on_player_entity_under_attack(world_pos: Vector2, _attacker: Node) -> void:
	add_flash(world_pos, Color(1.0, 0.15, 0.15))

func _on_building_destroyed(building: Node, owner_id: int) -> void:
	if owner_id != 0:
		return
	add_flash((building as Node2D).global_position, Color(1.0, 0.50, 0.10))

func _on_minimap_move_order(world_pos: Vector2) -> void:
	add_flash(world_pos, Color(0.25, 1.0, 0.35))

func _on_hero_low_hp(player_id: int) -> void:
	if player_id != 0 or world_node == null:
		return
	var units_layer: Node = world_node.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return
	for unit: Node in units_layer.get_children():
		if unit is HeroUnit and (unit as HeroUnit).player_id == 0:
			add_flash((unit as Node2D).global_position, Color(1.0, 0.90, 0.10))
			return

func _refresh_world_bounds() -> void:
	var mh: float = TerrainManager.minimap_map_half
	_world_min = Vector2(-mh, -mh)
	_world_size = mh * 2.0

# Terrain, fog, resources, buildings and units — the expensive iteration,
# redrawn on the decoupled CONTENT_REDRAW_INTERVAL tick.
func _draw_content() -> void:
	var ms: Vector2 = size
	_refresh_world_bounds()

	if TerrainManager.minimap_texture != null:
		_content.draw_texture_rect(TerrainManager.minimap_texture, Rect2(Vector2.ZERO, ms), false)
	else:
		_content.draw_rect(Rect2(Vector2.ZERO, ms), COLOR_BG)

	# Fog of war overlay — drawn over terrain, under units/buildings
	if fog != null:
		var cell_w: float = ms.x / float(FogOfWar.GRID_W)
		var cell_h: float = ms.y / float(FogOfWar.GRID_H)
		for cy: int in range(FogOfWar.GRID_H):
			for cx: int in range(FogOfWar.GRID_W):
				var state: int = fog._cells[cy * FogOfWar.GRID_W + cx]
				if state == FogOfWar.STATE_VISIBLE:
					continue
				var fog_col: Color = Color(0.0, 0.0, 0.0, 1.0) if state == FogOfWar.STATE_UNEXPLORED else Color(0.0, 0.0, 0.0, 0.55)
				_content.draw_rect(Rect2(Vector2(cx * cell_w, cy * cell_h), Vector2(cell_w + 1.0, cell_h + 1.0)), fog_col)

	# Subtle grid lines every 25% of the map
	for i: int in range(1, 4):
		var t: float = float(i) * 0.25
		_content.draw_line(Vector2(ms.x * t, 0.0), Vector2(ms.x * t, ms.y), COLOR_GRID, 1.0)
		_content.draw_line(Vector2(0.0, ms.y * t), Vector2(ms.x, ms.y * t), COLOR_GRID, 1.0)

	if world_node == null:
		return

	# Resources: show when an own unit is within sight range of the node.
	# Remembered (explored but not in sight) nodes show dimmed.
	for rn_node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(rn_node) or not (rn_node is ResourceNode):
			continue
		var rn: ResourceNode = rn_node as ResourceNode
		if fog != null and fog.get_cell_state(rn.global_position) == FogOfWar.STATE_UNEXPLORED:
			continue
		var in_sight: bool = false
		var rpos: Vector2 = rn.global_position
		for entry: Dictionary in _own_unit_sights:
			if (entry["pos"] as Vector2).distance_to(rpos) <= (entry["r"] as float):
				in_sight = true
				break
		var col: Color = _resource_color(rn.resource_type)
		if not in_sight:
			col.a = 0.4
		var mp: Vector2 = _to_mm(rpos, ms)
		_content.draw_rect(Rect2(mp - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), col)

	# Buildings layer
	var buildings_layer: Node = world_node.get_node_or_null("BuildingsLayer")
	if buildings_layer != null:
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building):
				continue
			var pid: Variant = building.get("player_id")
			var is_own: bool = pid != null and (pid as int) == 0
			if not _fog_allows_see((building as Node2D).global_position, is_own):
				continue
			var mp: Vector2 = _to_mm((building as Node2D).global_position, ms)
			var col: Color = PlayerColors.get_color(pid as int) if pid != null else Color(0.7, 0.5, 0.2)
			_content.draw_rect(Rect2(mp - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), col)

	# Last-known-position ghosts of enemy buildings under fog (memory is
	# maintained by _update_enemy_building_memory on the content tick)
	if fog != null:
		for entry: Dictionary in _known_enemy_buildings.values():
			var epos: Vector2 = entry["pos"] as Vector2
			if fog.get_cell_state(epos) != FogOfWar.STATE_EXPLORED:
				continue  # visible spots draw the live dot instead
			var gcol: Color = PlayerColors.get_color(entry["pid"] as int)
			gcol.a = 0.55
			var gp: Vector2 = _to_mm(epos, ms)
			_content.draw_rect(Rect2(gp - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), gcol)

	# Town Center (DropOffNode in world root)
	var drop_off: Node = world_node.get_node_or_null("DropOffNode")
	if drop_off != null and _fog_allows_see((drop_off as Node2D).global_position, true):
		var mp: Vector2 = _to_mm((drop_off as Node2D).global_position, ms)
		var pid: Variant = drop_off.get("player_id")
		var col: Color = PlayerColors.get_color(pid as int) if pid != null else Color(0.7, 0.5, 0.2)
		_content.draw_rect(Rect2(mp - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), col)

	# Units
	var units_layer: Node = world_node.get_node_or_null("UnitsLayer")
	if units_layer != null:
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			var pid: Variant = unit.get("player_id")
			var is_own: bool = pid != null and (pid as int) == 0
			if not _fog_allows_see((unit as Node2D).global_position, is_own):
				continue
			var mp: Vector2 = _to_mm((unit as Node2D).global_position, ms)
			if unit is Animal:
				_content.draw_circle(mp, 2.5, COLOR_ANIMAL)
				continue
			var col: Color = PlayerColors.get_color(pid as int) if pid != null else Color(0.8, 0.8, 0.8)
			_content.draw_circle(mp, 3.0, col)

# Runs on the content tick: records every enemy building currently in a
# VISIBLE fog cell at its last known position, then forgets entries whose
# spot has been re-observed without the building.
func _update_enemy_building_memory() -> void:
	if world_node == null or fog == null:
		return
	var buildings_layer: Node = world_node.get_node_or_null("BuildingsLayer")
	if buildings_layer != null:
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building):
				continue
			var pid: Variant = building.get("player_id")
			if pid == null or (pid as int) == 0:
				continue
			var bpos: Vector2 = (building as Node2D).global_position
			if fog.get_cell_state(bpos) == FogOfWar.STATE_VISIBLE:
				_known_enemy_buildings[building.get_instance_id()] = {"pos": bpos, "pid": pid as int}
	_prune_known_enemy_buildings()

# Forget a remembered enemy building only once its spot is re-observed
# (cell VISIBLE) and the building no longer exists there — while fogged the
# ghost persists even if the building was destroyed, exactly like AoE2.
func _prune_known_enemy_buildings() -> void:
	if fog == null:
		return
	for id: int in _known_enemy_buildings.keys():
		var entry: Dictionary = _known_enemy_buildings[id]
		if fog.get_cell_state(entry["pos"] as Vector2) != FogOfWar.STATE_VISIBLE:
			continue
		var obj: Object = instance_from_id(id)
		if obj == null or not is_instance_valid(obj) or not (obj as Node).is_inside_tree():
			_known_enemy_buildings.erase(id)

# Camera rect, flashes and border — cheap, redrawn only while changing.
func _draw_overlay() -> void:
	var ms: Vector2 = size
	_refresh_world_bounds()

	# Camera viewport indicator — the world region on screen is a rotated
	# rectangle under the isometric camera (see IsoProjection), so project the
	# four screen corners back to world and draw the resulting quad. The
	# overlay layer clips, so it never bleeds outside the widget at map edges.
	if camera_node != null:
		var half: Vector2 = get_viewport().get_visible_rect().size * 0.5
		var cam_pos: Vector2 = camera_node.global_position
		var pts: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				half, Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]:
			var wp: Vector2 = cam_pos + IsoProjection.screen_delta_to_world(corner, camera_node.zoom)
			pts.append(_to_mm(wp, ms))
		_overlay.draw_polyline(pts, COLOR_CAMERA_RECT, 1.5)

	# Attack / event flashes — expanding rings that fade out
	for flash: Dictionary in _flashes:
		var t: float = 1.0 - flash["timer"] / FLASH_DURATION   # 0..1 as flash ages
		var radius: float = FLASH_RADIUS_MAX * t
		var alpha: float = 1.0 - t
		var col: Color = flash["color"]
		col.a = alpha
		var fp: Vector2 = _to_mm(flash["world_pos"], ms)
		_overlay.draw_circle(fp, radius, col)
		# Solid dot at origin so it is visible at t=0
		var dot_col: Color = flash["color"]
		dot_col.a = alpha * 0.6
		_overlay.draw_circle(fp, 3.0, dot_col)

	_overlay.draw_rect(Rect2(Vector2.ZERO, ms), COLOR_BORDER, false, 1.5)

# Click on minimap → move camera to that world position
func _gui_input(event: InputEvent) -> void:
	_refresh_world_bounds()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_move_camera_to(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			EventBus.minimap_move_order.emit(_to_world(mb.position, size))
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_camera_to(mm.position)

func _move_camera_to(minimap_pos: Vector2) -> void:
	if camera_node == null:
		return
	var clamped: Vector2 = minimap_pos.clamp(Vector2.ZERO, size)
	camera_node.global_position = _to_world(clamped, size)

# --- Coordinate helpers ---

func _to_mm(world_pos: Vector2, ms: Vector2) -> Vector2:
	return (world_pos - _world_min) / _world_size * ms

func _to_world(mm_pos: Vector2, ms: Vector2) -> Vector2:
	return mm_pos / ms * _world_size + _world_min

# own units/buildings: visible in explored+visible cells; enemies: only in visible cells
func _fog_allows_see(world_pos: Vector2, is_own: bool) -> bool:
	if fog == null:
		return true
	var state: int = fog.get_cell_state(world_pos)
	if is_own:
		return state >= FogOfWar.STATE_EXPLORED
	return state == FogOfWar.STATE_VISIBLE

func _resource_color(rtype: ResourceNode.ResourceType) -> Color:
	match rtype:
		ResourceNode.ResourceType.GOLD:
			return COLOR_RESOURCE_GOLD
		ResourceNode.ResourceType.STONE:
			return COLOR_RESOURCE_STONE
		ResourceNode.ResourceType.OLIVINA:
			return Color(0.20, 0.75, 0.25, 1.0)
		_:
			return COLOR_RESOURCE_WOOD

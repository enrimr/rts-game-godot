extends Node2D

class_name FogOfWar

const CELL_SIZE: float = 50.0
## Grid overshoot past the playable rect, so shoreline reveals never clip at
## the map edge. The grid itself is sized from MatchConfig.get_map_half() in
## _ready(): a hard-coded 80×80 rect used to leave a 600 px ring of a LARGE
## map (±2600) permanently unfogged — islands at the margins showed on the
## minimap without ever being scouted.
const GRID_MARGIN: float = 200.0

# Defaults match a MEDIUM map (±1800 + margin); _ready() recomputes them.
var grid_w: int = 80
var grid_h: int = 80
var map_origin: Vector2 = Vector2(-2000.0, -2000.0)

const STATE_UNEXPLORED: int = 0
const STATE_EXPLORED: int = 1
const STATE_VISIBLE: int = 2

# One shroud tint for every fog state (only alpha varies): unexplored space,
# the explored dim layer and the out-of-map void (GameWorld sets the clear
# colour to SHROUD_RGB) all read as the same night-blue darkness instead of
# raw black tiles over a light-gray backdrop. The slight blue keeps explored
# terrain from smearing into muddy dark green.
const SHROUD_RGB: Color = Color(0.03, 0.04, 0.07)
const COLOR_UNEXPLORED: Color = Color(SHROUD_RGB.r, SHROUD_RGB.g, SHROUD_RGB.b, 1.0)
const COLOR_EXPLORED: Color = Color(SHROUD_RGB.r, SHROUD_RGB.g, SHROUD_RGB.b, 0.55)
const COLOR_VISIBLE: Color = Color(SHROUD_RGB.r, SHROUD_RGB.g, SHROUD_RGB.b, 0.0)

const UPDATE_INTERVAL: float = 0.12
const EXPLORE_THRESHOLD: int = 350  # cells newly revealed to satisfy tutorial

var _cells: PackedByteArray
## Dedupe mask + index list: _render walks only _dirty_list instead of the
## whole grid (the full-grid scan twice per tick dominated big battles).
var _dirty_cells: PackedByteArray
var _dirty_list: PackedInt32Array = PackedInt32Array()
## Transient marks (_mark_circle API: tutorial, tests): VISIBLE for one tick
## unless a watcher's refcount below sustains the cell.
var _lit: PackedInt32Array = PackedInt32Array()
## Incremental reveal: per-cell watcher refcount + per-entity stamp cache.
## A stationary army costs nothing per tick — only entities that changed grid
## cell (or a weather shift that rescales every radius) pay the circle diff.
var _watch_count: PackedInt32Array = PackedInt32Array()
var _watch: Dictionary = {}   # instance_id -> [cell_x, cell_y, r, stamp]
var _watch_stamp: int = 0
var _weather_sig: String = ""
## radius-in-cells -> PackedVector2Array of (dx, dy) offsets inside the circle;
## shared template so _mark_circle stops re-testing dx²+dy² per unit per tick.
static var _circle_offsets: Dictionary = {}
var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D

var _units_node: Node = null
var _buildings_node: Node = null
var _explore_baseline: int = -1   # -1 = not tracking
var _explore_emitted: bool = false
var _drop_off_node: Node = null
var _world_node: Node = null

var _update_timer: float = 0.0

func _ready() -> void:
	var half_cells: int = int(ceil((MatchConfig.get_map_half() + GRID_MARGIN) / CELL_SIZE))
	grid_w = half_cells * 2
	grid_h = grid_w
	map_origin = Vector2(-half_cells * CELL_SIZE, -half_cells * CELL_SIZE)

	_cells = PackedByteArray()
	_cells.resize(grid_w * grid_h)
	_cells.fill(STATE_UNEXPLORED)

	_dirty_cells = PackedByteArray()
	_dirty_cells.resize(grid_w * grid_h)
	_dirty_cells.fill(0)

	_watch_count = PackedInt32Array()
	_watch_count.resize(grid_w * grid_h)
	_watch_count.fill(0)

	_image = Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	_image.fill(COLOR_UNEXPLORED)
	_texture = ImageTexture.create_from_image(_image)

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.scale = Vector2(CELL_SIZE, CELL_SIZE)
	# Bilinear filtering turns the full-tile sawtooth teeth at the reveal
	# frontier into a soft one-cell gradient (all states share SHROUD_RGB, so
	# only alpha interpolates).
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.centered = false
	_sprite.position = map_origin
	add_child(_sprite)
	z_index = IsoBillboard.Z_FOG

## Whose perspective this fog renders — the local player (0 offline/host).
var local_player_id: int = 0

func setup(units: Node, buildings: Node, drop_off: Node, world: Node = null) -> void:
	local_player_id = NetworkSession.local_player_id
	_units_node = units
	_buildings_node = buildings
	_drop_off_node = drop_off
	_world_node = world
	GameManager.game_over.connect(_on_game_over)

func reveal_all() -> void:
	_cells.fill(STATE_VISIBLE)
	mark_all_dirty()
	_render()
	_sprite.visible = false
	# Stop ticking or the next tick demotes everything back to EXPLORED and the
	# minimap re-darkens even though the world fog sprite is hidden.
	set_process(false)
	# Make all previously hidden enemy units and buildings visible
	if is_instance_valid(_units_node):
		for unit: Node in _units_node.get_children():
			if is_instance_valid(unit):
				(unit as Node2D).visible = true
	if is_instance_valid(_buildings_node):
		for building: Node in _buildings_node.get_children():
			if is_instance_valid(building):
				(building as Node2D).visible = true
	if is_instance_valid(_world_node):
		for child: Node in _world_node.get_children():
			if child is ResourceNode:
				(child as Node2D).visible = true

func _on_game_over(_winner: int) -> void:
	reveal_all()
	set_process(false)

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_tick()

## Call this when the tutorial exploration step activates to start counting new cells.
func start_explore_tracking() -> void:
	_explore_baseline = _count_explored_cells()
	_explore_emitted = false

func _count_explored_cells() -> int:
	var count: int = 0
	for i: int in range(_cells.size()):
		if _cells[i] >= STATE_EXPLORED:
			count += 1
	return count

func _tick() -> void:
	var t0: int = Time.get_ticks_usec()
	for i: int in _lit:
		if _watch_count[i] == 0 and _cells[i] == STATE_VISIBLE:
			_cells[i] = STATE_EXPLORED
			_mark_dirty(i)
	_lit.clear()

	var t1: int = Time.get_ticks_usec()
	_update_watchers()
	var t2: int = Time.get_ticks_usec()
	var t3: int = Time.get_ticks_usec()
	_render()
	var t4: int = Time.get_ticks_usec()
	if _explore_baseline >= 0 and not _explore_emitted:
		var newly_explored: int = _count_explored_cells() - _explore_baseline
		if newly_explored >= EXPLORE_THRESHOLD:
			_explore_emitted = true
			EventBus.map_explored.emit(newly_explored)
	_apply_visibility()
	if _stats:
		var t5: int = Time.get_ticks_usec()
		print("FOG demote %4d us  units %5d us  bld %4d us  render %5d us  vis %5d us" % [
			t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4])

## CALIMA_FOG_STATS=1 prints a per-phase timing line each tick (perf triage).
var _stats: bool = OS.get_environment("CALIMA_FOG_STATS") == "1"

## Incremental reveal pass: every allied watcher is tracked by instance id;
## only cell changes (or a global weather shift) restamp its circle, so an
## army standing its ground — melee lock, eco routine — costs O(entities)
## dictionary checks instead of O(entities × circle cells) rewrites.
func _update_watchers() -> void:
	_watch_stamp += 1
	var sig: String = "%d|%.1f" % [WeatherManager.current_weather as int, WeatherManager.intensity]
	var weather_changed: bool = sig != _weather_sig
	_weather_sig = sig

	if is_instance_valid(_units_node):
		for unit: Node in _units_node.get_children():
			if not is_instance_valid(unit):
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or not GameManager.are_allied(pid as int, local_player_id):
				continue
			if unit is Animal and (unit as Animal).current_state != Animal.AnimalState.OWNED:
				continue
			_track(unit as Node2D, weather_changed, false)
	if is_instance_valid(_buildings_node):
		for building: Node in _buildings_node.get_children():
			if not is_instance_valid(building):
				continue
			var pid: Variant = building.get("player_id")
			if pid == null or not GameManager.are_allied(pid as int, local_player_id):
				continue
			var state_val: Variant = building.get("state")
			if state_val != null and (state_val as int) != BuildingBase.BuildingState.COMPLETE:
				continue
			_track(building as Node2D, weather_changed, true)
	if is_instance_valid(_drop_off_node):
		var pid: Variant = _drop_off_node.get("player_id")
		if pid != null and GameManager.are_allied(pid as int, local_player_id):
			_track(_drop_off_node as Node2D, weather_changed, true)

	# Watchers that vanished (death, conversion, demolition) release their cells.
	for iid: Variant in _watch.keys():
		var entry: Array = _watch[iid] as Array
		if (entry[3] as int) != _watch_stamp:
			_unstamp(Vector2i(entry[0] as int, entry[1] as int), entry[2] as int)
			_watch.erase(iid)

func _track(entity: Node2D, weather_changed: bool, is_building: bool) -> void:
	var cell: Vector2i = _world_to_cell(entity.global_position)
	var iid: int = entity.get_instance_id()
	var prev: Variant = _watch.get(iid)
	if prev != null and not weather_changed \
			and ((prev as Array)[0] as int) == cell.x and ((prev as Array)[1] as int) == cell.y:
		(prev as Array)[3] = _watch_stamp
		return
	var r: int = _vision_radius_cells(entity, is_building)
	if prev != null:
		var entry: Array = prev as Array
		if (entry[0] as int) == cell.x and (entry[1] as int) == cell.y and (entry[2] as int) == r:
			entry[3] = _watch_stamp
			return
		_unstamp(Vector2i(entry[0] as int, entry[1] as int), entry[2] as int)
	_stamp(cell, r)
	_watch[iid] = [cell.x, cell.y, r, _watch_stamp]

func _vision_radius_cells(entity: Node2D, is_building: bool) -> int:
	var los: float
	if is_building:
		los = 8.0
		var bdata: Variant = entity.get("building_data")
		if bdata is BuildingResource:
			los = (bdata as BuildingResource).line_of_sight
	elif entity is Animal:
		los = (entity as Animal).line_of_sight
	else:
		los = 5.0
		var udata: Variant = entity.get("unit_data")
		if udata is UnitResource:
			los = (udata as UnitResource).line_of_sight
	var mult: float = WeatherManager.get_vision_multiplier(entity.global_position, local_player_id) \
		* _coastal_vision_mult(entity.global_position)
	# Terrain factor: laurisilva canopy shortens LOS. Buildings skip this —
	# laurisilva is not buildable, so their factor is always 1.0.
	if not is_building:
		mult *= TerrainManager.get_vision_mult(entity.global_position)
	return int(ceil(los * 64.0 * mult / CELL_SIZE)) + 1

func _stamp(cell: Vector2i, r: int) -> void:
	for off: Vector2 in _offsets_for_radius(r):
		var nx: int = cell.x + int(off.x)
		var ny: int = cell.y + int(off.y)
		if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
			continue
		var idx: int = ny * grid_w + nx
		_watch_count[idx] += 1
		if _watch_count[idx] == 1 and _cells[idx] != STATE_VISIBLE:
			_cells[idx] = STATE_VISIBLE
			_mark_dirty(idx)

func _unstamp(cell: Vector2i, r: int) -> void:
	for off: Vector2 in _offsets_for_radius(r):
		var nx: int = cell.x + int(off.x)
		var ny: int = cell.y + int(off.y)
		if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
			continue
		var idx: int = ny * grid_w + nx
		_watch_count[idx] = maxi(_watch_count[idx] - 1, 0)
		if _watch_count[idx] == 0 and _cells[idx] == STATE_VISIBLE:
			_cells[idx] = STATE_EXPLORED
			_mark_dirty(idx)

## Civ line-of-sight bonus along one's own shores: the "coastal_vision" multiplier
## applies inside the same band sea fog uses (COASTAL_ZONE_DEPTH), so the Atlantes
## see 50 % further exactly where the fog hides things. The fast path keeps the
## coast query out of the way for the civs without the bonus.
func _coastal_vision_mult(world_pos: Vector2) -> float:
	var mult: float = CivBonusManager.get_multiplier(local_player_id, "coastal_vision")
	if is_equal_approx(mult, 1.0):
		return 1.0
	if TerrainManager.distance_to_coast(world_pos) > WeatherManager.COASTAL_ZONE_DEPTH:
		return 1.0
	return mult

func _mark_dirty(idx: int) -> void:
	if _dirty_cells[idx] == 0:
		_dirty_cells[idx] = 1
		_dirty_list.append(idx)

## External state swaps (save restore, resumed-match resync, reveal_all)
## repaint everything on the next render and rebuild the reveal bookkeeping:
## restored VISIBLE cells become transient (they decay unless a watcher
## re-stamps them on the next tick) and every watcher restamps fresh.
func mark_all_dirty() -> void:
	_dirty_cells.fill(1)
	_dirty_list.clear()
	_lit.clear()
	_watch.clear()
	_watch_count.fill(0)
	for i: int in range(_cells.size()):
		_dirty_list.append(i)
		if _cells[i] == STATE_VISIBLE:
			_lit.append(i)

static func _offsets_for_radius(r: int) -> PackedVector2Array:
	var cached: Variant = _circle_offsets.get(r)
	if cached != null:
		return cached as PackedVector2Array
	var out: PackedVector2Array = PackedVector2Array()
	var r2: int = r * r
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= r2:
				out.append(Vector2(float(dx), float(dy)))
	_circle_offsets[r] = out
	return out

func _mark_circle(world_pos: Vector2, radius_px: float) -> void:
	var cell: Vector2i = _world_to_cell(world_pos)
	var r: int = int(ceil(radius_px / CELL_SIZE)) + 1
	for off: Vector2 in _offsets_for_radius(r):
		var nx: int = cell.x + int(off.x)
		var ny: int = cell.y + int(off.y)
		if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
			continue
		var idx: int = ny * grid_w + nx
		if _cells[idx] != STATE_VISIBLE:
			_cells[idx] = STATE_VISIBLE
			_mark_dirty(idx)
			_lit.append(idx)

func _render() -> void:
	if _dirty_list.is_empty():
		return
	for i: int in _dirty_list:
		_dirty_cells[i] = 0
		var x: int = i % grid_w
		var y: int = i / grid_w
		match _cells[i]:
			STATE_UNEXPLORED:
				_image.set_pixel(x, y, COLOR_UNEXPLORED)
			STATE_EXPLORED:
				_image.set_pixel(x, y, COLOR_EXPLORED)
			_:
				_image.set_pixel(x, y, COLOR_VISIBLE)
	_dirty_list.clear()
	_texture.update(_image)

func _apply_visibility() -> void:
	var own_positions: PackedVector2Array = _own_watcher_positions()
	# Enemy units and animals: only visible when in a currently visible cell
	if is_instance_valid(_units_node):
		for unit: Node in _units_node.get_children():
			if not is_instance_valid(unit):
				continue
			var pid: Variant = unit.get("player_id")
			var is_own: bool = pid != null and GameManager.are_allied(pid as int, local_player_id)
			if is_own:
				continue
			var was_visible: bool = (unit as Node2D).visible
			var state: int = get_cell_state((unit as Node2D).global_position)
			var fog_cloaked: bool = WeatherManager.is_unit_cloaked_by_weather((unit as Node2D).global_position) \
				and not _breaks_fog_cloak(unit, own_positions)
			var now_visible: bool = (state == STATE_VISIBLE) and not fog_cloaked
			(unit as Node2D).visible = now_visible
			if now_visible and not was_visible:
				EventBus.enemy_unit_spotted.emit(unit)

	# Enemy buildings: remembered once explored (stay visible under grey shroud)
	# Own buildings are always visible — skip them
	if is_instance_valid(_buildings_node):
		for building: Node in _buildings_node.get_children():
			if not is_instance_valid(building):
				continue
			var pid: Variant = building.get("player_id")
			var is_own: bool = pid != null and GameManager.are_allied(pid as int, local_player_id)
			if is_own:
				continue
			var state: int = get_cell_state((building as Node2D).global_position)
			(building as Node2D).visible = (state >= STATE_EXPLORED)

	# Resource nodes: shown once the area has been explored
	if is_instance_valid(_world_node):
		for child: Node in _world_node.get_children():
			if not (child is ResourceNode):
				continue
			var state: int = get_cell_state((child as Node2D).global_position)
			(child as Node2D).visible = (state >= STATE_EXPLORED)

## Positions that can spot a fog-cloaked enemy at short range: every own unit and
## every finished own building, gathered once per tick.
func _own_watcher_positions() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if is_instance_valid(_units_node):
		for unit: Node in _units_node.get_children():
			if not is_instance_valid(unit):
				continue
			var pid: Variant = unit.get("player_id")
			if pid != null and GameManager.are_allied(pid as int, local_player_id):
				out.append((unit as Node2D).global_position)
	if is_instance_valid(_buildings_node):
		for building: Node in _buildings_node.get_children():
			if not is_instance_valid(building):
				continue
			var pid: Variant = building.get("player_id")
			if pid == null or not GameManager.are_allied(pid as int, local_player_id):
				continue
			var state_val: Variant = building.get("state")
			if state_val != null and (state_val as int) != BuildingBase.BuildingState.COMPLETE:
				continue
			out.append((building as Node2D).global_position)
	if is_instance_valid(_drop_off_node):
		var tc_pid: Variant = _drop_off_node.get("player_id")
		if tc_pid != null and GameManager.are_allied(tc_pid as int, local_player_id):
			out.append((_drop_off_node as Node2D).global_position)
	return out

## Sea fog hides units at distance, not the ones already at arm's length — and it
## never hides a unit that is shooting. Without this the cloak wiped every enemy
## off the screen on Islands maps, where the whole map lies inside the coastal band.
func _breaks_fog_cloak(unit: Node, own_positions: PackedVector2Array) -> bool:
	if unit.has_method("is_revealed_by_combat") and unit.call("is_revealed_by_combat"):
		return true
	var pid: Variant = unit.get("player_id")
	var spot: float = WeatherManager.fog_spot_range(pid as int if pid != null else -1)
	var pos: Vector2 = (unit as Node2D).global_position
	for watcher: Vector2 in own_positions:
		if pos.distance_squared_to(watcher) <= spot * spot:
			return true
	return false

func _world_to_cell(world_pos: Vector2) -> Vector2i:
	var rel: Vector2 = (world_pos - map_origin) / CELL_SIZE
	return Vector2i(int(rel.x), int(rel.y))

func get_cell_state(world_pos: Vector2) -> int:
	var cell: Vector2i = _world_to_cell(world_pos)
	if cell.x < 0 or cell.x >= grid_w or cell.y < 0 or cell.y >= grid_h:
		return STATE_UNEXPLORED
	return _cells[cell.y * grid_w + cell.x]

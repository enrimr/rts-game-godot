extends Node2D

class_name FogOfWar

const CELL_SIZE: float = 50.0
const GRID_W: int = 80   # 4000 / 50
const GRID_H: int = 80
const MAP_ORIGIN: Vector2 = Vector2(-2000.0, -2000.0)

const STATE_UNEXPLORED: int = 0
const STATE_EXPLORED: int = 1
const STATE_VISIBLE: int = 2

const COLOR_UNEXPLORED: Color = Color(0.0, 0.0, 0.0, 1.0)
const COLOR_EXPLORED: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_VISIBLE: Color = Color(0.0, 0.0, 0.0, 0.0)

const UPDATE_INTERVAL: float = 0.12

var _cells: PackedByteArray
var _dirty_cells: PackedByteArray
var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D

var _units_node: Node = null
var _buildings_node: Node = null
var _drop_off_node: Node = null
var _world_node: Node = null

var _update_timer: float = 0.0

func _ready() -> void:
	_cells = PackedByteArray()
	_cells.resize(GRID_W * GRID_H)
	_cells.fill(STATE_UNEXPLORED)

	_dirty_cells = PackedByteArray()
	_dirty_cells.resize(GRID_W * GRID_H)
	_dirty_cells.fill(0)

	_image = Image.create(GRID_W, GRID_H, false, Image.FORMAT_RGBA8)
	_image.fill(COLOR_UNEXPLORED)
	_texture = ImageTexture.create_from_image(_image)

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.scale = Vector2(CELL_SIZE, CELL_SIZE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = false
	_sprite.position = MAP_ORIGIN
	add_child(_sprite)
	z_index = 10

func setup(units: Node, buildings: Node, drop_off: Node, world: Node = null) -> void:
	_units_node = units
	_buildings_node = buildings
	_drop_off_node = drop_off
	_world_node = world
	GameManager.game_over.connect(_on_game_over)

func reveal_all() -> void:
	_cells.fill(STATE_VISIBLE)
	_dirty_cells.fill(1)
	_render()
	_sprite.visible = false
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

func _tick() -> void:
	for i: int in range(_cells.size()):
		if _cells[i] == STATE_VISIBLE:
			_cells[i] = STATE_EXPLORED
			_dirty_cells[i] = 1

	_reveal_from_units()
	_reveal_from_buildings()
	_render()
	_apply_visibility()

func _reveal_from_units() -> void:
	if not is_instance_valid(_units_node):
		return
	for unit: Node in _units_node.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		var los: float
		if unit is Animal:
			# Only owned animals reveal; use their line_of_sight export
			if (unit as Animal).current_state != Animal.AnimalState.OWNED:
				continue
			los = (unit as Animal).line_of_sight
		else:
			los = 5.0
			var udata: Variant = unit.get("unit_data")
			if udata is UnitResource:
				los = (udata as UnitResource).line_of_sight
		_mark_circle((unit as Node2D).global_position, los * 64.0)

func _reveal_from_buildings() -> void:
	# Buildings layer
	if is_instance_valid(_buildings_node):
		for building: Node in _buildings_node.get_children():
			if not is_instance_valid(building):
				continue
			var pid: Variant = building.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			var state_val: Variant = building.get("state")
			if state_val != null and (state_val as int) != BuildingBase.BuildingState.COMPLETE:
				continue
			var los: float = 8.0
			var bdata: Variant = building.get("building_data")
			if bdata is BuildingResource:
				los = (bdata as BuildingResource).line_of_sight
			_mark_circle((building as Node2D).global_position, los * 64.0)

	# Town Center (drop_off_node in world root)
	if is_instance_valid(_drop_off_node):
		var pid: Variant = _drop_off_node.get("player_id")
		if pid != null and (pid as int) == 0:
			_mark_circle((_drop_off_node as Node2D).global_position, 8.0 * 64.0)

func _mark_circle(world_pos: Vector2, radius_px: float) -> void:
	var cell: Vector2i = _world_to_cell(world_pos)
	var r: int = int(ceil(radius_px / CELL_SIZE)) + 1
	var r2: int = r * r
	for dy: int in range(-r, r + 1):
		var ny: int = cell.y + dy
		if ny < 0 or ny >= GRID_H:
			continue
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy > r2:
				continue
			var nx: int = cell.x + dx
			if nx < 0 or nx >= GRID_W:
				continue
			var idx: int = ny * GRID_W + nx
			_cells[idx] = STATE_VISIBLE
			_dirty_cells[idx] = 1

func _render() -> void:
	var any_updated: bool = false
	for i: int in range(_dirty_cells.size()):
		if _dirty_cells[i] == 0:
			continue
		_dirty_cells[i] = 0
		any_updated = true
		var x: int = i % GRID_W
		var y: int = i / GRID_W
		match _cells[i]:
			STATE_UNEXPLORED:
				_image.set_pixel(x, y, COLOR_UNEXPLORED)
			STATE_EXPLORED:
				_image.set_pixel(x, y, COLOR_EXPLORED)
			_:
				_image.set_pixel(x, y, COLOR_VISIBLE)
	if any_updated:
		_texture.update(_image)

func _apply_visibility() -> void:
	# Enemy units and animals: only visible when in a currently visible cell
	if is_instance_valid(_units_node):
		for unit: Node in _units_node.get_children():
			if not is_instance_valid(unit):
				continue
			var pid: Variant = unit.get("player_id")
			var is_own: bool = pid != null and (pid as int) == 0
			if is_own:
				continue
			var was_visible: bool = (unit as Node2D).visible
			var state: int = get_cell_state((unit as Node2D).global_position)
			var now_visible: bool = (state == STATE_VISIBLE)
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
			var is_own: bool = pid != null and (pid as int) == 0
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

func _world_to_cell(world_pos: Vector2) -> Vector2i:
	var rel: Vector2 = (world_pos - MAP_ORIGIN) / CELL_SIZE
	return Vector2i(int(rel.x), int(rel.y))

func get_cell_state(world_pos: Vector2) -> int:
	var cell: Vector2i = _world_to_cell(world_pos)
	if cell.x < 0 or cell.x >= GRID_W or cell.y < 0 or cell.y >= GRID_H:
		return STATE_UNEXPLORED
	return _cells[cell.y * GRID_W + cell.x]

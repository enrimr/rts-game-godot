class_name WorldSelection extends RefCounted

## Click/drag selection for the match: the screen-space drag band, single and
## double click-select, building/resource click-select, control-group hotkeys
## and the SelectionManager mirror. Shared selection state (_selected_units,
## _selected_building) stays on GameWorld — the command handlers read it too.
## _building_click_hit / the _find_*_at pickers live on WorldCommands and are
## reached through _world._commands.

const DOUBLE_CLICK_SEC: float = 0.35
const DOUBLE_CLICK_RADIUS: float = 600.0
# A small screen area is a click regardless of zoom (a world-space area
# threshold was zoom-dependent).
const CLICK_MAX_SCREEN_AREA: float = 25.0

var _world  # GameWorld — untyped so dynamic access works

var _drag_start: Vector2 = Vector2.ZERO
# Screen-space anchor of the drag: the band the player draws is a plain 2D
# rectangle on the screen; world membership is tested by projecting units
# into screen space (never by an axis-aligned world rect, which the iso
# camera would render as a parallelogram).
var _drag_start_screen: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _last_click_time: float = -1.0
var _last_click_unit_script: Script = null
var _last_building_click_time: float = -1.0
var _last_building_click_script: Script = null

## Single click selects one building; a double click on the same type selects
## every OWN building of that type map-wide (rally them all at once, and the
## HUD's train buttons queue into the least-loaded of the group).
func _select_building(building: Node) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var bscript: Script = building.get_script() as Script
	var is_double: bool = (now - _last_building_click_time) <= DOUBLE_CLICK_SEC \
		and bscript == _last_building_click_script
	_last_building_click_time = now
	_last_building_click_script = bscript

	_world._selected_building = building
	_world._selected_buildings = [building] as Array[Node]
	var bpid: Variant = building.get("player_id")
	if is_double and bpid != null and (bpid as int) == NetworkSession.local_player_id:
		var candidates: Array[Node] = []
		if is_instance_valid(_world.drop_off):
			candidates.append(_world.drop_off)
		for other: Node in _world.buildings_layer.get_children():
			if is_instance_valid(other):
				candidates.append(other)
		for other: Node in candidates:
			if other == building or other.get_script() != bscript:
				continue
			var opid: Variant = other.get("player_id")
			if opid == null or (opid as int) != NetworkSession.local_player_id:
				continue
			var state_val: Variant = other.get("state")
			if state_val != null and (state_val as int) != BuildingBase.BuildingState.COMPLETE:
				continue
			_world._selected_buildings.append(other)
			if other.has_method("set_selected"):
				other.set_selected(true)
	EventBus.building_selected.emit(building)

# Inspect-only selection (resource node, enemy unit/building, wild animal).
var _selected_node: Node = null

# Drag-select rectangle overlay (child of GameWorld; freed with the scene).
var _drag_overlay: _DragOverlay = null

func setup(world) -> void:
	_world = world

func create_drag_overlay() -> void:
	_drag_overlay = _DragOverlay.new()
	_drag_overlay.z_index = IsoBillboard.Z_DRAG_SELECT
	_world.add_child(_drag_overlay)

## Per-frame overlay refresh; called from GameWorld._process.
func update_drag_overlay() -> void:
	if not is_instance_valid(_drag_overlay):
		return
	_drag_overlay.active = _dragging
	if _dragging:
		_drag_overlay.drag_rect = Rect2(_drag_start_screen, Vector2.ZERO) \
			.expand(_world.get_viewport().get_mouse_position())
	_drag_overlay.queue_redraw()

## Ctrl (or Cmd on macOS) + digit assigns a control group; plain digit recalls.
## Returns true when the key was a 1..9 group hotkey.
func handle_group_hotkey(ke: InputEventKey) -> bool:
	var group_id: int = ke.physical_keycode - KEY_0
	if group_id < 1 or group_id > 9:
		return false
	if ke.ctrl_pressed or ke.meta_pressed:
		SelectionManager.save_group(group_id)
	else:
		SelectionManager.recall_group(group_id)
	return true

## Left-button press starts a drag; release finishes it as click or band select.
func handle_left_mouse(pressed: bool) -> void:
	if pressed:
		_drag_start = _world.get_global_mouse_position()
		_drag_start_screen = _world.get_viewport().get_mouse_position()
		_dragging = true
	elif _dragging:
		_dragging = false
		_finish_selection()

## Mirrors SelectionManager-driven changes (control-group recall, HUD chips)
## into the world's live selection list.
func _on_selection_manager_changed(units: Array) -> void:
	_world._selected_units.clear()
	# Variant loop variable on purpose: a freed entry in an untyped array aborts
	# the loop on the typed assignment, before the guard below can drop it.
	for u: Variant in units:
		if is_instance_valid(u):
			_world._selected_units.append(u)

func _finish_selection() -> void:
	var screen_rect: Rect2 = Rect2(_drag_start_screen, Vector2.ZERO) \
		.expand(_world.get_viewport().get_mouse_position())
	var is_click: bool = screen_rect.get_area() < CLICK_MAX_SCREEN_AREA

	for sel: Node in _world.live_selection():
		if is_instance_valid(sel):
			sel.set_selected(false)
	_world._selected_units.clear()
	if is_instance_valid(_world._selected_building) and _world._selected_building.has_method("set_selected"):
		_world._selected_building.set_selected(false)
	_world._selected_building = null
	for b: Node in _world.live_selected_buildings():
		if b.has_method("set_selected"):
			b.set_selected(false)
	_world._selected_buildings.clear()
	if is_instance_valid(_selected_node) and _selected_node.has_method("set_selected"):
		_selected_node.set_selected(false)
	_selected_node = null

	if is_click:
		# Click: select only the single nearest friendly unit within radius
		var best_unit: Node = null
		var best_dist: float = WorldCommands.UNIT_CLICK_RADIUS
		for unit: Node in _world.units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			var unit2d: Node2D = unit as Node2D
			var d: float = _drag_start.distance_to(unit2d.global_position)
			if d >= best_dist:
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == NetworkSession.local_player_id:
					best_dist = d
					best_unit = unit
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != NetworkSession.local_player_id:
				continue
			best_dist = d
			best_unit = unit
		if best_unit != null:
			var now: float = Time.get_ticks_msec() / 1000.0
			var unit_script: Script = best_unit.get_script() as Script
			var is_double: bool = (now - _last_click_time) <= DOUBLE_CLICK_SEC \
				and unit_script == _last_click_unit_script
			_last_click_time = now
			_last_click_unit_script = unit_script

			if is_double:
				# Select all friendly units of the same type within DOUBLE_CLICK_RADIUS
				for unit: Node in _world.units_layer.get_children():
					if not is_instance_valid(unit):
						continue
					var pid: Variant = unit.get("player_id")
					if pid == null or (pid as int) != NetworkSession.local_player_id:
						continue
					if unit.get_script() != unit_script:
						continue
					if (unit as Node2D).global_position.distance_to(
							(best_unit as Node2D).global_position) > DOUBLE_CLICK_RADIUS:
						continue
					unit.set_selected(true)
					if not _world._selected_units.has(unit):
						_world._selected_units.append(unit)
			else:
				best_unit.set_selected(true)
				_world._selected_units.append(best_unit)

			AudioManager.play("ui_select")
			SelectionManager.select(_world._selected_units)
			return
		# Check Town Center first
		if is_instance_valid(_world.drop_off) and _world._commands._building_click_hit(_world.drop_off as Node2D, _drag_start):
			_select_building(_world.drop_off)
			return
		for building: Node in _world.buildings_layer.get_children():
			if not is_instance_valid(building):
				continue
			var b2d: Node2D = building as Node2D
			if _world._commands._building_click_hit(b2d, _drag_start):
				_select_building(building)
				return
		for child: Node in _world.get_children():
			if not (child is ResourceNode):
				continue
			var rn: ResourceNode = child as ResourceNode
			if _drag_start.distance_to(rn.global_position) < WorldCommands.UNIT_CLICK_RADIUS:
				rn.set_selected(true)
				_selected_node = rn
				EventBus.resource_node_selected.emit(rn)
				return
		# Enemy unit / wild animal / enemy building — inspect only (no command)
		var enemy_unit: Node = _world._commands._find_enemy_unit_at(_drag_start)
		if enemy_unit != null:
			enemy_unit.set_selected(true)
			_selected_node = enemy_unit
			return
		var wild_animal: Animal = _world._commands._find_animal_at(_drag_start)
		if wild_animal != null and (wild_animal.current_state != Animal.AnimalState.OWNED or wild_animal.player_id != NetworkSession.local_player_id):
			wild_animal.set_selected(true)
			_selected_node = wild_animal
			return
		var enemy_building: Node = _world._commands._find_enemy_building_at(_drag_start)
		if enemy_building != null:
			enemy_building.set_selected(true)
			_selected_node = enemy_building
			return
	else:
		# Drag: select all friendly units and owned animals whose projected
		# screen position falls inside the screen-space band.
		var to_screen: Transform2D = _world.get_viewport().get_canvas_transform()
		for unit: Node in _world.units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == NetworkSession.local_player_id:
					if screen_rect.has_point(to_screen * (unit as Node2D).global_position):
						animal.set_selected(true)
						_world._selected_units.append(animal)
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != NetworkSession.local_player_id:
				continue
			if screen_rect.has_point(to_screen * (unit as Node2D).global_position):
				unit.set_selected(true)
				_world._selected_units.append(unit)

	if not _world._selected_units.is_empty():
		AudioManager.play("ui_select")
	SelectionManager.select(_world._selected_units)

class _DragOverlay extends Node2D:
	var drag_rect: Rect2 = Rect2()   # screen-space (viewport) coordinates
	var active: bool = false
	func _draw() -> void:
		if not active:
			return
		# Cancel the iso camera transform so the band is a plain screen-space
		# rectangle, like any classic RTS (same trick as weather_overlay).
		draw_set_transform_matrix(get_canvas_transform().affine_inverse())
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.18), true)
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.75), false, 1.5)

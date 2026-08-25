class_name HudControls
extends Node

## On-screen control widgets: game-speed buttons (x1/x2/x4), the camera dpad
## (with its own per-frame panning), and the idle-villager / idle-military
## cycle buttons. Builds its widgets into the provided HUDRoot and owns the
## small periodic refresh of the idle-button states.

const CAMERA_PAN_SPEED: float = 600.0
const IDLE_REFRESH_INTERVAL: float = 0.5

var local_player_id: int = 0
var _hud_root: Control = null

var _speed_buttons: Array[Button] = []
var _dpad: Control = null
var _dpad_dir: Vector2 = Vector2.ZERO
var _idle_villager_btn: Button = null
var _idle_villager_index: int = 0
var _idle_military_btn: Button = null
var _idle_military_index: int = 0
var _idle_check_timer: float = 0.0

func init(player_id: int, hud_root: Control) -> void:
	local_player_id = player_id
	_hud_root = hud_root

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_idle_villager_button()
	_build_idle_military_button()
	_build_dpad()
	_build_speed_buttons()
	set_game_speed(1)

func _process(delta: float) -> void:
	_idle_check_timer += delta
	if _idle_check_timer >= IDLE_REFRESH_INTERVAL:
		_idle_check_timer = 0.0
		_update_idle_villager_button()
		_update_idle_military_button()
	if _dpad_dir != Vector2.ZERO:
		var cam: Camera2D = _camera()
		if cam != null:
			# Pan along SCREEN axes so the dpad feels right under the iso rotation.
			cam.position += IsoProjection.screen_dir_to_world(_dpad_dir) * CAMERA_PAN_SPEED * delta

func set_dpad_visible(visible: bool) -> void:
	if is_instance_valid(_dpad):
		_dpad.visible = visible

func _camera() -> Camera2D:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		return null
	return world.get_node_or_null("Camera2D") as Camera2D

func _build_speed_buttons() -> void:
	if _hud_root == null:
		return
	var speeds: Array = [1, 2, 4]
	# Place to the left of the ☰ menu button (which ends at offset_right=-31)
	# Each button 36px wide, 4px gap between them
	var btn_w: float = 36.0
	var gap: float = 4.0
	var menu_left: float = -69.0  # offset_left of the menu button
	for i: int in range(speeds.size()):
		var speed: int = speeds[speeds.size() - 1 - i]  # right to left: 4, 2, 1
		var btn: Button = Button.new()
		btn.text = "x%d" % speed
		btn.custom_minimum_size = Vector2(btn_w, 36.0)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.anchor_left   = 1.0
		btn.anchor_top    = 0.0
		btn.anchor_right  = 1.0
		btn.anchor_bottom = 0.0
		var right_offset: float = menu_left - gap - i * (btn_w + gap)
		btn.offset_right  = right_offset
		btn.offset_left   = right_offset - btn_w
		btn.offset_top    = 31.0
		btn.offset_bottom = 67.0
		var s: StyleBoxFlat = HudStyle.panel(Color(0.12, 0.22, 0.12, 0.92) if speed == 1 else Color(0.12, 0.12, 0.18, 0.92), 4)
		btn.add_theme_stylebox_override("normal", s)
		var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
		sh.bg_color = Color(0.28, 0.28, 0.42, 0.97)
		btn.add_theme_stylebox_override("hover", sh)
		var sp: int = speed
		btn.pressed.connect(func() -> void: set_game_speed(sp))
		_hud_root.add_child(btn)
		_speed_buttons.append(btn)
	# Reverse so index 0=x1, 1=x2, 2=x4
	_speed_buttons.reverse()

func set_game_speed(speed: int) -> void:
	GameManager.set_game_speed(float(speed))
	var active_bg: Color = Color(0.12, 0.42, 0.12, 0.95)
	var inactive_bg: Color = Color(0.12, 0.12, 0.18, 0.92)
	var speeds: Array = [1, 2, 4]
	for i: int in range(_speed_buttons.size()):
		if not is_instance_valid(_speed_buttons[i]):
			continue
		var s: StyleBoxFlat = HudStyle.panel(active_bg if speeds[i] == speed else inactive_bg, 4)
		_speed_buttons[i].add_theme_stylebox_override("normal", s)

func _build_idle_villager_button() -> void:
	if _hud_root == null:
		return
	_idle_villager_btn = Button.new()
	_idle_villager_btn.text = "👷"
	_idle_villager_btn.custom_minimum_size = Vector2(36, 36)
	_idle_villager_btn.focus_mode = Control.FOCUS_NONE
	_idle_villager_btn.add_theme_font_size_override("font_size", 22)
	_idle_villager_btn.tooltip_text = tr("UI_IDLE_VILLAGER")
	# Anchor to bottom-right, above minimap top (220px), flush with minimap left edge (220px from right)
	_idle_villager_btn.anchor_left   = 1.0
	_idle_villager_btn.anchor_top    = 1.0
	_idle_villager_btn.anchor_right  = 1.0
	_idle_villager_btn.anchor_bottom = 1.0
	_idle_villager_btn.offset_left   = -256.0
	_idle_villager_btn.offset_top    = -260.0
	_idle_villager_btn.offset_right  = -220.0
	_idle_villager_btn.offset_bottom = -224.0
	var s: StyleBoxFlat = HudStyle.panel(Color(0.20, 0.40, 0.12, 0.92), 4)
	_idle_villager_btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.32, 0.58, 0.18, 0.97)
	_idle_villager_btn.add_theme_stylebox_override("hover", sh)
	_idle_villager_btn.pressed.connect(_on_idle_villager_pressed)
	_hud_root.add_child(_idle_villager_btn)

func _get_idle_villagers() -> Array[Node]:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		return []
	var units_layer: Node = world.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return []
	var result: Array[Node] = []
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit.get("player_id") != local_player_id:
			continue
		if not unit.has_method("order_gather"):
			continue
		var state: Variant = unit.get("current_state")
		if state != null and (state as int) == UnitBase.UnitState.IDLE:
			result.append(unit)
	return result

func _update_idle_villager_button() -> void:
	if not is_instance_valid(_idle_villager_btn):
		return
	var idle: Array[Node] = _get_idle_villagers()
	_idle_villager_btn.disabled = idle.is_empty()
	_idle_villager_btn.tooltip_text = tr("UI_IDLE_VILLAGER") + " (%d)" % idle.size()

func _on_idle_villager_pressed() -> void:
	var idle: Array[Node] = _get_idle_villagers()
	if idle.is_empty():
		return
	_idle_villager_index = _idle_villager_index % idle.size()
	var villager: Node = idle[_idle_villager_index]
	_idle_villager_index = (_idle_villager_index + 1) % idle.size()
	SelectionManager.select([villager])
	var cam: Camera2D = _camera()
	if cam != null:
		cam.position = (villager as Node2D).global_position

func _build_idle_military_button() -> void:
	if _hud_root == null:
		return
	_idle_military_btn = Button.new()
	_idle_military_btn.text = "⚔"
	_idle_military_btn.custom_minimum_size = Vector2(36, 36)
	_idle_military_btn.focus_mode = Control.FOCUS_NONE
	_idle_military_btn.add_theme_font_size_override("font_size", 22)
	_idle_military_btn.tooltip_text = tr("UI_IDLE_MILITARY")
	# Anchor to bottom-right, same row as villager button, 4px to the left of it
	_idle_military_btn.anchor_left   = 1.0
	_idle_military_btn.anchor_top    = 1.0
	_idle_military_btn.anchor_right  = 1.0
	_idle_military_btn.anchor_bottom = 1.0
	_idle_military_btn.offset_left   = -296.0
	_idle_military_btn.offset_top    = -260.0
	_idle_military_btn.offset_right  = -260.0
	_idle_military_btn.offset_bottom = -224.0
	var s: StyleBoxFlat = HudStyle.panel(Color(0.40, 0.12, 0.12, 0.92), 4)
	_idle_military_btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.60, 0.18, 0.18, 0.97)
	_idle_military_btn.add_theme_stylebox_override("hover", sh)
	_idle_military_btn.pressed.connect(_on_idle_military_pressed)
	_hud_root.add_child(_idle_military_btn)

func _get_idle_military() -> Array[Node]:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		return []
	var units_layer: Node = world.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return []
	var result: Array[Node] = []
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit.get("player_id") != local_player_id:
			continue
		if unit.get("unit_data") == null:
			continue
		if unit.has_method("order_gather"):
			continue
		if unit is Animal or unit is ShipBase:
			continue
		var state: Variant = unit.get("current_state")
		if state != null and (state as int) == UnitBase.UnitState.IDLE:
			result.append(unit)
	return result

func _update_idle_military_button() -> void:
	if not is_instance_valid(_idle_military_btn):
		return
	var idle: Array[Node] = _get_idle_military()
	_idle_military_btn.disabled = idle.is_empty()
	_idle_military_btn.tooltip_text = tr("UI_IDLE_MILITARY") + " (%d)" % idle.size()

func _on_idle_military_pressed() -> void:
	var idle: Array[Node] = _get_idle_military()
	if idle.is_empty():
		return
	_idle_military_index = _idle_military_index % idle.size()
	var unit: Node = idle[_idle_military_index]
	_idle_military_index = (_idle_military_index + 1) % idle.size()
	SelectionManager.select([unit])
	var cam: Camera2D = _camera()
	if cam != null:
		cam.position = (unit as Node2D).global_position

func _build_dpad() -> void:
	if _hud_root == null:
		return
	_dpad = Control.new()
	_dpad.anchor_left   = 0.0
	_dpad.anchor_top    = 1.0
	_dpad.anchor_right  = 0.0
	_dpad.anchor_bottom = 1.0
	const OFFSET_BOTTOM: float = -(175.0 + 8.0)
	const CELL: float = 96.0
	const GAP: float = 6.0
	const GRID_W: float = CELL * 3.0 + GAP * 2.0
	const GRID_H: float = CELL * 3.0 + GAP * 2.0
	_dpad.offset_left   = 8.0
	_dpad.offset_bottom = OFFSET_BOTTOM
	_dpad.offset_right  = 8.0 + GRID_W
	_dpad.offset_top    = OFFSET_BOTTOM - GRID_H
	_dpad.visible       = GameSettings.show_dpad
	_hud_root.add_child(_dpad)

	var dirs: Array[Dictionary] = [
		{"label": "↑", "row": 0, "col": 1, "dir": Vector2(0.0, -1.0)},
		{"label": "←", "row": 1, "col": 0, "dir": Vector2(-1.0, 0.0)},
		{"label": "→", "row": 1, "col": 2, "dir": Vector2(1.0, 0.0)},
		{"label": "↓", "row": 2, "col": 1, "dir": Vector2(0.0, 1.0)},
	]
	for entry: Dictionary in dirs:
		var btn: Button = Button.new()
		btn.text             = entry["label"] as String
		btn.focus_mode       = Control.FOCUS_NONE
		btn.mouse_filter     = Control.MOUSE_FILTER_STOP
		btn.custom_minimum_size = Vector2(CELL, CELL)
		var col: int = entry["col"] as int
		var row: int = entry["row"] as int
		btn.position = Vector2(col * (CELL + GAP), row * (CELL + GAP))
		btn.size     = Vector2(CELL, CELL)
		btn.add_theme_font_size_override("font_size", 40)
		var s: StyleBoxFlat = HudStyle.panel(Color(0.12, 0.12, 0.18, 0.85), 6)
		btn.add_theme_stylebox_override("normal", s)
		var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
		sh.bg_color = Color(0.22, 0.22, 0.32, 0.95)
		btn.add_theme_stylebox_override("hover", sh)
		_dpad.add_child(btn)
		var move_dir: Vector2 = entry["dir"] as Vector2
		btn.button_down.connect(func() -> void:
			# Manual panning must win over camera-follow of the selection.
			EventBus.camera_follow_cancelled.emit()
			_dpad_dir += move_dir)
		btn.button_up.connect(func() -> void: _dpad_dir -= move_dir)

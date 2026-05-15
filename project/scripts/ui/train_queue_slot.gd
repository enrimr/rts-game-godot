extends PanelContainer

class_name TrainQueueSlot

signal cancel_requested(index: int)

var slot_index: int = 0
var _progress_bar: ColorRect = null

func setup(index: int, label: String, color: Color, is_active: bool, is_blocked: bool = false) -> void:
	slot_index = index
	custom_minimum_size = Vector2(40.0, 40.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	if is_blocked:
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_color = Color(1.0, 0.25, 0.25)
	elif is_active:
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_color = Color(1.0, 1.0, 0.3)
	add_theme_stylebox_override("panel", style)

	# Single child for PanelContainer to avoid layout doubling
	var overlay: Control = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.clip_contents = true
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	if is_active:
		_progress_bar = ColorRect.new()
		_progress_bar.color = Color(0.0, 0.0, 0.0, 0.45)
		_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(_progress_bar)
		set_progress(0.0)

	var lbl: Label = Label.new()
	lbl.text = label if not is_blocked else label + "\n!"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_blocked:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	overlay.add_child(lbl)

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

## p: 0.0 (not started) → 1.0 (complete). Overlay shrinks from top as progress grows.
func set_progress(p: float) -> void:
	if not is_instance_valid(_progress_bar):
		return
	_progress_bar.anchor_top    = clampf(p, 0.0, 1.0)
	_progress_bar.anchor_bottom = 1.0

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			cancel_requested.emit(slot_index)

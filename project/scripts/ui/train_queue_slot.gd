extends PanelContainer

class_name TrainQueueSlot

signal cancel_requested(index: int)

var slot_index: int = 0

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

	var lbl: Label = Label.new()
	lbl.text = label if not is_blocked else label + "\n!"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_blocked:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	add_child(lbl)

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			cancel_requested.emit(slot_index)

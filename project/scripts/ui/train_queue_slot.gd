extends PanelContainer

class_name TrainQueueSlot

signal cancel_requested(index: int)

var slot_index: int = 0
var _progress_bar: ColorRect = null

func setup(index: int, label: String, color: Color, is_active: bool,
		is_blocked: bool = false, icon: Texture2D = null) -> void:
	slot_index = index
	custom_minimum_size = Vector2(50.0, 50.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	# With an entity icon the colour drops to a dark backdrop (like the
	# selection portraits); letter-only slots keep the full colour block.
	style.bg_color = color.darkened(0.55) if icon != null else color
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

	if icon != null:
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = icon
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 2.0
		icon_rect.offset_right = -2.0
		icon_rect.offset_top = 2.0
		icon_rect.offset_bottom = -2.0
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(icon_rect)

	if is_active:
		_progress_bar = ColorRect.new()
		_progress_bar.color = Color(0.0, 0.0, 0.0, 0.45)
		_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(_progress_bar)
		set_progress(0.0)

	# With an icon the letter is redundant — keep only the blocked "!" badge.
	if icon == null or is_blocked:
		var lbl: Label = Label.new()
		if icon != null:
			lbl.text = "!"
		else:
			lbl.text = label if not is_blocked else label + "\n!"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 18)
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

class_name ActionButton
extends Button

signal action_pressed(action_id: String)

const ICON_DIM: Color = Color(0.45, 0.45, 0.45)

@export var action_id: String = ""

var _icon_rect: TextureRect = null
var _name_label: Label = null
var _icon_label: Label = null   # secondary line: hotkey (+ queue badge)
var _icon_caption: String = ""

func _ready() -> void:
	pressed.connect(func() -> void: action_pressed.emit(action_id))
	custom_minimum_size = Vector2(60.0, 44.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 14)
	focus_mode = FOCUS_NONE

## Entity-creating actions (train unit / build building) show the runtime-baked
## entity icon on the LEFT with the name and hotkey beside it — the wide-button
## layout gives the icon twice the surface of the old stacked one.
func set_entity_icon(texture: Texture2D, entity_name: String, key_hint: String = "") -> void:
	text = ""
	custom_minimum_size = Vector2(130.0, 56.0)
	if _icon_rect == null:
		_build_icon_layout()
	_icon_rect.texture = texture
	_icon_caption = key_hint
	_name_label.text = entity_name
	_icon_label.text = key_hint

func has_entity_icon() -> bool:
	return _icon_rect != null

## Queue counter shown next to the caption on icon buttons (train actions);
## text-only buttons keep composing Button.text in the HUD manager instead.
func set_train_queue_badge(queued: int, max_queue: int) -> void:
	if _icon_rect == null:
		return
	if queued <= 0:
		_icon_label.text = _icon_caption
	else:
		_icon_label.text = "%s  %d/%d" % [_icon_caption, queued, max_queue]

## Dims the icon overlay together with the button's disabled state. No-op for
## text-only buttons.
func set_icon_enabled(enabled: bool) -> void:
	if _icon_rect == null:
		return
	var tint: Color = Color.WHITE if enabled else ICON_DIM
	_icon_rect.modulate = tint
	_name_label.modulate = tint
	_icon_label.modulate = tint * Color(1.0, 1.0, 1.0, 0.75)

func _build_icon_layout() -> void:
	var layout: HBoxContainer = HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 5.0
	layout.offset_right = -5.0
	layout.offset_top = 4.0
	layout.offset_bottom = -4.0
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 7)
	add_child(layout)

	_icon_rect = TextureRect.new()
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.custom_minimum_size = Vector2(46.0, 46.0)
	_icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_icon_rect)

	var text_col: VBoxContainer = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_theme_constant_override("separation", 0)
	layout.add_child(text_col)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_name_label)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_icon_label.add_theme_font_size_override("font_size", 10)
	_icon_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_icon_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_icon_label)

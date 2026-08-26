class_name ActionButton
extends Button

signal action_pressed(action_id: String)

const ICON_DIM: Color = Color(0.45, 0.45, 0.45)

@export var action_id: String = ""

var _icon_rect: TextureRect = null
var _icon_label: Label = null
var _icon_caption: String = ""

func _ready() -> void:
	pressed.connect(func() -> void: action_pressed.emit(action_id))
	custom_minimum_size = Vector2(60.0, 44.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 14)
	focus_mode = FOCUS_NONE

## Entity-creating actions (train unit / build building) show the runtime-baked
## entity icon on top with a short caption below; plain actions keep the
## default button text.
func set_entity_icon(texture: Texture2D, caption: String) -> void:
	text = ""
	custom_minimum_size = Vector2(64.0, 64.0)
	if _icon_rect == null:
		_build_icon_layout()
	_icon_rect.texture = texture
	_icon_caption = caption
	_icon_label.text = caption

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
	_icon_label.modulate = tint

func _build_icon_layout() -> void:
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_top = 3.0
	layout.offset_bottom = -2.0
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 1)
	add_child(layout)

	_icon_rect = TextureRect.new()
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_icon_rect)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 10)
	_icon_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_icon_label)

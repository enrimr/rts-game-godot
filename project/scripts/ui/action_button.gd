class_name ActionButton
extends Button

signal action_pressed(action_id: String)

const ICON_DIM: Color = Color(0.45, 0.45, 0.45)

@export var action_id: String = ""

var _icon_rect: TextureRect = null
var _name_label: Label = null   # single line: "Name  [Key]" (+ queue badge)
var _icon_caption: String = ""

func _ready() -> void:
	pressed.connect(func() -> void: action_pressed.emit(action_id))
	# set_entity_icon may run before _ready (buttons are configured before
	# add_child) — don't clobber the wide icon-layout minimum it already set.
	if _icon_rect == null:
		custom_minimum_size = Vector2(64.0, 48.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 16)
	HudStyle.add_text_outline(self)
	focus_mode = FOCUS_NONE

## Entity-creating actions (train unit / build building) show the runtime-baked
## entity icon on the LEFT with the name and hotkey beside it — the wide-button
## layout gives the icon twice the surface of the old stacked one.
func set_entity_icon(texture: Texture2D, entity_name: String, key_hint: String = "") -> void:
	text = ""
	custom_minimum_size = Vector2(195.0, 62.0)
	if _icon_rect == null:
		_build_icon_layout()
	_icon_rect.texture = texture
	_icon_caption = "%s  %s" % [entity_name, key_hint] if not key_hint.is_empty() else entity_name
	_name_label.text = _icon_caption

func has_entity_icon() -> bool:
	return _icon_rect != null

## Queue counter shown next to the caption on icon buttons (train actions);
## text-only buttons keep composing Button.text in the HUD manager instead.
func set_train_queue_badge(queued: int, max_queue: int) -> void:
	if _icon_rect == null:
		return
	if queued <= 0:
		_name_label.text = _icon_caption
	else:
		_name_label.text = "%s  %d/%d" % [_icon_caption, queued, max_queue]

## Dims the icon overlay together with the button's disabled state. No-op for
## text-only buttons.
func set_icon_enabled(enabled: bool) -> void:
	if _icon_rect == null:
		return
	var tint: Color = Color.WHITE if enabled else ICON_DIM
	_icon_rect.modulate = tint
	_name_label.modulate = tint

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
	_icon_rect.custom_minimum_size = Vector2(52.0, 52.0)
	# Fixed square, centered — never stretched, never outside the button.
	_icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_icon_rect)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.size_flags_vertical = Control.SIZE_FILL
	_name_label.add_theme_font_size_override("font_size", 16)
	HudStyle.add_text_outline(_name_label)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_name_label)

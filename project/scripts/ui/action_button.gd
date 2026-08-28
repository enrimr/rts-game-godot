class_name ActionButton
extends Button

## Uniform square command button for the HUD action grid.
##
## Every command renders the same way: a dark neutral well, a centered glyph
## (procedural UiIcons texture) or entity miniature (IconBaker), a small
## hotkey badge top-left and an optional count/cooldown badge bottom-right.
## The action category shows only as a thin accent edge along the bottom.
## Full names, costs and descriptions belong in the tooltip.

signal action_pressed(action_id: String)

const BTN_SIZE: Vector2 = Vector2(64.0, 64.0)
const GLYPH_INSET: float = 9.0
const ENTITY_INSET: float = 5.0
const ICON_DIM: Color = Color(0.42, 0.42, 0.42)
const UPGRADE_GOLD: Color = Color(0.85, 0.72, 0.10)

@export var action_id: String = ""
## Resource costs shown as a glyph row inside this button's tooltip popup.
var action_costs: Dictionary = {}

var _accent: Color = HudStyle.ACCENT_UTILITY
var _enabled_look: bool = true
var _active: bool = false
var _upgrade: bool = false

var _icon_rect: TextureRect = null
var _abbr_label: Label = null
var _key_label: Label = null
var _badge_label: Label = null

func _ready() -> void:
	pressed.connect(func() -> void: action_pressed.emit(action_id))
	custom_minimum_size = BTN_SIZE
	text = ""
	focus_mode = FOCUS_NONE
	_ensure_layout()
	_restyle()

## Procedural command glyph (UiIcons texture), centered.
func set_glyph(texture: Texture2D) -> void:
	_ensure_layout()
	_icon_rect.texture = texture
	_set_icon_inset(GLYPH_INSET)
	_abbr_label.visible = false

## Entity miniature (IconBaker render) for train/build/hire actions — slightly
## larger inset so the figure fills the square like the selection portraits.
func set_entity_icon(texture: Texture2D) -> void:
	_ensure_layout()
	_icon_rect.texture = texture
	_set_icon_inset(ENTITY_INSET)
	_abbr_label.visible = false

func has_entity_icon() -> bool:
	return _icon_rect != null and _icon_rect.texture != null

## Fallback for actions without a glyph: a short 2-3 letter code (full name
## stays in the tooltip).
func set_abbreviation(abbr: String) -> void:
	_ensure_layout()
	_icon_rect.texture = null
	_abbr_label.text = abbr
	_abbr_label.visible = true

## Small hotkey badge in the top-left corner ("" hides it).
func set_hotkey(key_hint: String) -> void:
	_ensure_layout()
	_key_label.text = key_hint
	_key_label.visible = not key_hint.is_empty()

## Small badge bottom-right: train-queue count, cooldown seconds... ("" hides).
func set_badge(badge: String) -> void:
	_ensure_layout()
	_badge_label.text = badge
	_badge_label.visible = not badge.is_empty()

func set_train_queue_badge(queued: int, _max_queue: int) -> void:
	set_badge(str(queued) if queued > 0 else "")

## Category accent colour shown as the bottom edge.
func set_accent(accent: Color) -> void:
	_accent = accent
	_restyle()

## Disables the button and dims the icon together.
func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	_enabled_look = enabled
	var tint: Color = Color.WHITE if enabled else ICON_DIM
	if _icon_rect != null:
		_icon_rect.modulate = tint
	if _abbr_label != null:
		_abbr_label.modulate = tint
	_restyle()

## Kept for callers that only re-tint (legacy name).
func set_icon_enabled(enabled: bool) -> void:
	set_enabled(enabled)

## Highlight for pending map-click actions and on-toggles (explore, follow).
func set_active(active: bool) -> void:
	_active = active
	_restyle()

## Gold frame marking unit-upgrade researches.
func set_upgrade(upgrade: bool) -> void:
	_upgrade = upgrade
	_restyle()

# ── Private ───────────────────────────────────────────────────────────────────

func _set_icon_inset(inset: float) -> void:
	_icon_rect.offset_left = inset
	_icon_rect.offset_top = inset
	_icon_rect.offset_right = -inset
	_icon_rect.offset_bottom = -inset

func _ensure_layout() -> void:
	if _icon_rect != null:
		return
	_icon_rect = TextureRect.new()
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_icon_inset(GLYPH_INSET)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	_abbr_label = Label.new()
	_abbr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_abbr_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_abbr_label.add_theme_font_size_override("font_size", 17)
	HudStyle.add_text_outline(_abbr_label, 4)
	_abbr_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_abbr_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_abbr_label.visible = false
	add_child(_abbr_label)

	_key_label = Label.new()
	_key_label.add_theme_font_size_override("font_size", 11)
	_key_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
	HudStyle.add_text_outline(_key_label, 3)
	_key_label.position = Vector2(4.0, 2.0)
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_label.visible = false
	add_child(_key_label)

	_badge_label = Label.new()
	_badge_label.add_theme_font_size_override("font_size", 13)
	_badge_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	HudStyle.add_text_outline(_badge_label, 3)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_badge_label.anchor_left = 1.0
	_badge_label.anchor_top = 1.0
	_badge_label.anchor_right = 1.0
	_badge_label.anchor_bottom = 1.0
	_badge_label.offset_left = -30.0
	_badge_label.offset_top = -20.0
	_badge_label.offset_right = -5.0
	_badge_label.offset_bottom = -2.0
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.visible = false
	add_child(_badge_label)

func _restyle() -> void:
	var accent: Color = UPGRADE_GOLD if _upgrade else _accent
	var base_state: String = "active" if _active else "normal"
	var normal: StyleBoxFlat = HudStyle.command_button(accent, base_state)
	var hover: StyleBoxFlat = HudStyle.command_button(accent, "active" if _active else "hover")
	if _active:
		hover.bg_color = hover.bg_color.lightened(0.08)
	if _upgrade and not _active:
		normal.border_width_left = 2
		normal.border_width_right = 2
		normal.border_width_top = 2
		hover.border_width_left = 2
		hover.border_width_right = 2
		hover.border_width_top = 2
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", HudStyle.command_button(accent, "pressed"))
	add_theme_stylebox_override("disabled", HudStyle.command_button(accent, "disabled"))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

## Rich tooltip: the plain tooltip text plus the cost as a glyph row
## (wood-log 25 instead of "25 Wood"), rendered inside the hover popup.
func _make_custom_tooltip(for_text: String) -> Object:
	if action_costs.is_empty():
		return null   # default text tooltip
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if not for_text.strip_edges().is_empty():
		var lbl: Label = Label.new()
		lbl.text = for_text
		lbl.add_theme_font_size_override("font_size", 13)
		box.add_child(lbl)
	box.add_child(UiIcons.cost_row(action_costs, 16.0, 14))
	return box

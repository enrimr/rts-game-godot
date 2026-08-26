class_name HudStyle
extends RefCounted

## Shared StyleBoxFlat factory for HUD panels and buttons. Extracted from
## hud_manager so the split-out HUD components (stats, menus) share one source.

static func panel(bg: Color, radius: int = 8) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s

## Warm command-bar chrome for the bottom HUD strip: dark leather tone with a
## bronze top edge, so the bar reads as designed furniture even when empty.
static func command_bar() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.155, 0.125, 0.095, 0.98)
	s.border_color = Color(0.52, 0.42, 0.25)
	s.border_width_top = 2
	s.border_blend = true
	return s

## Recessed inner well framing the portraits + action grid area.
static func command_well() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.075, 0.06, 0.05, 0.9)
	s.border_color = Color(0.36, 0.29, 0.17)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	return s

## Overlays a subtle vertical light-to-shade gradient on a panel (procedural
## GradientTexture2D, no external assets). Drawn behind existing children.
static var _bold_font: FontVariation = null

## Synthetic bold of the default UI font: the outline eats into thin white
## glyphs, so outlined text needs the extra stroke weight to stay bright.
static func bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = ThemeDB.fallback_font
		_bold_font.variation_embolden = 0.85
	return _bold_font

## Dark font outline + bold weight so text stays readable over ANY
## background colour — white on yellow/light action buttons was washing out.
static func add_text_outline(ctrl: Control, size: int = 5) -> void:
	ctrl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	ctrl.add_theme_constant_override("outline_size", size)
	ctrl.add_theme_font_override("font", bold_font())

static func add_top_sheen(panel: Control, strength: float = 0.10) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.88, 0.62, strength),
		Color(1.0, 0.88, 0.62, 0.015),
		Color(0.0, 0.0, 0.0, 0.10),
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	var sheen: TextureRect = TextureRect.new()
	sheen.name = "PanelSheen"
	sheen.texture = tex
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(sheen)
	panel.move_child(sheen, 0)

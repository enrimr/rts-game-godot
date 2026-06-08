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

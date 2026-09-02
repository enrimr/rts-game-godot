class_name HudFpsCounter extends Node

## Small FPS readout under the top bar, right side. Off by default; toggled
## live from the settings panel (GameSettings.show_fps). Colour grades the
## number so a struggling match reads at a glance: green ≥50, amber ≥25,
## red below.

const REFRESH_SEC: float = 0.25

var _label: Label = null
var _accum: float = 0.0

func init(hud_root: Node) -> void:
	_label = Label.new()
	_label.text = ""
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -110.0
	_label.offset_top = 64.0
	_label.offset_bottom = 86.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_label)
	_label.visible = GameSettings.show_fps

func _process(delta: float) -> void:
	if not GameSettings.show_fps:
		if _label.visible:
			_label.visible = false
		return
	_label.visible = true
	_accum += delta
	if _accum < REFRESH_SEC:
		return
	_accum = 0.0
	var fps: float = Engine.get_frames_per_second()
	_label.text = "%d FPS" % int(fps)
	var color: Color = Color(0.55, 0.90, 0.55)
	if fps < 25.0:
		color = Color(0.95, 0.45, 0.40)
	elif fps < 50.0:
		color = Color(0.95, 0.82, 0.45)
	_label.add_theme_color_override("font_color", color)

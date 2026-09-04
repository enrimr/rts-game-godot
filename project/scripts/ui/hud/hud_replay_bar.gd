class_name HudReplayBar
extends Control

## Replay spectator controls, mounted by GameWorld only in replay mode: a
## bottom-center strip with pause/play, a seekable timeline (drag anywhere —
## forward fast-forwards in place, backward reboots the mirror world and
## fast-forwards from zero), the clock, playback speed, and the "reveal all"
## toggle that lifts the spectator's player-0 fog.

var _replicator: StateReplicator = null
var _fog: CanvasItem = null
var _minimap: MinimapRenderer = null

var _slider: HSlider = null
var _time_label: Label = null
var _pause_btn: Button = null
var _speed_btn: Button = null
var _dragging: bool = false
var _speed_idx: int = 0

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

func init(hud_root: Control, replicator: StateReplicator,
		fog: CanvasItem, minimap: MinimapRenderer) -> void:
	_replicator = replicator
	_fog = fog
	_minimap = minimap

	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -320.0
	offset_right = 320.0
	offset_top = 8.0
	offset_bottom = 56.0
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		HudStyle.panel(Color(0.07, 0.08, 0.11, 0.92)))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var badge: Label = Label.new()
	badge.text = tr("REPLAY_BADGE")
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.93, 0.80, 0.45))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	_pause_btn = Button.new()
	_pause_btn.text = "❙❙"
	_pause_btn.custom_minimum_size = Vector2(38, 30)
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(_toggle_pause)
	row.add_child(_pause_btn)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.001
	_slider.custom_minimum_size = Vector2(280, 30)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(_on_seek)
	row.add_child(_slider)

	_time_label = Label.new()
	_time_label.text = "0:00 / 0:00"
	_time_label.add_theme_font_size_override("font_size", 13)
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_time_label)

	_speed_btn = Button.new()
	_speed_btn.text = "×1"
	_speed_btn.custom_minimum_size = Vector2(44, 30)
	_speed_btn.focus_mode = Control.FOCUS_NONE
	_speed_btn.pressed.connect(_cycle_speed)
	row.add_child(_speed_btn)

	var reveal: CheckButton = CheckButton.new()
	reveal.text = tr("REPLAY_VIEW_ALL")
	reveal.add_theme_font_size_override("font_size", 13)
	reveal.focus_mode = Control.FOCUS_NONE
	reveal.toggled.connect(_set_reveal_all)
	row.add_child(reveal)

	hud_root.add_child(self)

func _process(_delta: float) -> void:
	if _replicator == null or not is_instance_valid(_replicator):
		return
	var total: float = maxf(_replicator.replay_duration(), 0.001)
	if not _dragging:
		_slider.set_value_no_signal(_replicator.replay_time() / total)
	_time_label.text = "%s / %s" % [_fmt(_replicator.replay_time()), _fmt(total)]
	if _replicator.replay_finished():
		_pause_btn.text = "■"

func _fmt(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

func _on_seek(changed: bool) -> void:
	_dragging = false
	if changed and is_instance_valid(_replicator):
		_replicator.seek((_slider.value as float) * _replicator.replay_duration())

func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	_pause_btn.text = "▶" if paused else "❙❙"

## The bar must keep working while the tree is paused, or play never resumes.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _cycle_speed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[_speed_idx]
	_speed_btn.text = "×%d" % int(SPEEDS[_speed_idx])

## Spectator omniscience: hide the fog overlay and unhook it from the
## minimap. Toggling back restores the player-0 perspective untouched —
## the fog kept computing underneath all along.
func _set_reveal_all(on: bool) -> void:
	if is_instance_valid(_fog):
		_fog.visible = not on
	if is_instance_valid(_minimap):
		_minimap.fog = null if on else (_fog as FogOfWar)

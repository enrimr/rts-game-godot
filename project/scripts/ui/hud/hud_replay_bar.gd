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
var _hud_root: Control = null
var _cine: bool = false
var _panel: PanelContainer = null
var _watermark: TextureRect = null
var _bar_idle: float = 0.0
var _finished_for: float = 0.0
## Optional floating minimap while cinematic: the minimap lives inside the
## (hidden) command bar, so showing it alone means temporarily reparenting
## it to the HUD root and pinning it to the bottom-right corner.
var _mini_in_cine: bool = false
var _mini_home: Node = null
var _mini_index: int = 0
var _mini_pos: Vector2 = Vector2.ZERO
var _mini_size: Vector2 = Vector2.ZERO
## A video-export run has no operator: the bar must never enter the frame
## (the headless mouse sits at (0,0), which reads as "near the top edge").
var _export_run: bool = false

## Global flag other HUD pieces that re-assert their own visibility every
## frame (the FPS counter) must respect.
static var cinematic_active: bool = false

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
## In cinematic mode the bar hides after this long without the mouse near it.
const BAR_HIDE_SEC: float = 2.0

func init(hud_root: Control, replicator: StateReplicator,
		fog: CanvasItem, minimap: MinimapRenderer) -> void:
	_replicator = replicator
	_fog = fog
	_minimap = minimap
	_hud_root = hud_root

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
	_panel = panel
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

	var cine: Button = Button.new()
	cine.text = tr("REPLAY_CINEMATIC")
	cine.custom_minimum_size = Vector2(0, 30)
	cine.focus_mode = Control.FOCUS_NONE
	cine.pressed.connect(func() -> void: _set_cinematic(not _cine))
	row.add_child(cine)

	var mini: CheckButton = CheckButton.new()
	mini.text = tr("REPLAY_CINE_MINIMAP")
	mini.add_theme_font_size_override("font_size", 13)
	mini.focus_mode = Control.FOCUS_NONE
	mini.toggled.connect(func(on: bool) -> void:
		_mini_in_cine = on
		if _cine:
			_float_minimap() if on else _restore_minimap())
	row.add_child(mini)
	if OS.get_environment("CALIMA_CINE_MINIMAP") == "1":
		_mini_in_cine = true
		mini.set_pressed_no_signal(true)

	hud_root.add_child(self)
	_build_watermark()
	_show_intro_card()
	# A video-export run is hands-free: cinematic from frame one, reveal-all
	# for the spectacle, quit when the story ends.
	if OS.has_feature("movie") or OS.get_environment("CALIMA_CINE") == "1":
		_export_run = true
		_set_reveal_all(true)
		reveal.set_pressed_no_signal(true)
		_set_cinematic(true)
		_panel.visible = false

## ── Creator mode ─────────────────────────────────────────────────────────────

## Cinematic: every HUD element hides except this bar (which fades unless the
## mouse visits the top edge) and a small logo watermark — clean footage with
## brand attribution built in. C toggles it too.
func _set_cinematic(on: bool) -> void:
	_cine = on
	cinematic_active = on
	for child: Node in _hud_root.get_children():
		if child == self or child == _minimap or not (child is CanvasItem):
			continue
		(child as CanvasItem).visible = not on
	if is_instance_valid(_watermark):
		_watermark.visible = on
	if on and _mini_in_cine:
		_float_minimap()
	elif not on:
		_restore_minimap()
	_bar_idle = 0.0
	_panel.visible = true

func _float_minimap() -> void:
	if not is_instance_valid(_minimap) or _mini_home != null:
		if is_instance_valid(_minimap):
			_minimap.visible = true
		return
	_mini_home = _minimap.get_parent()
	_mini_index = _minimap.get_index()
	_mini_pos = _minimap.position
	_mini_size = _minimap.size
	_mini_home.remove_child(_minimap)
	_hud_root.add_child(_minimap)
	# Outside its container the anchors would stretch it across the screen:
	# pin it top-left-anchored at its ORIGINAL size, docked bottom-right.
	_minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_minimap.size = _mini_size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_minimap.position = vp - _mini_size - Vector2(14.0, 14.0)
	_minimap.visible = true
	# The corner is taken now — the watermark steps aside to bottom-left.
	if is_instance_valid(_watermark):
		_watermark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_watermark.offset_left = 16.0
		_watermark.offset_top = -84.0
		_watermark.offset_right = 166.0
		_watermark.offset_bottom = -16.0

func _restore_minimap() -> void:
	if not is_instance_valid(_minimap):
		return
	if _mini_home != null:
		_hud_root.remove_child(_minimap)
		_mini_home.add_child(_minimap)
		_mini_home.move_child(_minimap, _mini_index)
		_minimap.size = _mini_size
		_minimap.position = _mini_pos
		_mini_home = null
	_minimap.visible = true
	if is_instance_valid(_watermark):
		_watermark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_watermark.offset_left = -166.0
		_watermark.offset_top = -84.0
		_watermark.offset_right = -16.0
		_watermark.offset_bottom = -16.0

func _unhandled_key_input(event: InputEvent) -> void:
	var ke: InputEventKey = event as InputEventKey
	if ke != null and ke.pressed and not ke.echo and ke.physical_keycode == KEY_C:
		_set_cinematic(not _cine)

func _build_watermark() -> void:
	_watermark = TextureRect.new()
	_watermark.texture = load("res://assets/backgrounds/calima-fota-logo.png") as Texture2D
	_watermark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_watermark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_watermark.custom_minimum_size = Vector2(150, 68)
	_watermark.modulate = Color(1, 1, 1, 0.5)
	_watermark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_watermark.offset_left = -166.0
	_watermark.offset_top = -84.0
	_watermark.offset_right = -16.0
	_watermark.offset_bottom = -16.0
	_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watermark.visible = false
	_hud_root.add_child(_watermark)

## Title card over the first seconds: logo, matchup, map and date — every
## shared clip opens introducing the game and the match.
func _show_intro_card() -> void:
	var header: Dictionary = ReplayFile.active_header
	var cfg: Dictionary = header.get("config", {}) as Dictionary
	var card: VBoxContainer = VBoxContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.add_theme_constant_override("separation", 10)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://assets/backgrounds/calima-fota-logo.png") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(420, 190)
	card.add_child(logo)
	var rivals: Array = cfg.get("rival_civ_ids", []) as Array
	var line: Label = Label.new()
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(header.get("timestamp", 0) as int)
	line.text = "%s  vs  %s\n%02d/%02d/%04d" % [
		str(cfg.get("player_civ_id", "?")).capitalize(),
		", ".join(rivals.map(func(c: Variant) -> String: return str(c).capitalize())),
		dt.get("day", 0), dt.get("month", 0), dt.get("year", 0)]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 24)
	line.add_theme_font_override("font", HudStyle.bold_font())
	HudStyle.add_text_outline(line)
	card.add_child(line)
	_hud_root.add_child(card)
	var tween: Tween = create_tween()
	tween.tween_interval(3.2)
	tween.tween_property(card, "modulate:a", 0.0, 0.8)
	tween.tween_callback(card.queue_free)

func _process(delta: float) -> void:
	if _replicator == null or not is_instance_valid(_replicator):
		return
	var total: float = maxf(_replicator.replay_duration(), 0.001)
	if not _dragging:
		_slider.set_value_no_signal(_replicator.replay_time() / total)
	_time_label.text = "%s / %s" % [_fmt(_replicator.replay_time()), _fmt(total)]
	if _replicator.replay_finished():
		_pause_btn.text = "■"
		# Export runs end themselves two beats after the last packet.
		if OS.has_feature("movie"):
			_finished_for += delta
			if _finished_for > 2.0:
				get_tree().quit()
	if _cine:
		if _export_run:
			_panel.visible = false
		else:
			var near_top: bool = get_viewport().get_mouse_position().y < 90.0
			_bar_idle = 0.0 if near_top or _dragging else _bar_idle + delta
			_panel.visible = near_top or _dragging or _bar_idle < BAR_HIDE_SEC

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

func _exit_tree() -> void:
	cinematic_active = false

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

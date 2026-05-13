class_name TutorialOverlay
extends Control

signal finished

const STEPS: Array[Dictionary] = [
	{"title": "TUTORIAL_STEP0_TITLE", "body": "TUTORIAL_STEP0_BODY"},
	{"title": "TUTORIAL_STEP1_TITLE", "body": "TUTORIAL_STEP1_BODY"},
	{"title": "TUTORIAL_STEP2_TITLE", "body": "TUTORIAL_STEP2_BODY"},
	{"title": "TUTORIAL_STEP3_TITLE", "body": "TUTORIAL_STEP3_BODY"},
	{"title": "TUTORIAL_STEP4_TITLE", "body": "TUTORIAL_STEP4_BODY"},
	{"title": "TUTORIAL_STEP5_TITLE", "body": "TUTORIAL_STEP5_BODY"},
	{"title": "TUTORIAL_STEP6_TITLE", "body": "TUTORIAL_STEP6_BODY"},
	{"title": "TUTORIAL_STEP7_TITLE", "body": "TUTORIAL_STEP7_BODY"},
	{"title": "TUTORIAL_STEP8_TITLE", "body": "TUTORIAL_STEP8_BODY"},
	{"title": "TUTORIAL_STEP9_TITLE", "body": "TUTORIAL_STEP9_BODY"},
]

var _current_step: int = 0

var _card: PanelContainer = null
var _step_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _back_btn: Button = null
var _skip_btn: Button = null
var _next_btn: Button = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_card()

func _build_card() -> void:
	# Outer VBox fills the full rect: spacer pushes card to bottom-center
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(spacer)

	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(center)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(pad)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(600.0, 0.0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.07, 0.10, 0.93)
	panel_style.corner_radius_top_left     = 8
	panel_style.corner_radius_top_right    = 8
	panel_style.corner_radius_bottom_left  = 8
	panel_style.corner_radius_bottom_right = 8
	_card.add_theme_stylebox_override("panel", panel_style)
	pad.add_child(_card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header row: step indicator left, title right
	var header_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(header_row)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 13)
	_step_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_step_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header_row.add_child(_step_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	header_row.add_child(_title_label)

	vbox.add_child(HSeparator.new())

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(0.0, 80.0)
	vbox.add_child(_body_label)

	vbox.add_child(HSeparator.new())

	# Buttons row
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_back_btn = Button.new()
	_back_btn.text = tr("TUTORIAL_BACK")
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.add_theme_font_size_override("font_size", 15)
	_back_btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0.18, 0.18, 0.25, 0.92)))
	_back_btn.add_theme_stylebox_override("hover",  _make_btn_style(Color(0.28, 0.28, 0.40, 0.95)))
	_back_btn.pressed.connect(func() -> void: _go_to(_current_step - 1))
	btn_row.add_child(_back_btn)

	_skip_btn = Button.new()
	_skip_btn.text = tr("TUTORIAL_SKIP")
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.add_theme_font_size_override("font_size", 15)
	_skip_btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0.35, 0.10, 0.10, 0.92)))
	_skip_btn.add_theme_stylebox_override("hover",  _make_btn_style(Color(0.55, 0.15, 0.15, 0.95)))
	_skip_btn.pressed.connect(close)
	btn_row.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.add_theme_font_size_override("font_size", 15)
	_next_btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0.18, 0.42, 0.18, 0.95)))
	_next_btn.add_theme_stylebox_override("hover",  _make_btn_style(Color(0.26, 0.58, 0.26, 0.95)))
	_next_btn.pressed.connect(_on_next_pressed)
	btn_row.add_child(_next_btn)

func start() -> void:
	visible = true
	_go_to(0)

func close() -> void:
	GameSettings.tutorial_seen = true
	GameSettings.save_settings()
	finished.emit()
	queue_free()

func _go_to(step: int) -> void:
	_current_step = clampi(step, 0, STEPS.size() - 1)
	var total: int = STEPS.size()
	_step_label.text = "%d / %d" % [_current_step + 1, total]
	_title_label.text = tr(STEPS[_current_step]["title"])
	_body_label.text  = tr(STEPS[_current_step]["body"])
	_back_btn.disabled = _current_step == 0
	var is_last: bool = _current_step == total - 1
	_next_btn.text = tr("TUTORIAL_FINISH") if is_last else tr("TUTORIAL_NEXT")

func _on_next_pressed() -> void:
	if _current_step >= STEPS.size() - 1:
		close()
	else:
		_go_to(_current_step + 1)

func _make_btn_style(col: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	return s

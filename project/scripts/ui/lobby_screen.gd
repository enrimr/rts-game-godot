extends Control

class_name LobbyScreen

## LobbyScreen — match configuration screen shown between main menu and game.
## Runs as a full-screen Control added over the main menu, not a separate scene.

signal start_requested
signal back_requested

const CIVS: Array[Dictionary] = [
	{"id": "britons",  "name": "Britons",  "desc_key": "CIV_BRITONS_DESC"},
	{"id": "franks",   "name": "Franks",   "desc_key": "CIV_FRANKS_DESC"},
	{"id": "mongols",  "name": "Mongols",  "desc_key": "CIV_MONGOLS_DESC"},
]

const AGE_KEYS: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]

var _civ_index: int = 0
var _civ_desc_label: Label = null
var _civ_btns: Array[Button] = []

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	# Dark background
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_PASS
	add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_PASS
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(580, 0)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	sty.corner_radius_top_left    = 8
	sty.corner_radius_top_right   = 8
	sty.corner_radius_bottom_left = 8
	sty.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", sty)
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("LOBBY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)

	vbox.add_child(_make_sep())

	# Map size
	vbox.add_child(_make_label(tr("LOBBY_MAP_SIZE")))
	var map_opts: Array[String] = [tr("LOBBY_MAP_SMALL"), tr("LOBBY_MAP_MEDIUM"), tr("LOBBY_MAP_LARGE")]
	vbox.add_child(_make_option_row(map_opts, MatchConfig.map_size,
		func(i: int) -> void: MatchConfig.map_size = i))

	# Resources
	vbox.add_child(_make_label(tr("LOBBY_RESOURCES")))
	var res_opts: Array[String] = [tr("LOBBY_RES_SCARCE"), tr("LOBBY_RES_NORMAL"), tr("LOBBY_RES_ABUNDANT")]
	vbox.add_child(_make_option_row(res_opts, MatchConfig.resources,
		func(i: int) -> void: MatchConfig.resources = i))

	# Starting age
	vbox.add_child(_make_label(tr("LOBBY_STARTING_AGE")))
	var age_opts: Array[String] = []
	for k: String in AGE_KEYS:
		age_opts.append(tr(k))
	vbox.add_child(_make_option_row(age_opts, MatchConfig.starting_age,
		func(i: int) -> void: MatchConfig.starting_age = i))

	# Civilization
	vbox.add_child(_make_label(tr("LOBBY_CIVILIZATION")))
	vbox.add_child(_make_civ_row())

	# Civ description
	_civ_desc_label = Label.new()
	_civ_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_civ_desc_label.add_theme_font_size_override("font_size", 13)
	_civ_desc_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	_civ_desc_label.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(_civ_desc_label)
	_refresh_civ_desc()

	vbox.add_child(_make_sep())

	# Bottom buttons
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var back_btn: Button = _make_btn(tr("LOBBY_BACK"), Color(0.20, 0.20, 0.25, 0.95), Color(0.35, 0.35, 0.40, 0.95))
	back_btn.custom_minimum_size = Vector2(140, 40)
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	btn_row.add_child(back_btn)

	var start_btn: Button = _make_btn(tr("LOBBY_START"), Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	start_btn.custom_minimum_size = Vector2(180, 40)
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(func() -> void: start_requested.emit())
	btn_row.add_child(start_btn)

# --- Civilization row ---

func _make_civ_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_civ_btns.clear()
	for i: int in range(CIVS.size()):
		var civ: Dictionary = CIVS[i] as Dictionary
		var btn: Button = Button.new()
		btn.text = civ["name"] as String
		btn.custom_minimum_size = Vector2(120, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		row.add_child(btn)
		_civ_btns.append(btn)
		var captured_i: int = i
		btn.pressed.connect(func() -> void:
			_civ_index = captured_i
			MatchConfig.player_civ_id = (CIVS[captured_i] as Dictionary)["id"] as String
			_refresh_civ_highlight()
			_refresh_civ_desc()
		)
	_refresh_civ_highlight()
	return row

func _refresh_civ_highlight() -> void:
	for i: int in range(_civ_btns.size()):
		var active: bool = i == _civ_index
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.22, 0.40, 0.55, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9)
		s.corner_radius_top_left    = 4
		s.corner_radius_top_right   = 4
		s.corner_radius_bottom_left = 4
		s.corner_radius_bottom_right = 4
		_civ_btns[i].add_theme_stylebox_override("normal", s)
		_civ_btns[i].add_theme_stylebox_override("pressed", s)

func _refresh_civ_desc() -> void:
	if not is_instance_valid(_civ_desc_label):
		return
	var key: String = (CIVS[_civ_index] as Dictionary)["desc_key"] as String
	_civ_desc_label.text = tr(key)

# --- Option row (segmented button group) ---

func _make_option_row(labels: Array[String], initial: int, on_select: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var btns: Array[Button] = []
	for i: int in range(labels.size()):
		var btn: Button = Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = Vector2(110, 32)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		row.add_child(btn)
		btns.append(btn)

	var refresh: Callable = func() -> void:
		for j: int in range(btns.size()):
			var active: bool = j == _get_btn_value(row, btns, btns[j])
			var s: StyleBoxFlat = StyleBoxFlat.new()
			s.bg_color = Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9)
			s.corner_radius_top_left    = 4
			s.corner_radius_top_right   = 4
			s.corner_radius_bottom_left = 4
			s.corner_radius_bottom_right = 4
			btns[j].add_theme_stylebox_override("normal", s)
			btns[j].add_theme_stylebox_override("pressed", s)

	# Store selected index on the row node as metadata
	row.set_meta("selected", initial)
	_apply_btn_styles(btns, initial)

	for i: int in range(labels.size()):
		var captured_i: int = i
		btns[i].pressed.connect(func() -> void:
			row.set_meta("selected", captured_i)
			on_select.call(captured_i)
			_apply_btn_styles(btns, captured_i)
		)
	return row

func _apply_btn_styles(btns: Array[Button], selected: int) -> void:
	for j: int in range(btns.size()):
		var active: bool = j == selected
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9)
		s.corner_radius_top_left    = 4
		s.corner_radius_top_right   = 4
		s.corner_radius_bottom_left = 4
		s.corner_radius_bottom_right = 4
		btns[j].add_theme_stylebox_override("normal", s)
		btns[j].add_theme_stylebox_override("pressed", s)

func _get_btn_value(_row: HBoxContainer, _btns: Array[Button], _btn: Button) -> int:
	return 0  # unused — styles applied directly

# --- Helpers ---

func _make_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	return lbl

func _make_sep() -> HSeparator:
	return HSeparator.new()

func _make_btn(text: String, normal_col: Color, hover_col: Color) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = normal_col
	s.corner_radius_top_left    = 4
	s.corner_radius_top_right   = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", s)
	var hs: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	hs.bg_color = hover_col
	btn.add_theme_stylebox_override("hover", hs)
	return btn

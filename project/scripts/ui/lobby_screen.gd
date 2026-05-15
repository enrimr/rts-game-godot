extends Control

class_name LobbyScreen

signal start_requested
signal back_requested

const CIVS: Array[Dictionary] = [
	{"id": "guanches",    "name_key": "CIV_GUANCHES_NAME",    "desc_key": "CIV_GUANCHES_DESC"},
	{"id": "canarii",     "name_key": "CIV_CANARII_NAME",     "desc_key": "CIV_CANARII_DESC"},
	{"id": "mahos",       "name_key": "CIV_MAHOS_NAME",       "desc_key": "CIV_MAHOS_DESC"},
	{"id": "franks",      "name_key": "CIV_FRANKS_NAME",      "desc_key": "CIV_FRANKS_DESC"},
	{"id": "britons",     "name_key": "CIV_BRITONS_NAME",     "desc_key": "CIV_BRITONS_DESC"},
	{"id": "castellanos", "name_key": "CIV_CASTELLANOS_NAME", "desc_key": "CIV_CASTELLANOS_DESC"},
	{"id": "atlantes",    "name_key": "CIV_ATLANTES_NAME",    "desc_key": "CIV_ATLANTES_DESC"},
	{"id": "fenicios",    "name_key": "CIV_FENICIOS_NAME",    "desc_key": "CIV_FENICIOS_DESC"},
]

const AGE_KEYS: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]
const DEFAULT_RIVAL_CIVS: Array[String] = ["castellanos", "franks", "atlantes"]

var _player_civ_index: int = 0
var _rival_civ_indices: Array[int] = [0, 0, 0]
var _rivals_section: VBoxContainer = null
var _scroll: ScrollContainer = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_init_rival_state()
	_build()

func _init_rival_state() -> void:
	for i: int in range(3):
		var civ_id: String = DEFAULT_RIVAL_CIVS[i] if i < DEFAULT_RIVAL_CIVS.size() else "castellanos"
		_rival_civ_indices[i] = _civ_index_for_id(civ_id)
	_sync_rival_config_to_match()

func _civ_index_for_id(id: String) -> int:
	for i: int in range(CIVS.size()):
		if (CIVS[i] as Dictionary)["id"] as String == id:
			return i
	return 0

func _sync_rival_config_to_match() -> void:
	MatchConfig.rival_civ_ids.clear()
	for i: int in range(MatchConfig.rival_count):
		MatchConfig.rival_civ_ids.append(
			(CIVS[_rival_civ_indices[i]] as Dictionary)["id"] as String)

func _build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_PASS
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var outer_center: CenterContainer = CenterContainer.new()
	outer_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll.add_child(outer_center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(820, 0)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	sty.corner_radius_top_left    = 8
	sty.corner_radius_top_right   = 8
	sty.corner_radius_bottom_left = 8
	sty.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", sty)
	outer_center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("LOBBY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(_make_sep())

	# Two-column layout
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	vbox.add_child(columns)

	# --- Left column: game settings ---
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 10)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_col)

	var type_opts: Array[String] = [
		tr("LOBBY_MAPTYPE_PLAINS"), tr("LOBBY_MAPTYPE_STANDARD"),
		tr("LOBBY_MAPTYPE_VOLCANIC"), tr("LOBBY_MAPTYPE_DESERT"), tr("LOBBY_MAPTYPE_ISLANDS"),
	]
	left_col.add_child(_make_inline_row(tr("LOBBY_MAP_TYPE"),
		_make_option_row(type_opts, MatchConfig.map_type,
			func(i: int) -> void: MatchConfig.map_type = i)))

	var size_opts: Array[String] = [tr("LOBBY_MAP_SMALL"), tr("LOBBY_MAP_MEDIUM"), tr("LOBBY_MAP_LARGE")]
	left_col.add_child(_make_inline_row(tr("LOBBY_MAP_SIZE"),
		_make_option_row(size_opts, MatchConfig.map_size,
			func(i: int) -> void: MatchConfig.map_size = i)))

	var res_opts: Array[String] = [tr("LOBBY_RES_SCARCE"), tr("LOBBY_RES_NORMAL"), tr("LOBBY_RES_ABUNDANT"), tr("LOBBY_RES_FULL_COMBAT")]
	left_col.add_child(_make_inline_row(tr("LOBBY_RESOURCES"),
		_make_option_row(res_opts, MatchConfig.resources,
			func(i: int) -> void: MatchConfig.resources = i)))

	var age_opts: Array[String] = []
	for k: String in AGE_KEYS:
		age_opts.append(tr(k))
	left_col.add_child(_make_inline_row(tr("LOBBY_STARTING_AGE"),
		_make_option_row(age_opts, MatchConfig.starting_age,
			func(i: int) -> void: MatchConfig.starting_age = i)))

	var rival_opts: Array[String] = ["1", "2", "3"]
	left_col.add_child(_make_inline_row(tr("LOBBY_RIVAL_COUNT"),
		_make_option_row(rival_opts, MatchConfig.rival_count - 1,
			func(i: int) -> void:
				MatchConfig.rival_count = i + 1
				_sync_rival_config_to_match()
				_rebuild_rivals_section())))

	var victory_opts: Array[String] = [tr("LOBBY_VICTORY_CONQUEST"), tr("LOBBY_VICTORY_REGICIDE"), tr("LOBBY_VICTORY_WONDER")]
	left_col.add_child(_make_inline_row(tr("LOBBY_VICTORY_MODE"),
		_make_option_row(victory_opts, MatchConfig.victory_mode,
			func(i: int) -> void: MatchConfig.victory_mode = i)))

	# Vertical spacer to push buttons to bottom
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(spacer)

	# --- Right column: civilizations ---
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right_col.custom_minimum_size = Vector2(240, 0)
	columns.add_child(right_col)

	# Player civ
	var player_civ_lbl: Label = _make_label(tr("LOBBY_CIVILIZATION"))
	player_civ_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	right_col.add_child(player_civ_lbl)

	right_col.add_child(_make_civ_dropdown(_player_civ_index,
		func(i: int) -> void:
			_player_civ_index = i
			MatchConfig.player_civ_id = (CIVS[i] as Dictionary)["id"] as String))

	right_col.add_child(_make_sep())

	# Rivals section (dynamic)
	_rivals_section = VBoxContainer.new()
	_rivals_section.add_theme_constant_override("separation", 8)
	right_col.add_child(_rivals_section)
	_rebuild_rivals_section()

	vbox.add_child(_make_sep())

	# Bottom buttons
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var back_btn: Button = _make_btn(tr("LOBBY_BACK"), Color(0.20, 0.20, 0.25, 0.95), Color(0.35, 0.35, 0.40, 0.95))
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	btn_row.add_child(back_btn)

	var start_btn: Button = _make_btn(tr("LOBBY_START"), Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	start_btn.custom_minimum_size = Vector2(180, 44)
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(func() -> void: start_requested.emit())
	btn_row.add_child(start_btn)

# --- Rivals section ---

func _rebuild_rivals_section() -> void:
	for child: Node in _rivals_section.get_children():
		child.queue_free()
	for ri: int in range(MatchConfig.rival_count):
		var lbl: Label = _make_label(tr("LOBBY_RIVAL") + " %d" % (ri + 1))
		lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		_rivals_section.add_child(lbl)
		var captured_ri: int = ri
		_rivals_section.add_child(_make_civ_dropdown(_rival_civ_indices[ri],
			func(i: int) -> void:
				_rival_civ_indices[captured_ri] = i
				_sync_rival_config_to_match()))

# --- Helpers ---

func _make_civ_dropdown(initial_idx: int, on_select: Callable) -> OptionButton:
	var opt: OptionButton = OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_theme_font_size_override("font_size", 17)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in range(CIVS.size()):
		opt.add_item(tr((CIVS[i] as Dictionary)["name_key"] as String), i)
	opt.select(initial_idx)
	opt.item_selected.connect(func(i: int) -> void: on_select.call(i))
	return opt

func _make_inline_row(label_text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl: Label = _make_label(label_text)
	lbl.custom_minimum_size = Vector2(148, 0)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _make_option_row(labels: Array[String], initial: int, on_select: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var btns: Array[Button] = []
	for i: int in range(labels.size()):
		var btn: Button = Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		row.add_child(btn)
		btns.append(btn)
	row.set_meta("selected", initial)
	_apply_btn_styles(btns, initial)
	for i: int in range(labels.size()):
		var captured_i: int = i
		btns[i].pressed.connect(func() -> void:
			row.set_meta("selected", captured_i)
			on_select.call(captured_i)
			_apply_btn_styles(btns, captured_i))
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

func _make_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	return lbl

func _make_sep() -> HSeparator:
	return HSeparator.new()

func _make_btn(text: String, normal_col: Color, hover_col: Color) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
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

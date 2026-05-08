extends Control

class_name LobbyScreen

## LobbyScreen — match configuration screen shown between main menu and game.
## Runs as a full-screen Control added over the main menu, not a separate scene.

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
var _player_civ_desc_label: Label = null
var _player_civ_btns: Array[Button] = []

# Per-rival state — indexed 0..2
var _rival_civ_indices: Array[int]       = [0, 0, 0]
var _rival_panels:      Array[Node]      = []  # VBoxContainer per rival
var _rival_civ_btns:    Array[Array]     = [[], [], []]
var _rival_desc_labels: Array[Label]     = [null, null, null]

var _rivals_container: VBoxContainer = null
var _scroll: ScrollContainer = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_init_rival_state()
	_build()

func _init_rival_state() -> void:
	for i: int in range(3):
		var civ_id: String = DEFAULT_RIVAL_CIVS[i] if i < DEFAULT_RIVAL_CIVS.size() else "castellanos"
		var idx: int = _civ_index_for_id(civ_id)
		_rival_civ_indices[i] = idx
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

	# Outer scroll so the panel never clips on small screens
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var outer_center: CenterContainer = CenterContainer.new()
	outer_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll.add_child(outer_center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(700, 0)
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
		margin.add_theme_constant_override("margin_" + side, 36)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("LOBBY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)

	vbox.add_child(_make_sep())

	# Map type
	vbox.add_child(_make_label(tr("LOBBY_MAP_TYPE")))
	var type_opts: Array[String] = [
		tr("LOBBY_MAPTYPE_STANDARD"),
		tr("LOBBY_MAPTYPE_VOLCANIC"),
		tr("LOBBY_MAPTYPE_DESERT"),
		tr("LOBBY_MAPTYPE_ISLANDS"),
	]
	vbox.add_child(_make_option_row(type_opts, MatchConfig.map_type,
		func(i: int) -> void: MatchConfig.map_type = i))

	# Map size
	vbox.add_child(_make_label(tr("LOBBY_MAP_SIZE")))
	var map_opts: Array[String] = [tr("LOBBY_MAP_SMALL"), tr("LOBBY_MAP_MEDIUM"), tr("LOBBY_MAP_LARGE")]
	vbox.add_child(_make_option_row(map_opts, MatchConfig.map_size,
		func(i: int) -> void: MatchConfig.map_size = i))

	# Resources
	vbox.add_child(_make_label(tr("LOBBY_RESOURCES")))
	var res_opts: Array[String] = [tr("LOBBY_RES_SCARCE"), tr("LOBBY_RES_NORMAL"), tr("LOBBY_RES_ABUNDANT"), tr("LOBBY_RES_FULL_COMBAT")]
	vbox.add_child(_make_option_row(res_opts, MatchConfig.resources,
		func(i: int) -> void: MatchConfig.resources = i))

	# Starting age
	vbox.add_child(_make_label(tr("LOBBY_STARTING_AGE")))
	var age_opts: Array[String] = []
	for k: String in AGE_KEYS:
		age_opts.append(tr(k))
	vbox.add_child(_make_option_row(age_opts, MatchConfig.starting_age,
		func(i: int) -> void: MatchConfig.starting_age = i))

	# Number of rivals
	vbox.add_child(_make_sep())
	vbox.add_child(_make_label(tr("LOBBY_RIVAL_COUNT")))
	var rival_count_opts: Array[String] = ["1", "2", "3"]
	vbox.add_child(_make_option_row(rival_count_opts, MatchConfig.rival_count - 1,
		func(i: int) -> void:
			MatchConfig.rival_count = i + 1
			_sync_rival_config_to_match()
			_rebuild_rivals_container()
	))

	vbox.add_child(_make_sep())

	# Player civilization
	vbox.add_child(_make_label(tr("LOBBY_CIVILIZATION")))
	vbox.add_child(_make_civ_grid(_player_civ_btns, _player_civ_index,
		func(i: int) -> void:
			_player_civ_index = i
			MatchConfig.player_civ_id = (CIVS[i] as Dictionary)["id"] as String
			_refresh_civ_highlight(_player_civ_btns, _player_civ_index)
			if is_instance_valid(_player_civ_desc_label):
				_player_civ_desc_label.text = tr((CIVS[i] as Dictionary)["desc_key"] as String)
	))

	_player_civ_desc_label = Label.new()
	_player_civ_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_player_civ_desc_label.add_theme_font_size_override("font_size", 13)
	_player_civ_desc_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	_player_civ_desc_label.custom_minimum_size = Vector2(0, 32)
	_player_civ_desc_label.text = tr((CIVS[_player_civ_index] as Dictionary)["desc_key"] as String)
	vbox.add_child(_player_civ_desc_label)

	vbox.add_child(_make_sep())

	# Rival civilization panels (dynamic)
	_rivals_container = VBoxContainer.new()
	_rivals_container.add_theme_constant_override("separation", 14)
	vbox.add_child(_rivals_container)
	_rebuild_rivals_container()

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

# --- Rival panels ---

func _rebuild_rivals_container() -> void:
	for child: Node in _rivals_container.get_children():
		child.queue_free()
	_rival_panels.clear()

	for ri: int in range(MatchConfig.rival_count):
		var panel: VBoxContainer = VBoxContainer.new()
		panel.add_theme_constant_override("separation", 6)
		_rivals_container.add_child(panel)
		_rival_panels.append(panel)

		var rival_num: int = ri + 1
		var header: Label = _make_label(tr("LOBBY_RIVAL") + " %d — " % rival_num + tr("LOBBY_CIVILIZATION"))
		header.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		panel.add_child(header)

		var captured_ri: int = ri
		var btns: Array[Button] = []
		_rival_civ_btns[ri] = btns
		panel.add_child(_make_civ_grid(btns, _rival_civ_indices[ri],
			func(i: int) -> void:
				_rival_civ_indices[captured_ri] = i
				_sync_rival_config_to_match()
				_refresh_civ_highlight(_rival_civ_btns[captured_ri] as Array[Button],
					_rival_civ_indices[captured_ri])
				if is_instance_valid(_rival_desc_labels[captured_ri]):
					_rival_desc_labels[captured_ri].text = \
						tr((CIVS[i] as Dictionary)["desc_key"] as String)
		))

		var desc: Label = Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		desc.custom_minimum_size = Vector2(0, 28)
		desc.text = tr((CIVS[_rival_civ_indices[ri]] as Dictionary)["desc_key"] as String)
		panel.add_child(desc)
		_rival_desc_labels[ri] = desc

# --- Civilization grid ---

func _make_civ_grid(btns_out: Array[Button], initial_idx: int, on_select: Callable) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	btns_out.clear()
	for i: int in range(CIVS.size()):
		var civ: Dictionary = CIVS[i] as Dictionary
		var btn: Button = Button.new()
		btn.text = tr(civ["name_key"] as String)
		btn.custom_minimum_size = Vector2(128, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		grid.add_child(btn)
		btns_out.append(btn)
		var captured_i: int = i
		btn.pressed.connect(func() -> void: on_select.call(captured_i))
	_refresh_civ_highlight(btns_out, initial_idx)
	return grid

func _refresh_civ_highlight(btns: Array[Button], selected: int) -> void:
	for i: int in range(btns.size()):
		var active: bool = i == selected
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.22, 0.40, 0.55, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9)
		s.corner_radius_top_left    = 4
		s.corner_radius_top_right   = 4
		s.corner_radius_bottom_left = 4
		s.corner_radius_bottom_right = 4
		btns[i].add_theme_stylebox_override("normal", s)
		btns[i].add_theme_stylebox_override("pressed", s)

# --- Option row (segmented button group) ---

func _make_option_row(labels: Array[String], initial: int, on_select: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var btns: Array[Button] = []
	for i: int in range(labels.size()):
		var btn: Button = Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = Vector2(100, 32)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		row.add_child(btn)
		btns.append(btn)

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

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

# Hero name, ability name key, ability description, unique unit display name
const CIV_DETAILS: Dictionary = {
	"guanches":    {"hero": "Bencomo",               "ability": "HERO_BENCOMO_ABILITY",     "ability_desc": "HERO_BENCOMO_ABILITY_DESC",     "unique_unit": "CIV_GUANCHES_UNIQUE_UNIT"},
	"canarii":     {"hero": "Doramas",               "ability": "HERO_DORAMAS_ABILITY",     "ability_desc": "HERO_DORAMAS_ABILITY_DESC",     "unique_unit": "CIV_CANARII_UNIQUE_UNIT"},
	"mahos":       {"hero": "Guadarfía",             "ability": "HERO_GUADARFIA_ABILITY",   "ability_desc": "HERO_GUADARFIA_ABILITY_DESC",   "unique_unit": "CIV_MAHOS_UNIQUE_UNIT"},
	"franks":      {"hero": "Jean de Béthencourt",   "ability": "HERO_BETHENCOURT_ABILITY", "ability_desc": "HERO_BETHENCOURT_ABILITY_DESC", "unique_unit": "CIV_FRANKS_UNIQUE_UNIT"},
	"britons":     {"hero": "Francis Drake",         "ability": "HERO_DRAKE_ABILITY",       "ability_desc": "HERO_DRAKE_ABILITY_DESC",       "unique_unit": "CIV_BRITONS_UNIQUE_UNIT"},
	"castellanos": {"hero": "Don Quijote",           "ability": "HERO_QUIJOTE_ABILITY",     "ability_desc": "HERO_QUIJOTE_ABILITY_DESC",     "unique_unit": "CIV_CASTELLANOS_UNIQUE_UNIT"},
	"atlantes":    {"hero": "Artaxerax",             "ability": "HERO_ARTAXERAX_ABILITY",   "ability_desc": "HERO_ARTAXERAX_ABILITY_DESC",   "unique_unit": "CIV_ATLANTES_UNIQUE_UNIT"},
	"fenicios":    {"hero": "Hannón el Navegante",   "ability": "HERO_HANNO_ABILITY",       "ability_desc": "HERO_HANNO_ABILITY_DESC",       "unique_unit": "CIV_FENICIOS_UNIQUE_UNIT"},
}

const AGE_KEYS: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]
const DEFAULT_RIVAL_CIVS: Array[String] = ["castellanos", "franks", "atlantes"]
const MAX_RIVALS: int = 3
# Height reserved for rivals section: MAX_RIVALS × (row_h + gap) = 3 × (38+8) = 138
const RIVALS_FIXED_H: float = 138.0

var _player_civ_index: int = 0
var _player_civ_btns: Array[Button] = []
var _player_civ_desc_label: Label = null  # kept for legacy reference, detail uses _rebuild_civ_detail

var _rival_civ_indices: Array[int] = [0, 0, 0]
var _rivals_section: VBoxContainer = null

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

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var outer: CenterContainer = CenterContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(860, 0)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	sty.corner_radius_top_left    = 8
	sty.corner_radius_top_right   = 8
	sty.corner_radius_bottom_left = 8
	sty.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", sty)
	outer.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("LOBBY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(_make_sep())

	# Two-column body
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	vbox.add_child(columns)

	# ── Left column ─────────────────────────────────────────────────────────
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	# Map type
	left.add_child(_make_label(tr("LOBBY_MAP_TYPE")))
	var type_opts: Array[String] = [
		tr("LOBBY_MAPTYPE_PLAINS"), tr("LOBBY_MAPTYPE_STANDARD"),
		tr("LOBBY_MAPTYPE_VOLCANIC"), tr("LOBBY_MAPTYPE_DESERT"), tr("LOBBY_MAPTYPE_ISLANDS"),
	]
	left.add_child(_make_option_row(type_opts, MatchConfig.map_type,
		func(i: int) -> void: MatchConfig.map_type = i))

	# Map size
	left.add_child(_make_label(tr("LOBBY_MAP_SIZE")))
	var size_opts: Array[String] = [tr("LOBBY_MAP_SMALL"), tr("LOBBY_MAP_MEDIUM"), tr("LOBBY_MAP_LARGE")]
	left.add_child(_make_option_row(size_opts, MatchConfig.map_size,
		func(i: int) -> void: MatchConfig.map_size = i))

	# Starting resources
	left.add_child(_make_label(tr("LOBBY_RESOURCES")))
	var res_opts: Array[String] = [tr("LOBBY_RES_SCARCE"), tr("LOBBY_RES_NORMAL"), tr("LOBBY_RES_ABUNDANT"), tr("LOBBY_RES_FULL_COMBAT")]
	left.add_child(_make_option_row(res_opts, MatchConfig.resources,
		func(i: int) -> void: MatchConfig.resources = i))

	# Starting age
	left.add_child(_make_label(tr("LOBBY_STARTING_AGE")))
	var age_opts: Array[String] = []
	for k: String in AGE_KEYS:
		age_opts.append(tr(k))
	left.add_child(_make_option_row(age_opts, MatchConfig.starting_age,
		func(i: int) -> void: MatchConfig.starting_age = i))

	# Victory condition
	left.add_child(_make_label(tr("LOBBY_VICTORY_MODE")))
	var victory_opts: Array[String] = [tr("LOBBY_VICTORY_CONQUEST"), tr("LOBBY_VICTORY_REGICIDE"), tr("LOBBY_VICTORY_WONDER")]
	left.add_child(_make_option_row(victory_opts, MatchConfig.victory_mode,
		func(i: int) -> void: MatchConfig.victory_mode = i))

	# Weather
	left.add_child(_make_label(tr("LOBBY_WEATHER_FREQUENCY")))
	var weather_opts: Array[String] = [
		tr("LOBBY_WEATHER_OFF"), tr("LOBBY_WEATHER_NORMAL"),
		tr("LOBBY_WEATHER_FREQUENT"), tr("LOBBY_WEATHER_EXTREME"),
	]
	var weather_initial: int = 0 if not MatchConfig.weather_enabled else MatchConfig.weather_frequency
	left.add_child(_make_option_row(weather_opts, weather_initial,
		func(i: int) -> void:
			MatchConfig.weather_enabled = i > 0
			MatchConfig.weather_frequency = i))

	left.add_child(_make_sep())

	# Rival count
	left.add_child(_make_label(tr("LOBBY_RIVAL_COUNT")))
	var rival_opts: Array[String] = ["1", "2", "3"]
	left.add_child(_make_option_row(rival_opts, MatchConfig.rival_count - 1,
		func(i: int) -> void:
			MatchConfig.rival_count = i + 1
			_sync_rival_config_to_match()
			_rebuild_rivals_section()))

	# Rivals section — fixed height so the card doesn't resize
	var rivals_clip: Control = Control.new()
	rivals_clip.custom_minimum_size = Vector2(0, RIVALS_FIXED_H)
	rivals_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rivals_clip.clip_contents = true
	left.add_child(rivals_clip)

	_rivals_section = VBoxContainer.new()
	_rivals_section.add_theme_constant_override("separation", 8)
	_rivals_section.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rivals_clip.add_child(_rivals_section)
	_rebuild_rivals_section()

	# ── Right column: player civ ─────────────────────────────────────────────
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # align to top
	columns.add_child(right)

	var civ_header: Label = _make_label(tr("LOBBY_CIVILIZATION"))
	civ_header.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	civ_header.add_theme_font_size_override("font_size", 21)
	right.add_child(civ_header)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	_player_civ_btns.clear()

	# Detail panel — built first so we can reference it in btn callbacks
	var detail_panel: PanelContainer = PanelContainer.new()
	var detail_sty: StyleBoxFlat = StyleBoxFlat.new()
	detail_sty.bg_color = Color(0.10, 0.10, 0.16, 0.90)
	detail_sty.corner_radius_top_left    = 5
	detail_sty.corner_radius_top_right   = 5
	detail_sty.corner_radius_bottom_left = 5
	detail_sty.corner_radius_bottom_right = 5
	detail_panel.add_theme_stylebox_override("panel", detail_sty)

	var detail_margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		detail_margin.add_theme_constant_override("margin_" + side, 12)
	detail_panel.add_child(detail_margin)

	var detail_vbox: VBoxContainer = VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail_vbox)

	_player_civ_desc_label = Label.new()  # reused as the full detail block

	for i: int in range(CIVS.size()):
		var civ: Dictionary = CIVS[i] as Dictionary
		var btn: Button = Button.new()
		btn.text = tr(civ["name_key"] as String)
		btn.custom_minimum_size = Vector2(120, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 16)
		grid.add_child(btn)
		_player_civ_btns.append(btn)
		var captured_i: int = i
		btn.pressed.connect(func() -> void:
			_player_civ_index = captured_i
			MatchConfig.player_civ_id = (CIVS[captured_i] as Dictionary)["id"] as String
			_refresh_civ_highlight(_player_civ_btns, captured_i)
			_rebuild_civ_detail(detail_vbox, captured_i))

	_refresh_civ_highlight(_player_civ_btns, _player_civ_index)

	right.add_child(detail_panel)
	_rebuild_civ_detail(detail_vbox, _player_civ_index)

	# Bottom buttons
	vbox.add_child(_make_sep())

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var back_btn: Button = _make_btn(tr("LOBBY_BACK"), Color(0.20, 0.20, 0.25, 0.95), Color(0.35, 0.35, 0.40, 0.95))
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	btn_row.add_child(back_btn)

	var start_btn: Button = _make_btn(tr("LOBBY_START"), Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	start_btn.custom_minimum_size = Vector2(200, 44)
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(func() -> void: start_requested.emit())
	btn_row.add_child(start_btn)

# --- Rivals section ---

func _rebuild_rivals_section() -> void:
	for child: Node in _rivals_section.get_children():
		child.queue_free()
	for ri: int in range(MatchConfig.rival_count):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rivals_section.add_child(row)
		var lbl: Label = _make_label(tr("LOBBY_RIVAL") + " %d:" % (ri + 1))
		lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(lbl)
		var captured_ri: int = ri
		var dropdown: OptionButton = _make_civ_dropdown(_rival_civ_indices[ri],
			func(i: int) -> void:
				_rival_civ_indices[captured_ri] = i
				_sync_rival_config_to_match())
		row.add_child(dropdown)

# --- Civ detail panel ---

func _rebuild_civ_detail(vbox: VBoxContainer, civ_idx: int) -> void:
	for child: Node in vbox.get_children():
		child.queue_free()

	var civ: Dictionary = CIVS[civ_idx] as Dictionary
	var civ_id: String = civ["id"] as String
	var details: Dictionary = CIV_DETAILS.get(civ_id, {}) as Dictionary

	# Description
	_add_detail_text(vbox, tr(civ["desc_key"] as String), Color(0.80, 0.80, 0.80))

	vbox.add_child(HSeparator.new())

	# Hero
	if details.has("hero"):
		_add_detail_row(vbox, tr("LOBBY_CIV_HERO"), details["hero"] as String, Color(1.0, 0.85, 0.40))
		_add_detail_text(vbox, tr(details["ability_desc"] as String), Color(0.68, 0.80, 0.95))

	vbox.add_child(HSeparator.new())

	# Unique unit
	if details.has("unique_unit"):
		_add_detail_row(vbox, tr("LOBBY_CIV_UNIQUE"), tr(details["unique_unit"] as String), Color(0.75, 0.95, 0.60))

func _add_detail_row(vbox: VBoxContainer, label: String, value: String, val_color: Color) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)
	var lbl: Label = Label.new()
	lbl.text = label + ":"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(lbl)
	var val: Label = Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", val_color)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)

func _add_detail_text(vbox: VBoxContainer, text: String, color: Color) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	vbox.add_child(lbl)

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

func _make_option_row(labels: Array[String], initial: int, on_select: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var btns: Array[Button] = []
	for i: int in range(labels.size()):
		var btn: Button = Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		row.add_child(btn)
		btns.append(btn)
	_apply_btn_styles(btns, initial)
	for i: int in range(labels.size()):
		var captured_i: int = i
		btns[i].pressed.connect(func() -> void:
			on_select.call(captured_i)
			_apply_btn_styles(btns, captured_i))
	return row

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
		btns[i].add_theme_stylebox_override("hover", s)
		btns[i].add_theme_stylebox_override("pressed", s)

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
		btns[j].add_theme_stylebox_override("hover", s)
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

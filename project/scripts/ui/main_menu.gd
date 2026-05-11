extends Control

@onready var _play_button: Button = %PlayButton
@onready var _quit_button: Button = %QuitButton

var _settings_panel: Control = null

func _ready() -> void:
	GameSettings.apply_language()
	_play_button.text = tr("MENU_PLAY")
	_quit_button.text = tr("MENU_QUIT")
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_build_settings_button()
	_build_continue_button()

# --- Continue button (shown only when a save exists) ---

var _continue_button: Button = null

func _build_continue_button() -> void:
	if not SaveManager.has_save():
		return
	var btn: Button = Button.new()
	btn.text = tr("MENU_CONTINUE")
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 18)
	btn.focus_mode = Control.FOCUS_NONE
	var container: Node = _play_button.get_parent()
	container.add_child(btn)
	container.move_child(btn, 0)   # Continue appears above Play
	_continue_button = btn
	btn.pressed.connect(_on_continue_pressed)

func _on_continue_pressed() -> void:
	if not SaveManager.load_game():
		return
	_play_button.disabled = true
	if is_instance_valid(_continue_button):
		_continue_button.disabled = true
	_show_loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")

# --- Settings button ---

func _build_settings_button() -> void:
	var btn: Button = Button.new()
	btn.text = tr("MENU_SETTINGS")
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 18)
	btn.focus_mode = Control.FOCUS_NONE

	# Insert after PlayButton inside its parent container
	var container: Node = _play_button.get_parent()
	var idx: int = _play_button.get_index() + 1
	container.add_child(btn)
	container.move_child(btn, idx)

	btn.pressed.connect(_open_settings)

# --- Play / Quit ---

var _lobby: Control = null

func _on_play_pressed() -> void:
	if is_instance_valid(_lobby):
		return
	_lobby = LobbyScreen.new()
	_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_lobby)
	_lobby.start_requested.connect(_on_lobby_start)
	_lobby.back_requested.connect(func() -> void:
		_lobby.queue_free()
		_lobby = null
	)

func _on_lobby_start() -> void:
	if is_instance_valid(_lobby):
		_lobby.queue_free()
		_lobby = null
	_play_button.disabled = true
	_show_loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")

func _show_loading_screen() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.06, 0.06, 0.10, 1.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var lbl: Label = Label.new()
	lbl.text = tr("MENU_LOADING")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.50))
	overlay.add_child(lbl)

func _on_quit_pressed() -> void:
	get_tree().quit()

# --- Settings panel ---

func _open_settings() -> void:
	if is_instance_valid(_settings_panel):
		return

	# Dark overlay
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_settings_panel = overlay

	# Centred card
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("SETTINGS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# Music volume
	vbox.add_child(_make_section_label(tr("SETTINGS_MUSIC")))
	var music_slider: HSlider = _make_slider(GameSettings.music_volume)
	vbox.add_child(music_slider)
	var music_pct: Label = _make_pct_label(GameSettings.music_volume)
	vbox.add_child(music_pct)
	music_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.music_volume = v
		music_pct.text = "%d%%" % int(v * 100.0)
		AudioManager.apply_settings()
	)

	# SFX volume
	vbox.add_child(_make_section_label(tr("SETTINGS_SFX")))
	var sfx_slider: HSlider = _make_slider(GameSettings.sfx_volume)
	vbox.add_child(sfx_slider)
	var sfx_pct: Label = _make_pct_label(GameSettings.sfx_volume)
	vbox.add_child(sfx_pct)
	sfx_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.sfx_volume = v
		sfx_pct.text = "%d%%" % int(v * 100.0)
		AudioManager.play("ui_select")
	)

	# Difficulty
	vbox.add_child(_make_section_label(tr("SETTINGS_DIFFICULTY")))
	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	vbox.add_child(diff_row)

	var diff_labels: Array[String] = [tr("SETTINGS_EASY"), tr("SETTINGS_NORMAL"), tr("SETTINGS_HARD")]
	var diff_btns: Array[Button] = []
	for d: int in range(3):
		var db: Button = Button.new()
		db.text = diff_labels[d]
		db.custom_minimum_size = Vector2(100, 36)
		db.focus_mode = Control.FOCUS_NONE
		db.add_theme_font_size_override("font_size", 15)
		diff_row.add_child(db)
		diff_btns.append(db)

	var _refresh_diff: Callable = func() -> void:
		for d: int in range(3):
			var active: bool = GameSettings.difficulty == d
			var s: StyleBoxFlat = StyleBoxFlat.new()
			s.bg_color = Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9)
			s.corner_radius_top_left    = 4
			s.corner_radius_top_right   = 4
			s.corner_radius_bottom_left = 4
			s.corner_radius_bottom_right = 4
			diff_btns[d].add_theme_stylebox_override("normal", s)
			diff_btns[d].add_theme_stylebox_override("pressed", s)

	_refresh_diff.call()

	for d: int in range(3):
		var captured_d: int = d
		diff_btns[d].pressed.connect(func() -> void:
			GameSettings.difficulty = captured_d
			_refresh_diff.call()
		)

	# Language section
	var sep_lang: HSeparator = HSeparator.new()
	vbox.add_child(sep_lang)

	vbox.add_child(_make_section_label(tr("SETTINGS_LANGUAGE")))
	var lang_row: HBoxContainer = HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vbox.add_child(lang_row)

	var lang_btns: Array[Button] = []
	var lang_codes: Array[String] = ["en", "es"]
	var lang_names: Array[String] = ["English", "Español"]
	for li: int in range(2):
		var lb: Button = Button.new()
		lb.text = lang_names[li]
		lb.custom_minimum_size = Vector2(100, 36)
		lb.focus_mode = Control.FOCUS_NONE
		lb.add_theme_font_size_override("font_size", 15)
		lang_row.add_child(lb)
		lang_btns.append(lb)

	var _refresh_lang: Callable = func() -> void:
		for li: int in range(2):
			var active: bool = GameSettings.language == lang_codes[li]
			var sl: StyleBoxFlat = StyleBoxFlat.new()
			sl.bg_color = Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9)
			sl.corner_radius_top_left    = 4
			sl.corner_radius_top_right   = 4
			sl.corner_radius_bottom_left = 4
			sl.corner_radius_bottom_right = 4
			lang_btns[li].add_theme_stylebox_override("normal", sl)
			lang_btns[li].add_theme_stylebox_override("pressed", sl)

	_refresh_lang.call()

	for li: int in range(2):
		var captured_li: int = li
		lang_btns[li].pressed.connect(func() -> void:
			GameSettings.language = lang_codes[captured_li]
			GameSettings.apply_language()
			GameSettings.save_settings()
			_refresh_menu_texts()
			overlay.queue_free()
			_settings_panel = null
			_open_settings()
		)

	# Spacer + close button
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn: Button = Button.new()
	close_btn.text = tr("SETTINGS_SAVE")
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 16)
	var close_style: StyleBoxFlat = StyleBoxFlat.new()
	close_style.bg_color = Color(0.20, 0.35, 0.55, 0.95)
	close_style.corner_radius_top_left    = 4
	close_style.corner_radius_top_right   = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	close_btn.add_theme_stylebox_override("normal", close_style)
	var close_hover: StyleBoxFlat = close_style.duplicate() as StyleBoxFlat
	close_hover.bg_color = Color(0.30, 0.50, 0.75, 0.95)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	vbox.add_child(close_btn)

	close_btn.pressed.connect(func() -> void:
		GameSettings.save_settings()
		overlay.queue_free()
		_settings_panel = null
	)

# --- Helpers ---

func _make_section_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	return lbl

func _make_slider(initial: float) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = initial
	s.custom_minimum_size = Vector2(0, 24)
	return s

func _refresh_menu_texts() -> void:
	_play_button.text = tr("MENU_PLAY")
	_quit_button.text = tr("MENU_QUIT")
	if is_instance_valid(_continue_button):
		_continue_button.text = tr("MENU_CONTINUE")
	var container: Node = _play_button.get_parent()
	for child: Node in container.get_children():
		if child is Button and child != _play_button and child != _quit_button \
				and child != _continue_button:
			(child as Button).text = tr("MENU_SETTINGS")
			break

func _make_pct_label(initial: float) -> Label:
	var lbl: Label = Label.new()
	lbl.text = "%d%%" % int(initial * 100.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	return lbl

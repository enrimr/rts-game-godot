extends Control

@onready var _play_button: Button = %PlayButton
@onready var _quit_button: Button = %QuitButton
@onready var _logo: TextureRect = %LogoImage

var _settings_panel: Control = null
var _settings_button: Button = null
var _how_to_play_button: Button = null

func _ready() -> void:
	GameSettings.apply_language()
	_play_button.text = tr("MENU_PLAY")
	_quit_button.text = tr("MENU_QUIT")
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_style_play_button()
	_build_settings_button()
	_build_how_to_play_button()
	_build_continue_button()
	_adapt_to_viewport()
	get_viewport().size_changed.connect(_adapt_to_viewport)
	if not GameSettings.tutorial_seen:
		_prompt_tutorial()

func _adapt_to_viewport() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var logo_w: float = clampf(vp.x * 0.45, 280.0, 720.0)
	var logo_h: float = logo_w * 0.45
	var btn_w: float  = clampf(vp.x * 0.18, 160.0, 320.0)
	_logo.custom_minimum_size = Vector2(logo_w, logo_h)
	_play_button.custom_minimum_size = Vector2(btn_w, 52.0)
	_quit_button.custom_minimum_size = Vector2(btn_w, 44.0)
	var container: Node = _play_button.get_parent()
	(container as Control).custom_minimum_size = Vector2(maxf(logo_w, btn_w), 0.0)
	# Resize dynamic buttons (Continue, Settings) created at runtime
	for child: Node in container.get_children():
		if child is Button and child != _play_button and child != _quit_button:
			(child as Button).custom_minimum_size = Vector2(btn_w, 44.0)

func _style_play_button() -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.42, 0.18, 0.95)
	normal.corner_radius_top_left    = 6
	normal.corner_radius_top_right   = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.26, 0.58, 0.26, 0.95)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.14, 0.32, 0.14, 0.95)
	_play_button.add_theme_stylebox_override("normal",  normal)
	_play_button.add_theme_stylebox_override("hover",   hover)
	_play_button.add_theme_stylebox_override("pressed", pressed)
	_play_button.add_theme_color_override("font_color", Color(0.92, 1.0, 0.88))

# --- Continue button (shown only when a save exists) ---

var _continue_button: Button = null

func _build_continue_button() -> void:
	var btn: Button = Button.new()
	btn.text = tr("MENU_CONTINUE")
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 18)
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not SaveManager.has_any_save()
	var container: Node = _play_button.get_parent()
	container.add_child(btn)
	container.move_child(btn, _play_button.get_index() + 1)
	_continue_button = btn
	btn.pressed.connect(_open_load_picker)

func _open_load_picker() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 0)
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
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("LOAD_PICKER_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(scroll)

	var slot_list: VBoxContainer = VBoxContainer.new()
	slot_list.add_theme_constant_override("separation", 6)
	slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(slot_list)

	var _rebuild: Callable
	_rebuild = func() -> void:
		if not is_instance_valid(slot_list):
			return
		for c: Node in slot_list.get_children():
			c.queue_free()
		var saves: Array[Dictionary] = SaveManager.list_saves()
		if saves.is_empty():
			var empty_lbl: Label = Label.new()
			empty_lbl.text = tr("SAVE_NO_SAVES")
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60))
			slot_list.add_child(empty_lbl)
			return
		for meta: Dictionary in saves:
			var slot: int = meta.get("slot", 0) as int
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			slot_list.add_child(row)

			var load_btn: Button = Button.new()
			load_btn.text = _format_save_label(meta)
			load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			load_btn.focus_mode = Control.FOCUS_NONE
			load_btn.add_theme_font_size_override("font_size", 14)
			var btn_style: StyleBoxFlat = StyleBoxFlat.new()
			btn_style.bg_color = Color(0.16, 0.20, 0.32, 0.95)
			btn_style.corner_radius_top_left    = 4
			btn_style.corner_radius_top_right   = 4
			btn_style.corner_radius_bottom_left = 4
			btn_style.corner_radius_bottom_right = 4
			var btn_hover: StyleBoxFlat = btn_style.duplicate() as StyleBoxFlat
			btn_hover.bg_color = Color(0.24, 0.32, 0.50, 0.95)
			load_btn.add_theme_stylebox_override("normal", btn_style)
			load_btn.add_theme_stylebox_override("hover",  btn_hover)
			row.add_child(load_btn)

			var captured_slot: int = slot
			load_btn.pressed.connect(func() -> void:
				if not SaveManager.load_game(captured_slot):
					return
				_play_button.disabled = true
				if is_instance_valid(_continue_button):
					_continue_button.disabled = true
				overlay.queue_free()
				_show_loading_screen()
				await get_tree().process_frame
				await get_tree().process_frame
				get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")
			)

			var del_btn: Button = Button.new()
			del_btn.text = tr("SAVE_DELETE")
			del_btn.custom_minimum_size = Vector2(36, 0)
			del_btn.focus_mode = Control.FOCUS_NONE
			del_btn.add_theme_font_size_override("font_size", 14)
			var del_style: StyleBoxFlat = StyleBoxFlat.new()
			del_style.bg_color = Color(0.38, 0.10, 0.10, 0.95)
			del_style.corner_radius_top_left    = 4
			del_style.corner_radius_top_right   = 4
			del_style.corner_radius_bottom_left = 4
			del_style.corner_radius_bottom_right = 4
			var del_hover: StyleBoxFlat = del_style.duplicate() as StyleBoxFlat
			del_hover.bg_color = Color(0.60, 0.15, 0.15, 0.95)
			del_btn.add_theme_stylebox_override("normal", del_style)
			del_btn.add_theme_stylebox_override("hover",  del_hover)
			row.add_child(del_btn)
			del_btn.pressed.connect(func() -> void:
				SaveManager.delete_save(captured_slot)
				if is_instance_valid(slot_list) and slot_list.has_meta("rebuild"):
					(slot_list.get_meta("rebuild") as Callable).call()
				if is_instance_valid(_continue_button):
					_continue_button.disabled = not SaveManager.has_any_save()
			)

	slot_list.set_meta("rebuild", _rebuild)
	_rebuild.call()

	vbox.add_child(HSeparator.new())
	var cancel_btn: Button = Button.new()
	cancel_btn.text = tr("SAVE_CANCEL")
	cancel_btn.custom_minimum_size = Vector2(200, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.add_theme_font_size_override("font_size", 16)
	var cancel_style: StyleBoxFlat = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.22, 0.10, 0.10, 0.95)
	cancel_style.corner_radius_top_left    = 4
	cancel_style.corner_radius_top_right   = 4
	cancel_style.corner_radius_bottom_left = 4
	cancel_style.corner_radius_bottom_right = 4
	var cancel_hover: StyleBoxFlat = cancel_style.duplicate() as StyleBoxFlat
	cancel_hover.bg_color = Color(0.38, 0.15, 0.12, 0.95)
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.add_theme_stylebox_override("hover", cancel_hover)
	cancel_btn.pressed.connect(func() -> void: overlay.queue_free())
	vbox.add_child(cancel_btn)

func _format_save_label(meta: Dictionary) -> String:
	var name: String = str(meta.get("display_name", ""))
	if name.is_empty():
		var civ: String = str(meta.get("civ", "?")).capitalize()
		var ts: int = meta.get("timestamp", 0) as int
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
		name = "%s — %02d/%02d %02d:%02d" % [civ,
			dt.get("day", 0), dt.get("month", 0),
			dt.get("hour", 0), dt.get("minute", 0)]
	return name

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

	_settings_button = btn
	btn.pressed.connect(_open_settings)

# --- How to Play button ---

func _build_how_to_play_button() -> void:
	var btn: Button = Button.new()
	btn.text = tr("MENU_HOW_TO_PLAY")
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 18)
	btn.focus_mode = Control.FOCUS_NONE

	# Insert after Settings button
	var container: Node = _play_button.get_parent()
	if is_instance_valid(_settings_button):
		var idx: int = _settings_button.get_index() + 1
		container.add_child(btn)
		container.move_child(btn, idx)
	else:
		container.add_child(btn)

	_how_to_play_button = btn
	btn.pressed.connect(_launch_tutorial_game)

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

# --- Tutorial prompt ---

func _prompt_tutorial() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

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
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("TUTORIAL_PROMPT_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var body: Label = Label.new()
	body.text = tr("TUTORIAL_PROMPT_BODY")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	vbox.add_child(body)

	vbox.add_child(HSeparator.new())

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var yes_btn: Button = Button.new()
	yes_btn.text = tr("TUTORIAL_PROMPT_YES")
	yes_btn.custom_minimum_size = Vector2(180, 40)
	yes_btn.focus_mode = Control.FOCUS_NONE
	yes_btn.add_theme_font_size_override("font_size", 16)
	var yes_style: StyleBoxFlat = StyleBoxFlat.new()
	yes_style.bg_color = Color(0.18, 0.42, 0.18, 0.95)
	yes_style.corner_radius_top_left    = 4
	yes_style.corner_radius_top_right   = 4
	yes_style.corner_radius_bottom_left = 4
	yes_style.corner_radius_bottom_right = 4
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	var yes_hover: StyleBoxFlat = yes_style.duplicate() as StyleBoxFlat
	yes_hover.bg_color = Color(0.26, 0.58, 0.26, 0.95)
	yes_btn.add_theme_stylebox_override("hover", yes_hover)
	btn_row.add_child(yes_btn)
	yes_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		_launch_tutorial_game()
	)

	var skip_btn: Button = Button.new()
	skip_btn.text = tr("TUTORIAL_PROMPT_SKIP")
	skip_btn.custom_minimum_size = Vector2(140, 40)
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.add_theme_font_size_override("font_size", 16)
	var skip_style: StyleBoxFlat = StyleBoxFlat.new()
	skip_style.bg_color = Color(0.22, 0.10, 0.10, 0.95)
	skip_style.corner_radius_top_left    = 4
	skip_style.corner_radius_top_right   = 4
	skip_style.corner_radius_bottom_left = 4
	skip_style.corner_radius_bottom_right = 4
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	var skip_hover: StyleBoxFlat = skip_style.duplicate() as StyleBoxFlat
	skip_hover.bg_color = Color(0.38, 0.15, 0.12, 0.95)
	skip_btn.add_theme_stylebox_override("hover", skip_hover)
	btn_row.add_child(skip_btn)
	skip_btn.pressed.connect(func() -> void: overlay.queue_free())

func _launch_tutorial_game() -> void:
	var saved_difficulty: int = GameSettings.difficulty
	MatchConfig.map_type        = MatchConfig.MapType.PLAINS
	MatchConfig.map_size        = MatchConfig.MapSize.SMALL
	MatchConfig.resources       = MatchConfig.Resources.TUTORIAL
	MatchConfig.player_civ_id   = "guanches"
	MatchConfig.starting_age    = 0
	MatchConfig.rival_count     = 1
	MatchConfig.rival_civ_ids.assign(["castellanos"])
	MatchConfig.victory_mode    = MatchConfig.VictoryMode.CONQUEST
	MatchConfig.launch_tutorial = true
	GameSettings.difficulty     = GameSettings.Difficulty.TUTORIAL
	# Restore player's real settings after the tutorial session ends
	GameManager.game_over.connect(func(_winner: int) -> void:
		GameSettings.difficulty = saved_difficulty
		MatchConfig.resources   = MatchConfig.Resources.NORMAL
	, CONNECT_ONE_SHOT)
	_on_lobby_start()

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
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("MENU_SETTINGS")
	if is_instance_valid(_how_to_play_button):
		_how_to_play_button.text = tr("MENU_HOW_TO_PLAY")

func _make_pct_label(initial: float) -> Label:
	var lbl: Label = Label.new()
	lbl.text = "%d%%" % int(initial * 100.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	return lbl

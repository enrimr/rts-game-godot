extends Control

@onready var _play_button: Button = %PlayButton
@onready var _quit_button: Button = %QuitButton
@onready var _logo: TextureRect = %LogoImage

var _settings_panel: Control = null
var _settings_button: Button = null
var _how_to_play_button: Button = null

func _ready() -> void:
	# Back at the menu with TUTORIAL still active = a tutorial abandoned
	# mid-lesson (the game_over restore never fired). Drop the transient
	# difficulty before it leaks into the next match or a settings save.
	if GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL:
		GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	# Same for replay leftovers: the mode ends where the menu begins.
	NetworkSession.replay_mode = false
	MatchConfig.replay_path = ""
	GameSettings.apply_language()
	_play_button.text = tr("MENU_PLAY")
	_quit_button.text = tr("MENU_QUIT")
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_build_settings_button()
	_build_how_to_play_button()
	_build_continue_button()
	_build_lan_button()
	_build_replays_button()
	# Built LAST inserting at play+1, so the final order reads:
	# Jugar, Campaña, Continuar, LAN, Internet.
	_build_campaign_button()
	_build_engine_credit()
	# Coming back from an aborted session must not leave a half-open peer.
	if NetworkSession.is_online():
		NetworkSession.leave()
	_restyle_menu()
	if not GameSettings.tutorial_seen:
		_prompt_tutorial()

# --- Continue button (shown only when a save exists) ---

var _campaign_button: Button = null

func _build_campaign_button() -> void:
	var btn: Button = Button.new()
	btn.text = tr("MENU_CAMPAIGN")
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 22)
	btn.focus_mode = Control.FOCUS_NONE
	var container: Node = _play_button.get_parent()
	container.add_child(btn)
	container.move_child(btn, _play_button.get_index() + 1)
	_campaign_button = btn
	btn.pressed.connect(_open_campaign_screen)

var _campaign_screen: CampaignScreen = null

func _open_campaign_screen() -> void:
	if is_instance_valid(_campaign_screen):
		return
	_campaign_screen = CampaignScreen.new()
	add_child(_campaign_screen)
	_campaign_screen.back_requested.connect(func() -> void:
		if is_instance_valid(_campaign_screen):
			_campaign_screen.queue_free()
		_campaign_screen = null)

var _continue_button: Button = null

func _build_continue_button() -> void:
	var btn: Button = Button.new()
	btn.text = tr("MENU_CONTINUE")
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 22)
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not SaveManager.has_any_save()
	var container: Node = _play_button.get_parent()
	container.add_child(btn)
	container.move_child(btn, _play_button.get_index() + 1)
	_continue_button = btn
	btn.pressed.connect(_open_load_picker)

# --- LAN multiplayer (host-authoritative; see NetworkSession) ---

var _lan_button: Button = null

func _build_lan_button() -> void:
	var container: Node = _play_button.get_parent()
	var lan_btn: Button = _make_mp_button(tr("MENU_LAN"))
	container.add_child(lan_btn)
	container.move_child(lan_btn, _play_button.get_index() + 2)
	_lan_button = lan_btn
	lan_btn.pressed.connect(_open_lan_panel)
	var inet_btn: Button = _make_mp_button(tr("MENU_INTERNET"))
	container.add_child(inet_btn)
	container.move_child(inet_btn, lan_btn.get_index() + 1)
	inet_btn.pressed.connect(_open_internet_panel)

# --- Replays (recorded snapshot streams; see StateReplicator/ReplayFile) ---

var _replays_button: Button = null
var _replays_panel: Control = null

func _build_replays_button() -> void:
	var container: Node = _play_button.get_parent()
	var btn: Button = _make_mp_button(tr("MENU_REPLAYS"))
	btn.disabled = ReplayFile.list_replays().is_empty()
	container.add_child(btn)
	container.move_child(btn, _quit_button.get_index())
	_replays_button = btn
	btn.pressed.connect(_open_replays_panel)

func _open_replays_panel() -> void:
	if is_instance_valid(_replays_panel):
		return
	var veil: Control = Control.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.09, 0.10, 0.13, 0.97)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	veil.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = tr("REPLAYS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 300)
	box.add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for header: Dictionary in ReplayFile.list_replays():
		rows.add_child(_make_replay_row(header))
	if rows.get_child_count() == 0:
		var empty: Label = Label.new()
		empty.text = tr("REPLAYS_EMPTY")
		rows.add_child(empty)
	var close: Button = Button.new()
	close.text = tr("REPLAYS_CLOSE")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(140, 36)
	close.pressed.connect(func() -> void:
		veil.queue_free()
		_replays_panel = null)
	box.add_child(close)
	add_child(veil)
	_replays_panel = veil
	panel.reset_size.call_deferred()
	panel.set_anchors_preset.call_deferred(Control.PRESET_CENTER)

func _make_replay_row(header: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cfg: Dictionary = header.get("config", {}) as Dictionary
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(header.get("timestamp", 0) as int)
	var rivals: Array = cfg.get("rival_civ_ids", []) as Array
	var label: Label = Label.new()
	label.text = "%02d/%02d %02d:%02d — %s vs %s" % [
		dt.get("day", 0), dt.get("month", 0), dt.get("hour", 0), dt.get("minute", 0),
		str(cfg.get("player_civ_id", "?")).capitalize(),
		", ".join(rivals.map(func(c: Variant) -> String: return str(c).capitalize()))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var watch: Button = Button.new()
	watch.text = tr("REPLAYS_WATCH")
	watch.custom_minimum_size = Vector2(90, 32)
	watch.pressed.connect(func() -> void: _play_replay(header))
	row.add_child(watch)
	return row

func _play_replay(header: Dictionary) -> void:
	NetworkSession.apply_config(header.get("config", {}) as Dictionary)
	NetworkSession.replay_mode = true
	MatchConfig.replay_path = str(header.get("path", ""))
	get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")

func _make_mp_button(label_text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 22)
	btn.focus_mode = Control.FOCUS_NONE
	return btn

func _build_engine_credit() -> void:
	var v: Dictionary = Engine.get_version_info()
	var lbl: Label = Label.new()
	lbl.text = tr("MENU_MADE_WITH") % ("%d.%d" % [v["major"] as int, v["minor"] as int])
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55, 0.75))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.offset_left = -240.0
	lbl.offset_top = -32.0
	lbl.offset_right = -14.0
	lbl.offset_bottom = -12.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

# ── Camera-key remap capture (the settings panel arms these) ──
var _key_capture_action: String = ""
var _key_capture_btn: Button = null

func _unhandled_key_input(event: InputEvent) -> void:
	if _key_capture_action.is_empty() or not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed:
		return
	if key.keycode != KEY_ESCAPE:
		GameSettings.set_pan_key(_key_capture_action,
			key.physical_keycode if key.physical_keycode != 0 else key.keycode)
	if is_instance_valid(_key_capture_btn):
		_key_capture_btn.text = GameSettings.pan_key_name(_key_capture_action)
	_key_capture_action = ""
	_key_capture_btn = null
	get_viewport().set_input_as_handled()

func _open_lan_panel() -> void:
	var panel: LanLobby = LanLobby.new()
	add_child(panel)

func _open_internet_panel() -> void:
	var panel: LanLobby = LanLobby.new()
	panel.internet_mode = true
	add_child(panel)

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
	title.add_theme_font_size_override("font_size", 26)
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
			load_btn.add_theme_font_size_override("font_size", 18)
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
			del_btn.add_theme_font_size_override("font_size", 18)
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
	cancel_btn.add_theme_font_size_override("font_size", 20)
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
	btn.add_theme_font_size_override("font_size", 22)
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
	btn.add_theme_font_size_override("font_size", 22)
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
	MatchConfig.campaign_mission = -1
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
	lbl.add_theme_font_size_override("font_size", 32)
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

	# The card outgrew the screen as settings accumulated (audio, difficulty,
	# language, controls, video, camera keys): title kissing the top edge,
	# close button lost below the bottom. Content scrolls inside a viewport-
	# bounded height instead.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(452.0,
		minf(700.0, get_viewport().get_visible_rect().size.y - 160.0))
	margin.add_child(scroll)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("SETTINGS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
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
		db.add_theme_font_size_override("font_size", 19)
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
		lb.add_theme_font_size_override("font_size", 19)
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

	# Controls section
	vbox.add_child(HSeparator.new())
	vbox.add_child(_make_section_label(tr("SETTINGS_CONTROLS")))

	var dpad_row: Button = _make_toggle_row(vbox, tr("SETTINGS_SHOW_DPAD"), GameSettings.show_dpad)
	dpad_row.pressed.connect(func() -> void:
		GameSettings.show_dpad = not GameSettings.show_dpad
		_style_toggle_btn(dpad_row, GameSettings.show_dpad)
	)

	var edge_row: Button = _make_toggle_row(vbox, tr("SETTINGS_EDGE_SCROLL"), GameSettings.edge_scroll_enabled)
	edge_row.pressed.connect(func() -> void:
		GameSettings.edge_scroll_enabled = not GameSettings.edge_scroll_enabled
		_style_toggle_btn(edge_row, GameSettings.edge_scroll_enabled)
	)

	# Video
	vbox.add_child(_make_section_label(tr("SETTINGS_VIDEO")))
	var fps_row: Button = _make_toggle_row(vbox, tr("SETTINGS_SHOW_FPS"), GameSettings.show_fps)
	fps_row.pressed.connect(func() -> void:
		GameSettings.show_fps = not GameSettings.show_fps
		_style_toggle_btn(fps_row, GameSettings.show_fps)
	)
	var fs_row: Button = _make_toggle_row(vbox, tr("SETTINGS_FULLSCREEN"), GameSettings.fullscreen)
	fs_row.pressed.connect(func() -> void:
		GameSettings.fullscreen = not GameSettings.fullscreen
		GameSettings.apply_video()
		_style_toggle_btn(fs_row, GameSettings.fullscreen)
	)
	var vs_row: Button = _make_toggle_row(vbox, tr("SETTINGS_VSYNC"), GameSettings.vsync)
	vs_row.pressed.connect(func() -> void:
		GameSettings.vsync = not GameSettings.vsync
		GameSettings.apply_video()
		_style_toggle_btn(vs_row, GameSettings.vsync)
	)

	# Camera pan keys (remappable; arrows always work as secondary)
	vbox.add_child(_make_section_label(tr("SETTINGS_CAMERA_KEYS")))
	var key_labels: Dictionary = {
		"camera_pan_left": tr("SETTINGS_PAN_LEFT"), "camera_pan_right": tr("SETTINGS_PAN_RIGHT"),
		"camera_pan_up": tr("SETTINGS_PAN_UP"), "camera_pan_down": tr("SETTINGS_PAN_DOWN"),
	}
	var keys_row: HBoxContainer = HBoxContainer.new()
	keys_row.add_theme_constant_override("separation", 8)
	vbox.add_child(keys_row)
	for action: String in key_labels:
		var cell: VBoxContainer = VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys_row.add_child(cell)
		var cl: Label = Label.new()
		cl.text = key_labels[action] as String
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_theme_font_size_override("font_size", 14)
		cl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
		cell.add_child(cl)
		var kb: Button = Button.new()
		kb.text = GameSettings.pan_key_name(action)
		kb.custom_minimum_size = Vector2(0, 34)
		kb.focus_mode = Control.FOCUS_NONE
		kb.add_theme_font_size_override("font_size", 17)
		cell.add_child(kb)
		var captured_action: String = action
		kb.pressed.connect(func() -> void:
			kb.text = tr("SETTINGS_PRESS_KEY")
			_key_capture_action = captured_action
			_key_capture_btn = kb)

	# Spacer + close button
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn: Button = Button.new()
	close_btn.text = tr("SETTINGS_SAVE")
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 20)
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
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var body: Label = Label.new()
	body.text = tr("TUTORIAL_PROMPT_BODY")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 19)
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
	yes_btn.add_theme_font_size_override("font_size", 20)
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
	skip_btn.add_theme_font_size_override("font_size", 20)
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
	lbl.add_theme_font_size_override("font_size", 19)
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
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	return lbl

func _make_toggle_row(parent: VBoxContainer, label_text: String, initial: bool) -> Button:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	row.add_child(lbl)
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(72, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	_style_toggle_btn(btn, initial)
	row.add_child(btn)
	return btn

func _style_toggle_btn(btn: Button, active: bool) -> void:
	btn.text = tr("SETTINGS_ON") if active else tr("SETTINGS_OFF")
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.35, 0.12, 0.12, 0.92)
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = s.bg_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)

# ── Centered layout, done right ──────────────────────────────────────────────
# The background painting is the hero and the logo is the crown: big and
# centered, as the original. What changes is the column under it — the old
# buttons inherited the LOGO's 720 px width from the shared VBox (a layout
# bug) and buried the sunset under nine grey bars. Now: a NARROW centered
# column of translucent pills, grouped by intent with thin gold separators,
# JUGAR as the single large primary, Salir last and dimmer.

const COL_W: float = 300.0
const GOLD: Color = Color(0.93, 0.80, 0.45)
const GOLD_DIM: Color = Color(0.90, 0.85, 0.72)

func _restyle_menu() -> void:
	var container: VBoxContainer = _play_button.get_parent() as VBoxContainer
	var overlay: ColorRect = get_node_or_null("Overlay") as ColorRect
	if overlay != null:
		overlay.color = Color(0.0, 0.0, 0.0, 0.30)
	container.add_theme_constant_override("separation", 8)
	container.custom_minimum_size = Vector2.ZERO

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var logo_w: float = clampf(vp.x * 0.42, 320.0, 680.0)
	_logo.custom_minimum_size = Vector2(logo_w, logo_w * 0.45)
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var internet_btn: Button = _find_button_by_text(container, tr("MENU_INTERNET"))
	var order: Array = [_play_button, _campaign_button, _continue_button,
		_replays_button, null, _lan_button, internet_btn, null,
		_settings_button, _how_to_play_button]
	var slot: int = _logo.get_index() + 2   # after logo + its spacer
	for entry: Variant in order:
		if entry == null:
			var sep: ColorRect = ColorRect.new()
			sep.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.30)
			sep.custom_minimum_size = Vector2(120.0, 1.0)
			sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			container.add_child(sep)
			container.move_child(sep, slot)
		elif is_instance_valid(entry as Node):
			container.move_child(entry as Node, slot)
			_style_menu_button(entry as Button, entry == _play_button)
		slot += 1
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	container.add_child(gap)
	container.move_child(gap, slot)
	container.move_child(_quit_button, container.get_child_count() - 1)
	_style_menu_button(_quit_button, false)
	_quit_button.add_theme_color_override("font_color", Color(0.75, 0.70, 0.62))

	var version: Label = Label.new()
	version.text = "v" + NetworkSession.game_version()
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -140.0
	version.offset_top = -48.0
	version.offset_bottom = -30.0
	add_child(version)

	_start_ken_burns()

func _find_button_by_text(container: Node, text: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and (child as Button).text == text:
			return child as Button
	return null

func _style_menu_button(btn: Button, primary: bool) -> void:
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.custom_minimum_size = Vector2(COL_W + (40.0 if primary else 0.0),
		52.0 if primary else 38.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 28 if primary else 20)
	var ink: Color = Color(0.16, 0.11, 0.03)   # dark letters on the gold slab
	btn.add_theme_color_override("font_color", ink if primary else GOLD_DIM)
	btn.add_theme_color_override("font_hover_color",
		Color(0.10, 0.06, 0.01) if primary else Color(1.0, 0.95, 0.75))
	btn.add_theme_color_override("font_pressed_color", ink if primary else GOLD)
	btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.52, 0.5))
	if primary:
		btn.text = btn.text.to_upper()
		btn.add_theme_font_override("font", HudStyle.bold_font())
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.set_corner_radius_all(7)
	if primary:
		# The one solid button on screen: a gold slab with dark lettering.
		normal.bg_color = Color(0.87, 0.72, 0.34)
		normal.border_width_bottom = 3
		normal.border_color = Color(0.55, 0.42, 0.16)
	else:
		normal.bg_color = Color(0.03, 0.03, 0.05, 0.52)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	if primary:
		hover.bg_color = Color(1.0, 0.86, 0.46)
		hover.border_color = Color(0.68, 0.53, 0.22)
	else:
		hover.bg_color = Color(0.10, 0.08, 0.04, 0.66)
		hover.border_width_left = 2
		hover.border_width_right = 2
		hover.border_width_top = 2
		hover.border_width_bottom = 2
		hover.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
	var pressed: StyleBoxFlat = hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.72, 0.58, 0.26) if primary else Color(0.16, 0.13, 0.06, 0.75)
	if primary:
		# Hover juice: the slab brightens AND swells a touch.
		btn.pivot_offset = btn.custom_minimum_size * 0.5
		btn.mouse_entered.connect(func() -> void:
			create_tween().tween_property(btn, "scale", Vector2(1.05, 1.05), 0.12)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
		btn.mouse_exited.connect(func() -> void:
			create_tween().tween_property(btn, "scale", Vector2.ONE, 0.12)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

## A barely-there breathing drift on the painting: alive, never distracting.
func _start_ken_burns() -> void:
	var bg: TextureRect = get_node_or_null("Background") as TextureRect
	if bg == null:
		return
	bg.pivot_offset = bg.size * 0.5
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(bg, "scale", Vector2(1.045, 1.045), 26.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(bg, "scale", Vector2.ONE, 26.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

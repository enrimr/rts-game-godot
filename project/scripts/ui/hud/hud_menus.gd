class_name HudMenus
extends Node

## In-game pause menu, settings panel, save-slot picker and surrender flow.
## A child of the HUD CanvasLayer; overlays are parented to that CanvasLayer
## (get_parent()) so they render full-screen exactly as before. Coupling to the
## tutorial and the on-screen dpad is injected via callables in init().

var _pause_menu: Control = null
var _start_tutorial: Callable
var _is_tutorial_active: Callable
var _set_dpad_visible: Callable

func init(start_tutorial: Callable, is_tutorial_active: Callable, set_dpad_visible: Callable) -> void:
	_start_tutorial = start_tutorial
	_is_tutorial_active = is_tutorial_active
	_set_dpad_visible = set_dpad_visible

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_pause_open() -> bool:
	return is_instance_valid(_pause_menu)

func _layer() -> Node:
	return get_parent()

func open_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		return
	if GameManager.state == GameManager.GameState.GAME_OVER:
		return
	# A LAN client cannot pause the authoritative simulation — its menu opens
	# over the live match (the HOST's pause replicates to everyone instead).
	if not NetworkSession.is_client():
		GameManager.toggle_pause()

	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer().add_child(overlay)
	_pause_menu = overlay

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 0)
	card.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.08, 0.08, 0.12, 0.97)))
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("MENU_SETTINGS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var resume_btn: Button = _make_pause_btn(tr("PAUSEMENU_RESUME"), Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	resume_btn.pressed.connect(close_pause_menu)
	vbox.add_child(resume_btn)

	var settings_btn: Button = _make_pause_btn(tr("MENU_SETTINGS"), Color(0.20, 0.20, 0.28, 0.95), Color(0.32, 0.32, 0.45, 0.95))
	settings_btn.pressed.connect(_open_ingame_settings)
	vbox.add_child(settings_btn)

	var how_to_play_btn: Button = _make_pause_btn(tr("MENU_HOW_TO_PLAY"), Color(0.22, 0.35, 0.45, 0.95), Color(0.32, 0.50, 0.62, 0.95))
	how_to_play_btn.disabled = _is_tutorial_active.is_valid() and bool(_is_tutorial_active.call())
	how_to_play_btn.pressed.connect(func() -> void:
		close_pause_menu()
		if _start_tutorial.is_valid():
			_start_tutorial.call()
	)
	vbox.add_child(how_to_play_btn)

	var save_btn: Button = _make_pause_btn(tr("PAUSEMENU_SAVE"), Color(0.16, 0.28, 0.44, 0.95), Color(0.24, 0.42, 0.62, 0.95))
	save_btn.pressed.connect(_open_save_slot_picker)
	# A client's world is a replicated mirror, not the simulation — only the
	# host can write a faithful (and later resumable) save.
	save_btn.disabled = NetworkSession.is_client()
	vbox.add_child(save_btn)

	vbox.add_child(HSeparator.new())

	var surrender_btn: Button = _make_pause_btn(tr("PAUSEMENU_SURRENDER"), Color(0.48, 0.12, 0.08, 0.95), Color(0.65, 0.18, 0.10, 0.95))
	surrender_btn.pressed.connect(_on_surrender)
	vbox.add_child(surrender_btn)

	var quit_btn: Button = _make_pause_btn(tr("PAUSEMENU_QUIT"), Color(0.22, 0.10, 0.10, 0.95), Color(0.38, 0.15, 0.12, 0.95))
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_btn)

func close_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
		_pause_menu = null
	if not NetworkSession.is_client() and GameManager.state == GameManager.GameState.PAUSED:
		GameManager.toggle_pause()

func _open_save_slot_picker() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer().add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 0)
	card.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.08, 0.08, 0.12, 0.97)))
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("SAVE_PICKER_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	vbox.add_child(scroll)

	var slot_list: VBoxContainer = VBoxContainer.new()
	slot_list.add_theme_constant_override("separation", 6)
	slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(slot_list)

	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		world = get_tree().current_scene

	var _rebuild_slots: Callable
	_rebuild_slots = func() -> void:
		if not is_instance_valid(slot_list):
			return
		for c: Node in slot_list.get_children():
			c.queue_free()
		# "New save" row
		var new_row: HBoxContainer = HBoxContainer.new()
		new_row.add_theme_constant_override("separation", 6)
		slot_list.add_child(new_row)
		var new_btn: Button = Button.new()
		new_btn.text = tr("SAVE_NEW_SLOT")
		new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		new_btn.focus_mode = Control.FOCUS_NONE
		new_btn.add_theme_font_size_override("font_size", 19)
		new_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.16, 0.30, 0.16, 0.95)))
		new_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.24, 0.46, 0.24, 0.95)))
		new_row.add_child(new_btn)
		new_btn.pressed.connect(func() -> void:
			var ok: bool = await SaveManager.save_game(world, -1)
			overlay.queue_free()
			close_pause_menu()
			_show_save_notification(ok)
		)
		# Existing slots
		var saves: Array[Dictionary] = SaveManager.list_saves()
		for meta: Dictionary in saves:
			var slot: int = meta.get("slot", 0) as int
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			slot_list.add_child(row)
			var slot_btn: Button = Button.new()
			slot_btn.text = _format_save_label(meta)
			slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot_btn.focus_mode = Control.FOCUS_NONE
			slot_btn.add_theme_font_size_override("font_size", 18)
			slot_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.16, 0.20, 0.32, 0.95)))
			slot_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.24, 0.32, 0.50, 0.95)))
			row.add_child(slot_btn)
			var captured_slot: int = slot
			slot_btn.pressed.connect(func() -> void:
				var ok: bool = await SaveManager.save_game(world, captured_slot)
				overlay.queue_free()
				close_pause_menu()
				_show_save_notification(ok)
			)
			var del_btn: Button = Button.new()
			del_btn.text = tr("SAVE_DELETE")
			del_btn.custom_minimum_size = Vector2(36, 0)
			del_btn.focus_mode = Control.FOCUS_NONE
			del_btn.add_theme_font_size_override("font_size", 18)
			del_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.38, 0.10, 0.10, 0.95)))
			del_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.60, 0.15, 0.15, 0.95)))
			row.add_child(del_btn)
			del_btn.pressed.connect(func() -> void:
				SaveManager.delete_save(captured_slot)
				if is_instance_valid(slot_list) and slot_list.has_meta("rebuild"):
					(slot_list.get_meta("rebuild") as Callable).call()
			)

	slot_list.set_meta("rebuild", _rebuild_slots)
	_rebuild_slots.call()

	vbox.add_child(HSeparator.new())
	var cancel_btn: Button = _make_pause_btn(tr("SAVE_CANCEL"), Color(0.22, 0.10, 0.10, 0.95), Color(0.38, 0.15, 0.12, 0.95))
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

func _show_save_notification(success: bool) -> void:
	var lbl: Label = Label.new()
	lbl.text = tr("SAVE_SUCCESS") if success else tr("SAVE_FAILED")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color",
		Color(0.4, 1.0, 0.5) if success else Color(1.0, 0.4, 0.4))
	lbl.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 150.0, 80.0)
	lbl.custom_minimum_size = Vector2(300.0, 0.0)
	_layer().add_child(lbl)
	var tw: Tween = create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free()
	)

func _open_ingame_settings() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer().add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)
	card.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.08, 0.08, 0.12, 0.97)))
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("SETTINGS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Music
	var music_lbl: Label = Label.new()
	music_lbl.text = tr("SETTINGS_MUSIC")
	music_lbl.add_theme_font_size_override("font_size", 19)
	music_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(music_lbl)
	var music_slider: HSlider = _make_settings_slider(GameSettings.music_volume)
	vbox.add_child(music_slider)
	var music_pct: Label = _make_settings_pct_label(GameSettings.music_volume)
	vbox.add_child(music_pct)
	music_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.music_volume = v
		music_pct.text = "%d%%" % int(v * 100.0)
		AudioManager.apply_settings()
	)

	# SFX
	var sfx_lbl: Label = Label.new()
	sfx_lbl.text = tr("SETTINGS_SFX")
	sfx_lbl.add_theme_font_size_override("font_size", 19)
	sfx_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(sfx_lbl)
	var sfx_slider: HSlider = _make_settings_slider(GameSettings.sfx_volume)
	vbox.add_child(sfx_slider)
	var sfx_pct: Label = _make_settings_pct_label(GameSettings.sfx_volume)
	vbox.add_child(sfx_pct)
	sfx_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.sfx_volume = v
		sfx_pct.text = "%d%%" % int(v * 100.0)
		AudioManager.apply_settings()
	)

	vbox.add_child(HSeparator.new())

	# Language
	var lang_lbl: Label = Label.new()
	lang_lbl.text = tr("SETTINGS_LANGUAGE")
	lang_lbl.add_theme_font_size_override("font_size", 19)
	lang_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(lang_lbl)
	var lang_row: HBoxContainer = HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vbox.add_child(lang_row)
	var lang_codes: Array[String] = ["en", "es"]
	var lang_names: Array[String] = ["English", "Español"]
	var lang_btns: Array[Button] = []
	for li: int in range(2):
		var lb: Button = Button.new()
		lb.text = lang_names[li]
		lb.custom_minimum_size = Vector2(100, 36)
		lb.focus_mode = Control.FOCUS_NONE
		lb.add_theme_font_size_override("font_size", 19)
		lang_row.add_child(lb)
		lang_btns.append(lb)
	var refresh_lang: Callable = func() -> void:
		for li: int in range(2):
			var active: bool = GameSettings.language == lang_codes[li]
			var sl: StyleBoxFlat = HudStyle.panel(Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9))
			lang_btns[li].add_theme_stylebox_override("normal", sl)
			lang_btns[li].add_theme_stylebox_override("pressed", sl)
	refresh_lang.call()
	for li: int in range(2):
		var captured_li: int = li
		lang_btns[li].pressed.connect(func() -> void:
			GameSettings.language = lang_codes[captured_li]
			GameSettings.apply_language()
			GameSettings.save_settings()
			refresh_lang.call()
		)

	vbox.add_child(HSeparator.new())

	# Zoom
	var zoom_lbl: Label = Label.new()
	zoom_lbl.text = "Zoom"
	zoom_lbl.add_theme_font_size_override("font_size", 19)
	zoom_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(zoom_lbl)
	var worlds: Array = get_tree().get_nodes_in_group("world")
	var initial_zoom: float = 1.0
	if not worlds.is_empty():
		initial_zoom = (worlds[0] as Node).call("get_zoom") as float
	var zoom_slider: HSlider = HSlider.new()
	zoom_slider.min_value = 0.5
	zoom_slider.max_value = 2.0
	zoom_slider.step = 0.1
	zoom_slider.value = initial_zoom
	zoom_slider.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(zoom_slider)
	var zoom_pct: Label = Label.new()
	zoom_pct.text = "%d%%" % int(initial_zoom * 100.0)
	zoom_pct.add_theme_font_size_override("font_size", 15)
	zoom_pct.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	vbox.add_child(zoom_pct)
	zoom_slider.value_changed.connect(func(v: float) -> void:
		zoom_pct.text = "%d%%" % int(v * 100.0)
		if not worlds.is_empty():
			(worlds[0] as Node).call("set_zoom", v)
	)

	vbox.add_child(HSeparator.new())

	var ctrl_lbl: Label = Label.new()
	ctrl_lbl.text = tr("SETTINGS_CONTROLS")
	ctrl_lbl.add_theme_font_size_override("font_size", 19)
	ctrl_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(ctrl_lbl)

	var dpad_row: Button = _make_toggle_row(vbox, tr("SETTINGS_SHOW_DPAD"), GameSettings.show_dpad)
	dpad_row.pressed.connect(func() -> void:
		GameSettings.show_dpad = not GameSettings.show_dpad
		_style_toggle_btn(dpad_row, GameSettings.show_dpad)
		if _set_dpad_visible.is_valid():
			_set_dpad_visible.call(GameSettings.show_dpad)
	)

	var edge_row: Button = _make_toggle_row(vbox, tr("SETTINGS_EDGE_SCROLL"), GameSettings.edge_scroll_enabled)
	edge_row.pressed.connect(func() -> void:
		GameSettings.edge_scroll_enabled = not GameSettings.edge_scroll_enabled
		_style_toggle_btn(edge_row, GameSettings.edge_scroll_enabled)
	)

	vbox.add_child(HSeparator.new())

	var close_btn: Button = Button.new()
	close_btn.text = tr("SETTINGS_SAVE")
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.20, 0.35, 0.55, 0.95)))
	close_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.30, 0.50, 0.75, 0.95)))
	vbox.add_child(close_btn)
	close_btn.pressed.connect(func() -> void:
		GameSettings.save_settings()
		overlay.queue_free()
	)

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
	var s: StyleBoxFlat = HudStyle.panel(Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.35, 0.12, 0.12, 0.92), 4)
	btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = s.bg_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)

func _make_settings_slider(initial: float) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = initial
	s.custom_minimum_size = Vector2(0, 24)
	return s

func _make_settings_pct_label(initial: float) -> Label:
	var lbl: Label = Label.new()
	lbl.text = "%d%%" % int(initial * 100.0)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	return lbl

func _on_surrender() -> void:
	close_pause_menu()
	if NetworkSession.is_client():
		# Tell the host (it eliminates us there); show our defeat locally
		# after the same breathing room every machine gets.
		NetworkSession.resign()
		await get_tree().create_timer(WorldVictory.RESIGN_END_DELAY).timeout
		GameManager.declare_winner(-1)
		return
	if NetworkSession.is_host():
		# The host's surrender must reach the chat too before the match ends.
		NetworkSession.announce("resigned",
			NetworkSession.display_name_of(NetworkSession.local_player_id))
		await get_tree().create_timer(WorldVictory.RESIGN_END_DELAY).timeout
	GameManager.declare_winner(1)

func _make_pause_btn(label_text: String, normal_col: Color, hover_col: Color) -> Button:
	var btn: Button = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(240, 42)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("normal", HudStyle.panel(normal_col))
	btn.add_theme_stylebox_override("hover", HudStyle.panel(hover_col))
	return btn

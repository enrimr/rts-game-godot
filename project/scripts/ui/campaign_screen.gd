class_name CampaignScreen
extends Control

## Mission selector for the Canarii campaign: one card per mission (locked /
## playable / completed), a briefing panel with the mission's intro text and
## a launch button. Progress comes from CampaignManager.

signal back_requested

var _briefing: PanelContainer = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	CampaignManager.progress_changed.connect(_rebuild)

func _exit_tree() -> void:
	if CampaignManager.progress_changed.is_connected(_rebuild):
		CampaignManager.progress_changed.disconnect(_rebuild)

func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_briefing = null
	_build()

func _build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_PASS
	add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	sty.corner_radius_top_left = 8
	sty.corner_radius_top_right = 8
	sty.corner_radius_bottom_left = 8
	sty.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", sty)
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	card.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("CAMP_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = tr("CAMP_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.70, 0.70, 0.75))
	vbox.add_child(subtitle)
	vbox.add_child(HSeparator.new())

	for i: int in range(CampaignData.size()):
		vbox.add_child(_mission_row(i))

	vbox.add_child(HSeparator.new())
	var back: Button = _make_btn(tr("LOBBY_BACK"), Color(0.20, 0.20, 0.25, 0.95))
	back.custom_minimum_size = Vector2(150, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: back_requested.emit())
	vbox.add_child(back)

func _mission_row(index: int) -> Control:
	var m: Dictionary = CampaignData.mission(index)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var state: Label = Label.new()
	state.custom_minimum_size = Vector2(30, 0)
	state.add_theme_font_size_override("font_size", 19)
	var unlocked: bool = CampaignManager.is_unlocked(index)
	if CampaignManager.is_completed(index):
		state.text = "✓"
		state.add_theme_color_override("font_color", Color(0.55, 0.90, 0.55))
	elif unlocked:
		state.text = "▶"
		state.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	else:
		state.text = "🔒"
		state.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	row.add_child(state)

	var name_lbl: Label = Label.new()
	# The prologue (tutorial) reads as chapter zero; real missions number 1..N.
	name_lbl.text = tr(m["title_key"] as String) if m.get("tutorial", false) \
		else "%d. %s" % [index, tr(m["title_key"] as String)]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 18)
	if not unlocked:
		name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	row.add_child(name_lbl)

	var play: Button = _make_btn(
		tr("CAMP_REPLAY") if CampaignManager.is_completed(index) else tr("CAMP_PLAY"),
		Color(0.18, 0.38, 0.18, 0.95))
	play.disabled = not unlocked
	play.pressed.connect(func() -> void: _open_briefing(index))
	row.add_child(play)
	return row

## The briefing: epic intro text + the launch button.
func _open_briefing(index: int) -> void:
	if is_instance_valid(_briefing):
		_briefing.queue_free()
	var m: Dictionary = CampaignData.mission(index)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_briefing = PanelContainer.new()
	_briefing.custom_minimum_size = Vector2(640, 0)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.06, 0.06, 0.10, 0.99)
	sty.border_color = Color(0.90, 0.82, 0.52, 0.85)
	for side: String in ["left", "right", "top", "bottom"]:
		sty.set("border_width_" + side, 1)
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	_briefing.add_theme_stylebox_override("panel", sty)
	center.add_child(_briefing)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	_briefing.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr(m["title_key"] as String)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)

	var intro: RichTextLabel = RichTextLabel.new()
	intro.bbcode_enabled = false
	intro.fit_content = true
	intro.custom_minimum_size = Vector2(0, 90)
	intro.text = tr(m["intro_key"] as String)
	intro.add_theme_font_size_override("normal_font_size", 15)
	vbox.add_child(intro)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	vbox.add_child(buttons)
	var cancel: Button = _make_btn(tr("SAVE_CANCEL"), Color(0.22, 0.10, 0.10, 0.95))
	var wrapper: CenterContainer = center
	cancel.pressed.connect(func() -> void: wrapper.queue_free())
	buttons.add_child(cancel)
	var go: Button = _make_btn(tr("CAMP_START"), Color(0.18, 0.38, 0.18, 0.95))
	go.custom_minimum_size = Vector2(200, 44)
	go.pressed.connect(func() -> void: CampaignManager.launch_mission(index))
	buttons.add_child(go)

func _make_btn(text: String, color: Color) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = color
	sty.corner_radius_top_left = 4
	sty.corner_radius_top_right = 4
	sty.corner_radius_bottom_left = 4
	sty.corner_radius_bottom_right = 4
	sty.content_margin_left = 14.0
	sty.content_margin_right = 14.0
	sty.content_margin_top = 7.0
	sty.content_margin_bottom = 7.0
	btn.add_theme_stylebox_override("normal", sty)
	var hover: StyleBoxFlat = sty.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.18)
	btn.add_theme_stylebox_override("hover", hover)
	return btn

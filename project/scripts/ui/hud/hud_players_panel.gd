class_name HudPlayersPanel
extends Control

## AoE2-style players overlay: a small button docked on the minimap toggles a
## roster panel listing every player — colour swatch, name, civilization,
## current Age and a live score. Mounted by HudManager as a child of the
## minimap control; the panel grows up-left so it never covers the map.
##
## The score is deliberately simple and readable (the aim is "who is ahead",
## not accounting): 200 per Age reached, 50 per technology, 10 per living
## unit, 20 per standing building. No stockpile term on purpose: hoarded
## resources made a passive player look ahead of an AI that SPENDS its
## income on army and buildings — the things the score already counts.
## Refreshed at 1 Hz while open only.

const REFRESH_SEC: float = 1.0

var _panel: PanelContainer = null
var _rows_box: VBoxContainer = null
var _toggle: Button = null
var _timer: Timer = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle = Button.new()
	_toggle.text = "≡"
	_toggle.tooltip_text = tr("PLAYERS_PANEL_TOOLTIP")
	_toggle.custom_minimum_size = Vector2(26, 22)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.toggle_mode = true
	_toggle.toggled.connect(_on_toggled)
	_toggle.position = Vector2(0, -26)
	add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		HudStyle.panel(Color(0.08, 0.09, 0.12, 0.93)))
	_panel.visible = false
	add_child(_panel)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	_panel.add_child(_rows_box)

	_timer = Timer.new()
	_timer.wait_time = REFRESH_SEC
	_timer.timeout.connect(_refresh)
	add_child(_timer)

func _on_toggled(open: bool) -> void:
	_panel.visible = open
	if open:
		_refresh()
		_timer.start()
	else:
		_timer.stop()

func _refresh() -> void:
	for child: Node in _rows_box.get_children():
		child.queue_free()
	var pids: Array[int] = [0]
	for rid: int in MatchConfig.get_rival_player_ids():
		pids.append(rid)
	# Living entities counted once for every player, not once per row.
	var units_of: Dictionary = {}
	var buildings_of: Dictionary = {}
	for u: Node in get_tree().get_nodes_in_group("units"):
		var pid: Variant = u.get("player_id")
		if pid != null:
			units_of[pid] = (units_of.get(pid, 0) as int) + 1
	for b: Node in get_tree().get_nodes_in_group("buildings"):
		var pid: Variant = b.get("player_id")
		if pid != null:
			buildings_of[pid] = (buildings_of.get(pid, 0) as int) + 1
	for pid: int in pids:
		_rows_box.add_child(_make_row(pid,
			units_of.get(pid, 0) as int, buildings_of.get(pid, 0) as int))
	# The panel sits ABOVE the minimap, right-aligned to its frame — clear of
	# the idle/alert buttons that live just left of the minimap's top edge.
	_panel.reset_size()
	var parent_w: float = (get_parent() as Control).size.x \
		if get_parent() is Control else 0.0
	_panel.position = Vector2(parent_w - _panel.size.x, -30.0 - _panel.size.y)

func _make_row(pid: int, units: int, buildings: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = PlayerColors.get_color(pid)
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var age: int = clampi(AgeManager.get_age(pid), 0, 3)
	var age_key: String = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE",
		"UI_AGE_IMPERIAL"][age]
	var text: String = "%s — %s · %s · %d" % [_name_of(pid), _civ_name_of(pid),
		tr(age_key), _score(pid, units, buildings)]
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	HudStyle.add_text_outline(label, 3)
	if pid == NetworkSession.local_player_id:
		label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	row.add_child(label)
	return row

func _name_of(pid: int) -> String:
	if NetworkSession.is_online() and NetworkSession.is_human_player(pid):
		return NetworkSession.display_name_of(pid)
	if pid == NetworkSession.local_player_id:
		return tr("PLAYERS_PANEL_YOU")
	return tr("PLAYERS_PANEL_AI") % pid

func _civ_name_of(pid: int) -> String:
	var civ_id: String = MatchConfig.player_civ_id if pid == 0 \
		else MatchConfig.get_rival_civ_id(pid)
	if civ_id.is_empty():
		return "?"
	var civ: CivilizationResource = load("res://resources/civilizations/%s.tres" % civ_id) \
		as CivilizationResource
	return civ.display_name if civ != null else civ_id.capitalize()

func _score(pid: int, units: int, buildings: int) -> int:
	var s: float = AgeManager.get_age(pid) * 200.0
	s += TechManager.get_researched_count(pid) * 50.0
	s += units * 10.0 + buildings * 20.0
	return int(s)

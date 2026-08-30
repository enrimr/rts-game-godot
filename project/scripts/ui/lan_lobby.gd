class_name LanLobby extends ColorRect

## The LAN lobby overlay: pick a name, host or join, see everyone who is
## connected (live roster with colours), pick your player colour, and — as
## host — configure the match with the SAME LobbyScreen the skirmish uses,
## kick players, and start. All roster state lives in NetworkSession
## (host-authoritative); this panel only renders it and sends requests.

signal closed()

const CARD_BG: Color = Color(0.08, 0.08, 0.12, 0.97)
const GOLD: Color = Color(0.90, 0.82, 0.52)

var _status: Label = null
var _name_edit: LineEdit = null
var _ip_edit: LineEdit = null
var _offline_row: Control = null
var _session_box: VBoxContainer = null
var _roster_box: VBoxContainer = null
var _palette_row: HBoxContainer = null
var _count_label: Label = null
var _start_btn: Button = null
var _configure_btn: Button = null
var _match_lobby: Control = null

func _ready() -> void:
	color = Color(0.0, 0.0, 0.0, 0.65)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_card()
	NetworkSession.roster_changed.connect(_refresh)
	NetworkSession.joined_host.connect(_refresh)
	NetworkSession.join_failed.connect(_on_join_failed)
	NetworkSession.kicked.connect(_on_kicked)
	_refresh()

func _exit_tree() -> void:
	NetworkSession.roster_changed.disconnect(_refresh)
	NetworkSession.joined_host.disconnect(_refresh)
	NetworkSession.join_failed.disconnect(_on_join_failed)
	NetworkSession.kicked.disconnect(_on_kicked)

func _build_card() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	for corner: String in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 8)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("LAN_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", GOLD)
	vbox.add_child(title)

	# Name (locked once the session is up).
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = tr("LAN_NAME")
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = NetworkSession.player_name
	_name_edit.placeholder_text = tr("LAN_NAME_PLACEHOLDER")
	_name_edit.max_length = 24
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String) -> void:
		NetworkSession.player_name = t)
	name_row.add_child(_name_edit)

	_status = Label.new()
	_status.text = tr("LAN_HINT")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	vbox.add_child(_status)

	# Offline controls: host, or IP + join.
	_offline_row = VBoxContainer.new()
	(_offline_row as VBoxContainer).add_theme_constant_override("separation", 8)
	vbox.add_child(_offline_row)
	var host_btn: Button = Button.new()
	host_btn.text = tr("LAN_HOST")
	host_btn.add_theme_font_size_override("font_size", 20)
	host_btn.pressed.connect(_on_host_pressed)
	_offline_row.add_child(host_btn)
	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_offline_row.add_child(join_row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "192.168.1."
	_ip_edit.placeholder_text = "IP"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	var join_btn: Button = Button.new()
	join_btn.text = tr("LAN_JOIN")
	join_btn.add_theme_font_size_override("font_size", 20)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

	# Live session: roster + colour palette + host controls.
	_session_box = VBoxContainer.new()
	_session_box.add_theme_constant_override("separation", 10)
	_session_box.visible = false
	vbox.add_child(_session_box)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 16)
	_count_label.add_theme_color_override("font_color", GOLD)
	_session_box.add_child(_count_label)
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 6)
	_session_box.add_child(_roster_box)
	var palette_label: Label = Label.new()
	palette_label.text = tr("LAN_PICK_COLOR")
	palette_label.add_theme_font_size_override("font_size", 14)
	_session_box.add_child(palette_label)
	_palette_row = HBoxContainer.new()
	_palette_row.add_theme_constant_override("separation", 6)
	_session_box.add_child(_palette_row)
	_configure_btn = Button.new()
	_configure_btn.text = tr("LAN_CONFIGURE")
	_configure_btn.add_theme_font_size_override("font_size", 18)
	_configure_btn.pressed.connect(_open_match_settings)
	_session_box.add_child(_configure_btn)
	_start_btn = Button.new()
	_start_btn.text = tr("LAN_START")
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.pressed.connect(func() -> void:
		_start_btn.disabled = true
		NetworkSession.start_match())
	_session_box.add_child(_start_btn)

	var back_btn: Button = Button.new()
	back_btn.text = tr("LAN_LEAVE")
	back_btn.pressed.connect(func() -> void:
		NetworkSession.leave()
		closed.emit()
		queue_free())
	vbox.add_child(back_btn)

func _on_host_pressed() -> void:
	if NetworkSession.host_game() != OK:
		_status.text = tr("LAN_PORT_ERROR")
		return
	_status.text = tr("LAN_WAITING") % [_local_ipv4(), NetworkSession.DEFAULT_PORT]
	_refresh()

func _on_join_pressed() -> void:
	if NetworkSession.join_game(_ip_edit.text.strip_edges()) != OK:
		_status.text = tr("LAN_JOIN_FAILED")
		return
	_status.text = tr("LAN_CONNECTING")
	_refresh()

func _on_join_failed() -> void:
	_status.text = tr("LAN_JOIN_FAILED")
	_refresh()

func _on_kicked() -> void:
	_status.text = tr("LAN_KICKED")
	_refresh()

func _local_ipv4() -> String:
	for addr: String in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") \
				or addr.begins_with("172.16.") or addr.begins_with("172.17."):
			return addr
	return "127.0.0.1"

## Re-renders the whole panel from NetworkSession state.
func _refresh() -> void:
	var online: bool = NetworkSession.is_online()
	_offline_row.visible = not online
	_session_box.visible = online
	_name_edit.editable = not online
	if not online:
		return
	var roster: Dictionary = NetworkSession.get_roster()
	_count_label.text = tr("LAN_PLAYER_COUNT") % [roster.size(), NetworkSession.MAX_CLIENTS + 1]
	_configure_btn.visible = NetworkSession.is_host()
	_start_btn.visible = NetworkSession.is_host()
	_start_btn.disabled = roster.size() < 2
	if NetworkSession.is_client():
		_status.text = tr("LAN_CONNECTED_WAIT")
	_rebuild_roster(roster)
	_rebuild_palette(roster)

func _rebuild_roster(roster: Dictionary) -> void:
	for child: Node in _roster_box.get_children():
		child.queue_free()
	var ids: Array = roster.keys()
	ids.sort()
	for pid: Variant in ids:
		var entry: Dictionary = roster[pid] as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_roster_box.add_child(row)
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.color = PlayerColors.COLORS[entry.get("color", 0) as int]
		row.add_child(swatch)
		var name_label: Label = Label.new()
		var suffix: String = ""
		if (pid as int) == 0:
			suffix = "  (%s)" % tr("LAN_HOST_TAG")
		if (pid as int) == NetworkSession.local_player_id:
			suffix += "  ◄"
		name_label.text = str(entry.get("name", "?")) + suffix
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 17)
		row.add_child(name_label)
		if NetworkSession.is_host() and (pid as int) != 0:
			var kick_btn: Button = Button.new()
			kick_btn.text = tr("LAN_KICK")
			kick_btn.add_theme_font_size_override("font_size", 14)
			var kick_pid: int = pid as int
			kick_btn.pressed.connect(func() -> void:
				NetworkSession.kick(kick_pid))
			row.add_child(kick_btn)

func _rebuild_palette(roster: Dictionary) -> void:
	for child: Node in _palette_row.get_children():
		child.queue_free()
	var taken: Dictionary = {}
	for entry: Variant in roster.values():
		taken[(entry as Dictionary).get("color", -1) as int] = true
	var own_color: int = -1
	if roster.has(NetworkSession.local_player_id):
		own_color = (roster[NetworkSession.local_player_id] as Dictionary).get("color", -1) as int
	for idx: int in range(PlayerColors.COLORS.size()):
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(34, 30)
		btn.focus_mode = Control.FOCUS_NONE
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = PlayerColors.COLORS[idx]
		if idx == own_color:
			sb.border_color = Color.WHITE
			for side: String in ["left", "right", "top", "bottom"]:
				sb.set("border_width_" + side, 3)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(state, sb)
		btn.disabled = taken.has(idx) and idx != own_color
		if btn.disabled:
			btn.modulate = Color(1.0, 1.0, 1.0, 0.35)
		var pick: int = idx
		btn.pressed.connect(func() -> void:
			NetworkSession.request_color(pick))
		_palette_row.add_child(btn)

## The host configures the match with the SAME screen the skirmish lobby
## uses (it writes MatchConfig live); both of its exits just come back here.
func _open_match_settings() -> void:
	if is_instance_valid(_match_lobby):
		return
	_match_lobby = LobbyScreen.new()
	_match_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_match_lobby)
	var close_settings: Callable = func() -> void:
		if is_instance_valid(_match_lobby):
			_match_lobby.queue_free()
			_match_lobby = null
	(_match_lobby as Object).connect("start_requested", close_settings)
	(_match_lobby as Object).connect("back_requested", close_settings)

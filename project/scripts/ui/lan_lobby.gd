class_name LanLobby extends ColorRect

## The LAN entry panel: pick a name, then host or join. Once the session is
## up, the panel swaps to the SAME LobbyScreen the skirmish uses (lan_mode):
## the host edits the match settings and the Open/AI/Closed player slots,
## clients see a live read-only summary, and everyone picks their own name,
## colour and civilization. All state lives in NetworkSession
## (host-authoritative); this panel only opens/closes the session.

signal closed()

const CARD_BG: Color = Color(0.08, 0.08, 0.12, 0.97)
const GOLD: Color = Color(0.90, 0.82, 0.52)

var _status: Label = null
var _name_edit: LineEdit = null
var _ip_edit: LineEdit = null
var _card_center: Control = null
var _match_lobby: Control = null

func _ready() -> void:
	color = Color(0.0, 0.0, 0.0, 0.65)
	# NOT set_anchors_preset: called while already in the tree it keeps the
	# current (0,0) size by writing compensating offsets — the panel stays
	# zero-sized and the LobbyScreen's ScrollContainer clips itself invisible.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_card()
	NetworkSession.joined_host.connect(_open_match_lobby)
	NetworkSession.join_failed.connect(_on_join_failed)
	NetworkSession.kicked.connect(_on_kicked)
	NetworkSession.session_closed.connect(_on_session_closed)
	NetworkSession.steam_session_started.connect(_open_match_lobby)
	NetworkSession.steam_lobbies_found.connect(_on_steam_lobbies)
	NetworkSession.steam_error.connect(_on_steam_error)

func _exit_tree() -> void:
	NetworkSession.joined_host.disconnect(_open_match_lobby)
	NetworkSession.join_failed.disconnect(_on_join_failed)
	NetworkSession.kicked.disconnect(_on_kicked)
	NetworkSession.session_closed.disconnect(_on_session_closed)
	NetworkSession.steam_session_started.disconnect(_open_match_lobby)
	NetworkSession.steam_lobbies_found.disconnect(_on_steam_lobbies)
	NetworkSession.steam_error.disconnect(_on_steam_error)

func _build_card() -> void:
	_card_center = CenterContainer.new()
	_card_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_card_center)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	for corner: String in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 8)
	card.add_theme_stylebox_override("panel", style)
	_card_center.add_child(card)
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

	var host_btn: Button = Button.new()
	host_btn.text = tr("LAN_HOST")
	host_btn.add_theme_font_size_override("font_size", 20)
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)
	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	vbox.add_child(join_row)
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

	_build_steam_section(vbox)

	var back_btn: Button = Button.new()
	back_btn.text = tr("LAN_LEAVE")
	back_btn.pressed.connect(func() -> void:
		NetworkSession.leave()
		closed.emit()
		queue_free())
	vbox.add_child(back_btn)

var _steam_list: VBoxContainer = null

## Steam block: host through Valve's relay (no ports, no IPs) or browse the
## public Calima lobbies. Only shown when the Steam client is up.
func _build_steam_section(vbox: VBoxContainer) -> void:
	if not NetworkSession.ensure_steam():
		var off: Label = Label.new()
		off.text = tr("STEAM_UNAVAILABLE")
		off.add_theme_font_size_override("font_size", 13)
		off.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
		vbox.add_child(off)
		return
	vbox.add_child(HSeparator.new())
	var title: Label = Label.new()
	title.text = "Steam — %s" % Steam.getPersonaName()
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
	vbox.add_child(title)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var host_btn: Button = Button.new()
	host_btn.text = tr("STEAM_HOST")
	host_btn.add_theme_font_size_override("font_size", 18)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(func() -> void: NetworkSession.host_steam())
	row.add_child(host_btn)
	var browse_btn: Button = Button.new()
	browse_btn.text = tr("STEAM_BROWSE")
	browse_btn.add_theme_font_size_override("font_size", 18)
	browse_btn.pressed.connect(func() -> void:
		NetworkSession.request_steam_lobbies())
	row.add_child(browse_btn)
	_steam_list = VBoxContainer.new()
	_steam_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_steam_list)

func _on_steam_lobbies(lobbies: Array) -> void:
	if _steam_list == null:
		return
	for c: Node in _steam_list.get_children():
		c.queue_free()
	if lobbies.is_empty():
		var none: Label = Label.new()
		none.text = tr("STEAM_NO_LOBBIES")
		none.add_theme_font_size_override("font_size", 14)
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_steam_list.add_child(none)
		return
	for lobby: Variant in lobbies:
		var l: Dictionary = lobby as Dictionary
		var btn: Button = Button.new()
		btn.text = "%s  (%d/4)" % [l.get("host", "?"), l.get("members", 0) as int]
		btn.add_theme_font_size_override("font_size", 15)
		var lobby_id: int = l.get("id", 0) as int
		btn.pressed.connect(func() -> void:
			NetworkSession.join_steam_lobby(lobby_id))
		_steam_list.add_child(btn)

func _on_steam_error(_message: String) -> void:
	_status.text = tr("LAN_JOIN_FAILED")

func _on_host_pressed() -> void:
	if NetworkSession.host_game() != OK:
		_status.text = tr("LAN_PORT_ERROR")
		return
	_status.text = tr("LAN_WAITING") % [NetworkSession.local_ipv4(), NetworkSession.DEFAULT_PORT]
	_open_match_lobby()

func _on_join_pressed() -> void:
	if NetworkSession.join_game(_ip_edit.text.strip_edges()) != OK:
		_status.text = tr("LAN_JOIN_FAILED")
		return
	_status.text = tr("LAN_CONNECTING")

func _on_join_failed() -> void:
	_status.text = tr("LAN_JOIN_FAILED")

func _on_kicked() -> void:
	_status.text = tr("LAN_KICKED")

func _on_session_closed() -> void:
	# Server gone, kicked, or the local player left — back to the entry card.
	_close_match_lobby()
	_card_center.visible = true

## The whole lobby is the skirmish LobbyScreen in lan_mode: settings on the
## left (host-editable, client summary), players panel below, your civ on the
## right. Its Back leaves the session and returns to this card.
func _open_match_lobby() -> void:
	if is_instance_valid(_match_lobby):
		return
	_card_center.visible = false
	var lobby: LobbyScreen = LobbyScreen.new()
	lobby.lan_mode = true
	_match_lobby = lobby
	add_child(lobby)
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.back_requested.connect(func() -> void:
		NetworkSession.leave())

func _close_match_lobby() -> void:
	if is_instance_valid(_match_lobby):
		_match_lobby.queue_free()
	_match_lobby = null

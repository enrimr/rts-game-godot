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
	"guanches":    {"hero_m": "Bencomo",               "hero_f": "Dácil",                 "ability_m": "HERO_BENCOMO_ABILITY",     "ability_f": "HERO_DACIL_ABILITY",      "ability_desc_m": "HERO_BENCOMO_ABILITY_DESC",     "ability_desc_f": "HERO_DACIL_ABILITY_DESC",      "unique_unit": "CIV_GUANCHES_UNIQUE_UNIT"},
	"canarii":     {"hero_m": "Doramas",               "hero_f": "Guayarmina",            "ability_m": "HERO_DORAMAS_ABILITY",     "ability_f": "HERO_GUAYARMINA_ABILITY", "ability_desc_m": "HERO_DORAMAS_ABILITY_DESC",     "ability_desc_f": "HERO_GUAYARMINA_ABILITY_DESC", "unique_unit": "CIV_CANARII_UNIQUE_UNIT"},
	"mahos":       {"hero_m": "Guadarfía",             "hero_f": "Tibiabin",              "ability_m": "HERO_GUADARFIA_ABILITY",   "ability_f": "HERO_TIBIABIN_ABILITY",   "ability_desc_m": "HERO_GUADARFIA_ABILITY_DESC",   "ability_desc_f": "HERO_TIBIABIN_ABILITY_DESC",   "unique_unit": "CIV_MAHOS_UNIQUE_UNIT"},
	"franks":      {"hero_m": "Jean de Béthencourt",   "hero_f": "Catalina",              "ability_m": "HERO_BETHENCOURT_ABILITY", "ability_f": "HERO_CATALINA_ABILITY",   "ability_desc_m": "HERO_BETHENCOURT_ABILITY_DESC", "ability_desc_f": "HERO_CATALINA_ABILITY_DESC",   "unique_unit": "CIV_FRANKS_UNIQUE_UNIT"},
	"britons":     {"hero_m": "Francis Drake",         "hero_f": "Grace O'Malley",        "ability_m": "HERO_DRAKE_ABILITY",       "ability_f": "HERO_GRACE_ABILITY",      "ability_desc_m": "HERO_DRAKE_ABILITY_DESC",       "ability_desc_f": "HERO_GRACE_ABILITY_DESC",      "unique_unit": "CIV_BRITONS_UNIQUE_UNIT"},
	"castellanos": {"hero_m": "Don Quijote",           "hero_f": "Dulcinea",              "ability_m": "HERO_QUIJOTE_ABILITY",     "ability_f": "HERO_DULCINEA_ABILITY",   "ability_desc_m": "HERO_QUIJOTE_ABILITY_DESC",     "ability_desc_f": "HERO_DULCINEA_ABILITY_DESC",   "unique_unit": "CIV_CASTELLANOS_UNIQUE_UNIT"},
	"atlantes":    {"hero_m": "Artaxerax",             "hero_f": "Cleito",                "ability_m": "HERO_ARTAXERAX_ABILITY",   "ability_f": "HERO_CLEITO_ABILITY",     "ability_desc_m": "HERO_ARTAXERAX_ABILITY_DESC",   "ability_desc_f": "HERO_CLEITO_ABILITY_DESC",     "unique_unit": "CIV_ATLANTES_UNIQUE_UNIT"},
	"fenicios":    {"hero_m": "Hannón el Navegante",   "hero_f": "Elissa",                "ability_m": "HERO_HANNO_ABILITY",       "ability_f": "HERO_ELISSA_ABILITY",     "ability_desc_m": "HERO_HANNO_ABILITY_DESC",       "ability_desc_f": "HERO_ELISSA_ABILITY_DESC",     "unique_unit": "CIV_FENICIOS_UNIQUE_UNIT"},
}

const AGE_KEYS: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]
const DEFAULT_RIVAL_CIVS: Array[String] = ["castellanos", "franks", "atlantes"]
const MAX_RIVALS: int = 3
# Height reserved for the single-row rivals section (compact lobby layout)
const RIVALS_FIXED_H: float = 46.0
# Fixed label column so inline setting rows align vertically
const SETTING_LABEL_W: float = 200.0

var _player_civ_index: int = 0
var _player_civ_btns: Array[Button] = []
var _player_civ_desc_label: Label = null  # kept for legacy reference, detail uses _rebuild_civ_detail

var _rival_civ_indices: Array[int] = [0, 0, 0]
var _rival_teams: Array[int] = [0, 0, 0]
var _player_team: int = 0
var _rivals_section: HBoxContainer = null

const TEAM_LABELS: Array[String] = ["—", "1", "2", "3", "4"]

func _sync_teams_to_match() -> void:
	MatchConfig.player_teams.clear()
	if _player_team > 0:
		MatchConfig.player_teams[0] = _player_team
	for i: int in range(MatchConfig.rival_count):
		if _rival_teams[i] > 0:
			MatchConfig.player_teams[i + 1] = _rival_teams[i]

func _make_team_dropdown(initial: int, on_select: Callable) -> OptionButton:
	var opt: OptionButton = OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_theme_font_size_override("font_size", 15)
	opt.tooltip_text = tr("LOBBY_TEAM")
	for i: int in range(TEAM_LABELS.size()):
		opt.add_item(TEAM_LABELS[i], i)
	opt.select(initial)
	opt.item_selected.connect(func(i: int) -> void: on_select.call(i))
	return opt

## LAN mode: the SAME screen hosts the multiplayer lobby. The rivals row is
## replaced by a players panel (live roster + Open/AI/Closed slots), the civ
## column picks YOUR civ (sent to the host), and on clients the settings
## column becomes a read-only summary that tracks the host's picks live.
var lan_mode: bool = false
var _players_panel: VBoxContainer = null
var _chat_log: RichTextLabel = null
var _chat_input: LineEdit = null
var _summary_label: Label = null
var _civ_detail_vbox: VBoxContainer = null
var _lobby_sync_timer: Timer = null
var _last_lobby_snapshot: Dictionary = {}
## What the current UI was built for; a flip (host picked a save / cancelled,
## or the client learned of it via the lobby broadcast) forces a full rebuild.
var _resume_built: bool = false

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_init_rival_state()
	_build()
	_resume_built = NetworkSession.resume_active
	if lan_mode:
		NetworkSession.roster_changed.connect(_refresh_lan_panels)
		NetworkSession.config_changed.connect(_refresh_lan_panels)
		if NetworkSession.is_host():
			# Push settings changes to the clients' summaries ~2×/s.
			_lobby_sync_timer = Timer.new()
			_lobby_sync_timer.wait_time = 0.5
			_lobby_sync_timer.timeout.connect(_maybe_broadcast_lobby)
			add_child(_lobby_sync_timer)
			_lobby_sync_timer.start()
		_refresh_lan_panels()

func _exit_tree() -> void:
	if lan_mode:
		NetworkSession.roster_changed.disconnect(_refresh_lan_panels)
		NetworkSession.config_changed.disconnect(_refresh_lan_panels)
		if NetworkSession.chat_received.is_connected(_on_chat_line):
			NetworkSession.chat_received.disconnect(_on_chat_line)
		if _avatar_wired and Steam.avatar_loaded.is_connected(_on_avatar_loaded):
			Steam.avatar_loaded.disconnect(_on_avatar_loaded)
		if NetworkSession.system_chat_received.is_connected(_on_system_line):
			NetworkSession.system_chat_received.disconnect(_on_system_line)
		if NetworkSession.internet_ready.is_connected(_on_internet_ready):
			NetworkSession.internet_ready.disconnect(_on_internet_ready)
		if NetworkSession.internet_failed.is_connected(_on_internet_failed):
			NetworkSession.internet_failed.disconnect(_on_internet_failed)

# --- LAN: Steam friend invite picker (the overlay needs a Steam launch) ---

var _friend_popup: PopupPanel = null
var _friend_shade: ColorRect = null

func _open_friend_picker() -> void:
	# Dim the whole lobby behind the picker and keep the panel itself fully
	# opaque — the default PopupPanel skin let the lobby bleed through.
	if not is_instance_valid(_friend_shade):
		_friend_shade = ColorRect.new()
		_friend_shade.color = Color(0.0, 0.0, 0.0, 0.62)
		_friend_shade.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_friend_shade)
		_friend_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_friend_shade.visible = true
	if is_instance_valid(_friend_popup):
		_friend_popup.popup_centered()
		return
	_friend_popup = PopupPanel.new()
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.10, 0.15, 1.0)
	sty.border_color = Color(0.90, 0.82, 0.52, 0.85)
	for side: String in ["left", "right", "top", "bottom"]:
		sty.set("border_width_" + side, 1)
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	_friend_popup.add_theme_stylebox_override("panel", sty)
	_friend_popup.popup_hide.connect(func() -> void:
		if is_instance_valid(_friend_shade):
			_friend_shade.visible = false)
	add_child(_friend_popup)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_friend_popup.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var title: Label = _make_label(tr("STEAM_INVITE"))
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var friends: Array = NetworkSession.get_steam_friends()
	if friends.is_empty():
		var none: Label = Label.new()
		none.text = tr("STEAM_NO_FRIENDS")
		none.add_theme_font_size_override("font_size", 15)
		list.add_child(none)
	for friend: Variant in friends:
		var f: Dictionary = friend as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var dot: Label = Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color",
			Color(0.35, 0.85, 0.35) if (f["online"] as bool) else Color(0.45, 0.45, 0.45))
		row.add_child(dot)
		var name_lbl: Label = Label.new()
		name_lbl.text = f["name"] as String
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not (f["online"] as bool):
			name_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		row.add_child(name_lbl)
		var btn: Button = _make_btn(tr("STEAM_INVITE_ACTION"), Color(0.16, 0.28, 0.40, 0.95), Color(0.22, 0.38, 0.55, 0.95))
		btn.add_theme_font_size_override("font_size", 13)
		var sid: int = f["id"] as int
		btn.pressed.connect(func() -> void:
			if NetworkSession.invite_steam_friend(sid):
				btn.text = tr("STEAM_INVITE_SENT")
				btn.disabled = true)
		row.add_child(btn)
	_friend_popup.popup_centered()

# --- LAN: Internet hosting (UPnP) ---

var _inet_btn: Button = null
var _inet_ip_label: Label = null

func _build_internet_button(row: HBoxContainer, ip_label: Label) -> void:
	_inet_ip_label = ip_label
	_inet_btn = _make_btn(tr("LAN_INTERNET_BTN"), Color(0.16, 0.28, 0.40, 0.95), Color(0.22, 0.38, 0.55, 0.95))
	_inet_btn.add_theme_font_size_override("font_size", 14)
	_inet_btn.tooltip_text = tr("LAN_INTERNET_TIP")
	row.add_child(_inet_btn)
	_inet_btn.pressed.connect(func() -> void:
		_inet_btn.disabled = true
		_inet_ip_label.text = tr("LAN_INTERNET_WAIT")
		NetworkSession.setup_internet())
	if not NetworkSession.internet_ready.is_connected(_on_internet_ready):
		NetworkSession.internet_ready.connect(_on_internet_ready)
	if not NetworkSession.internet_failed.is_connected(_on_internet_failed):
		NetworkSession.internet_failed.connect(_on_internet_failed)

func _on_internet_ready(external_ip: String) -> void:
	if is_instance_valid(_inet_ip_label):
		_inet_ip_label.text = tr("LAN_INTERNET_OK") % [external_ip, NetworkSession.DEFAULT_PORT]
	if is_instance_valid(_inet_btn):
		_inet_btn.visible = false

func _on_internet_failed(_reason: String) -> void:
	if is_instance_valid(_inet_ip_label):
		_inet_ip_label.text = tr("LAN_INTERNET_FAIL") % NetworkSession.DEFAULT_PORT
	if is_instance_valid(_inet_btn):
		_inet_btn.disabled = false

# --- LAN: lobby chat ---

func _build_chat_panel(left: VBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.05, 0.05, 0.09, 0.85)
	sty.corner_radius_top_left = 4
	sty.corner_radius_top_right = 4
	sty.corner_radius_bottom_left = 4
	sty.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sty)
	left.add_child(panel)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(0, 96)
	_chat_log.add_theme_font_size_override("normal_font_size", 14)
	panel.add_child(_chat_log)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	left.add_child(row)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = tr("CHAT_PLACEHOLDER")
	_chat_input.max_length = NetworkSession.CHAT_MAX_LEN
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(t: String) -> void:
		NetworkSession.send_chat(t)
		_chat_input.text = "")
	row.add_child(_chat_input)
	var send: Button = _make_btn(tr("CHAT_SEND"), Color(0.18, 0.30, 0.42, 0.95), Color(0.25, 0.42, 0.58, 0.95))
	send.add_theme_font_size_override("font_size", 15)
	send.pressed.connect(func() -> void:
		NetworkSession.send_chat(_chat_input.text)
		_chat_input.text = "")
	row.add_child(send)
	if not NetworkSession.chat_received.is_connected(_on_chat_line):
		NetworkSession.chat_received.connect(_on_chat_line)
	if not NetworkSession.system_chat_received.is_connected(_on_system_line):
		NetworkSession.system_chat_received.connect(_on_system_line)

func _on_system_line(kind: String, display_name: String) -> void:
	if _chat_log == null:
		return
	_chat_log.append_text("[i][color=#9a9a9a]%s[/color][/i]\n"
		% (tr("CHAT_SYS_" + kind.to_upper()) % display_name.replace("[", "[lb]")))

func _on_chat_line(pid: int, text: String) -> void:
	if _chat_log == null:
		return
	var col: Color = PlayerColors.get_color(pid).lightened(0.35)
	_chat_log.append_text("[color=#%s]%s:[/color] %s\n"
		% [col.to_html(false), NetworkSession.display_name_of(pid), text.replace("[", "[lb]")])

func _maybe_broadcast_lobby() -> void:
	var snap: Dictionary = NetworkSession.snapshot_config()
	if snap != _last_lobby_snapshot:
		_last_lobby_snapshot = snap
		NetworkSession.broadcast_lobby()

func _init_rival_state() -> void:
	for i: int in range(3):
		var civ_id: String = DEFAULT_RIVAL_CIVS[i] if i < DEFAULT_RIVAL_CIVS.size() else "castellanos"
		_rival_civ_indices[i] = _civ_index_for_id(civ_id)
	_sync_rival_config_to_match()
	_sync_teams_to_match()

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
	card.custom_minimum_size = Vector2(960, 0)
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
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("LOBBY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(_make_sep())

	# Two-column body
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	vbox.add_child(columns)

	# ── Left column ─────────────────────────────────────────────────────────
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	# Only the LAN host edits the match settings; clients get a live read-only
	# summary that tracks the host's picks (broadcast_lobby → config_changed).
	# A resumed match freezes the settings for everyone, host included.
	if lan_mode and NetworkSession.resume_active:
		var note: Label = _make_label(tr("LOBBY_RESUME_NOTE"))
		note.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		left.add_child(note)
		_build_settings_summary(left)
		if NetworkSession.is_host():
			var cancel_btn: Button = _make_btn(tr("LOBBY_RESUME_CANCEL"),
				Color(0.30, 0.16, 0.12, 0.95), Color(0.45, 0.24, 0.18, 0.95))
			cancel_btn.add_theme_font_size_override("font_size", 14)
			cancel_btn.pressed.connect(func() -> void:
				NetworkSession.cancel_resume()
				_refresh_lan_panels())
			left.add_child(cancel_btn)
	elif lan_mode and not NetworkSession.is_host():
		_build_settings_summary(left)
	else:
		_build_setting_rows(left)

	if lan_mode:
		left.add_child(_make_sep())
		var players_row: HBoxContainer = HBoxContainer.new()
		players_row.add_theme_constant_override("separation", 12)
		left.add_child(players_row)
		var players_header: Label = _make_label(tr("LAN_PLAYERS"))
		players_header.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
		players_header.add_theme_font_size_override("font_size", 21)
		players_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		players_row.add_child(players_header)
		if NetworkSession.is_steam_session():
			var invite_btn: Button = _make_btn(tr("STEAM_INVITE"), Color(0.16, 0.28, 0.40, 0.95), Color(0.22, 0.38, 0.55, 0.95))
			invite_btn.add_theme_font_size_override("font_size", 15)
			invite_btn.pressed.connect(func() -> void:
				NetworkSession.invite_steam_friends()
				_open_friend_picker())
			players_row.add_child(invite_btn)
		elif NetworkSession.is_host():
			# The address the other players must type to join.
			var ip_label: Label = Label.new()
			ip_label.text = tr("LAN_HOST_IP") % [NetworkSession.local_ipv4(), NetworkSession.DEFAULT_PORT]
			ip_label.add_theme_font_size_override("font_size", 17)
			ip_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
			ip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			players_row.add_child(ip_label)
			_build_internet_button(players_row, ip_label)
		_players_panel = VBoxContainer.new()
		_players_panel.add_theme_constant_override("separation", 6)
		left.add_child(_players_panel)
		_rebuild_players_panel()
		_build_chat_panel(left)

	# ── Right column: player civ ─────────────────────────────────────────────
	# A resumed match fixes every seat's civ from the save — no picker.
	if not (lan_mode and NetworkSession.resume_active):
		_build_civ_column(columns)

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

	if lan_mode and NetworkSession.is_host() and not NetworkSession.resume_active:
		var resume_btn: Button = _make_btn(tr("LOBBY_RESUME_BTN"),
			Color(0.16, 0.28, 0.40, 0.95), Color(0.22, 0.38, 0.55, 0.95))
		resume_btn.custom_minimum_size = Vector2(200, 44)
		resume_btn.pressed.connect(_open_resume_picker)
		btn_row.add_child(resume_btn)

	var start_btn: Button = _make_btn(
		tr("LOBBY_RESUME_START") if NetworkSession.resume_active else tr("LOBBY_START"),
		Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	start_btn.custom_minimum_size = Vector2(200, 44)
	start_btn.add_theme_font_size_override("font_size", 22)
	if lan_mode:
		# Only the host launches; every machine then loads the same world.
		start_btn.visible = NetworkSession.is_host()
		start_btn.pressed.connect(func() -> void:
			start_btn.disabled = true
			NetworkSession.start_match())
	else:
		start_btn.pressed.connect(func() -> void: start_requested.emit())
	btn_row.add_child(start_btn)

## Rebuilds the whole screen in place (used when resume mode flips on/off).
func _rebuild_all() -> void:
	for child: Node in get_children():
		if child != _lobby_sync_timer:
			child.queue_free()
	_players_panel = null
	_chat_log = null
	_chat_input = null
	_summary_label = null
	_civ_detail_vbox = null
	_inet_btn = null
	_inet_ip_label = null
	_player_civ_btns.clear()
	_build()

func _build_civ_column(columns: HBoxContainer) -> void:
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(340, 0)
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
	detail_panel.custom_minimum_size = Vector2(0, 240)

	var detail_margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		detail_margin.add_theme_constant_override("margin_" + side, 12)
	detail_panel.add_child(detail_margin)

	var detail_vbox: VBoxContainer = VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail_vbox)

	_player_civ_desc_label = Label.new()  # reused as the full detail block
	_civ_detail_vbox = detail_vbox

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
			var civ_id: String = (CIVS[captured_i] as Dictionary)["id"] as String
			if lan_mode:
				# YOUR civ pick goes through the host (it lands in the roster
				# and comes back via roster_changed on every machine).
				NetworkSession.request_civ(civ_id)
			else:
				MatchConfig.player_civ_id = civ_id
			_refresh_civ_highlight(_player_civ_btns, captured_i)
			_rebuild_civ_detail(detail_vbox, captured_i))

	_refresh_civ_highlight(_player_civ_btns, _player_civ_index)

	right.add_child(detail_panel)
	_rebuild_civ_detail(detail_vbox, _player_civ_index)

	if lan_mode and not NetworkSession.is_steam_session():
		var name_row: HBoxContainer = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		right.add_child(name_row)
		var name_lbl: Label = _make_label(tr("LAN_NAME"))
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_row.add_child(name_lbl)
		var name_edit: LineEdit = LineEdit.new()
		name_edit.text = NetworkSession.player_name
		name_edit.placeholder_text = tr("LAN_NAME_PLACEHOLDER")
		name_edit.max_length = 24
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Commit on Enter or when leaving the field — never per keystroke, so
		# the roster is not rebroadcast while someone is still typing.
		name_edit.text_submitted.connect(func(t: String) -> void:
			NetworkSession.request_name(t)
			name_edit.release_focus())
		name_edit.focus_exited.connect(func() -> void:
			NetworkSession.request_name(name_edit.text))
		name_row.add_child(name_edit)

# --- Settings rows (offline lobby + LAN host) ---

func _build_setting_rows(left: VBoxContainer) -> void:
	# Map type
	var type_opts: Array[String] = [
		tr("LOBBY_MAPTYPE_PLAINS"), tr("LOBBY_MAPTYPE_STANDARD"),
		tr("LOBBY_MAPTYPE_VOLCANIC"), tr("LOBBY_MAPTYPE_DESERT"), tr("LOBBY_MAPTYPE_ISLANDS"),
	]
	left.add_child(_make_setting_row(tr("LOBBY_MAP_TYPE"), type_opts, MatchConfig.map_type,
		func(i: int) -> void: MatchConfig.map_type = i))

	# Map size
	var size_opts: Array[String] = [tr("LOBBY_MAP_SMALL"), tr("LOBBY_MAP_MEDIUM"), tr("LOBBY_MAP_LARGE")]
	left.add_child(_make_setting_row(tr("LOBBY_MAP_SIZE"), size_opts, MatchConfig.map_size,
		func(i: int) -> void: MatchConfig.map_size = i))

	# Starting resources
	var res_opts: Array[String] = [tr("LOBBY_RES_SCARCE"), tr("LOBBY_RES_NORMAL"), tr("LOBBY_RES_ABUNDANT"), tr("LOBBY_RES_FULL_COMBAT")]
	left.add_child(_make_setting_row(tr("LOBBY_RESOURCES"), res_opts, MatchConfig.resources,
		func(i: int) -> void: MatchConfig.resources = i))

	# Starting age
	var age_opts: Array[String] = []
	for k: String in AGE_KEYS:
		age_opts.append(tr(k))
	left.add_child(_make_setting_row(tr("LOBBY_STARTING_AGE"), age_opts, MatchConfig.starting_age,
		func(i: int) -> void: MatchConfig.starting_age = i))

	# Victory condition
	var victory_opts: Array[String] = [tr("LOBBY_VICTORY_CONQUEST"), tr("LOBBY_VICTORY_REGICIDE"), tr("LOBBY_VICTORY_WONDER")]
	left.add_child(_make_setting_row(tr("LOBBY_VICTORY_MODE"), victory_opts, MatchConfig.victory_mode,
		func(i: int) -> void: MatchConfig.victory_mode = i))

	# Hero gender selection
	var hero_gender_opts: Array[String] = [tr("LOBBY_HERO_RANDOM"), tr("LOBBY_HERO_MALE"), tr("LOBBY_HERO_FEMALE")]
	left.add_child(_make_setting_row(tr("LOBBY_HERO_GENDER"), hero_gender_opts, MatchConfig.hero_gender,
		func(i: int) -> void: MatchConfig.hero_gender = i))

	# Weather
	var weather_opts: Array[String] = [
		tr("LOBBY_WEATHER_OFF"), tr("LOBBY_WEATHER_NORMAL"),
		tr("LOBBY_WEATHER_FREQUENT"), tr("LOBBY_WEATHER_EXTREME"),
	]
	var weather_initial: int = 0 if not MatchConfig.weather_enabled else MatchConfig.weather_frequency
	left.add_child(_make_setting_row(tr("LOBBY_WEATHER_FREQUENCY"), weather_opts, weather_initial,
		func(i: int) -> void:
			MatchConfig.weather_enabled = i > 0
			MatchConfig.weather_frequency = i))

	# In LAN mode the players panel (roster + Open/AI/Closed slots) replaces
	# the rival count/civ rows — rivals are derived from it at match start.
	if not lan_mode:
		left.add_child(_make_sep())

		# Rival count
		var rival_opts: Array[String] = ["1", "2", "3"]
		left.add_child(_make_setting_row(tr("LOBBY_RIVAL_COUNT"), rival_opts, MatchConfig.rival_count - 1,
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

		_rivals_section = HBoxContainer.new()
		_rivals_section.add_theme_constant_override("separation", 10)
		_rivals_section.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		rivals_clip.add_child(_rivals_section)
		_rebuild_rivals_section()

	# Your team (offline: rival teams sit in each rival cell above)
	left.add_child(_make_setting_row(tr("LOBBY_TEAM_YOU"), TEAM_LABELS, _player_team,
		func(i: int) -> void:
			_player_team = i
			_sync_teams_to_match()))

	# AI difficulty
	var diff_opts: Array[String] = [
		tr("LOBBY_DIFFICULTY_EASY"), tr("LOBBY_DIFFICULTY_NORMAL"), tr("LOBBY_DIFFICULTY_HARD"),
	]
	var diff_initial: int = clampi(GameSettings.difficulty, 0, 2)
	left.add_child(_make_setting_row(tr("LOBBY_AI_DIFFICULTY"), diff_opts, diff_initial,
		func(i: int) -> void: GameSettings.difficulty = i))

# --- LAN: read-only settings summary (clients) ---

func _build_settings_summary(left: VBoxContainer) -> void:
	var header: Label = _make_label(tr("LAN_SETTINGS_SUMMARY"))
	left.add_child(header)
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 16)
	_summary_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
	_summary_label.text = _settings_summary_text()
	left.add_child(_summary_label)

func _settings_summary_text() -> String:
	var type_opts: Array[String] = [
		tr("LOBBY_MAPTYPE_PLAINS"), tr("LOBBY_MAPTYPE_STANDARD"),
		tr("LOBBY_MAPTYPE_VOLCANIC"), tr("LOBBY_MAPTYPE_DESERT"), tr("LOBBY_MAPTYPE_ISLANDS"),
	]
	var size_opts: Array[String] = [tr("LOBBY_MAP_SMALL"), tr("LOBBY_MAP_MEDIUM"), tr("LOBBY_MAP_LARGE")]
	var res_opts: Array[String] = [tr("LOBBY_RES_SCARCE"), tr("LOBBY_RES_NORMAL"), tr("LOBBY_RES_ABUNDANT"), tr("LOBBY_RES_FULL_COMBAT")]
	var victory_opts: Array[String] = [tr("LOBBY_VICTORY_CONQUEST"), tr("LOBBY_VICTORY_REGICIDE"), tr("LOBBY_VICTORY_WONDER")]
	var hero_opts: Array[String] = [tr("LOBBY_HERO_RANDOM"), tr("LOBBY_HERO_MALE"), tr("LOBBY_HERO_FEMALE")]
	var weather_opts: Array[String] = [
		tr("LOBBY_WEATHER_OFF"), tr("LOBBY_WEATHER_NORMAL"),
		tr("LOBBY_WEATHER_FREQUENT"), tr("LOBBY_WEATHER_EXTREME"),
	]
	var weather_idx: int = MatchConfig.weather_frequency if MatchConfig.weather_enabled else 0
	var lines: Array[String] = [
		"%s  %s" % [tr("LOBBY_MAP_TYPE"), type_opts[clampi(MatchConfig.map_type, 0, type_opts.size() - 1)]],
		"%s  %s" % [tr("LOBBY_MAP_SIZE"), size_opts[clampi(MatchConfig.map_size, 0, size_opts.size() - 1)]],
		"%s  %s" % [tr("LOBBY_RESOURCES"), res_opts[clampi(MatchConfig.resources, 0, res_opts.size() - 1)]],
		"%s  %s" % [tr("LOBBY_STARTING_AGE"), tr(AGE_KEYS[clampi(MatchConfig.starting_age, 0, AGE_KEYS.size() - 1)])],
		"%s  %s" % [tr("LOBBY_VICTORY_MODE"), victory_opts[clampi(MatchConfig.victory_mode, 0, victory_opts.size() - 1)]],
		"%s  %s" % [tr("LOBBY_HERO_GENDER"), hero_opts[clampi(MatchConfig.hero_gender, 0, hero_opts.size() - 1)]],
		"%s  %s" % [tr("LOBBY_WEATHER_FREQUENCY"), weather_opts[clampi(weather_idx, 0, weather_opts.size() - 1)]],
	]
	return "\n".join(lines)

# --- LAN: players panel (live roster + Open/AI/Closed slots) ---

func _refresh_lan_panels() -> void:
	if not lan_mode:
		return
	if NetworkSession.resume_active != _resume_built:
		_resume_built = NetworkSession.resume_active
		_rebuild_all()
		return
	_rebuild_players_panel()
	if _summary_label != null:
		_summary_label.text = _settings_summary_text()
	# Your civ highlight follows the host-confirmed roster, not the raw click.
	var roster: Dictionary = NetworkSession.get_roster()
	var entry: Variant = roster.get(NetworkSession.local_player_id)
	if entry is Dictionary:
		var idx: int = _civ_index_for_id((entry as Dictionary).get("civ", "castellanos") as String)
		if idx != _player_civ_index:
			_player_civ_index = idx
			_refresh_civ_highlight(_player_civ_btns, idx)
			if _civ_detail_vbox != null:
				_rebuild_civ_detail(_civ_detail_vbox, idx)

func _rebuild_players_panel() -> void:
	if _players_panel == null:
		return
	for child: Node in _players_panel.get_children():
		child.queue_free()
	if NetworkSession.resume_active:
		for seat: Variant in NetworkSession.resume_seat_view():
			_add_resume_row(seat as Dictionary)
		return
	var roster: Dictionary = NetworkSession.get_roster()
	_add_human_row(0, roster)
	var client_ids: Array = []
	for pid: Variant in roster:
		if (pid as int) != 0:
			client_ids.append(pid)
	client_ids.sort()
	# Each connected client occupies the earliest still-open slot; the other
	# slots stay configurable (Open waits, AI shows its civ, Closed is off).
	var next_client: int = 0
	for si: int in range(NetworkSession.lobby_slots.size()):
		var slot: Dictionary = NetworkSession.lobby_slots[si] as Dictionary
		if (slot.get("type", "") as String) == "open" and next_client < client_ids.size():
			_add_human_row(client_ids[next_client] as int, roster)
			next_client += 1
		else:
			_add_slot_row(si, slot)
	while next_client < client_ids.size():
		_add_human_row(client_ids[next_client] as int, roster)
		next_client += 1

## One original seat of a resumed match: claimed (normal look) or greyed-out
## "waiting for <name>…". Everything is locked — the save decides it all.
func _add_resume_row(seat: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_players_panel.add_child(row)

	var connected: bool = seat.get("connected", false) as bool
	var pid: int = seat.get("pid", -1) as int
	var swatch: ColorRect = ColorRect.new()
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.color = PlayerColors.COLORS[clampi(seat.get("color", 0) as int,
		0, PlayerColors.COLORS.size() - 1)]
	if not connected:
		swatch.color = swatch.color.darkened(0.55)
	row.add_child(swatch)

	var name_label: Label = Label.new()
	var display: String = str(seat.get("name", "?"))
	if pid == 0:
		display += "  (%s)" % tr("LAN_HOST_TAG")
	if connected and pid == NetworkSession.local_player_id:
		display += "  ◄"
	name_label.text = display if connected else tr("LAN_SEAT_WAITING") % display
	if not connected:
		name_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.65))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	row.add_child(name_label)

	var civ_label: Label = Label.new()
	civ_label.text = _civ_name(seat.get("civ", "") as String)
	civ_label.add_theme_font_size_override("font_size", 15)
	civ_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.60))
	row.add_child(civ_label)

	var team: int = seat.get("team", 0) as int
	var team_lbl: Label = Label.new()
	team_lbl.text = "%s %s" % [tr("LOBBY_TEAM"), TEAM_LABELS[clampi(team, 0, 4)]]
	team_lbl.add_theme_font_size_override("font_size", 14)
	team_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.75))
	row.add_child(team_lbl)

## Overlay listing only MULTIPLAYER saves; picking one freezes the lobby.
func _open_resume_picker() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	var sty: StyleBoxFlat = StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.10, 0.15, 1.0)
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", sty)
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	card.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title: Label = _make_label(tr("LOBBY_RESUME_TITLE"))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)
	vbox.add_child(_make_sep())

	var mp_saves: Array[Dictionary] = []
	for meta: Dictionary in SaveManager.list_saves():
		if meta.get("multiplayer", false):
			mp_saves.append(meta)
	if mp_saves.is_empty():
		var none: Label = Label.new()
		none.text = tr("LOBBY_RESUME_EMPTY")
		none.add_theme_font_size_override("font_size", 15)
		none.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60))
		vbox.add_child(none)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(56.0 * mp_saves.size() + 8.0, 300.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for meta: Dictionary in mp_saves:
		var slot: int = meta.get("slot", 0) as int
		var names: Array = meta.get("player_names", []) as Array
		var btn: Button = _make_btn("%s\n%s" % [str(meta.get("display_name", "")),
			", ".join(PackedStringArray(names))],
			Color(0.16, 0.20, 0.32, 0.95), Color(0.24, 0.32, 0.50, 0.95))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		list.add_child(btn)
		var captured_slot: int = slot
		btn.pressed.connect(func() -> void:
			if NetworkSession.begin_resume(captured_slot):
				shade.queue_free()
				_refresh_lan_panels())

	vbox.add_child(_make_sep())
	var cancel: Button = _make_btn(tr("SAVE_CANCEL"),
		Color(0.22, 0.10, 0.10, 0.95), Color(0.38, 0.15, 0.12, 0.95))
	cancel.pressed.connect(func() -> void: shade.queue_free())
	vbox.add_child(cancel)

func _add_human_row(pid: int, roster: Dictionary) -> void:
	if not roster.has(pid):
		return
	var entry: Dictionary = roster[pid] as Dictionary
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_players_panel.add_child(row)

	var is_local: bool = pid == NetworkSession.local_player_id
	var sid: int = entry.get("sid", 0) as int
	if sid != 0:
		row.add_child(_avatar_rect(sid))
	if is_local:
		# Your row carries the palette: pick your colour right here.
		var own_color: int = entry.get("color", 0) as int
		for idx: int in range(PlayerColors.COLORS.size()):
			row.add_child(_make_color_swatch(idx, own_color, roster))
	else:
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.color = PlayerColors.COLORS[entry.get("color", 0) as int]
		row.add_child(swatch)

	var name_label: Label = Label.new()
	var suffix: String = ""
	if pid == 0:
		suffix = "  (%s)" % tr("LAN_HOST_TAG")
	if is_local:
		suffix += "  ◄"
	name_label.text = str(entry.get("name", "?")) + suffix
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	row.add_child(name_label)

	var civ_label: Label = Label.new()
	civ_label.text = _civ_name(entry.get("civ", "") as String)
	civ_label.add_theme_font_size_override("font_size", 15)
	civ_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.60))
	row.add_child(civ_label)
	var team: int = entry.get("team", 0) as int
	if is_local:
		row.add_child(_make_team_dropdown(team,
			func(i: int) -> void: NetworkSession.request_team(i)))
	else:
		var team_lbl: Label = Label.new()
		team_lbl.text = "%s %s" % [tr("LOBBY_TEAM"), TEAM_LABELS[clampi(team, 0, 4)]]
		team_lbl.add_theme_font_size_override("font_size", 14)
		team_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.75))
		row.add_child(team_lbl)

	if NetworkSession.is_host() and pid != 0:
		var kick_btn: Button = Button.new()
		kick_btn.text = tr("LAN_KICK")
		kick_btn.focus_mode = Control.FOCUS_NONE
		kick_btn.add_theme_font_size_override("font_size", 13)
		kick_btn.pressed.connect(func() -> void: NetworkSession.kick(pid))
		row.add_child(kick_btn)

# ── Steam avatars: async fetch, cached per steam id ──
var _avatar_cache: Dictionary = {}
var _avatar_wired: bool = false

func _avatar_rect(sid: int) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.custom_minimum_size = Vector2(24, 24)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	if _avatar_cache.has(sid):
		rect.texture = _avatar_cache[sid]
	else:
		if not _avatar_wired:
			_avatar_wired = true
			Steam.avatar_loaded.connect(_on_avatar_loaded)
		Steam.getPlayerAvatar(2, sid)   # AVATAR_MEDIUM (64x64)
	return rect

func _on_avatar_loaded(avatar_id: int, av_size: int, data: PackedByteArray) -> void:
	var img: Image = Image.create_from_data(av_size, av_size, false, Image.FORMAT_RGBA8, data)
	_avatar_cache[avatar_id] = ImageTexture.create_from_image(img)
	_rebuild_players_panel()

func _make_color_swatch(idx: int, own_color: int, roster: Dictionary) -> Button:
	var taken: bool = false
	for e: Variant in roster.values():
		if ((e as Dictionary).get("color", -1) as int) == idx:
			taken = true
			break
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(24, 24)
	btn.focus_mode = Control.FOCUS_NONE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PlayerColors.COLORS[idx]
	if idx == own_color:
		sb.border_color = Color.WHITE
		for side: String in ["left", "right", "top", "bottom"]:
			sb.set("border_width_" + side, 3)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.disabled = taken and idx != own_color
	if btn.disabled:
		btn.modulate = Color(1.0, 1.0, 1.0, 0.35)
	btn.pressed.connect(func() -> void: NetworkSession.request_color(idx))
	return btn

func _add_slot_row(si: int, slot: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_players_panel.add_child(row)
	var slot_type: String = slot.get("type", "closed") as String

	var lbl: Label = Label.new()
	lbl.text = tr("LAN_SLOT") % (si + 2)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	row.add_child(lbl)

	if not NetworkSession.is_host():
		var state_label: Label = Label.new()
		var text: String = tr("LAN_SLOT_" + slot_type.to_upper())
		if slot_type == "ai":
			text += " — " + _civ_name(slot.get("civ", "") as String)
		state_label.text = text
		state_label.add_theme_font_size_override("font_size", 15)
		row.add_child(state_label)
		return

	var type_opt: OptionButton = OptionButton.new()
	type_opt.focus_mode = Control.FOCUS_NONE
	type_opt.add_theme_font_size_override("font_size", 15)
	type_opt.add_item(tr("LAN_SLOT_OPEN"), 0)
	type_opt.add_item(tr("LAN_SLOT_AI"), 1)
	type_opt.add_item(tr("LAN_SLOT_CLOSED"), 2)
	var type_ids: Array[String] = ["open", "ai", "closed"]
	type_opt.select(type_ids.find(slot_type))
	type_opt.item_selected.connect(func(i: int) -> void:
		(NetworkSession.lobby_slots[si] as Dictionary)["type"] = type_ids[i]
		NetworkSession.broadcast_lobby()
		_rebuild_players_panel())
	row.add_child(type_opt)

	if slot_type == "ai":
		var civ_opt: OptionButton = _make_civ_dropdown(
			_civ_index_for_id(slot.get("civ", "castellanos") as String),
			func(i: int) -> void:
				(NetworkSession.lobby_slots[si] as Dictionary)["civ"] = (CIVS[i] as Dictionary)["id"] as String
				NetworkSession.broadcast_lobby())
		civ_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(civ_opt)
		row.add_child(_make_team_dropdown(slot.get("team", 0) as int,
			func(i: int) -> void:
				(NetworkSession.lobby_slots[si] as Dictionary)["team"] = i
				NetworkSession.broadcast_lobby()))

func _civ_name(civ_id: String) -> String:
	for civ: Dictionary in CIVS:
		if (civ["id"] as String) == civ_id:
			return tr(civ["name_key"] as String)
	return civ_id

# --- Rivals section ---

func _rebuild_rivals_section() -> void:
	if _rivals_section == null:
		return
	for child: Node in _rivals_section.get_children():
		child.queue_free()
	# One compact cell per rival, all on a single row: "1: [civ v]" ...
	for ri: int in range(MatchConfig.rival_count):
		var cell: HBoxContainer = HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rivals_section.add_child(cell)
		var lbl: Label = _make_label("%d:" % (ri + 1))
		lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		lbl.tooltip_text = tr("LOBBY_RIVAL") + " %d" % (ri + 1)
		cell.add_child(lbl)
		var captured_ri: int = ri
		var dropdown: OptionButton = _make_civ_dropdown(_rival_civ_indices[ri],
			func(i: int) -> void:
				_rival_civ_indices[captured_ri] = i
				_sync_rival_config_to_match())
		dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(dropdown)
		cell.add_child(_make_team_dropdown(_rival_teams[ri],
			func(i: int) -> void:
				_rival_teams[captured_ri] = i
				_sync_teams_to_match()))

# --- Civ detail panel ---

func _rebuild_civ_detail(vbox: VBoxContainer, civ_idx: int) -> void:
	for child: Node in vbox.get_children():
		child.queue_free()

	var civ: Dictionary = CIVS[civ_idx] as Dictionary
	var civ_id: String = civ["id"] as String
	var details: Dictionary = CIV_DETAILS.get(civ_id, {}) as Dictionary

	# Description
	_add_detail_text(vbox, tr(civ["desc_key"] as String), Color(0.80, 0.80, 0.80), 4)

	vbox.add_child(HSeparator.new())

	# Hero (show based on gender selection)
	var hero_name: String = ""
	var hero_ability_desc: String = ""
	match MatchConfig.hero_gender:
		MatchConfig.HeroGender.RANDOM:
			hero_name = details.get("hero_m", "") as String + " / " + details.get("hero_f", "") as String
			hero_ability_desc = tr("LOBBY_HERO_RANDOM_DESC")
		MatchConfig.HeroGender.MALE:
			hero_name = details.get("hero_m", "") as String
			hero_ability_desc = tr(details.get("ability_desc_m", "") as String)
		MatchConfig.HeroGender.FEMALE:
			hero_name = details.get("hero_f", "") as String
			hero_ability_desc = tr(details.get("ability_desc_f", "") as String)

	if not hero_name.is_empty():
		_add_detail_row(vbox, tr("LOBBY_CIV_HERO"), hero_name, Color(1.0, 0.85, 0.40))
		_add_detail_text(vbox, hero_ability_desc, Color(0.68, 0.80, 0.95))

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

# Height of one wrapped line at the detail font size (14 px + leading).
const DETAIL_LINE_H: float = 21.0

func _add_detail_text(vbox: VBoxContainer, text: String, color: Color,
		min_lines: int = 0) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	# Reserving a fixed line count keeps the detail card height stable when
	# switching between civs with shorter and longer descriptions.
	if min_lines > 0:
		lbl.custom_minimum_size = Vector2(0, DETAIL_LINE_H * float(min_lines))
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

# Compact single-line setting: fixed-width label left, segmented options
# right — halves the card height vs the stacked label-above-row layout.
func _make_setting_row(label_text: String, labels: Array[String], initial: int,
		on_select: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl: Label = _make_label(label_text)
	lbl.custom_minimum_size = Vector2(SETTING_LABEL_W, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var opts: HBoxContainer = _make_option_row(labels, initial, on_select)
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opts)
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

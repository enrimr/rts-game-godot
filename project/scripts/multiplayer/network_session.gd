extends Node

## NetworkSession (autoload) — host-authoritative LAN/Internet session over
## ENet. The HOST is the single simulation authority: clients never execute
## commands locally, they serialize them to the host (CommandBus redirects),
## and the host stamps the SENDER's assigned player_id onto every incoming
## command — the wire never decides identity, so a hostile client cannot order
## another player's units no matter what it puts in the payload.
##
## Match start: the host freezes MatchConfig + a shared seed and broadcasts
## them; every machine then loads game_world with identical settings, so the
## deterministic map generation and EntityRegistry hand out identical entity
## IDs on both sides — command payloads reference entities by those IDs.
##
## Phase 1 scope: session + lobby handshake + the client→host command pipe.
## Phase 2 adds host→client state replication with interpolation; until then
## a client's local world does not mirror the host's simulation.

enum Role { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT: int = 8910
const MAX_CLIENTS: int = 3

signal peer_joined(peer_id: int, player_id: int)
signal peer_left(peer_id: int)
signal joined_host()
signal join_failed()
signal session_closed()
## CLIENT only: the connection to the host dropped unexpectedly (host quit,
## network loss) — emitted BEFORE the session resets, so a running match can
## tell the player apart from a voluntary leave.
signal connection_lost()
## HOST only: a human player resigned (explicitly, or by disconnecting
## mid-match). The victory system turns this into an elimination.
signal player_resigned(player_id: int)
## The lobby roster (names/colours/civs/joins/leaves) changed on any machine.
signal roster_changed()
## The host's lobby settings (MatchConfig snapshot + AI/open slots) changed.
signal config_changed()
## This machine was kicked by the host.
signal kicked()
## Fired on every machine when the host starts the match (config applied).
signal match_started()
## CLIENT: the host refused this connection (kind "version" carries the host's
## version) — emitted just before the socket drops so the join UI can say WHY.
signal join_refused(kind: String, detail: String)

var role: Role = Role.OFFLINE
var local_player_id: int = 0
## Local profile, set by the lobby UI BEFORE hosting/joining.
var player_name: String = ""
## Harnesses instantiate the world themselves instead of a scene change.
var auto_change_scene: bool = true

var _peer_players: Dictionary = {}   # peer_id -> player_id (host side)
# Peers thrown out by the host: their disconnect must not announce "left".
var _kicked_peers: Dictionary = {}
var _next_player_id: int = 1
## player_id -> {"name": String, "color": int, "civ": String, "peer": int}.
## Host-authoritative, rebroadcast in full on every change (≤ 4 rows).
var _roster: Dictionary = {}
## Host-authored rival slots BEYOND the humans: [{"type": "open"|"ai"|"closed",
## "civ": String}] × 3, broadcast with the lobby config so clients render them.
var lobby_slots: Array = []
## Which player ids are humans in the RUNNING match (set at start; [0] offline
## so skirmish rivals always get their AI brains).
var match_human_ids: Array = [0]

# ── Mid-match reconnection ──
## Seconds a dropped player's seat stays reserved before it becomes a
## resignation. Var (not const) so harnesses can shrink it via env.
var rejoin_grace_sec: float = 90.0
## pid -> {"entry": roster row, "deadline_msec": int} for dropped players.
var _vacant_seats: Dictionary = {}
## peer_id -> true: connected mid-match, waiting for its profile to claim a seat.
var _pending_rejoin: Dictionary = {}
## The frozen start_match config — resent verbatim to a rejoiner.
var _match_cfg: Dictionary = {}
## HOST: a rejoined client booted its mirror world and wants the full state.
signal peer_resync_requested(player_id: int)
## CLIENT: set by apply_config of an in-progress match; the replicator asks
## for the resync once the world is up.
var rejoin_pending: bool = false
# Last endpoints, so "Reconectar" can retry after a drop.
var _last_join_ip: String = ""
var _last_steam_lobby: int = 0

# ── Resumed multiplayer saves ──
## A reserved resume seat has no expiry until the match actually starts.
const RESUME_NO_DEADLINE: int = 1 << 62
## HOST lobby (and mirrored to clients via the lobby broadcast): a multiplayer
## save was picked — the settings are frozen and every original seat waits for
## its player (matched by Steam ID or name, same rules as the mid-match rejoin).
var resume_active: bool = false
## Every machine, frozen at start: this match was restored from a save. Clients
## boot an EMPTY mirror world and adopt the host's entities via the resync.
var resumed_match: bool = false
## CLIENT: the host's resume seat rows for the lobby players panel.
var remote_resume_seats: Array = []
## HOST: per-player fog collected from the clients for a mid-match save.
var client_fogs: Dictionary = {}   # pid -> base64(zstd-compressed fog cells)

func _ready() -> void:
	# Networking must survive a paused SceneTree: the host keeps serving
	# clients while its pause menu is open, and a remotely-paused client must
	# still receive the unpause event.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var grace_env: String = OS.get_environment("CALIMA_REJOIN_GRACE")
	if not grace_env.is_empty():
		rejoin_grace_sec = float(grace_env)

func _process(_delta: float) -> void:
	if _steam_initialized:
		Steam.run_callbacks()
	if role == Role.HOST and _match_running() and not _vacant_seats.is_empty():
		for pid: Variant in _vacant_seats.keys():
			if Time.get_ticks_msec() >= (_vacant_seats[pid] as Dictionary)["deadline_msec"] as int:
				var gone: Dictionary = (_vacant_seats[pid] as Dictionary)["entry"] as Dictionary
				_vacant_seats.erase(pid)
				announce("resigned", gone.get("name", "") as String)
				player_resigned.emit(pid as int)

func is_online() -> bool:
	return role != Role.OFFLINE

## Single source of truth for the build version the handshake compares.
static func game_version() -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return v if not v.is_empty() else "dev"

func is_client() -> bool:
	return role == Role.CLIENT

func is_host() -> bool:
	return role == Role.HOST

func player_count() -> int:
	return 1 + _peer_players.size()

func _match_running() -> bool:
	return GameManager.state == GameManager.GameState.PLAYING \
		or GameManager.state == GameManager.GameState.PAUSED

func host_game(port: int = DEFAULT_PORT) -> Error:
	# A stale session (e.g. a previous Host click whose lobby never opened)
	# still holds the port — close it before rebinding. Only a REAL session:
	# the engine's default OfflineMultiplayerPeer must not be touched.
	if is_online():
		leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_enter_host_state()
	return OK

## Everything a fresh host session needs, whatever the transport.
func _enter_host_state() -> void:
	role = Role.HOST
	local_player_id = 0
	_peer_players.clear()
	_next_player_id = 1
	_roster = {0: {"name": _display_name(0), "color": 0, "civ": MatchConfig.player_civ_id, "team": 0, "peer": 1}}
	lobby_slots = _default_lobby_slots()
	_connect_signals()
	roster_changed.emit()

static func _default_lobby_slots() -> Array:
	return [
		{"type": "open", "civ": "castellanos", "team": 0},
		{"type": "closed", "civ": "franks", "team": 0},
		{"type": "closed", "civ": "atlantes", "team": 0},
	]

## The LAN address other players must type to join (best-effort pick of the
## private-range interface; shown in the host's lobby).
static func local_ipv4() -> String:
	var fallback: String = "127.0.0.1"
	for addr: String in IP.get_local_addresses():
		if addr.contains(":") or addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or _is_172_private(addr):
			return addr
		if fallback == "127.0.0.1":
			fallback = addr
	return fallback

## 172.16.0.0/12 spans 172.16. through 172.31. (hotspots often hand out 172.20.x).
static func _is_172_private(addr: String) -> bool:
	if not addr.begins_with("172."):
		return false
	var second: int = int(addr.get_slice(".", 1))
	return second >= 16 and second <= 31

## Human seats still free: "open" slots not yet taken by a connected client.
func open_seats_left() -> int:
	var open_count: int = 0
	for slot: Variant in lobby_slots:
		if ((slot as Dictionary).get("type", "") as String) == "open":
			open_count += 1
	return open_count - _peer_players.size()

func _display_name(player_id: int) -> String:
	var trimmed: String = player_name.strip_edges()
	return trimmed if not trimmed.is_empty() else tr("LAN_DEFAULT_NAME") % (player_id + 1)

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	if is_online():
		leave()
	_last_join_ip = ip
	_last_steam_lobby = 0
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_connect_signals()
	return OK

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	role = Role.OFFLINE
	local_player_id = 0
	_peer_players.clear()
	_kicked_peers.clear()
	_vacant_seats.clear()
	_pending_rejoin.clear()
	_match_cfg = {}
	rejoin_pending = false
	resume_active = false
	resumed_match = false
	remote_resume_seats = []
	client_fogs.clear()
	_teardown_internet()
	if steam_lobby_id != 0:
		Steam.leaveLobby(steam_lobby_id)
		Steam.clearRichPresence()
		steam_lobby_id = 0
	_roster.clear()
	lobby_slots = []
	match_human_ids = [0]
	PlayerColors.clear_overrides()
	session_closed.emit()

func _connect_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	if _match_running() or resume_active:
		# Mid-match (and the resume lobby) only a reserved seat's owner may
		# enter; the seat is claimed by the profile that arrives next
		# (identity by Steam ID or name — or by being the only vacancy).
		if _vacant_seats.is_empty():
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		else:
			_pending_rejoin[peer_id] = true
		return
	# No open human seat left → refuse the connection outright.
	if open_seats_left() <= 0:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	var pid: int = _next_player_id
	_next_player_id += 1
	_peer_players[peer_id] = pid
	_roster[pid] = {"name": tr("LAN_DEFAULT_NAME") % (pid + 1),
		"color": _first_free_color(), "civ": "castellanos", "team": 0, "peer": peer_id}
	if is_steam_session():
		(_roster[pid] as Dictionary)["sid"] = \
			(multiplayer.multiplayer_peer as SteamMultiplayerPeer).get_steam_id_for_peer_id(peer_id)
	_rx_assign_player.rpc_id(peer_id, pid)
	_broadcast_roster()
	broadcast_lobby()
	peer_joined.emit(peer_id, pid)

func _on_peer_disconnected(peer_id: int) -> void:
	var pid: int = _peer_players.get(peer_id, -1) as int
	_peer_players.erase(peer_id)
	if pid >= 0:
		var gone_name: String = display_name_of(pid)
		var gone_entry: Dictionary = (_roster.get(pid, {}) as Dictionary).duplicate()
		_roster.erase(pid)
		_broadcast_roster()
		if _kicked_peers.has(peer_id):
			_kicked_peers.erase(peer_id)
		elif resume_active:
			# A claimed resume seat opens up again — no expiry until start.
			_vacant_seats[pid] = {"entry": gone_entry, "deadline_msec": RESUME_NO_DEADLINE}
			announce("left", gone_name)
			broadcast_lobby()
		elif _match_running() and match_human_ids.has(pid):
			# Reserve the seat: crashes and wifi blips deserve a way back.
			_vacant_seats[pid] = {"entry": gone_entry,
				"deadline_msec": Time.get_ticks_msec() + int(rejoin_grace_sec * 1000.0)}
			announce("disconnected", gone_name)
		else:
			announce("left", gone_name)
	peer_left.emit(peer_id)

func _on_connected_to_server() -> void:
	# Introduce ourselves; the host validates and rebroadcasts the roster.
	_tx_profile.rpc_id(1, player_name, game_version())
	joined_host.emit()

func _on_connection_failed() -> void:
	leave()
	join_failed.emit()

func _on_server_disconnected() -> void:
	connection_lost.emit()
	leave()

@rpc("authority", "reliable")
func _rx_assign_player(player_id: int) -> void:
	local_player_id = player_id

# ── Lobby roster: names, colours, kicks (host-authoritative) ────────────────

func get_roster() -> Dictionary:
	return _roster

func _first_free_color() -> int:
	for idx: int in range(PlayerColors.COLORS.size()):
		if not _color_taken(idx):
			return idx
	return 0

func _color_taken(idx: int) -> bool:
	for entry: Variant in _roster.values():
		if ((entry as Dictionary).get("color", -1) as int) == idx:
			return true
	return false

func _broadcast_roster() -> void:
	if role == Role.HOST:
		_rx_roster.rpc(_roster)
	roster_changed.emit()

@rpc("authority", "reliable")
func _rx_roster(roster: Dictionary) -> void:
	_roster = roster
	roster_changed.emit()

@rpc("any_peer", "reliable")
func _tx_profile(display_name: String, version: String = "") -> void:
	if role != Role.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# Version guard — fresh joins AND rejoins introduce themselves here, so one
	# check covers both. A mismatched build would desync the mirror world.
	if version != game_version():
		_refuse_peer(sender, "version", game_version())
		return
	if _pending_rejoin.has(sender):
		_pending_rejoin.erase(sender)
		_try_rejoin(sender, display_name.strip_edges().left(24))
		return
	var pid: int = _peer_players.get(sender, -1) as int
	if pid < 0 or not _roster.has(pid):
		return
	var trimmed: String = display_name.strip_edges().left(24)
	if not trimmed.is_empty():
		(_roster[pid] as Dictionary)["name"] = trimmed
	_broadcast_roster()
	announce("joined", (_roster[pid] as Dictionary)["name"] as String)

## HOST: turn a connection away with a reason the other side can display.
## The reliable refusal flushes before the graceful disconnect lands.
func _refuse_peer(peer_id: int, kind: String, detail: String) -> void:
	_pending_rejoin.erase(peer_id)
	var pid: int = _peer_players.get(peer_id, -1) as int
	if pid >= 0:
		_peer_players.erase(peer_id)
		_roster.erase(pid)
		_broadcast_roster()
	_kicked_peers[peer_id] = true
	_rx_refused.rpc_id(peer_id, kind, detail)
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)

@rpc("authority", "reliable")
func _rx_refused(kind: String, detail: String) -> void:
	join_refused.emit(kind, detail)

## Rename YOURSELF mid-lobby (or mid-match); the host validates and the
## roster broadcast updates every players panel and chat display name.
func request_name(new_name: String) -> void:
	var trimmed: String = new_name.strip_edges().left(24)
	if trimmed.is_empty():
		return
	player_name = trimmed
	if role == Role.HOST:
		_apply_rename(0, trimmed)
	elif role == Role.CLIENT:
		_tx_rename.rpc_id(1, trimmed)

@rpc("any_peer", "reliable")
func _tx_rename(new_name: String) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		_apply_rename(pid, new_name.strip_edges().left(24))

func _apply_rename(pid: int, new_name: String) -> void:
	# Steam sessions show the players' real Steam names — never editable.
	# Resume seats are identity: renaming would break the seat matching.
	if is_steam_session() or resume_active:
		return
	if new_name.is_empty() or not _roster.has(pid):
		return
	var old_name: String = (_roster[pid] as Dictionary).get("name", "") as String
	if old_name == new_name:
		return
	(_roster[pid] as Dictionary)["name"] = new_name
	_broadcast_roster()
	announce("renamed", "%s → %s" % [old_name, new_name])

## HOST: a mid-match connection introduced itself — match it to a vacant
## seat (by roster name, or the single vacancy) and put it back in the game.
func _try_rejoin(peer_id: int, claimed_name: String) -> void:
	var seat_pid: int = -1
	if is_steam_session():
		# Steam identity is cryptographic: the seat's steam id must match the
		# connecting peer's — a display name proves nothing and is spoofable.
		var sid: int = (multiplayer.multiplayer_peer as SteamMultiplayerPeer) \
			.get_steam_id_for_peer_id(peer_id)
		for pid: Variant in _vacant_seats:
			if ((_vacant_seats[pid] as Dictionary)["entry"] as Dictionary).get("sid", 0) as int == sid \
					and sid != 0:
				seat_pid = pid as int
				break
	else:
		for pid: Variant in _vacant_seats:
			if ((_vacant_seats[pid] as Dictionary)["entry"] as Dictionary).get("name", "") == claimed_name:
				seat_pid = pid as int
				break
		if seat_pid < 0 and _vacant_seats.size() == 1:
			seat_pid = _vacant_seats.keys()[0] as int
	if seat_pid < 0:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	var entry: Dictionary = (_vacant_seats[seat_pid] as Dictionary)["entry"] as Dictionary
	_vacant_seats.erase(seat_pid)
	entry["peer"] = peer_id
	if is_steam_session():
		entry["sid"] = (multiplayer.multiplayer_peer as SteamMultiplayerPeer) \
			.get_steam_id_for_peer_id(peer_id)
	if not claimed_name.is_empty() and not is_steam_session():
		entry["name"] = claimed_name
	_roster[seat_pid] = entry
	_peer_players[peer_id] = seat_pid
	_rx_assign_player.rpc_id(peer_id, seat_pid)
	_broadcast_roster()
	if _match_running():
		announce("returned", entry.get("name", "") as String)
		# Same frozen config, flagged so the client asks for the full resync
		# once its mirror world is up.
		var cfg: Dictionary = _match_cfg.duplicate(true)
		cfg["in_progress"] = true
		_rx_match_config.rpc_id(peer_id, cfg)
	else:
		# Resume lobby: the seat is claimed; the match starts when the host says.
		announce("joined", entry.get("name", "") as String)
		broadcast_lobby()

## CLIENT (rejoiner): the mirror world finished booting — ask for the state.
func notify_resync_ready() -> void:
	if role == Role.CLIENT:
		_tx_resync_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _tx_resync_ready() -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid > 0:
		peer_resync_requested.emit(pid)

## Retry the last session after a drop ("Reconectar" on the lost dialog).
func rejoin_last() -> bool:
	if _last_steam_lobby != 0 and ensure_steam():
		join_steam_lobby(_last_steam_lobby)
		return true
	if not _last_join_ip.is_empty():
		return join_game(_last_join_ip) == OK
	return false

## Pick a colour for YOURSELF; the host validates it is free.
func request_color(idx: int) -> void:
	if role == Role.HOST:
		_apply_color_pick(0, idx)
	elif role == Role.CLIENT:
		_tx_pick_color.rpc_id(1, idx)

## Pick YOUR team (0 = none / free-for-all).
func request_team(team: int) -> void:
	if role == Role.HOST:
		_apply_team_pick(0, team)
	elif role == Role.CLIENT:
		_tx_pick_team.rpc_id(1, team)

@rpc("any_peer", "reliable")
func _tx_pick_team(team: int) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		_apply_team_pick(pid, team)

func _apply_team_pick(pid: int, team: int) -> void:
	if not _roster.has(pid) or resume_active:
		return
	(_roster[pid] as Dictionary)["team"] = clampi(team, 0, 4)
	_broadcast_roster()

## Pick YOUR civilization (duplicates allowed — mirror matches are fine).
func request_civ(civ_id: String) -> void:
	if role == Role.HOST:
		_apply_civ_pick(0, civ_id)
	elif role == Role.CLIENT:
		_tx_pick_civ.rpc_id(1, civ_id)

@rpc("any_peer", "reliable")
func _tx_pick_civ(civ_id: String) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		_apply_civ_pick(pid, civ_id)

func _apply_civ_pick(pid: int, civ_id: String) -> void:
	if not _roster.has(pid) or resume_active:
		return
	if not ResourceLoader.exists("res://resources/civilizations/%s.tres" % civ_id):
		return
	(_roster[pid] as Dictionary)["civ"] = civ_id
	_broadcast_roster()

## Host: push the lobby settings (MatchConfig snapshot + rival slots) to every
## client, so their read-only summary tracks the host's picks live.
func broadcast_lobby() -> void:
	if role != Role.HOST:
		return
	var d: Dictionary = {"cfg": snapshot_config(), "slots": lobby_slots}
	if resume_active:
		d["resume"] = true
		d["seats"] = resume_seat_view()
	_rx_lobby.rpc(d)
	config_changed.emit()

@rpc("authority", "reliable")
func _rx_lobby(d: Dictionary) -> void:
	apply_config(d.get("cfg", {}) as Dictionary)
	lobby_slots = d.get("slots", []) as Array
	resume_active = d.get("resume", false) as bool
	remote_resume_seats = d.get("seats", []) as Array
	config_changed.emit()

@rpc("any_peer", "reliable")
func _tx_pick_color(idx: int) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		_apply_color_pick(pid, idx)

func _apply_color_pick(pid: int, idx: int) -> void:
	if not _roster.has(pid) or resume_active or idx < 0 or idx >= PlayerColors.COLORS.size():
		return
	if _color_taken(idx):
		return
	(_roster[pid] as Dictionary)["color"] = idx
	_broadcast_roster()

## Host only: throw a player out of the lobby.
func kick(player_id: int) -> void:
	if role != Role.HOST or player_id == 0 or not _roster.has(player_id):
		return
	var peer_id: int = (_roster[player_id] as Dictionary).get("peer", 0) as int
	if peer_id > 1:
		_kicked_peers[peer_id] = true
		announce("kicked", display_name_of(player_id))
		_rx_kicked.rpc_id(peer_id)
		# The disconnect lands right after the kick notice; the roster prunes
		# itself in _on_peer_disconnected.
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

@rpc("authority", "reliable")
func _rx_kicked() -> void:
	kicked.emit()
	leave()

# ── Resumed multiplayer saves (host lobby flow) ─────────────────────────────

## HOST (lobby, before start): freeze the lobby onto a multiplayer save. The
## save's MatchConfig is applied, every original seat becomes a reservation,
## and connected guests are re-seated (or turned away) by Steam ID / name.
func begin_resume(slot: int) -> bool:
	if role != Role.HOST or _match_running() or resume_active:
		return false
	if not SaveManager.load_game(slot):
		return false
	var sheet: Dictionary = SaveManager.resume_sheet()
	var roster_sheet: Dictionary = sheet.get("roster", {}) as Dictionary
	if roster_sheet.is_empty():
		SaveManager.cancel_pending()
		return false
	MatchConfig.forced_seed = SaveManager.get_saved_rng_seed()
	resume_active = true
	_vacant_seats.clear()
	var guests: Dictionary = _peer_players.duplicate()   # peer_id -> old pid
	var old_roster: Dictionary = _roster.duplicate(true)
	_peer_players.clear()
	_roster = {}
	for pid_str: Variant in roster_sheet:
		var pid: int = int(str(pid_str))
		var entry: Dictionary = (roster_sheet[pid_str] as Dictionary).duplicate()
		_next_player_id = maxi(_next_player_id, pid + 1)
		if pid == 0:
			entry["peer"] = 1
			_roster[0] = entry
			player_name = str(entry.get("name", player_name))
		else:
			_vacant_seats[pid] = {"entry": entry, "deadline_msec": RESUME_NO_DEADLINE}
	# Guests already in the lobby claim their original seat right away; anyone
	# who was not part of the saved match is politely thrown back to the menu.
	for peer_id: Variant in guests:
		var old_entry: Dictionary = old_roster.get(guests[peer_id], {}) as Dictionary
		_pending_rejoin[peer_id as int] = true
		_try_rejoin(peer_id as int, str(old_entry.get("name", "")))
		_pending_rejoin.erase(peer_id as int)
	lobby_slots = []
	_broadcast_roster()
	broadcast_lobby()
	return true

## HOST: abandon the resume pick and unfreeze the lobby (guests keep seats).
func cancel_resume() -> void:
	if not resume_active:
		return
	resume_active = false
	_vacant_seats.clear()
	SaveManager.cancel_pending()
	MatchConfig.forced_seed = 0
	if role == Role.HOST:
		lobby_slots = _default_lobby_slots()
		_broadcast_roster()
		broadcast_lobby()

## Lobby display rows for a resumed match, one per original seat.
func resume_seat_view() -> Array:
	if role != Role.HOST:
		return remote_resume_seats
	var out: Array = []
	var seats: Dictionary = seat_snapshot()
	var pids: Array = seats.keys()
	pids.sort()
	for pid: Variant in pids:
		var entry: Dictionary = seats[pid] as Dictionary
		out.append({
			"pid": pid as int,
			"name": entry.get("name", ""),
			"civ": entry.get("civ", ""),
			"color": entry.get("color", 0),
			"team": entry.get("team", 0),
			"connected": _roster.has(pid),
		})
	return out

## pid -> roster entry for every human seat, including currently dropped
## players (their reserved entry). What a multiplayer save persists.
func seat_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for pid: Variant in _roster:
		out[pid as int] = (_roster[pid] as Dictionary).duplicate()
	for pid: Variant in _vacant_seats:
		out[pid as int] = ((_vacant_seats[pid] as Dictionary)["entry"] as Dictionary).duplicate()
	return out

# ── Match start (host freezes the settings, everyone loads the same world) ──

## Host only: snapshot MatchConfig + a shared seed and start on every machine.
func start_match() -> void:
	if role != Role.HOST:
		return
	if resume_active:
		_start_resumed_match()
		return
	var cfg: Dictionary = snapshot_config()
	if (cfg["seed"] as int) == 0:
		cfg["seed"] = int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF
	# Rivals = the connected humans (ids 1.., their lobby civs) followed by the
	# host's AI slots. The humans list rides along so WorldSetup knows which
	# rivals get an AI brain and which are played from another machine.
	var human_ids: Array = _roster.keys()
	human_ids.sort()
	var rival_civs: Array = []
	for pid: Variant in human_ids:
		if (pid as int) != 0:
			rival_civs.append((_roster[pid] as Dictionary).get("civ", "castellanos"))
	for slot: Variant in lobby_slots:
		if ((slot as Dictionary).get("type", "") as String) == "ai":
			rival_civs.append((slot as Dictionary).get("civ", "castellanos"))
	cfg["player_civ_id"] = (_roster[0] as Dictionary).get("civ", MatchConfig.player_civ_id)
	cfg["rival_civ_ids"] = rival_civs
	cfg["rival_count"] = rival_civs.size()
	cfg["humans"] = human_ids
	var teams: Dictionary = {}
	for pid: Variant in human_ids:
		var t: int = (_roster[pid] as Dictionary).get("team", 0) as int
		if t > 0:
			teams[pid as int] = t
	var next_rival: int = human_ids.size()   # AI seats follow the humans
	for slot: Variant in lobby_slots:
		if ((slot as Dictionary).get("type", "") as String) == "ai":
			var ai_team: int = (slot as Dictionary).get("team", 0) as int
			if ai_team > 0:
				teams[next_rival] = ai_team
			next_rival += 1
	cfg["player_teams"] = teams
	# The lobby colour picks ride along so every machine paints players alike.
	var colors: Dictionary = {}
	for pid: Variant in _roster:
		colors[pid] = (_roster[pid] as Dictionary).get("color", pid) as int
	cfg["colors"] = colors
	if is_steam_session():
		Steam.setRichPresence("status", "Playing Calima: Flames of the Atlantic")
	_match_cfg = cfg.duplicate(true)
	_rx_match_config.rpc(cfg)
	_apply_and_start(cfg)

## HOST: start a match restored from a save. MatchConfig already holds the
## save's settings (begin_resume ran load_game); absent original players keep
## a reserved seat under the standard rejoin grace and may join mid-match.
func _start_resumed_match() -> void:
	var cfg: Dictionary = snapshot_config()
	var seats: Dictionary = seat_snapshot()
	var humans: Array = seats.keys()
	humans.sort()
	var colors: Dictionary = {}
	for pid: Variant in seats:
		colors[pid] = (seats[pid] as Dictionary).get("color", pid) as int
	cfg["humans"] = humans
	cfg["colors"] = colors
	var teams: Dictionary = {}
	for pid: Variant in MatchConfig.player_teams:
		if (MatchConfig.player_teams[pid] as int) > 0:
			teams[pid] = MatchConfig.player_teams[pid]
	cfg["player_teams"] = teams
	cfg["resumed"] = true
	for pid: Variant in _vacant_seats:
		(_vacant_seats[pid] as Dictionary)["deadline_msec"] = \
			Time.get_ticks_msec() + int(rejoin_grace_sec * 1000.0)
	resume_active = false
	if is_steam_session():
		Steam.setRichPresence("status", "Playing Calima: Flames of the Atlantic")
	_match_cfg = cfg.duplicate(true)
	_rx_match_config.rpc(cfg)
	_apply_and_start(cfg)

## True when `player_id` is a human seat of the current match. Offline only
## player 0 is human, so skirmish rivals keep their AI brains.
func is_human_player(player_id: int) -> bool:
	return match_human_ids.has(player_id)

## The lobby-relevant MatchConfig fields, as one serializable dictionary.
static func snapshot_config() -> Dictionary:
	return {
		"seed": MatchConfig.forced_seed,
		"map_size": MatchConfig.map_size,
		"resources": MatchConfig.resources,
		"map_type": MatchConfig.map_type,
		"player_civ_id": MatchConfig.player_civ_id,
		"starting_age": MatchConfig.starting_age,
		"victory_mode": MatchConfig.victory_mode,
		"rival_count": MatchConfig.rival_count,
		"rival_civ_ids": MatchConfig.rival_civ_ids.duplicate(),
		"weather_enabled": MatchConfig.weather_enabled,
		"weather_frequency": MatchConfig.weather_frequency,
		"hero_gender": MatchConfig.hero_gender,
	}

## Applies a config snapshot verbatim — every machine simulates the SAME match
## (player 0 = host, player 1.. = clients); which one YOU control is
## local_player_id, never the config.
static func apply_config(cfg: Dictionary) -> void:
	MatchConfig.forced_seed = cfg.get("seed", 0) as int
	MatchConfig.map_size = cfg.get("map_size", MatchConfig.MapSize.MEDIUM) as int
	MatchConfig.resources = cfg.get("resources", MatchConfig.Resources.NORMAL) as int
	MatchConfig.map_type = cfg.get("map_type", MatchConfig.MapType.STANDARD) as int
	MatchConfig.player_civ_id = cfg.get("player_civ_id", "guanches") as String
	MatchConfig.starting_age = cfg.get("starting_age", 0) as int
	MatchConfig.victory_mode = cfg.get("victory_mode", MatchConfig.VictoryMode.CONQUEST) as int
	MatchConfig.rival_count = maxi(cfg.get("rival_count", 1) as int, 1)
	var civs: Array[String] = []
	for c: Variant in cfg.get("rival_civ_ids", []) as Array:
		civs.append(c as String)
	if civs.is_empty():
		civs.append("castellanos")
	MatchConfig.rival_civ_ids = civs
	MatchConfig.weather_enabled = cfg.get("weather_enabled", true) as bool
	MatchConfig.weather_frequency = cfg.get("weather_frequency", 1) as int
	MatchConfig.hero_gender = cfg.get("hero_gender", 0) as int
	MatchConfig.launch_tutorial = false
	MatchConfig.campaign_mission = -1
	PlayerColors.clear_overrides()
	var colors: Variant = cfg.get("colors")
	if colors is Dictionary:
		for pid: Variant in colors as Dictionary:
			PlayerColors.set_override(pid as int, (colors as Dictionary)[pid] as int)
	var humans: Variant = cfg.get("humans")
	NetworkSession.match_human_ids = (humans as Array).duplicate() if humans is Array else [0]
	NetworkSession.resumed_match = cfg.get("resumed", false) as bool
	# A resumed match's client boots an empty mirror world — it needs the same
	# "ask the host for everything" flow a mid-match rejoiner uses.
	NetworkSession.rejoin_pending = (cfg.get("in_progress", false) as bool) \
		or (NetworkSession.resumed_match and NetworkSession.role == Role.CLIENT)
	MatchConfig.player_teams.clear()
	var teams: Variant = cfg.get("player_teams")
	if teams is Dictionary:
		for key: Variant in teams as Dictionary:
			MatchConfig.player_teams[int(str(key))] = int(str((teams as Dictionary)[key]))

@rpc("authority", "reliable")
func _rx_match_config(cfg: Dictionary) -> void:
	_apply_and_start(cfg)

func _apply_and_start(cfg: Dictionary) -> void:
	apply_config(cfg)
	match_started.emit()
	if auto_change_scene:
		get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")

## CLIENT: give up the match. The host validates the sender and eliminates it.
func resign() -> void:
	if role == Role.CLIENT and multiplayer.multiplayer_peer != null:
		_tx_resign.rpc_id(1)

@rpc("any_peer", "reliable")
func _tx_resign() -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid > 0:
		announce("resigned", display_name_of(pid))
		player_resigned.emit(pid)

## HOST: tell every client the simulation is paused/resumed.
func notify_pause(paused: bool) -> void:
	if role == Role.HOST:
		send_events({"pause": paused})

# ── Steam transport (lobbies + invites + Valve relay; AppID 480 for dev) ────

## Lobby search finished: [{ "id": int, "host": String, "members": int }].
signal steam_lobbies_found(lobbies: Array)
## A Steam session came up (host or client) — the UI can open the lobby.
signal steam_session_started()
signal steam_error(message: String)

const STEAM_APP_ID: int = 480         # Valve's public test app ("Spacewar")
const STEAM_GAME_KEY: String = "calima_fota"
const LOBBY_TYPE_PUBLIC: int = 2      # k_ELobbyTypePublic
const LOBBY_COMPARISON_EQUAL: int = 0
const CHAT_ENTER_SUCCESS: int = 1     # k_EChatRoomEnterResponseSuccess

var _steam_initialized: bool = false
var steam_lobby_id: int = 0
var _steam_signals_wired: bool = false

## Lazily boot the Steam API (needs the Steam client running & logged in).
## Called when the multiplayer screen opens — never at game start, so plain
## offline play never touches Steam.
var steam_init_error: String = ""

func ensure_steam() -> bool:
	if _steam_initialized:
		return true
	# A Finder-launched .app runs with cwd "/", where the Steam API would
	# never find steam_appid.txt — the env vars work from anywhere.
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	var result: Dictionary = Steam.steamInitEx(STEAM_APP_ID, false)
	if (result.get("status", 1) as int) != 0 or not Steam.loggedOn():
		steam_init_error = str(result.get("verbal", "")) 			if (result.get("status", 1) as int) != 0 else "not logged on"
		print("Steam init failed: status=%s verbal=%s logged_on=%s" % [
			str(result.get("status")), str(result.get("verbal")), str(Steam.loggedOn())])
		return false
	_steam_initialized = true
	if not _steam_signals_wired:
		_steam_signals_wired = true
		Steam.lobby_created.connect(_on_steam_lobby_created)
		Steam.lobby_joined.connect(_on_steam_lobby_joined)
		Steam.lobby_match_list.connect(_on_steam_lobby_list)
		Steam.join_requested.connect(_on_steam_join_requested)
	return true

func is_steam_session() -> bool:
	return steam_lobby_id != 0

## HOST over Steam: a public lobby (filterable) + the message-bridge peer.
func host_steam() -> void:
	if not ensure_steam() or is_online():
		return
	Steam.createLobby(LOBBY_TYPE_PUBLIC, MAX_CLIENTS + 1)

func _on_steam_lobby_created(connect_result: int, lobby_id: int) -> void:
	if connect_result != 1:
		steam_error.emit("lobby_create_failed")
		return
	steam_lobby_id = lobby_id
	player_name = Steam.getPersonaName()
	Steam.setLobbyData(lobby_id, "game", STEAM_GAME_KEY)
	Steam.setLobbyData(lobby_id, "host", _display_name(0))
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	peer.host_with_lobby(lobby_id)
	multiplayer.multiplayer_peer = peer
	_enter_host_state()
	(_roster[0] as Dictionary)["sid"] = Steam.getSteamID()
	Steam.setRichPresence("status", "In the Calima lobby")
	steam_session_started.emit()

## CLIENT over Steam: join the lobby, then bridge to its owner.
func join_steam_lobby(lobby_id: int) -> void:
	if not ensure_steam() or is_online():
		return
	_last_steam_lobby = lobby_id
	_last_join_ip = ""
	Steam.joinLobby(lobby_id)

func _on_steam_lobby_joined(lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	if is_host():
		return   # the host also "joins" its own lobby — already set up
	if response != CHAT_ENTER_SUCCESS:
		steam_error.emit("lobby_join_failed")
		return
	steam_lobby_id = lobby_id
	player_name = Steam.getPersonaName()
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	peer.connect_to_lobby(lobby_id)
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_connect_signals()
	steam_session_started.emit()

## Browse OUR lobbies only (everyone shares AppID 480 — filter by game key).
func request_steam_lobbies() -> void:
	if not ensure_steam():
		steam_lobbies_found.emit([])
		return
	Steam.addRequestLobbyListStringFilter("game", STEAM_GAME_KEY, LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_steam_lobby_list(lobbies: Array) -> void:
	var out: Array = []
	for lobby: Variant in lobbies:
		out.append({
			"id": lobby as int,
			"host": Steam.getLobbyData(lobby as int, "host"),
			"members": Steam.getNumLobbyMembers(lobby as int),
		})
	steam_lobbies_found.emit(out)

## Overlay dialog to invite Steam friends into the current lobby. The
## overlay only exists when the game was LAUNCHED through Steam — dev
## builds need the in-game picker below instead.
func invite_steam_friends() -> void:
	if steam_lobby_id != 0 and Steam.isOverlayEnabled():
		Steam.activateGameOverlayInviteDialog(steam_lobby_id)

const FRIEND_FLAG_IMMEDIATE: int = 0x04

## Steam friends for the in-game invite picker: online first.
func get_steam_friends() -> Array:
	if not _steam_initialized:
		return []
	var out: Array = []
	var count: int = Steam.getFriendCount(FRIEND_FLAG_IMMEDIATE)
	for i: int in range(count):
		var sid: int = Steam.getFriendByIndex(i, FRIEND_FLAG_IMMEDIATE)
		out.append({
			"id": sid,
			"name": Steam.getFriendPersonaName(sid),
			"online": Steam.getFriendPersonaState(sid) > 0,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a["online"] as bool) != (b["online"] as bool):
			return a["online"] as bool
		return (a["name"] as String).naturalnocasecmp_to(b["name"] as String) < 0)
	return out

## Direct API invite — lands in the friend's Steam chat, works without the
## overlay. With the game open on their side, accepting fires join_requested.
func invite_steam_friend(steam_id: int) -> bool:
	if steam_lobby_id == 0:
		return false
	return Steam.inviteUserToLobby(steam_lobby_id, steam_id)

## A friend accepted an invite (game already running).
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	if not is_online():
		join_steam_lobby(lobby_id)

# ── Internet hosting (UPnP port mapping, threaded — discovery blocks) ───────

## UPnP succeeded: friends can join at this external address.
signal internet_ready(external_ip: String)
## UPnP failed: the player must forward the port manually.
signal internet_failed(reason: String)

var _upnp: UPNP = null
var _upnp_thread: Thread = null
var _upnp_mapped_port: int = 0

## HOST: try to open the port on the router and learn the public address.
func setup_internet(port: int = DEFAULT_PORT) -> void:
	if role != Role.HOST or _upnp_thread != null or _upnp != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))

func _upnp_worker(port: int) -> void:
	var upnp: UPNP = UPNP.new()
	var err: int = upnp.discover(2000)
	if err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null \
			or not upnp.get_gateway().is_valid_gateway():
		call_deferred("_upnp_done", "", "discover", null, 0)
		return
	var map_err: int = upnp.add_port_mapping(port, port, "Calima RTS", "UDP")
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_upnp_done", "", "mapping", null, 0)
		return
	var ip: String = upnp.query_external_address()
	if ip.is_empty():
		upnp.delete_port_mapping(port, "UDP")
		call_deferred("_upnp_done", "", "address", null, 0)
		return
	call_deferred("_upnp_done", ip, "", upnp, port)

func _upnp_done(ip: String, reason: String, upnp: UPNP, port: int) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if ip.is_empty():
		internet_failed.emit(reason)
		return
	_upnp = upnp
	_upnp_mapped_port = port
	internet_ready.emit(ip)

func _teardown_internet() -> void:
	if _upnp != null and _upnp_mapped_port > 0:
		# Best effort; a stale mapping expires with the router anyway.
		_upnp.delete_port_mapping(_upnp_mapped_port, "UDP")
	_upnp = null
	_upnp_mapped_port = 0

# ── Chat (lobby AND in-game; host validates and rebroadcasts) ────────────────

## A chat line arrived on this machine (own lines included).
signal chat_received(player_id: int, text: String)
## A system event for the chat log (join/leave/kick/resign). Ships as a KIND
## plus a display name so every machine renders it in its own language.
signal system_chat_received(kind: String, display_name: String)

const CHAT_MAX_LEN: int = 120

func send_chat(text: String) -> void:
	var msg: String = text.strip_edges().left(CHAT_MAX_LEN)
	if msg.is_empty() or not is_online():
		return
	if role == Role.HOST:
		_rx_chat.rpc(0, msg)
		chat_received.emit(0, msg)
	else:
		_tx_chat.rpc_id(1, msg)

@rpc("any_peer", "reliable")
func _tx_chat(text: String) -> void:
	if role != Role.HOST:
		return
	# Identity comes from the connection, never from the payload.
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid < 0:
		return
	var msg: String = text.strip_edges().left(CHAT_MAX_LEN)
	if msg.is_empty():
		return
	_rx_chat.rpc(pid, msg)
	chat_received.emit(pid, msg)

@rpc("authority", "reliable")
func _rx_chat(pid: int, text: String) -> void:
	chat_received.emit(pid, text)

## The roster name for a player id, with a sane fallback after roster loss.
## HOST: announce a lobby/match event to every chat log (self included).
func announce(kind: String, display_name: String) -> void:
	if role != Role.HOST:
		return
	_rx_system.rpc(kind, display_name)
	system_chat_received.emit(kind, display_name)

@rpc("authority", "reliable")
func _rx_system(kind: String, display_name: String) -> void:
	system_chat_received.emit(kind, display_name)

func display_name_of(pid: int) -> String:
	var entry: Variant = _roster.get(pid)
	if entry is Dictionary:
		return (entry as Dictionary).get("name", "") as String
	return tr("LAN_DEFAULT_NAME") % (pid + 1)

# ── Minimap pings (Alt+click; allies-only display, filtered on receive) ─────

const PING_COOLDOWN_MSEC: int = 600
var _last_ping_msec: Dictionary = {}   # host: pid -> last accepted ping

func send_ping(world_pos: Vector2) -> void:
	if not is_online():
		EventBus.map_ping.emit(local_player_id, world_pos)
		return
	if role == Role.HOST:
		_accept_ping(0, world_pos)
	else:
		_tx_ping.rpc_id(1, world_pos)

@rpc("any_peer", "reliable")
func _tx_ping(world_pos: Vector2) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		_accept_ping(pid, world_pos)

func _accept_ping(pid: int, world_pos: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if now - (_last_ping_msec.get(pid, -10000) as int) < PING_COOLDOWN_MSEC:
		return
	_last_ping_msec[pid] = now
	_rx_ping.rpc(pid, world_pos)
	EventBus.map_ping.emit(pid, world_pos)

@rpc("authority", "reliable")
func _rx_ping(pid: int, world_pos: Vector2) -> void:
	EventBus.map_ping.emit(pid, world_pos)

## Host-side AI ping (assist/attack callouts). Display filtering by alliance
## happens at the receivers, same as player pings.
func ai_ping(pid: int, world_pos: Vector2) -> void:
	if is_online() and role == Role.HOST:
		_accept_ping(pid, world_pos)
	elif not is_online():
		EventBus.map_ping.emit(pid, world_pos)

# ── Per-player fog of war (multiplayer saves) ────────────────────────────────

const FOG_COLLECT_TIMEOUT: float = 2.0

## HOST: ask every client for its fog cells and wait (bounded) for the replies.
## SaveManager awaits this before collecting a multiplayer save.
func collect_client_fogs() -> void:
	client_fogs.clear()
	if role != Role.HOST or _peer_players.is_empty():
		return
	_rx_fog_request.rpc()
	var waited: float = 0.0
	while waited < FOG_COLLECT_TIMEOUT and client_fogs.size() < _peer_players.size():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1

@rpc("authority", "reliable")
func _rx_fog_request() -> void:
	var b64: String = local_fog_b64()
	if not b64.is_empty():
		_tx_fog_reply.rpc_id(1, b64)

@rpc("any_peer", "reliable")
func _tx_fog_reply(b64: String) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		client_fogs[pid] = b64

## This machine's fog cells, zstd-compressed and base64-wrapped for the wire.
func local_fog_b64() -> String:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return ""
	var fog: Variant = world.get("_fog")
	if not (fog is FogOfWar):
		return ""
	return Marshalls.raw_to_base64(
		(fog as FogOfWar)._cells.compress(FileAccess.COMPRESSION_ZSTD))

## Reverse of local_fog_b64; empty when the payload does not fit the grid.
## decompress (not decompress_dynamic — that mode rejects zstd) is safe here:
## the receiver always knows its own grid size.
static func fog_cells_from_b64(b64: String, expected_size: int) -> PackedByteArray:
	var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return PackedByteArray()
	var cells: PackedByteArray = raw.decompress(expected_size, FileAccess.COMPRESSION_ZSTD)
	return cells if cells.size() == expected_size else PackedByteArray()

# ── State replication (host → clients, driven by StateReplicator) ───────────

## Dense per-snapshot stream (positions/HP/stockpiles) on this machine.
signal state_received(d: Dictionary)
## Reliable events (spawns/removals/match outcome) on this machine.
signal events_received(d: Dictionary)

func send_state(d: Dictionary) -> void:
	if role == Role.HOST:
		_rx_state.rpc(d)

func send_events(d: Dictionary) -> void:
	if role == Role.HOST:
		_rx_events.rpc(d)

## Reliable events to ONE player (the rejoin resync).
func send_events_to(player_id: int, d: Dictionary) -> void:
	if role != Role.HOST:
		return
	for peer_id: Variant in _peer_players:
		if (_peer_players[peer_id] as int) == player_id:
			_rx_events.rpc_id(peer_id as int, d)
			return

@rpc("authority", "unreliable_ordered")
func _rx_state(d: Dictionary) -> void:
	state_received.emit(d)

@rpc("authority", "reliable")
func _rx_events(d: Dictionary) -> void:
	events_received.emit(d)

# ── Command pipe (client → host) ─────────────────────────────────────────────

## CLIENT: CommandBus routes every submit here instead of executing locally.
func send_command(command: GameCommand) -> void:
	if role != Role.CLIENT or multiplayer.multiplayer_peer == null:
		return
	_rx_command.rpc_id(1, command.to_dict())

## A human cannot legitimately issue more than this many commands per
## second; anything past it is a malfunctioning or hostile client.
const COMMANDS_PER_SEC_LIMIT: int = 25
var _cmd_windows: Dictionary = {}   # pid -> {"start_msec": int, "count": int}

func _command_rate_ok(pid: int) -> bool:
	var now: int = Time.get_ticks_msec()
	var window: Dictionary = _cmd_windows.get(pid, {"start_msec": now, "count": 0}) as Dictionary
	if now - (window["start_msec"] as int) >= 1000:
		window = {"start_msec": now, "count": 0}
	window["count"] = (window["count"] as int) + 1
	_cmd_windows[pid] = window
	return (window["count"] as int) <= COMMANDS_PER_SEC_LIMIT

@rpc("any_peer", "reliable")
func _rx_command(d: Dictionary) -> void:
	if role != Role.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var pid: int = _peer_players.get(sender, -1) as int
	if pid < 0:
		return
	if not _command_rate_ok(pid):
		return
	var command: GameCommand = CommandBus.command_from_dict(d)
	if command == null:
		return
	# Identity comes from the connection, never from the payload — and the
	# command is branded as wire-borne so privileged local-only verbs
	# (instant placement, board_instant) refuse it at execute time.
	command.player_id = pid
	command.remote_origin = true
	CommandBus.submit_remote(command)

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
## The lobby roster (names/colours/joins/leaves) changed on any machine.
signal roster_changed()
## This machine was kicked by the host.
signal kicked()
## Fired on every machine when the host starts the match (config applied).
signal match_started()

var role: Role = Role.OFFLINE
var local_player_id: int = 0
## Local profile, set by the lobby UI BEFORE hosting/joining.
var player_name: String = ""
## Harnesses instantiate the world themselves instead of a scene change.
var auto_change_scene: bool = true

var _peer_players: Dictionary = {}   # peer_id -> player_id (host side)
var _next_player_id: int = 1
## player_id -> {"name": String, "color": int, "peer": int}. Host-authoritative,
## rebroadcast in full on every change (tiny — a lobby has ≤ 4 rows).
var _roster: Dictionary = {}

func is_online() -> bool:
	return role != Role.OFFLINE

func is_client() -> bool:
	return role == Role.CLIENT

func is_host() -> bool:
	return role == Role.HOST

func player_count() -> int:
	return 1 + _peer_players.size()

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	local_player_id = 0
	_peer_players.clear()
	_next_player_id = 1
	_roster = {0: {"name": _display_name(0), "color": 0, "peer": 1}}
	_connect_signals()
	roster_changed.emit()
	return OK

func _display_name(player_id: int) -> String:
	var trimmed: String = player_name.strip_edges()
	return trimmed if not trimmed.is_empty() else tr("LAN_DEFAULT_NAME") % (player_id + 1)

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
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
	_roster.clear()
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
	var pid: int = _next_player_id
	_next_player_id += 1
	_peer_players[peer_id] = pid
	_roster[pid] = {"name": tr("LAN_DEFAULT_NAME") % (pid + 1),
		"color": _first_free_color(), "peer": peer_id}
	_rx_assign_player.rpc_id(peer_id, pid)
	_broadcast_roster()
	peer_joined.emit(peer_id, pid)

func _on_peer_disconnected(peer_id: int) -> void:
	var pid: int = _peer_players.get(peer_id, -1) as int
	_peer_players.erase(peer_id)
	if pid >= 0:
		_roster.erase(pid)
		_broadcast_roster()
	peer_left.emit(peer_id)

func _on_connected_to_server() -> void:
	# Introduce ourselves; the host validates and rebroadcasts the roster.
	_tx_profile.rpc_id(1, player_name)
	joined_host.emit()

func _on_connection_failed() -> void:
	leave()
	join_failed.emit()

func _on_server_disconnected() -> void:
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
func _tx_profile(display_name: String) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid < 0 or not _roster.has(pid):
		return
	var trimmed: String = display_name.strip_edges().left(24)
	if not trimmed.is_empty():
		(_roster[pid] as Dictionary)["name"] = trimmed
	_broadcast_roster()

## Pick a colour for YOURSELF; the host validates it is free.
func request_color(idx: int) -> void:
	if role == Role.HOST:
		_apply_color_pick(0, idx)
	elif role == Role.CLIENT:
		_tx_pick_color.rpc_id(1, idx)

@rpc("any_peer", "reliable")
func _tx_pick_color(idx: int) -> void:
	if role != Role.HOST:
		return
	var pid: int = _peer_players.get(multiplayer.get_remote_sender_id(), -1) as int
	if pid >= 0:
		_apply_color_pick(pid, idx)

func _apply_color_pick(pid: int, idx: int) -> void:
	if not _roster.has(pid) or idx < 0 or idx >= PlayerColors.COLORS.size():
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
		_rx_kicked.rpc_id(peer_id)
		# The disconnect lands right after the kick notice; the roster prunes
		# itself in _on_peer_disconnected.
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)

@rpc("authority", "reliable")
func _rx_kicked() -> void:
	kicked.emit()
	leave()

# ── Match start (host freezes the settings, everyone loads the same world) ──

## Host only: snapshot MatchConfig + a shared seed and start on every machine.
func start_match() -> void:
	if role != Role.HOST:
		return
	var cfg: Dictionary = snapshot_config()
	# The number of rivals in the SIMULATION is the number of connected humans.
	cfg["rival_count"] = _peer_players.size()
	if (cfg["seed"] as int) == 0:
		cfg["seed"] = int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF
	# The lobby colour picks ride along so every machine paints players alike.
	var colors: Dictionary = {}
	for pid: Variant in _roster:
		colors[pid] = (_roster[pid] as Dictionary).get("color", pid) as int
	cfg["colors"] = colors
	_rx_match_config.rpc(cfg)
	_apply_and_start(cfg)

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
	PlayerColors.clear_overrides()
	var colors: Variant = cfg.get("colors")
	if colors is Dictionary:
		for pid: Variant in colors as Dictionary:
			PlayerColors.set_override(pid as int, (colors as Dictionary)[pid] as int)

@rpc("authority", "reliable")
func _rx_match_config(cfg: Dictionary) -> void:
	_apply_and_start(cfg)

func _apply_and_start(cfg: Dictionary) -> void:
	apply_config(cfg)
	match_started.emit()
	if auto_change_scene:
		get_tree().change_scene_to_file("res://scenes/game/game_world.tscn")

# ── Command pipe (client → host) ─────────────────────────────────────────────

## CLIENT: CommandBus routes every submit here instead of executing locally.
func send_command(command: GameCommand) -> void:
	if role != Role.CLIENT or multiplayer.multiplayer_peer == null:
		return
	_rx_command.rpc_id(1, command.to_dict())

@rpc("any_peer", "reliable")
func _rx_command(d: Dictionary) -> void:
	if role != Role.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var pid: int = _peer_players.get(sender, -1) as int
	if pid < 0:
		return
	var command: GameCommand = CommandBus.command_from_dict(d)
	if command == null:
		return
	# Identity comes from the connection, never from the payload.
	command.player_id = pid
	CommandBus.submit_remote(command)

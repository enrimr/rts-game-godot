extends Node2D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _saved_rng_seed: int = 0
var _saved_tc_position: Vector2 = Vector2.ZERO

@onready var units_layer: Node2D = $UnitsLayer
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var camera: Camera2D = $Camera2D
# The human player's Town Center. Instanced from the same scene as buildable
# TCs (in _ready) and named "DropOffNode" so existing name-based lookups
# (minimap, save_manager, fog) keep working. Previously this was a divergent
# inline node in game_world.tscn with no physics collision (let you build on
# top of it) and an old hand-built sprite.
var drop_off: Node2D = null
@onready var hud: CanvasLayer = $HUD
@onready var _nav_region: NavigationRegion2D = $NavigationRegion2D

var _terrain_advantage_overlay: TerrainAdvantageOverlay = null

# All AI town centers indexed by player_id
var _ai_town_centers: Dictionary = {}   # int → Node2D
var _ai_town_center: Node2D = null      # legacy alias for player_id 1
var _fog: FogOfWar = null

var _selected_units: Array[Node] = []
var _selected_building: Node = null
# Double-clicking a building selects every own building of the same type;
# _selected_building stays the primary (drives the HUD panel), this holds the
# whole group (rally fan-out, least-loaded train distribution).
var _selected_buildings: Array[Node] = []

# Contextual mouse cursor: hover resolution is throttled, not per mouse event.
var _cursor_timer: float = 0.0
const CURSOR_UPDATE_INTERVAL: float = 0.1

var _victory: WorldVictory = null
var _camera_ctl: WorldCamera = null
var _placement: WorldPlacement = null
var _setup: WorldSetup = null
var _selection: WorldSelection = null
var _commands: WorldCommands = null

func _ready() -> void:
	add_to_group("world")
	_victory = WorldVictory.new()
	_victory.setup(self)
	_camera_ctl = WorldCamera.new()
	_camera_ctl.setup(self)
	_placement = WorldPlacement.new()
	_placement.setup(self)
	_setup = WorldSetup.new()
	_setup.setup(self)
	_selection = WorldSelection.new()
	_selection.setup(self)
	_commands = WorldCommands.new()
	_commands.setup(self)
	# Isometric projection lives entirely in the camera; the scene's zoom.x is
	# kept as the starting user zoom. Game logic below stays cartesian.
	IsoProjection.apply_to_camera(camera, IsoProjection.user_zoom_from(camera.zoom))
	_setup._create_player_town_center()
	# Init all players — for a load, SaveManager will overwrite afterwards
	var starting_res: Dictionary = MatchConfig.get_starting_resources()
	ResourceManager.init_player(0, starting_res)
	PopulationManager.init_player(0)
	AgeManager.init_player(0, MatchConfig.starting_age)
	for rival_id: int in MatchConfig.get_rival_player_ids():
		ResourceManager.init_player(rival_id, starting_res)
		PopulationManager.init_player(rival_id)
		# Rivals start at the lobby-selected age too, not always Dark Age.
		AgeManager.init_player(rival_id, MatchConfig.starting_age)

	_setup._apply_civilization()

	# Deterministic seed: when loading a save we re-use the stored seed so the
	# map generator produces the exact same layout.
	if SaveManager.pending_load:
		_rng.seed = SaveManager.get_saved_rng_seed()
		_saved_rng_seed = _rng.seed
	else:
		# Tooling hook: a fixed seed makes visual-review runs reproducible
		# (see tools/screenshot_runner.gd).
		var env_seed: String = OS.get_environment("CALIMA_SEED")
		if MatchConfig.forced_seed != 0:
			# Multiplayer: every machine generates the identical world.
			_rng.seed = MatchConfig.forced_seed
		elif not env_seed.is_empty():
			_rng.seed = int(env_seed)
		else:
			_rng.randomize()
		_saved_rng_seed = _rng.seed

	# One seed drives every simulation RNG draw of the match (units, animals,
	# weather, AI) — independent stream from the map generator's.
	MatchRng.reset(_rng.seed)

	_setup._setup_ambient_lighting()

	var map_data: Dictionary = MapGenerator.generate(self, units_layer, _rng)
	var tc_positions: Array[Vector2] = map_data["tc_positions"] as Array[Vector2]

	_terrain_advantage_overlay = TerrainAdvantageOverlay.new()
	add_child(_terrain_advantage_overlay)
	_terrain_advantage_overlay.build_from_terrain_manager(MatchConfig.player_civ_id)

	# Place player TC at tc_positions[0]
	drop_off.global_position = tc_positions[0]
	_saved_tc_position = tc_positions[0]
	camera.position = drop_off.global_position

	if SaveManager.pending_load:
		# AI node structure must still exist for signals / victory checks.
		for rival_id: int in MatchConfig.get_rival_player_ids():
			var tc_pos: Vector2 = tc_positions[rival_id] if rival_id < tc_positions.size() \
				else tc_positions[tc_positions.size() - 1]
			_setup._setup_ai_node_only(rival_id, tc_pos)
		if _ai_town_centers.size() > 0:
			_ai_town_center = _ai_town_centers[1]
	else:
		_setup.spawn_player_start()

		# Spawn one AI per rival
		for rival_id: int in MatchConfig.get_rival_player_ids():
			var tc_pos: Vector2 = tc_positions[rival_id] if rival_id < tc_positions.size() \
				else tc_positions[tc_positions.size() - 1]
			_setup._setup_ai(rival_id, tc_pos)

		# Legacy alias points at the first rival TC
		if _ai_town_centers.size() > 0:
			_ai_town_center = _ai_town_centers[1]

	# A LAN client controls a rival seat — open the match looking at ITS base.
	var local_id: int = NetworkSession.local_player_id
	if local_id != 0 and _ai_town_centers.has(local_id):
		camera.position = (_ai_town_centers[local_id] as Node2D).global_position

	_setup._setup_ai_debug_overlay()

	hud.action_requested.connect(_on_action_requested)
	hud.follow_requested.connect(toggle_follow)
	hud.pending_action_started.connect(func(id: String) -> void: _commands._pending_action = id)
	hud.pending_action_cancelled.connect(func() -> void: _commands._pending_action = "")
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.unit_died.connect(_on_unit_died_check_victory)
	EventBus.building_destroyed.connect(_on_building_destroyed_check_victory)
	EventBus.building_construction_complete.connect(_on_building_construction_complete)
	EventBus.player_eliminated.connect(_on_player_eliminated)
	EventBus.wonder_built.connect(_on_wonder_built)
	EventBus.wonder_destroyed.connect(_on_wonder_destroyed)
	EventBus.minimap_move_order.connect(func(p: Vector2) -> void:
		_camera_ctl.cancel_follow()
		_commands._order_move_all(p)
	)
	# HUD-side camera controls (minimap click, dpad) emit this so their pans
	# are not undone by the per-frame follow re-centre. Re-entrant no-op when
	# this node is itself the emitter.
	EventBus.camera_follow_cancelled.connect(func() -> void: _camera_ctl.cancel_follow())
	EventBus.player_entity_under_attack.connect(
		func(pos: Vector2, _attacker: Node) -> void: _camera_ctl.record_alert(pos))
	EventBus.building_destroyed.connect(_on_building_destroyed_alert)
	EventBus.unit_selected.connect(_on_unit_selected_follow)
	SelectionManager.selection_changed.connect(_on_selection_manager_changed)
	EventBus.tutorial_spawn_enemy_scout.connect(_on_tutorial_spawn_enemy_scout)
	EventBus.tutorial_highlight_unit.connect(_on_tutorial_highlight_unit)
	EventBus.tutorial_reset_camera_flag.connect(func() -> void: _camera_ctl.reset_moved_flag())

	_fog = FogOfWar.new()
	add_child(_fog)
	_fog.setup(units_layer, buildings_layer, drop_off, self)

	var minimap: MinimapRenderer = hud.get_node_or_null("%Minimap") as MinimapRenderer
	if minimap != null:
		minimap.world_node = self
		minimap.camera_node = camera
		minimap.fog = _fog

	_selection.create_drag_overlay()

	var weather_overlay: Node2D = load("res://scripts/ui/weather_overlay.gd").new() as Node2D
	weather_overlay.name = "WeatherOverlay"
	add_child(weather_overlay)
	WeatherManager.weather_changed.connect(_on_weather_changed)
	WeatherManager.weather_cleared.connect(_on_weather_cleared)

	EventBus.building_placed.connect(func(_b: Node, _pid: int) -> void: _request_nav_rebake())
	EventBus.building_destroyed.connect(func(_b: Node, _pid: int) -> void: _request_nav_rebake())
	EventBus.gate_state_changed.connect(func(_g: Node) -> void: _request_nav_rebake())
	_request_nav_rebake()

	CursorManager.prebake()

	var player_list: Array[Dictionary] = [{"id": 0}]
	for rival_id: int in MatchConfig.get_rival_player_ids():
		player_list.append({"id": rival_id})
	GameManager.start_game(player_list)
	AudioManager.play_music(MatchConfig.map_type)
	GameManager.game_over.connect(_on_game_over)

	# Boarding a transport hides the unit; drop it from the selection so the
	# HUD does not keep showing (or ordering) a garrisoned ghost.
	EventBus.garrison_changed.connect(_on_garrison_changed_prune_selection)

	EventBus.map_ping.connect(_on_map_ping)

	# Restore dynamic state from save (must be after start_game so GameState is PLAYING)
	if SaveManager.pending_load:
		SaveManager.restore_world(self)
		camera.position = drop_off.global_position

	# Last: every entity of the finished match setup (including a save restore)
	# gets its deterministic EntityRegistry ID, and the command log starts.
	CommandBus.start_match(self)

	# Multiplayer: the host streams the authoritative state, a client puppets
	# its mirror world from it. Must come after start_match so both machines
	# reference entities by the same deterministic IDs.
	if NetworkSession.is_online():
		var replicator: StateReplicator = StateReplicator.new()
		replicator.name = "StateReplicator"
		add_child(replicator)
		replicator.setup(self)
		if NetworkSession.is_host():
			NetworkSession.player_resigned.connect(_on_player_resigned)
		else:
			NetworkSession.connection_lost.connect(_on_connection_lost, CONNECT_ONE_SHOT)

# --- Match bootstrap (implementation in WorldSetup) ---

func _on_tutorial_spawn_enemy_scout(near_pos: Vector2) -> void:
	_setup._on_tutorial_spawn_enemy_scout(near_pos)

func _on_tutorial_highlight_unit(unit_type: String) -> void:
	_setup._on_tutorial_highlight_unit(unit_type)

func _on_building_destroyed_check_victory(building: Node, owner_id: int) -> void:
	_victory._on_building_destroyed_check_victory(building, owner_id)

func _on_unit_died_check_victory(unit: Node, owner_id: int) -> void:
	_victory._on_unit_died_check_victory(unit, owner_id)

func _on_player_eliminated(eliminated_id: int) -> void:
	_victory._on_player_eliminated(eliminated_id)

func _on_building_construction_complete(building: Node) -> void:
	_victory._on_building_construction_complete(building)

func _on_wonder_built(pid: int) -> void:
	_victory._on_wonder_built(pid)

func _on_wonder_destroyed(pid: int) -> void:
	_victory._on_wonder_destroyed(pid)

func _process(delta: float) -> void:
	_placement.tick_nav_rebake(delta)
	_victory.tick(delta)
	_camera_ctl.handle_camera(delta)
	_camera_ctl.handle_follow()
	_placement.update_previews()
	_selection.update_drag_overlay()
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_UPDATE_INTERVAL:
		_cursor_timer = 0.0
		CursorManager.set_context(_commands._resolve_cursor_context())

func _exit_tree() -> void:
	CursorManager.set_context("default")
	if NetworkSession.player_resigned.is_connected(_on_player_resigned):
		NetworkSession.player_resigned.disconnect(_on_player_resigned)
	if NetworkSession.connection_lost.is_connected(_on_connection_lost):
		NetworkSession.connection_lost.disconnect(_on_connection_lost)
	if NetworkSession.join_failed.is_connected(_on_rejoin_failed):
		NetworkSession.join_failed.disconnect(_on_rejoin_failed)

func _on_player_resigned(pid: int) -> void:
	_victory.handle_resignation(pid)

## An ally pinged the map: ring on the ground, flash on the minimap, a blip
## of sound, and the SPACE alert ring remembers the spot. Enemy pings are
## never shown (the wire broadcasts; display filters here).
func _on_map_ping(pid: int, world_pos: Vector2) -> void:
	if not GameManager.are_allied(pid, NetworkSession.local_player_id):
		return
	_commands._flash_point(world_pos, PlayerColors.get_color(pid).lightened(0.3))
	var minimap: MinimapRenderer = hud.get_node_or_null("%Minimap") as MinimapRenderer
	if minimap != null:
		minimap.add_flash(world_pos, PlayerColors.get_color(pid))
	_camera_ctl.record_alert(world_pos)
	AudioManager.play("ui_click", -6.0)

## Player-allied AIs cannot target the player's TC — give each brain the
## nearest HOSTILE town center once every TC exists (deferred from setup).
func _assign_ai_enemy_targets() -> void:
	for child: Node in get_children():
		var script: Script = child.get_script() as Script
		if script == null or not script.resource_path.contains("ai_player"):
			continue
		if child.get("enemy_town_center") != null:
			continue
		var my_pid: int = child.get("player_id") as int
		var target: Node2D = null
		if not GameManager.are_allied(my_pid, 0):
			target = drop_off
		else:
			for other_pid: int in _ai_town_centers:
				if not GameManager.are_allied(my_pid, other_pid):
					target = _ai_town_centers[other_pid]
					break
		child.set("enemy_town_center", target if target != null else drop_off)

## The connection dropped mid-match (host gone OR our own wifi blip): offer
## a reconnect — the host reserves our seat for a grace window — or the menu.
func _on_connection_lost() -> void:
	get_tree().paused = false
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.dialog_text = tr("LAN_CONNECTION_LOST")
	dialog.title = tr("LAN_TITLE")
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.ok_button_text = tr("GAMEOVER_BACK_MENU")
	dialog.add_button(tr("LAN_RECONNECT"), true, "retry")
	dialog.confirmed.connect(_leave_to_menu)
	dialog.canceled.connect(_leave_to_menu)
	dialog.custom_action.connect(func(_action: StringName) -> void:
		dialog.hide()
		_attempt_rejoin())
	_rejoin_dialog = dialog
	hud.add_child(dialog)
	dialog.popup_centered()

var _rejoin_dialog: AcceptDialog = null

## Success re-enters through the match config (full scene reload); a failed
## attempt brings the dialog back for another try or the menu.
func _attempt_rejoin() -> void:
	if not NetworkSession.join_failed.is_connected(_on_rejoin_failed):
		NetworkSession.join_failed.connect(_on_rejoin_failed)
	if not NetworkSession.rejoin_last():
		_on_rejoin_failed()

func _on_rejoin_failed() -> void:
	if is_instance_valid(_rejoin_dialog):
		_rejoin_dialog.popup_centered()

func _leave_to_menu() -> void:
	NetworkSession.leave()
	get_tree().change_scene_to_file("res://scenes/game/main_menu.tscn")

func toggle_follow() -> void:
	_camera_ctl.toggle_follow()

func _on_unit_selected_follow(units: Array) -> void:
	_camera_ctl._on_unit_selected_follow(units)

func _on_selection_manager_changed(units: Array) -> void:
	_selection._on_selection_manager_changed(units)

## The selection every controller iterates, with freed units dropped in place.
## Units die on their own schedule and nothing removes them from the list, so
## this is the read barrier: the controllers reach the list through the untyped
## `_world` reference, which makes GDScript validate each element against the
## loop's declared type at runtime and raise "invalid previously freed instance"
## before any is_instance_valid() guard in the loop body can run.
func live_selection() -> Array[Node]:
	var i: int = _selected_units.size() - 1
	while i >= 0:
		if not is_instance_valid(_selected_units[i]):
			_selected_units.remove_at(i)
		i -= 1
	return _selected_units

## Same prune-on-read barrier for the multi-building selection.
func live_selected_buildings() -> Array[Node]:
	var i: int = _selected_buildings.size() - 1
	while i >= 0:
		if not is_instance_valid(_selected_buildings[i]):
			_selected_buildings.remove_at(i)
		i -= 1
	return _selected_buildings

func _on_garrison_changed_prune_selection(ship: Node, _count: int, _capacity: int) -> void:
	if not is_instance_valid(ship):
		return
	var garrison: Variant = ship.get("_garrison")
	if not (garrison is Array):
		return
	var changed: bool = false
	for unit: Variant in garrison as Array:
		if is_instance_valid(unit) and unit is Node and _selected_units.has(unit):
			_selected_units.erase(unit)
			changed = true
	if changed:
		SelectionManager.select(_selected_units)

func _on_building_destroyed_alert(building: Node, owner_id: int) -> void:
	_camera_ctl._on_building_destroyed_alert(building, owner_id)

## Instant camera jump used by alert hotkeys and clickable notifications.
func jump_camera_to(world_pos: Vector2) -> void:
	_camera_ctl.jump_camera_to(world_pos)

func _is_mouse_over_hud() -> bool:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for control: Node in _get_hud_blocking_rects():
		if not is_instance_valid(control):
			continue
		var c: Control = control as Control
		if c.get_global_rect().has_point(mouse_pos):
			return true
	return false

func _get_hud_blocking_rects() -> Array[Control]:
	var result: Array[Control] = []
	var top_bar: Control = hud.get_node_or_null("HUDRoot/TopBar") as Control
	var bottom_bar: Control = hud.get_node_or_null("HUDRoot/BottomBar") as Control
	if top_bar != null: result.append(top_bar)
	if bottom_bar != null: result.append(bottom_bar)
	return result

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if _placement.handle_placement_key(ke):
			return
		if ke.pressed and not ke.echo:
			if ke.unicode == 43 or ke.physical_keycode == KEY_KP_ADD:
				_camera_ctl.zoom(WorldCamera.CAMERA_ZOOM_STEP)
				get_viewport().set_input_as_handled()
				return
			if ke.unicode == 45 or ke.physical_keycode == KEY_KP_SUBTRACT:
				_camera_ctl.zoom(-WorldCamera.CAMERA_ZOOM_STEP)
				get_viewport().set_input_as_handled()
				return
			if _selection.handle_group_hotkey(ke):
				get_viewport().set_input_as_handled()
				return
			if ke.physical_keycode == KEY_SPACE:
				_camera_ctl.jump_to_last_alert()
				get_viewport().set_input_as_handled()
				return
		return

	if event is InputEventMouseMotion and _camera_ctl.is_panning():
		_camera_ctl.apply_pan_motion(event as InputEventMouseMotion)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_camera_ctl.set_panning(mb.pressed)
			get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_camera_ctl.zoom(WorldCamera.CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_camera_ctl.zoom(-WorldCamera.CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return

		if _is_mouse_over_hud():
			return

		if _placement.handle_placement_mouse(mb):
			return

		if not _commands._pending_action.is_empty():
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_commands._execute_pending_action(get_global_mouse_position())
				get_viewport().set_input_as_handled()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				hud.cancel_pending()
				get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			_selection.handle_left_mouse(mb.pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_commands._handle_right_click(get_global_mouse_position())

func get_zoom() -> float:
	return _camera_ctl.get_zoom()

func set_zoom(value: float) -> void:
	_camera_ctl.set_zoom(value)

# --- Orders / commands (implementation in WorldCommands) ---

## Kept as a thin delegate: tools/check_hero_attack probes click-picking
## through the world node.
func _find_enemy_building_at(world_pos: Vector2) -> Node:
	return _commands._find_enemy_building_at(world_pos)

# --- Building placement (implementation in WorldPlacement) ---

## Kept as thin delegates: the HUD action router and headless tools
## (screenshot_runner, check_placement_preview) call these on the world node.
func _start_placement(building_id: String) -> void:
	_placement._start_placement(building_id)

func _cancel_placement() -> void:
	_placement._cancel_placement()

func _request_nav_rebake() -> void:
	_placement._request_nav_rebake()

# --- HUD action buttons (implementation in WorldCommands) ---

func _on_action_requested(action_id: String) -> void:
	_commands._on_action_requested(action_id)

func _on_unit_spawned(unit: Node, _player: int) -> void:
	if unit.get_parent() != units_layer:
		unit.reparent(units_layer)

func _on_weather_changed(weather_id: String, _intensity: float) -> void:
	var hud_mgr: Node = hud.get_node_or_null("HudManager")
	if is_instance_valid(hud_mgr) and hud_mgr.has_method("show_weather"):
		hud_mgr.call("show_weather", weather_id)
	const WEATHER_SOUNDS: Dictionary = {
		"calima":         "weather_calima",
		"atlantic_storm": "weather_storm",
		"sea_fog":        "weather_fog",
		"trade_winds":    "weather_wind",
		"volcanic_ash":   "weather_ash",
	}
	var sound_id: String = WEATHER_SOUNDS.get(weather_id, "") as String
	if not sound_id.is_empty():
		AudioManager.play_weather_ambient(sound_id)

func _on_weather_cleared() -> void:
	var hud_mgr: Node = hud.get_node_or_null("HudManager")
	if is_instance_valid(hud_mgr) and hud_mgr.has_method("hide_weather"):
		hud_mgr.call("hide_weather")
	AudioManager.stop_weather_ambient()

func _on_game_over(winner: int) -> void:
	_victory._on_game_over(winner)

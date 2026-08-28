extends Node2D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _saved_rng_seed: int = 0
var _saved_tc_position: Vector2 = Vector2.ZERO

const UNIT_CLICK_RADIUS: float = 32.0

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
var _selected_node: Node = null
var _drag_start: Vector2 = Vector2.ZERO
# Screen-space anchor of the drag: the band the player draws is a plain 2D
# rectangle on the screen; world membership is tested by projecting units
# into screen space (never by an axis-aligned world rect, which the iso
# camera would render as a parallelogram).
var _drag_start_screen: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _last_click_time: float = -1.0
var _last_click_unit_script: Script = null
const DOUBLE_CLICK_SEC: float  = 0.35
const DOUBLE_CLICK_RADIUS: float = 600.0

# Pending action waiting for a map click ("move_to" or "attack_move")
var _pending_action: String = ""

# Contextual mouse cursor: hover resolution is throttled, not per mouse event.
var _cursor_timer: float = 0.0
const CURSOR_UPDATE_INTERVAL: float = 0.1

var _victory: WorldVictory = null
var _camera_ctl: WorldCamera = null
var _placement: WorldPlacement = null
var _setup: WorldSetup = null

# Drag-select rectangle overlay
var _drag_overlay: Node2D = null

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
		if not env_seed.is_empty():
			_rng.seed = int(env_seed)
		else:
			_rng.randomize()
		_saved_rng_seed = _rng.seed

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

	_setup._setup_ai_debug_overlay()

	hud.action_requested.connect(_on_action_requested)
	hud.follow_requested.connect(toggle_follow)
	hud.pending_action_started.connect(func(id: String) -> void: _pending_action = id)
	hud.pending_action_cancelled.connect(func() -> void: _pending_action = "")
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.unit_died.connect(_on_unit_died_check_victory)
	EventBus.building_destroyed.connect(_on_building_destroyed_check_victory)
	EventBus.building_construction_complete.connect(_on_building_construction_complete)
	EventBus.player_eliminated.connect(_on_player_eliminated)
	EventBus.wonder_built.connect(_on_wonder_built)
	EventBus.wonder_destroyed.connect(_on_wonder_destroyed)
	EventBus.minimap_move_order.connect(func(p: Vector2) -> void:
		_camera_ctl.cancel_follow()
		_order_move_all(p)
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

	_drag_overlay = _DragOverlay.new()
	_drag_overlay.z_index = IsoBillboard.Z_DRAG_SELECT
	add_child(_drag_overlay)

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

	# Restore dynamic state from save (must be after start_game so GameState is PLAYING)
	if SaveManager.pending_load:
		SaveManager.restore_world(self)
		camera.position = drop_off.global_position

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
	if is_instance_valid(_drag_overlay):
		var overlay: _DragOverlay = _drag_overlay as _DragOverlay
		overlay.active = _dragging
		if _dragging:
			overlay.drag_rect = Rect2(_drag_start_screen, Vector2.ZERO) \
				.expand(get_viewport().get_mouse_position())
		overlay.queue_redraw()
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_UPDATE_INTERVAL:
		_cursor_timer = 0.0
		CursorManager.set_context(_resolve_cursor_context())

func _exit_tree() -> void:
	CursorManager.set_context("default")

## Feeds CursorManager.resolve_context (the pure, tested mapping) with the
## current selection and whatever right-click target sits under the mouse,
## reusing the same _find_*_at helpers _handle_right_click uses — in the same
## priority order, so cursor and click never disagree.
func _resolve_cursor_context() -> String:
	if _selected_units.is_empty() or _placement._placing_building \
			or _placement._wall_drag_active or not _pending_action.is_empty():
		return "default"
	if _is_mouse_over_hud() or get_viewport().gui_get_hovered_control() != null:
		return "default"
	var has_villagers: bool = false
	var has_military: bool = false
	var has_land_units: bool = false
	for unit: Node in _selected_units:
		if not is_instance_valid(unit) or unit is Animal:
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if unit is Villager:
			has_villagers = true
		elif unit.has_method("is_combat_unit") and unit.is_combat_unit():
			has_military = true
		if not (unit is ShipBase):
			has_land_units = true
	var world_pos: Vector2 = get_global_mouse_position()
	var target_kind: String = "none"
	var target_resource: String = ""
	var transport: TransportShip = _find_own_transport_at(world_pos)
	if transport != null and not transport.is_full():
		target_kind = "transport"
	elif _find_enemy_unit_at(world_pos) != null:
		target_kind = "enemy"
	elif _find_animal_at(world_pos) != null:
		target_kind = "animal"
	elif _find_enemy_building_at(world_pos) != null:
		target_kind = "enemy"
	else:
		var resource_node: ResourceNode = _find_resource_at(world_pos)
		if resource_node != null:
			target_kind = "resource"
			target_resource = resource_node.get_resource_name()
		elif _find_farm_at(world_pos) != null:
			target_kind = "resource"
			target_resource = "food"
		elif _find_own_construction_at(world_pos) != null:
			target_kind = "construction"
		elif _find_own_damaged_building_at(world_pos) != null:
			target_kind = "damaged"
	return CursorManager.resolve_context(has_villagers, has_military,
		has_land_units, target_kind, target_resource)

class _DragOverlay extends Node2D:
	var drag_rect: Rect2 = Rect2()   # screen-space (viewport) coordinates
	var active: bool = false
	func _draw() -> void:
		if not active:
			return
		# Cancel the iso camera transform so the band is a plain screen-space
		# rectangle, like any classic RTS (same trick as weather_overlay).
		draw_set_transform_matrix(get_canvas_transform().affine_inverse())
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.18), true)
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.75), false, 1.5)

class _FlashMarker extends Node2D:
	var flash_color: Color = Color.WHITE
	var flash_t: float = 0.0:
		set(v):
			flash_t = v
			queue_redraw()
	# Drawn in world space on purpose: the iso camera turns the circle into a
	# 2:1 ground ellipse and the world-axis square into the classic ground
	# diamond, so the order marker reads as lying flat on the terrain.
	func _draw() -> void:
		var radius: float = 10.0 + flash_t * 10.0
		var alpha: float = (1.0 - flash_t) * 0.85
		var col: Color = Color(flash_color.r, flash_color.g, flash_color.b, alpha)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col, 2.0)
		var d: float = maxf(2.0, radius * (1.0 - flash_t) * 0.7)
		var diamond: PackedVector2Array = PackedVector2Array([
			Vector2(-d, -d), Vector2(d, -d), Vector2(d, d), Vector2(-d, d), Vector2(-d, -d),
		])
		draw_polyline(diamond, col, 1.5)

func toggle_follow() -> void:
	_camera_ctl.toggle_follow()

func _on_unit_selected_follow(units: Array) -> void:
	_camera_ctl._on_unit_selected_follow(units)

func _on_selection_manager_changed(units: Array) -> void:
	_selected_units.clear()
	for u: Node in units:
		if is_instance_valid(u):
			_selected_units.append(u)

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
			var group_id: int = ke.physical_keycode - KEY_0
			if group_id >= 1 and group_id <= 9:
				# Ctrl (or Cmd on macOS) + digit assigns; plain digit recalls.
				if ke.ctrl_pressed or ke.meta_pressed:
					SelectionManager.save_group(group_id)
				else:
					SelectionManager.recall_group(group_id)
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

		if not _pending_action.is_empty():
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_execute_pending_action(get_global_mouse_position())
				get_viewport().set_input_as_handled()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				hud.cancel_pending()
				get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = get_global_mouse_position()
				_drag_start_screen = get_viewport().get_mouse_position()
				_dragging = true
			else:
				if _dragging:
					_dragging = false
					_finish_selection()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(get_global_mouse_position())

func get_zoom() -> float:
	return _camera_ctl.get_zoom()

func set_zoom(value: float) -> void:
	_camera_ctl.set_zoom(value)

# --- Selection ---

const BUILDING_CLICK_RADIUS: float = 40.0

func _finish_selection() -> void:
	# The band lives in screen space; a small screen area is a click regardless
	# of the current zoom (a world-space area threshold was zoom-dependent).
	var screen_rect: Rect2 = Rect2(_drag_start_screen, Vector2.ZERO) \
		.expand(get_viewport().get_mouse_position())
	var is_click: bool = screen_rect.get_area() < 25.0

	for sel: Node in _selected_units:
		if is_instance_valid(sel):
			sel.set_selected(false)
	_selected_units.clear()
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null
	if is_instance_valid(_selected_node) and _selected_node.has_method("set_selected"):
		_selected_node.set_selected(false)
	_selected_node = null

	if is_click:
		# Click: select only the single nearest friendly unit within radius
		var best_unit: Node = null
		var best_dist: float = UNIT_CLICK_RADIUS
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			var unit2d: Node2D = unit as Node2D
			var d: float = _drag_start.distance_to(unit2d.global_position)
			if d >= best_dist:
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
					best_dist = d
					best_unit = unit
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			best_dist = d
			best_unit = unit
		if best_unit != null:
			var now: float = Time.get_ticks_msec() / 1000.0
			var unit_script: Script = best_unit.get_script() as Script
			var is_double: bool = (now - _last_click_time) <= DOUBLE_CLICK_SEC \
				and unit_script == _last_click_unit_script
			_last_click_time = now
			_last_click_unit_script = unit_script

			if is_double:
				# Select all friendly units of the same type within DOUBLE_CLICK_RADIUS
				for unit: Node in units_layer.get_children():
					if not is_instance_valid(unit):
						continue
					var pid: Variant = unit.get("player_id")
					if pid == null or (pid as int) != 0:
						continue
					if unit.get_script() != unit_script:
						continue
					if (unit as Node2D).global_position.distance_to(
							(best_unit as Node2D).global_position) > DOUBLE_CLICK_RADIUS:
						continue
					unit.set_selected(true)
					if not _selected_units.has(unit):
						_selected_units.append(unit)
			else:
				best_unit.set_selected(true)
				_selected_units.append(best_unit)

			AudioManager.play("ui_select")
			SelectionManager.select(_selected_units)
			return
		# Check Town Center first
		if is_instance_valid(drop_off) and _building_click_hit(drop_off as Node2D, _drag_start):
			_selected_building = drop_off
			EventBus.building_selected.emit(drop_off)
			return
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building):
				continue
			var b2d: Node2D = building as Node2D
			if _building_click_hit(b2d, _drag_start):
				_selected_building = building
				EventBus.building_selected.emit(building)
				return
		for child: Node in get_children():
			if not (child is ResourceNode):
				continue
			var rn: ResourceNode = child as ResourceNode
			if _drag_start.distance_to(rn.global_position) < UNIT_CLICK_RADIUS:
				rn.set_selected(true)
				_selected_node = rn
				EventBus.resource_node_selected.emit(rn)
				return
		# Enemy unit / wild animal / enemy building — inspect only (no command)
		var enemy_unit: Node = _find_enemy_unit_at(_drag_start)
		if enemy_unit != null:
			enemy_unit.set_selected(true)
			_selected_node = enemy_unit
			return
		var wild_animal: Animal = _find_animal_at(_drag_start)
		if wild_animal != null and (wild_animal.current_state != Animal.AnimalState.OWNED or wild_animal.player_id != 0):
			wild_animal.set_selected(true)
			_selected_node = wild_animal
			return
		var enemy_building: Node = _find_enemy_building_at(_drag_start)
		if enemy_building != null:
			enemy_building.set_selected(true)
			_selected_node = enemy_building
			return
	else:
		# Drag: select all friendly units and owned animals whose projected
		# screen position falls inside the screen-space band.
		var to_screen: Transform2D = get_viewport().get_canvas_transform()
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
					if screen_rect.has_point(to_screen * (unit as Node2D).global_position):
						animal.set_selected(true)
						_selected_units.append(animal)
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			if screen_rect.has_point(to_screen * (unit as Node2D).global_position):
				unit.set_selected(true)
				_selected_units.append(unit)

	if not _selected_units.is_empty():
		AudioManager.play("ui_select")
	SelectionManager.select(_selected_units)

# --- Right-click: gather or move ---

func _handle_right_click(world_pos: Vector2) -> void:
	if _selected_units.is_empty():
		if is_instance_valid(_selected_building) and _selected_building.has_method("set_rally_point"):
			_selected_building.set_rally_point(world_pos)
			_flash_target(_selected_building, Color(1.0, 0.92, 0.2, 1.0))
		return

	# 0a. Own transport ship clicked with boardable land units → board
	var transport: TransportShip = _find_own_transport_at(world_pos)
	if transport != null and not transport.is_full():
		var any_boarded: bool = false
		for unit: Node in _selected_units.duplicate():
			if not is_instance_valid(unit) or unit is ShipBase:
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			_order_board(unit, transport)
			any_boarded = true
		if any_boarded:
			_flash_target(transport, Color(0.4, 1.0, 0.4, 1.0))
			return

	# 0b. Transport ship selected → right-click on land = move then unload
	if _selected_units.size() == 1 and is_instance_valid(_selected_units[0]) and _selected_units[0] is TransportShip:
		var ts: TransportShip = _selected_units[0] as TransportShip
		if not ts._garrison.is_empty() and not TerrainManager.is_ocean(world_pos):
			ts.order_move_then_unload(world_pos)
			return

	# 1. Enemy unit clicked → attack
	var enemy_unit: Node = _find_enemy_unit_at(world_pos)
	if enemy_unit != null:
		_order_attack_all(enemy_unit)
		return

	# 2. Animal clicked
	var animal: Animal = _find_animal_at(world_pos)
	if animal != null:
		_order_interact_animal(animal)
		return

	# 3. Enemy building clicked → attack
	var enemy_building: Node = _find_enemy_building_at(world_pos)
	if enemy_building != null:
		_order_attack_all(enemy_building)
		return

	# 4. Own resource drop-off → drop off carried resources, or repair if damaged and no one carries
	var drop_off_node: Node = _find_drop_off_at(world_pos)
	if drop_off_node != null:
		var hp: Variant = drop_off_node.get("health")
		var mhp: Variant = drop_off_node.get("max_health")
		var is_damaged: bool = hp != null and mhp != null and (hp as float) < (mhp as float)
		var any_carrying: bool = false
		for u: Node in _selected_units:
			var ca: Variant = u.get("carried_amount")
			if is_instance_valid(u) and ca != null and (ca as float) > 0.0:
				any_carrying = true
				break
		if is_damaged and not any_carrying:
			_order_build_all(drop_off_node)
		else:
			_order_drop_off_all(drop_off_node)
		return

	# 5. Resource node → gather
	var resource_node: ResourceNode = _find_resource_at(world_pos)
	if resource_node != null:
		_order_gather_all(resource_node)
		return

	# 6. Farm → gather/restore
	var farm: Farm = _find_farm_at(world_pos)
	if farm != null:
		_order_gather_farm(farm)
		return

	# 6b. Fish Trap clicked by fishing boat → gather/restore
	var fish_trap: FishTrap = _find_fish_trap_at(world_pos)
	if fish_trap != null:
		_order_gather_fish_trap(fish_trap)
		return

	# 7. Own gate → just move through it
	var gate: Gate = _find_gate_at(world_pos)
	if gate != null and gate.state == BuildingBase.BuildingState.COMPLETE:
		_order_move_all(world_pos)
		return

	# 8. Own building under construction → build
	var own_construction: Node = _find_own_construction_at(world_pos)
	if own_construction != null:
		_order_build_all(own_construction)
		return

	# 9. Own complete but damaged building → repair
	var damaged_building: Node = _find_own_damaged_building_at(world_pos)
	if damaged_building != null:
		_order_build_all(damaged_building)
		return

	_order_move_all(world_pos)

func _order_attack_ground_all(world_pos: Vector2) -> void:
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_attack_ground"):
			unit.call("order_attack_ground", world_pos)
	_flash_point(world_pos, Color(1.0, 0.6, 0.1, 1.0))
	EventBus.minimap_move_order.emit(world_pos)

func _find_own_transport_at(world_pos: Vector2) -> TransportShip:
	for unit: Node in units_layer.get_children():
		if not (unit is TransportShip):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit as TransportShip
	return null

func _order_board(unit: Node, transport: TransportShip) -> void:
	# Make the unit walk toward the transport; board once in range.
	# We use a lightweight polling approach: move the unit toward the ship
	# and board immediately if already close, otherwise let movement handle it.
	var dist: float = (unit as Node2D).global_position.distance_to(
		(transport as Node2D).global_position)
	if dist <= TransportShip.BOARD_RANGE:
		transport.board(unit)
		_selected_units.erase(unit)
		SelectionManager.select(_selected_units)
	else:
		# Move toward ship; boarding completes when the unit arrives via _board_poll
		if unit.has_method("order_move"):
			unit.call("order_move", (transport as Node2D).global_position)
		_start_board_poll(unit, transport)

func _start_board_poll(unit: Node, transport: TransportShip, attempts: int = 0) -> void:
	const MAX_BOARD_ATTEMPTS: int = 100  # 10 seconds (100 * 0.1s)
	var gw: Node = self
	var timer: SceneTreeTimer = get_tree().create_timer(0.1)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(unit) or not is_instance_valid(transport):
			return
		# Transport destroyed/moved/full - abort boarding
		if transport.is_full():
			return
		var d: float = (unit as Node2D).global_position.distance_to(
			(transport as Node2D).global_position)
		if d <= TransportShip.BOARD_RANGE:
			transport.board(unit)
			gw._selected_units.erase(unit)
			SelectionManager.select(gw._selected_units)
		elif attempts < MAX_BOARD_ATTEMPTS:
			gw._start_board_poll(unit, transport, attempts + 1)
		# else: timeout - unit couldn't reach transport, silently abort
	)

func _find_animal_at(world_pos: Vector2) -> Animal:
	for unit: Node in units_layer.get_children():
		if not (unit is Animal):
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit as Animal
	return null

func _order_interact_animal(animal: Animal) -> void:
	# Right-clicking any animal (own herded sheep included) sends the selected
	# units to slaughter it for food — that's how a sheep yields meat. If no
	# gatherer is selected (e.g. only soldiers), they still attack it.
	for unit: Node in _selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("order_attack"):
			unit.order_attack(animal)

func _find_gate_at(world_pos: Vector2) -> Gate:
	for building: Node in buildings_layer.get_children():
		if not (building is Gate):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			return building as Gate
	return null

func _find_drop_off_at(world_pos: Vector2) -> Node:
	# Town Center
	if is_instance_valid(drop_off) and _building_click_hit(drop_off as Node2D, world_pos):
		return drop_off
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var b2d: Node2D = building as Node2D
		if not _building_click_hit(b2d, world_pos):
			continue
		# Dock — drop-off for fishing boats
		if building is Dock:
			return building
		# Lumber/Mining camps (any complete building that has a DropOffBuilding child)
		for child: Node in building.get_children():
			if child is DropOffBuilding:
				return building
	return null

func _order_drop_off_all(target: Node) -> void:
	_flash_target(target, Color(1.8, 1.8, 0.4, 1.0))
	for unit: Node in _selected_units:
		if not is_instance_valid(unit):
			continue
		if unit is FishingBoat:
			var fb: FishingBoat = unit as FishingBoat
			fb.drop_off_target = target
			if fb.carried_amount > 0.0:
				fb.current_state = UnitBase.UnitState.RETURNING
				fb.nav_agent.target_position = fb._safe_destination((target as Node2D).global_position)
		elif unit.has_method("order_drop_off"):
			unit.order_drop_off(target)

func _find_farm_at(world_pos: Vector2) -> Farm:
	for building: Node in buildings_layer.get_children():
		if not (building is Farm):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			var farm: Farm = building as Farm
			if farm.state == BuildingBase.BuildingState.COMPLETE:
				return farm
	return null

func _order_gather_farm(farm: Farm) -> void:
	_flash_target(farm, Color(1.8, 1.8, 0.4, 1.0))
	if farm.is_depleted():
		_order_restore_farm(farm)
		return
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(farm, "food", null)

func _order_restore_farm(farm: Farm) -> void:
	if not ResourceManager.spend_resource(0, farm.get_restore_cost()):
		return
	farm.restore()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(farm, "food", null)

func _find_fish_trap_at(world_pos: Vector2) -> FishTrap:
	for building: Node in buildings_layer.get_children():
		if not (building is FishTrap):
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			var ft: FishTrap = building as FishTrap
			if ft.state == BuildingBase.BuildingState.COMPLETE:
				return ft
	return null

func _order_gather_fish_trap(fish_trap: FishTrap) -> void:
	_flash_target(fish_trap, Color(1.8, 1.8, 0.4, 1.0))
	if fish_trap.is_depleted():
		_order_restore_fish_trap(fish_trap)
		return
	for unit: Node in _selected_units:
		if unit is FishingBoat:
			var fb: FishingBoat = unit as FishingBoat
			var dock_node: Node = _find_nearest_dock(fb)
			fb.order_fish(fish_trap, dock_node)

func _order_restore_fish_trap(fish_trap: FishTrap) -> void:
	if not ResourceManager.spend_resource(0, fish_trap.get_restore_cost()):
		return
	fish_trap.restore()
	for unit: Node in _selected_units:
		if unit is FishingBoat:
			var fb: FishingBoat = unit as FishingBoat
			var dock_node: Node = _find_nearest_dock(fb)
			fb.order_fish(fish_trap, dock_node)

func _find_enemy_unit_at(world_pos: Vector2) -> Node:
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or unit is Animal:
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit
	return null

## True when a click at `world_pos` lands on `building` as the player SEES it:
## the world-space footprint, or the upright massing volume the iso projection
## draws up-screen from the origin. A distance-to-origin test misses most of a
## large building's base and all of its elevation (the whole visible facade of
## a Town Center resolved to "nothing", silently degrading attack clicks).
func _building_click_hit(building: Node2D, world_pos: Vector2) -> bool:
	var local: Vector2 = world_pos - building.global_position
	var half: Vector2 = Vector2(BUILDING_CLICK_RADIUS, BUILDING_CLICK_RADIUS)
	var cs: CollisionShape2D = building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		half = (cs.shape as RectangleShape2D).size * 0.5 + Vector2(6.0, 6.0)
	if absf(local.x) <= half.x and absf(local.y) <= half.y:
		return true
	# Massing test in screen space; ground-plane buildings (farms) have no
	# massing metadata and fall back to a shallow band over the footprint.
	var s: Vector2 = IsoProjection.world_to_screen(local)
	var half_w: float = (half.x + half.y) * 0.7071
	var top_y: float = (building.get_meta("massing_top_y") as float) \
		if building.has_meta("massing_top_y") else -half_w * 0.5
	var bot_y: float = (building.get_meta("massing_bot_y") as float) \
		if building.has_meta("massing_bot_y") else half_w * 0.5
	return absf(s.x) <= half_w and s.y >= top_y - 4.0 and s.y <= bot_y + 4.0

func _find_enemy_building_at(world_pos: Vector2) -> Node:
	# Front-most (greatest projected origin y) wins when facades overlap.
	var best: Node = null
	var best_depth: float = -INF
	if is_instance_valid(_ai_town_center) and _building_click_hit(_ai_town_center, world_pos):
		best = _ai_town_center
		best_depth = IsoProjection.world_to_screen((_ai_town_center as Node2D).global_position).y
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if not _building_click_hit(building as Node2D, world_pos):
			continue
		var depth: float = IsoProjection.world_to_screen((building as Node2D).global_position).y
		if depth > best_depth:
			best_depth = depth
			best = building
	return best

func _find_own_construction_at(world_pos: Vector2) -> Node:
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if _building_click_hit(building as Node2D, world_pos):
			var state_val: Variant = building.get("state")
			if state_val != null and (state_val as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
				return building
	return null

func _find_own_damaged_building_at(world_pos: Vector2) -> Node:
	# Helper: returns true if a node is a complete (or TC-style) building with less than full HP
	var check: Callable = func(node: Node) -> bool:
		var hp: Variant = node.get("health")
		var mhp: Variant = node.get("max_health")
		if hp == null or mhp == null or (mhp as float) <= 0.0:
			return false
		if (hp as float) >= (mhp as float):
			return false
		# Must be complete (BuildingBase) or have no state field (TownCenterBuilding)
		var sv: Variant = node.get("state")
		if sv != null and (sv as int) != BuildingBase.BuildingState.COMPLETE:
			return false
		return true

	if is_instance_valid(drop_off) and _building_click_hit(drop_off as Node2D, world_pos) and check.call(drop_off):
		return drop_off
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if _building_click_hit(building as Node2D, world_pos) and check.call(building):
			return building
	return null

func _flash_target(node: Node, flash_color: Color = Color(2.0, 2.0, 2.0, 1.0)) -> void:
	if not is_instance_valid(node):
		return
	var n2d: Node2D = node as Node2D
	var original: Color = n2d.modulate
	var tw: Tween = create_tween()
	tw.tween_property(n2d, "modulate", flash_color, 0.07)
	tw.tween_property(n2d, "modulate", original,    0.28)

func _order_attack_all(target: Node) -> void:
	AudioManager.play("cmd_attack")
	_flash_target(target, Color(2.2, 0.4, 0.4, 1.0))
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_attack"):
			unit.order_attack(target)

func _order_build_all(building: Node) -> void:
	_flash_target(building, Color(0.6, 1.8, 0.6, 1.0))
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_build"):
			unit.order_build(building)

func _find_resource_at(world_pos: Vector2) -> ResourceNode:
	for child: Node in get_children():
		if child is ResourceNode:
			var rn: ResourceNode = child as ResourceNode
			if world_pos.distance_to(rn.global_position) < 32.0:
				return rn
	return null

func _order_gather_all(resource_node: ResourceNode) -> void:
	_flash_target(resource_node, Color(1.8, 1.8, 0.4, 1.0))
	var resource_name: String = resource_node.get_resource_name()
	var is_fish: bool = resource_node.resource_type == ResourceNode.ResourceType.FOOD_FISH
	for unit: Node in _selected_units:
		if not is_instance_valid(unit):
			continue
		if is_fish and unit is FishingBoat:
			# Find the nearest friendly dock to use as drop-off
			var dock_node: Node = _find_nearest_dock(unit as Node2D)
			(unit as FishingBoat).order_fish(resource_node, dock_node)
		elif not is_fish and unit.has_method("order_gather"):
			unit.order_gather(resource_node, resource_name, drop_off)

func _find_nearest_dock(requester: Node2D) -> Node:
	var best: Node = null
	var best_dist: float = 9999999.0
	for b: Node in buildings_layer.get_children():
		if not (b is Dock):
			continue
		var pid: Variant = b.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		var d: float = requester.global_position.distance_to((b as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best

func _execute_pending_action(world_pos: Vector2) -> void:
	var action: String = _pending_action
	hud.cancel_pending()   # clears _pending_action via signal
	match action:
		"move_to":
			_order_move_all(world_pos)
			_flash_point(world_pos, Color(0.4, 0.8, 1.0, 1.0))
		"attack_move":
			# If an enemy is directly at the click position, attack it
			var enemy_unit: Node = _find_enemy_unit_at(world_pos)
			var enemy_building: Node = _find_enemy_building_at(world_pos)
			var target: Node = enemy_unit if enemy_unit != null else enemy_building
			if target != null:
				_order_attack_all(target)
			else:
				# Move to position; units will auto-attack any enemy they spot en route
				_order_attack_move_all(world_pos)
			_flash_point(world_pos, Color(1.0, 0.35, 0.15, 1.0))
		"cover_fire":
			_order_attack_ground_all(world_pos)

func _order_attack_move_all(world_pos: Vector2) -> void:
	AudioManager.play("cmd_move")
	var valid_units: Array[Node] = []
	for u: Node in _selected_units:
		if is_instance_valid(u) and u.has_method("order_move"):
			valid_units.append(u)
	var count: int = valid_units.size()
	if count == 0:
		return
	var slots: Array[Vector2] = _formation_slots(world_pos, count)
	for i: int in range(count):
		if valid_units[i].has_method("order_attack_move"):
			valid_units[i].order_attack_move(slots[i])
		else:
			valid_units[i].order_move(slots[i])

## Briefly shows a coloured expanding ring at `world_pos` to confirm a click order.
func _flash_point(world_pos: Vector2, color: Color) -> void:
	var marker: _FlashMarker = _FlashMarker.new()
	marker.flash_color = color
	marker.z_index = 10
	add_child(marker)
	marker.global_position = world_pos
	var tween: Tween = create_tween()
	tween.tween_property(marker, "flash_t", 1.0, 0.45).from(0.0)
	tween.tween_callback(func() -> void:
		if is_instance_valid(marker):
			marker.queue_free()
	)

func _order_move_all(world_pos: Vector2) -> void:
	AudioManager.play("cmd_move")
	var valid_units: Array[Node] = []
	for u: Node in _selected_units:
		if is_instance_valid(u) and u.has_method("order_move"):
			valid_units.append(u)
	var count: int = valid_units.size()
	if count == 0:
		return
	var slots: Array[Vector2] = _formation_slots(world_pos, count)
	for i: int in range(count):
		valid_units[i].order_move(slots[i])
	# Ground flash where the player clicked — move was the only order
	# without click feedback (gather/attack flash their target already).
	_flash_point(world_pos, Color(0.35, 1.0, 0.45, 1.0))
	EventBus.unit_command_issued.emit(valid_units, {"type": "move", "pos": world_pos})

## Returns world-space positions for `count` units in concentric rings around `center`.
## The formation faces away from the average origin of the selected units (nearest ring
## is placed on the side closest to where units are coming from).
func _formation_slots(center: Vector2, count: int) -> Array[Vector2]:
	const SPACING: float = 34.0  # px between slots

	# Average position of selected units → direction they approach from
	var avg_origin: Vector2 = Vector2.ZERO
	for u: Node in _selected_units:
		if is_instance_valid(u):
			avg_origin += (u as Node2D).global_position
	avg_origin /= float(_selected_units.size())
	# "back" direction: from center toward average origin (units arrive from that side)
	var back_dir: Vector2 = (avg_origin - center).normalized()
	if back_dir == Vector2.ZERO:
		back_dir = Vector2.DOWN

	var slots: Array[Vector2] = []
	slots.append(center)  # slot 0: the exact target point
	if count == 1:
		return slots

	# Fill concentric rings: ring r has 6*r slots, radius r*SPACING
	var ring: int = 1
	while slots.size() < count:
		var slots_in_ring: int = 6 * ring
		var radius: float = ring * SPACING
		# Start angle: point the first slot toward the back (approaching side)
		var start_angle: float = back_dir.angle()
		for s: int in range(slots_in_ring):
			if slots.size() >= count:
				break
			var angle: float = start_angle + s * TAU / float(slots_in_ring)
			slots.append(center + Vector2(cos(angle), sin(angle)) * radius)
		ring += 1

	return slots

# --- Building placement (implementation in WorldPlacement) ---

## Kept as thin delegates: the HUD action router and headless tools
## (screenshot_runner, check_placement_preview) call these on the world node.
func _start_placement(building_id: String) -> void:
	_placement._start_placement(building_id)

func _cancel_placement() -> void:
	_placement._cancel_placement()

func _request_nav_rebake() -> void:
	_placement._request_nav_rebake()

# --- HUD action buttons ---

func _on_action_requested(action_id: String) -> void:
	if action_id.begins_with("build:"):
		_start_placement(action_id.trim_prefix("build:"))
		return
	if action_id.begins_with("research:"):
		var tech_id: String = action_id.substr("research:".length())
		if is_instance_valid(_selected_building):
			TechManager.start_research(0, tech_id, _selected_building)
		return
	if action_id.begins_with("market:"):
		if is_instance_valid(_selected_building) and _selected_building is Market:
			var parts: PackedStringArray = action_id.split(":")
			if parts.size() == 3:
				var op: String = parts[1]
				var res: String = parts[2]
				if op == "sell":
					(_selected_building as Market).sell_lot(0, res)
				elif op == "buy":
					(_selected_building as Market).buy_lot(0, res)
				elif op == "hire":
					_hire_mercenary_from_market(_selected_building as Market, res)
		return
	match action_id:
		"gather_wood":
			_order_gather_nearest_resource(ResourceNode.ResourceType.WOOD)
		"gather_gold":
			_order_gather_nearest_resource(ResourceNode.ResourceType.GOLD)
		"gather_stone":
			_order_gather_nearest_resource(ResourceNode.ResourceType.STONE)
		"gather_food":
			_order_gather_nearest_resource(ResourceNode.ResourceType.FOOD_HUNT)
		"train:villager":
			if is_instance_valid(_selected_building) and _selected_building.has_method("order_train"):
				# TownCenterBuildable is now also the player's STARTING TC, so it
				# must be accepted here too or the villager button does nothing.
				if _selected_building is TownCenter or _selected_building is TownCenterBuilding \
						or _selected_building is TownCenterBuildable:
					_selected_building.order_train()
		"train:militia", "train:pikeman", \
		"train:menceyes_guard", \
		"train:conquistador", "train:tidecaller", "train:sand_raider":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train(action_id.trim_prefix("train:"))
		"train:archer", "train:ravine_archer", "train:longbowman":
			if is_instance_valid(_selected_building) and _selected_building is ArcheryRange:
				(_selected_building as ArcheryRange).order_train(action_id.trim_prefix("train:"))
		"train:scout", "train:heavy_scout", "train:knight":
			if is_instance_valid(_selected_building) and _selected_building is Stable:
				(_selected_building as Stable).order_train(action_id.trim_prefix("train:"))
		"train:battering_ram", "train:mangonel", "train:trebuchet":
			if is_instance_valid(_selected_building) and _selected_building is SiegeWorkshop:
				(_selected_building as SiegeWorkshop).order_train(action_id.trim_prefix("train:"))
		"trebuchet_deploy":
			for unit: Node in _selected_units:
				if unit is Trebuchet:
					var treb: Trebuchet = unit as Trebuchet
					if treb.is_deployed:
						treb.order_undeploy()
					else:
						treb.order_deploy()
					hud.call_deferred("_populate_trebuchet_buttons", treb)
					break
		"train:fishing_boat", "train:transport_ship", "train:war_galley":
			if is_instance_valid(_selected_building) and _selected_building is Dock:
				(_selected_building as Dock).order_train(action_id.trim_prefix("train:"))
		"advance_age":
			AgeManager.start_advance(0)
		"gate_lock":
			if is_instance_valid(_selected_building) and _selected_building is Gate:
				(_selected_building as Gate).toggle_lock()
		"unload":
			for unit: Node in _selected_units:
				if unit is TransportShip:
					(unit as TransportShip).unload_all()
					break
		"scout_explore":
			for unit: Node in _selected_units:
				if unit is Scout:
					(unit as Scout).start_auto_explore()
		"scout_explore_stop":
			for unit: Node in _selected_units:
				if unit is Scout:
					(unit as Scout).stop_auto_explore()
		"show_path":
			for unit: Node in _selected_units:
				if is_instance_valid(unit) and unit.has_method("toggle_path_display"):
					unit.toggle_path_display()
		"stop":
			for unit: Node in _selected_units:
				if is_instance_valid(unit) and unit.has_method("order_move"):
					unit.order_move((unit as Node2D).global_position)
		"hero_ability":
			for unit: Node in _selected_units:
				if unit is HeroUnit:
					(unit as HeroUnit).use_ability()
					break
		"destroy":
			if is_instance_valid(_selected_building):
				var target: Node = _selected_building
				if target.has_method("set_selected"):
					target.set_selected(false)
				_selected_building = null
				if target.has_method("take_damage"):
					var hp: Variant = target.get("health")
					var dmg: float = (hp as float + 1.0) if hp != null else 9999.0
					target.take_damage(dmg)
				elif target.has_method("queue_free"):
					target.queue_free()
			elif not _selected_units.is_empty():
				for unit: Node in _selected_units:
					if is_instance_valid(unit) and unit.has_method("die"):
						unit.die()
				_selected_units.clear()
				SelectionManager.select([])
		_:
			if action_id.begins_with("unload_unit:"):
				var idx: int = int(action_id.substr(12))
				for unit: Node in _selected_units:
					if unit is TransportShip:
						(unit as TransportShip).unload_one(idx)
						break

func _hire_mercenary_from_market(market: Market, unit_id: String) -> void:
	if not market.hire_mercenary(unit_id):
		return
	var scene_path: String = "res://scenes/units/%s.tscn" % unit_id
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var unit: Node2D = packed.instantiate() as Node2D
	unit.set("player_id", 0)
	unit.set("civ_id", "fenicios")
	units_layer.add_child(unit)
	var spawn_pos: Vector2 = market.rally_point if market.rally_point != Vector2.ZERO else market.global_position + Vector2(60.0, 0.0)
	unit.global_position = spawn_pos
	PopulationManager.add_unit(0)
	if unit.has_method("order_move") and market.rally_point != Vector2.ZERO:
		unit.order_move(market.rally_point)
	AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, 0)

func _order_gather_nearest_resource(rtype: ResourceNode.ResourceType) -> void:
	if _selected_units.is_empty():
		return
	_selected_units = _selected_units.filter(func(u: Node) -> bool: return is_instance_valid(u))
	if _selected_units.is_empty():
		return
	var pivot: Vector2 = (_selected_units[0] as Node2D).global_position
	var nearest: ResourceNode = _find_nearest_resource_of_type(rtype, pivot)
	if nearest == null:
		return
	var resource_name: String = nearest.get_resource_name()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(nearest, resource_name, drop_off)

func _find_nearest_resource_of_type(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for child: Node in get_children():
		if not (child is ResourceNode):
			continue
		var rn: ResourceNode = child as ResourceNode
		if rn.resource_type != rtype:
			continue
		var d: float = from.distance_to(rn.global_position)
		if d < best_dist:
			best_dist = d
			best = rn
	return best

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

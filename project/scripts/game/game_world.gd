extends Node2D

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const SCOUT_SCENE: PackedScene = preload("res://scenes/units/scout.tscn")
const AI_TOWN_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/town_center_ai.tscn")

const HERO_DATA_BY_CIV: Dictionary = {
	"guanches":    "res://resources/units/hero_bencomo.tres",
	"canarii":     "res://resources/units/hero_doramas.tres",
	"mahos":       "res://resources/units/hero_guadarfia.tres",
	"franks":      "res://resources/units/hero_bethencourt.tres",
	"britons":     "res://resources/units/hero_drake.tres",
	"castellanos": "res://resources/units/hero_quijote.tres",
	"atlantes":    "res://resources/units/hero_artaxerax.tres",
	"fenicios":    "res://resources/units/hero_hanno.tres",
}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _saved_rng_seed: int = 0
var _saved_tc_position: Vector2 = Vector2.ZERO

const BUILDING_SCENES: Dictionary = {
	"house":         "res://scenes/buildings/house.tscn",
	"barracks":      "res://scenes/buildings/barracks.tscn",
	"blacksmith":    "res://scenes/buildings/blacksmith.tscn",
	"stable":        "res://scenes/buildings/stable.tscn",
	"lumber_camp":   "res://scenes/buildings/lumber_camp.tscn",
	"mining_camp":   "res://scenes/buildings/mining_camp.tscn",
	"farm":          "res://scenes/buildings/farm.tscn",
	"wall_segment":  "res://scenes/buildings/wall_segment.tscn",
	"gate":          "res://scenes/buildings/gate.tscn",
	"dock":          "res://scenes/buildings/dock.tscn",
	"fish_trap":     "res://scenes/buildings/fish_trap.tscn",
	"university":    "res://scenes/buildings/university.tscn",
	"market":        "res://scenes/buildings/market.tscn",
	"temple":          "res://scenes/buildings/temple.tscn",
	"siege_workshop":  "res://scenes/buildings/siege_workshop.tscn",
	"town_center":     "res://scenes/buildings/town_center.tscn",
	"wonder":          "res://scenes/buildings/wonder.tscn",
	"watch_tower":     "res://scenes/buildings/watch_tower.tscn",
}

const BUILDING_COSTS: Dictionary = {
	"house":         {"wood": 25},
	"barracks":      {"wood": 175},
	"blacksmith":    {"wood": 150},
	"stable":        {"wood": 175},
	"lumber_camp":   {"wood": 100},
	"mining_camp":   {"wood": 100},
	"farm":          {"wood": 60},
	"wall_segment":  {"stone": 5},
	"gate":          {"wood": 30},
	"dock":          {"wood": 150},
	"fish_trap":       {"wood": 75},
	"siege_workshop":  {"wood": 200},
	"town_center":     {"wood": 275},
	"wonder":          {"wood": 2500, "food": 2500, "stone": 2500, "gold": 5000},
	"watch_tower":     {"stone": 125},
}

# Buildings that must be placed adjacent to water (at least one edge in ocean terrain).
const COASTAL_BUILDINGS: Array = ["dock"]

# Buildings that must be placed fully in ocean (all footprint probes in ocean terrain).
const OCEAN_BUILDINGS: Array = ["fish_trap"]

const CAMERA_SPEED: float = 400.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
const CAMERA_ZOOM_STEP: float = 0.1
const UNIT_CLICK_RADIUS: float = 32.0

@onready var units_layer: Node2D = $UnitsLayer
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var camera: Camera2D = $Camera2D
@onready var drop_off: Node2D = $DropOffNode
@onready var hud: CanvasLayer = $HUD
@onready var _nav_region: NavigationRegion2D = $NavigationRegion2D

# All AI town centers indexed by player_id
var _ai_town_centers: Dictionary = {}   # int → Node2D
var _ai_town_center: Node2D = null      # legacy alias for player_id 1
var _fog: FogOfWar = null

var _selected_units: Array[Node] = []
var _selected_building: Node = null
var _selected_node: Node = null
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _last_click_time: float = -1.0
var _last_click_unit_script: Script = null
const DOUBLE_CLICK_SEC: float  = 0.35
const DOUBLE_CLICK_RADIUS: float = 600.0

var _panning: bool = false
var _pan_last_pos: Vector2 = Vector2.ZERO

var _following: bool = false
var _camera_moved_emitted: bool = false
var _edge_scroll_timer: float = 0.0
var _edge_scroll_last_mouse: Vector2 = Vector2.ZERO
const EDGE_SCROLL_DELAY: float = 0.3
const EDGE_SCROLL_MOUSE_THRESHOLD: float = 4.0  # px — movement above this resets the timer

# Build placement state
var _placing_building: bool = false
var _placing_id: String = ""
var _ghost: Node2D = null
var _ghost_rotation: float = 0.0
var _ghost_shape_cached: RectangleShape2D = null
var _ghost_params_cached: PhysicsShapeQueryParameters2D = null

# Wall drag placement state
var _wall_drag_active: bool = false
var _wall_drag_start: Vector2 = Vector2.ZERO
var _wall_ghosts: Array[Node2D] = []
var _wall_cost_layer: CanvasLayer = null
var _wall_cost_label: Label = null

# Pending action waiting for a map click ("move_to" or "attack_move")
var _pending_action: String = ""

var _wonder_timer: float = 0.0
var _wonder_owner: int = -1
var _wonder_node: Node = null
var _nav_rebake_timer: float = 0.0
var _nav_rebake_pending: bool = false
const NAV_REBAKE_DELAY: float = 1.0

# Drag-select rectangle overlay
var _drag_overlay: Node2D = null

func _ready() -> void:
	add_to_group("world")
	# Init all players — for a load, SaveManager will overwrite afterwards
	var starting_res: Dictionary = MatchConfig.get_starting_resources()
	ResourceManager.init_player(0, starting_res)
	PopulationManager.init_player(0)
	AgeManager.init_player(0, MatchConfig.starting_age)
	for rival_id: int in MatchConfig.get_rival_player_ids():
		ResourceManager.init_player(rival_id, starting_res)
		PopulationManager.init_player(rival_id)
		AgeManager.init_player(rival_id)

	_apply_civilization()

	# Deterministic seed: when loading a save we re-use the stored seed so the
	# map generator produces the exact same layout.
	if SaveManager.pending_load:
		_rng.seed = SaveManager.get_saved_rng_seed()
		_saved_rng_seed = _rng.seed
	else:
		_rng.randomize()
		_saved_rng_seed = _rng.seed

	var map_data: Dictionary = MapGenerator.generate(self, units_layer, _rng)
	var tc_positions: Array[Vector2] = map_data["tc_positions"] as Array[Vector2]

	# Place player TC at tc_positions[0]
	drop_off.global_position = tc_positions[0]
	_saved_tc_position = tc_positions[0]
	camera.position = drop_off.global_position

	if SaveManager.pending_load:
		# AI node structure must still exist for signals / victory checks.
		for rival_id: int in MatchConfig.get_rival_player_ids():
			var tc_pos: Vector2 = tc_positions[rival_id] if rival_id < tc_positions.size() \
				else tc_positions[tc_positions.size() - 1]
			_setup_ai_node_only(rival_id, tc_pos)
		if _ai_town_centers.size() > 0:
			_ai_town_center = _ai_town_centers[1]
	else:
		for i: int in range(3):
			var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
			units_layer.add_child(v)
			v.global_position = drop_off.global_position + Vector2(i * 40 - 40, 60.0)
			v.set("player_id", 0)
			v.set("civ_id", MatchConfig.player_civ_id)
			PopulationManager.add_unit(0)
			EventBus.unit_spawned.emit(v, 0)

		var scout0: CharacterBody2D = SCOUT_SCENE.instantiate()
		units_layer.add_child(scout0)
		scout0.global_position = drop_off.global_position + Vector2(80.0, -60.0)
		scout0.set("player_id", 0)
		scout0.set("civ_id", MatchConfig.player_civ_id)
		PopulationManager.add_unit(0)
		EventBus.unit_spawned.emit(scout0, 0)

		_spawn_hero(0, drop_off.global_position)

		# Spawn one AI per rival
		for rival_id: int in MatchConfig.get_rival_player_ids():
			var tc_pos: Vector2 = tc_positions[rival_id] if rival_id < tc_positions.size() \
				else tc_positions[tc_positions.size() - 1]
			_setup_ai(rival_id, tc_pos)

		# Legacy alias points at the first rival TC
		if _ai_town_centers.size() > 0:
			_ai_town_center = _ai_town_centers[1]

	_setup_ai_debug_overlay()

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
		_following = false
		_order_move_all(p)
	)
	EventBus.unit_selected.connect(_on_unit_selected_follow)
	SelectionManager.selection_changed.connect(_on_selection_manager_changed)
	EventBus.tutorial_spawn_enemy_scout.connect(_on_tutorial_spawn_enemy_scout)
	EventBus.tutorial_highlight_unit.connect(_on_tutorial_highlight_unit)
	EventBus.tutorial_reset_camera_flag.connect(func() -> void: _camera_moved_emitted = false)

	_fog = FogOfWar.new()
	add_child(_fog)
	_fog.setup(units_layer, buildings_layer, drop_off, self)

	var minimap: MinimapRenderer = hud.get_node_or_null("%Minimap") as MinimapRenderer
	if minimap != null:
		minimap.world_node = self
		minimap.camera_node = camera
		minimap.fog = _fog

	_drag_overlay = _DragOverlay.new()
	_drag_overlay.z_index = 20
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

func _apply_civilization() -> void:
	var civ_path: String = "res://resources/civilizations/%s.tres" % MatchConfig.player_civ_id
	var civ: CivilizationResource = load(civ_path) as CivilizationResource
	if civ != null:
		for key: String in (civ.starting_bonuses as Dictionary):
			ResourceManager.add_resource(0, key, (civ.starting_bonuses as Dictionary)[key] as float)
		MatchConfig.set_meta("civ", civ)
	CivBonusManager.init_player(0, MatchConfig.player_civ_id)
	TechManager.init_player(0)
	for rival_id: int in MatchConfig.get_rival_player_ids():
		CivBonusManager.init_player(rival_id, MatchConfig.get_rival_civ_id(rival_id))
		TechManager.init_player(rival_id)

func _get_civ_id_for_player(player_id: int) -> String:
	if player_id == 0:
		return MatchConfig.player_civ_id
	return MatchConfig.get_rival_civ_id(player_id)

func _spawn_hero(player_id: int, tc_pos: Vector2) -> void:
	var civ_id: String = _get_civ_id_for_player(player_id)
	var data_path: String = HERO_DATA_BY_CIV.get(civ_id, "") as String
	if data_path.is_empty():
		return
	var hero_data: UnitResource = load(data_path) as UnitResource
	if hero_data == null:
		return
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var hero: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", hero_data)
	hero.set("player_id", player_id)
	hero.set("civ_id", civ_id)
	hero.global_position = tc_pos + Vector2(-80.0, -60.0)
	units_layer.add_child(hero)
	EventBus.unit_spawned.emit(hero, player_id)

func _on_tutorial_spawn_enemy_scout(near_pos: Vector2) -> void:
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var civ_id: String = MatchConfig.get_rival_civ_id(1)
	var spawn_pos: Vector2 = _find_tutorial_spawn_pos(near_pos, civ_id)
	var militia: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	militia.set("player_id", 1)
	militia.set("civ_id", civ_id)
	militia.global_position = spawn_pos
	units_layer.add_child(militia)
	PopulationManager.add_unit(1)
	EventBus.unit_spawned.emit(militia, 1)

# Returns a passable spawn position near near_pos, avoiding buildings and other units.
# Tries candidate offsets at increasing distances until a clear spot is found.
func _find_tutorial_spawn_pos(near_pos: Vector2, civ_id: String) -> Vector2:
	const MIN_DIST: float = 280.0
	const UNIT_CLEAR_RADIUS: float = 40.0
	var angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5, PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]
	for dist_mult: int in range(1, 6):
		var dist: float = MIN_DIST + dist_mult * 60.0
		for angle: float in angles:
			var candidate: Vector2 = near_pos + Vector2(cos(angle), sin(angle)) * dist
			var passable: Vector2 = TerrainManager.nearest_passable(candidate, civ_id)
			if passable.distance_to(candidate) > 80.0:
				continue  # snapped too far — terrain blocked the whole area
			# Check no building overlaps
			var blocked: bool = false
			for b: Node in buildings_layer.get_children():
				if not is_instance_valid(b):
					continue
				if (b as Node2D).global_position.distance_to(passable) < UNIT_CLEAR_RADIUS + 48.0:
					blocked = true
					break
			if not blocked:
				return passable
	# Fallback: just use nearest_passable from default offset
	return TerrainManager.nearest_passable(near_pos + Vector2(320.0, 0.0), civ_id)

func _on_tutorial_highlight_unit(unit_type: String) -> void:
	var target: Node2D = null
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit.get("player_id") != 0:
			continue
		if unit_type == "hero" and unit is HeroUnit:
			target = unit as Node2D
			break
		if unit_type == "scout" and unit is Scout:
			target = unit as Node2D
			break
	if target == null:
		return
	camera.position = target.global_position
	# Golden pulse: cycle modulate between white and gold several times
	var tween: Tween = target.create_tween()
	tween.set_loops(4)
	tween.tween_property(target, "modulate", Color(1.0, 0.85, 0.1, 1.0), 0.25)
	tween.tween_property(target, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _setup_ai_node_only(rival_id: int, _tc_pos: Vector2) -> void:
	# Creates only the AI controller node; buildings are restored by SaveManager.
	# town_center will be wired up in restore_world() after buildings are recreated.
	var ai: Node = Node.new()
	ai.set_script(load("res://scripts/ai/ai_player.gd"))
	ai.set("player_id", rival_id)
	ai.set_name("AIPlayer_%d" % rival_id)
	add_child(ai)
	ai.set("town_center", null)
	ai.set("units_layer", units_layer)
	ai.set("buildings_layer", buildings_layer)
	ai.set("drop_off", drop_off)
	ai.set("enemy_town_center", drop_off)

func _setup_ai(rival_id: int, tc_pos: Vector2) -> void:
	var rival_civ: String = MatchConfig.get_rival_civ_id(rival_id)
	var tc: Node2D = AI_TOWN_CENTER_SCENE.instantiate() as Node2D
	tc.global_position = tc_pos
	tc.set("player_id", rival_id)
	buildings_layer.add_child(tc)
	_ai_town_centers[rival_id] = tc

	var ai_drop_off: Node = tc.get_node_or_null("DropOff")

	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		units_layer.add_child(v)
		v.global_position = tc.global_position + Vector2(i * 40 - 40, 60.0)
		v.set("player_id", rival_id)
		v.set("civ_id", rival_civ)
		PopulationManager.add_unit(rival_id)
		EventBus.unit_spawned.emit(v, rival_id)

	var scout: CharacterBody2D = SCOUT_SCENE.instantiate()
	units_layer.add_child(scout)
	scout.global_position = tc.global_position + Vector2(80.0, -60.0)
	scout.set("player_id", rival_id)
	scout.set("civ_id", rival_civ)
	PopulationManager.add_unit(rival_id)
	EventBus.unit_spawned.emit(scout, rival_id)

	var ai: Node = Node.new()
	ai.set_script(load("res://scripts/ai/ai_player.gd"))
	ai.set("player_id", rival_id)
	add_child(ai)
	ai.set("town_center", tc)
	ai.set("units_layer", units_layer)
	ai.set("buildings_layer", buildings_layer)
	ai.set("drop_off", ai_drop_off if ai_drop_off != null else tc)
	# AI targets player TC initially; will switch dynamically in Fase 4
	ai.set("enemy_town_center", drop_off)

	_spawn_hero(rival_id, tc_pos)

func _on_building_destroyed_check_victory(building: Node, owner_id: int) -> void:
	if building is Wonder:
		EventBus.wonder_destroyed.emit(owner_id)

	if owner_id == 0:
		if building == drop_off:
			drop_off = null
		_check_player_defeat()
		return

	# Rival TC destroyed → notify; AI handles rebuilding
	var destroyed_rival: int = -1
	for rival_id: int in _ai_town_centers:
		if _ai_town_centers[rival_id] == building:
			destroyed_rival = rival_id
			break

	if destroyed_rival < 0:
		return

	_ai_town_centers.erase(destroyed_rival)
	if _ai_town_center == building:
		_ai_town_center = null

func _on_unit_died_check_victory(unit: Node, owner_id: int) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if owner_id == 0:
		_check_player_defeat()

## Defeat check for the human player: loses when no units AND no buildings remain.
func _check_player_defeat() -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if _has_any_units(0) or _has_any_buildings(0):
		return
	# Pick the first surviving rival as winner
	for rival_id: int in _ai_town_centers:
		if is_instance_valid(_ai_town_centers[rival_id]):
			GameManager.declare_winner(rival_id)
			return
	# Fallback: any rival that still has units or buildings
	for rival_id: int in MatchConfig.get_rival_player_ids():
		if _has_any_units(rival_id) or _has_any_buildings(rival_id):
			GameManager.declare_winner(rival_id)
			return
	GameManager.declare_winner(1)

func _on_player_eliminated(eliminated_id: int) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	# Remove from active rivals list
	if _ai_town_centers.has(eliminated_id):
		_ai_town_centers.erase(eliminated_id)
	if is_instance_valid(_ai_town_center) and _ai_town_center.get("player_id") == eliminated_id:
		_ai_town_center = null
	# Check if all rivals are eliminated
	var any_rival_alive: bool = false
	for rival_id: int in _ai_town_centers:
		if is_instance_valid(_ai_town_centers[rival_id]):
			any_rival_alive = true
			break
	if not any_rival_alive:
		# Also check rivals with no TC but still units
		for rival_id: int in MatchConfig.get_rival_player_ids():
			if _has_any_units(rival_id) or _has_any_buildings(rival_id):
				any_rival_alive = true
				break
	if not any_rival_alive:
		GameManager.declare_winner(0)

## Returns true if player_id has at least one living unit.
func _has_any_units(pid: int) -> bool:
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var p: Variant = unit.get("player_id")
		if p != null and (p as int) == pid:
			return true
	return false

## Returns true if player_id has at least one standing building.
func _has_any_buildings(pid: int) -> bool:
	if pid == 0 and is_instance_valid(drop_off):
		return true
	for b: Node in buildings_layer.get_children():
		if not is_instance_valid(b):
			continue
		var p: Variant = b.get("player_id")
		if p != null and (p as int) == pid:
			return true
	return false

func _on_building_construction_complete(building: Node) -> void:
	if building is Wonder:
		EventBus.wonder_built.emit(building.get("player_id") as int)

func _on_wonder_built(pid: int) -> void:
	if MatchConfig.victory_mode != MatchConfig.VictoryMode.WONDER:
		return
	_wonder_owner = pid
	_wonder_timer = 240.0
	for b: Node in buildings_layer.get_children():
		if b is Wonder and b.get("player_id") == pid:
			_wonder_node = b
			break
	var hud_mgr: Node = hud.get_node_or_null("HudManager")
	if is_instance_valid(hud_mgr) and hud_mgr.has_method("show_wonder_timer"):
		hud_mgr.call("show_wonder_timer", _wonder_owner)

func _on_wonder_destroyed(pid: int) -> void:
	if _wonder_owner != pid:
		return
	var loser: int = pid
	_wonder_timer = 0.0
	_wonder_owner = -1
	_wonder_node = null
	var hud_mgr: Node = hud.get_node_or_null("HudManager")
	if is_instance_valid(hud_mgr) and hud_mgr.has_method("hide_wonder_timer"):
		hud_mgr.call("hide_wonder_timer")
	# The player whose Wonder was destroyed loses
	if loser == 0:
		GameManager.declare_winner(1)
	else:
		GameManager.declare_winner(0)

func _process(delta: float) -> void:
	if _nav_rebake_pending:
		_nav_rebake_timer -= delta
		if _nav_rebake_timer <= 0.0:
			_nav_rebake_pending = false
			_do_nav_rebake()
	if _wonder_timer > 0.0:
		_wonder_timer -= delta
		var hud_mgr: Node = hud.get_node_or_null("HudManager")
		if is_instance_valid(hud_mgr) and hud_mgr.has_method("update_wonder_timer"):
			hud_mgr.call("update_wonder_timer", _wonder_timer)
		if _wonder_timer <= 0.0:
			GameManager.declare_winner(_wonder_owner)
	_handle_camera(delta)
	_handle_follow()
	if _placing_building and is_instance_valid(_ghost):
		var mouse_pos: Vector2 = get_global_mouse_position()
		_ghost.visible = not _wall_drag_active
		_ghost.global_position = mouse_pos
		_ghost.rotation = _ghost_rotation
		var terrain_ok: bool = not TerrainManager.is_ocean(mouse_pos)
		if _placing_id in OCEAN_BUILDINGS:
			terrain_ok = TerrainManager.is_ocean(mouse_pos)
		_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5) if terrain_ok else Color(1.0, 0.2, 0.2, 0.5)
	if _wall_drag_active:
		_update_wall_drag_preview(get_global_mouse_position())
	if is_instance_valid(_drag_overlay):
		var overlay: _DragOverlay = _drag_overlay as _DragOverlay
		overlay.active = _dragging
		if _dragging:
			overlay.drag_rect = Rect2(_drag_start, Vector2.ZERO).expand(get_global_mouse_position())
		overlay.queue_redraw()

class _DragOverlay extends Node2D:
	var drag_rect: Rect2 = Rect2()
	var active: bool = false
	func _draw() -> void:
		if not active:
			return
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.18), true)
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.75), false, 1.5)

class _FlashMarker extends Node2D:
	var flash_color: Color = Color.WHITE
	var flash_t: float = 0.0:
		set(v):
			flash_t = v
			queue_redraw()
	func _draw() -> void:
		var radius: float = 10.0 + flash_t * 10.0
		var alpha: float = (1.0 - flash_t) * 0.85
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24,
			Color(flash_color.r, flash_color.g, flash_color.b, alpha), 2.0)

func _handle_follow() -> void:
	if not _following or _selected_units.is_empty():
		return
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit: Node in _selected_units:
		if is_instance_valid(unit):
			centroid += (unit as Node2D).global_position
			count += 1
	if count == 0:
		_following = false
		return
	camera.position = centroid / float(count)

func toggle_follow() -> void:
	_following = not _following

func _on_unit_selected_follow(_units: Array) -> void:
	_following = false

func _on_selection_manager_changed(units: Array) -> void:
	_selected_units.clear()
	for u: Node in units:
		if is_instance_valid(u):
			_selected_units.append(u)

const EDGE_SCROLL_MARGIN: float = 60.0

func _handle_camera(delta: float) -> void:
	# Keyboard input — immediate response
	# Use is_physical_key_pressed to bypass UI focus interception of arrow keys
	var key_dir: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):  key_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): key_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):    key_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):  key_dir.y += 1.0

	var edge_dir: Vector2 = Vector2.ZERO
	if GameSettings.edge_scroll_enabled:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var mp: Vector2 = get_viewport().get_mouse_position()
		if mp.x < EDGE_SCROLL_MARGIN:          edge_dir.x -= 1.0
		elif mp.x > vp.x - EDGE_SCROLL_MARGIN: edge_dir.x += 1.0
		if mp.y < EDGE_SCROLL_MARGIN:          edge_dir.y -= 1.0
		elif mp.y > vp.y - EDGE_SCROLL_MARGIN: edge_dir.y += 1.0

		if edge_dir != Vector2.ZERO:
			# Reset timer if the mouse is still moving — only count time while stationary in the margin
			if mp.distance_to(_edge_scroll_last_mouse) > EDGE_SCROLL_MOUSE_THRESHOLD:
				_edge_scroll_timer = 0.0
			else:
				_edge_scroll_timer += delta
		else:
			_edge_scroll_timer = 0.0
		_edge_scroll_last_mouse = mp

	var dir: Vector2 = key_dir
	if GameSettings.edge_scroll_enabled and _edge_scroll_timer >= EDGE_SCROLL_DELAY:
		dir += edge_dir

	if dir != Vector2.ZERO:
		if _following:
			_following = false
			EventBus.camera_follow_cancelled.emit()
		camera.position += dir.normalized() * CAMERA_SPEED * delta
		if not _camera_moved_emitted:
			_camera_moved_emitted = true
			EventBus.camera_moved.emit()
	var mh: float = TerrainManager.minimap_map_half
	camera.position = camera.position.clamp(Vector2(-mh, -mh), Vector2(mh, mh))

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
		if _placing_building and ke.pressed and not ke.echo:
			if ke.physical_keycode == KEY_R:
				_ghost_rotation += PI / 2.0
				get_viewport().set_input_as_handled()
			elif ke.physical_keycode == KEY_ESCAPE:
				_cancel_placement()
				get_viewport().set_input_as_handled()
			return
		if ke.pressed and not ke.echo:
			if ke.unicode == 43 or ke.physical_keycode == KEY_KP_ADD:
				_zoom(CAMERA_ZOOM_STEP)
				get_viewport().set_input_as_handled()
				return
			if ke.unicode == 45 or ke.physical_keycode == KEY_KP_SUBTRACT:
				_zoom(-CAMERA_ZOOM_STEP)
				get_viewport().set_input_as_handled()
				return
		return

	if event is InputEventMouseMotion and _panning:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		camera.position -= motion.relative / camera.zoom.x
		get_viewport().set_input_as_handled()
		if not _camera_moved_emitted:
			_camera_moved_emitted = true
			EventBus.camera_moved.emit()
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			if _panning and _following:
				_following = false
				EventBus.camera_follow_cancelled.emit()
			get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(-CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return

		if _is_mouse_over_hud():
			return

		if _placing_building:
			var is_wall_drag: bool = _placing_id == "wall_segment"
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if is_wall_drag and not _wall_drag_active:
					_wall_drag_start = get_global_mouse_position()
					_wall_drag_active = true
				elif is_wall_drag and _wall_drag_active:
					_confirm_wall_drag(get_global_mouse_position())
				else:
					_confirm_placement(get_global_mouse_position())
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_placement()
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
				_dragging = true
			else:
				if _dragging:
					_dragging = false
					_finish_selection(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(get_global_mouse_position())

func _zoom(step: float) -> void:
	camera.zoom = (camera.zoom + Vector2(step, step)).clamp(
		Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
		Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX))

func get_zoom() -> float:
	return camera.zoom.x

func set_zoom(value: float) -> void:
	camera.zoom = Vector2(value, value).clamp(
		Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
		Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX))

# --- Selection ---

const BUILDING_CLICK_RADIUS: float = 40.0

func _finish_selection(release_pos: Vector2) -> void:
	var rect: Rect2 = Rect2(_drag_start, Vector2.ZERO).expand(release_pos)
	var is_click: bool = rect.get_area() < 10.0

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
		if is_instance_valid(drop_off) and _drag_start.distance_to(drop_off.global_position) < BUILDING_CLICK_RADIUS:
			_selected_building = drop_off
			EventBus.building_selected.emit(drop_off)
			return
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building):
				continue
			var b2d: Node2D = building as Node2D
			if _drag_start.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
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
		# Drag: select all friendly units and owned animals inside the rectangle
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
					if rect.has_point((unit as Node2D).global_position):
						animal.set_selected(true)
						_selected_units.append(animal)
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			if rect.has_point((unit as Node2D).global_position):
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

func _start_board_poll(unit: Node, transport: TransportShip) -> void:
	var gw: Node = self
	var timer: SceneTreeTimer = get_tree().create_timer(0.1)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(unit) or not is_instance_valid(transport):
			return
		var d: float = (unit as Node2D).global_position.distance_to(
			(transport as Node2D).global_position)
		if d <= TransportShip.BOARD_RANGE:
			transport.board(unit)
			gw._selected_units.erase(unit)
			SelectionManager.select(gw._selected_units)
		else:
			gw._start_board_poll(unit, transport)
	)

func _find_animal_at(world_pos: Vector2) -> Animal:
	for unit: Node in units_layer.get_children():
		if not (unit is Animal):
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit as Animal
	return null

func _order_interact_animal(animal: Animal) -> void:
	# Own sheep: move selected units toward it (to escort / bring closer)
	# Enemy or wild animals: attack
	if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
		_order_move_all((animal as Node2D).global_position)
		return
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
	if is_instance_valid(drop_off) and world_pos.distance_to(drop_off.global_position) < BUILDING_CLICK_RADIUS:
		return drop_off
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) >= BUILDING_CLICK_RADIUS:
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

func _find_enemy_building_at(world_pos: Vector2) -> Node:
	# Check enemy Town Center
	if is_instance_valid(_ai_town_center):
		if world_pos.distance_to((_ai_town_center as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			return _ai_town_center
	# Check buildings layer
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			return building
	return null

func _find_own_construction_at(world_pos: Vector2) -> Node:
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS:
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

	if is_instance_valid(drop_off) and world_pos.distance_to(drop_off.global_position) < BUILDING_CLICK_RADIUS and check.call(drop_off):
		return drop_off
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS and check.call(building):
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

# --- Building placement ---

func _start_placement(building_id: String) -> void:
	if not BUILDING_SCENES.has(building_id):
		return
	if not ResourceManager.can_afford(0, BUILDING_COSTS.get(building_id, {})):
		return

	_cancel_placement()
	_placing_building = true
	_placing_id = building_id
	_ghost_rotation = 0.0

	var scene: PackedScene = load(BUILDING_SCENES[building_id]) as PackedScene
	_ghost = scene.instantiate() as Node2D
	_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5)
	for child: Node in _ghost.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			(child as CollisionShape2D).disabled = true
	buildings_layer.add_child(_ghost)

	_ghost_shape_cached = _get_ghost_shape()
	_ghost_params_cached = PhysicsShapeQueryParameters2D.new()
	_ghost_params_cached.shape = _ghost_shape_cached
	_ghost_params_cached.collision_mask = 1

func _placement_overlaps(world_pos: Vector2) -> bool:
	if _ghost_params_cached == null or _ghost_shape_cached == null:
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	_ghost_params_cached.transform = Transform2D(_ghost_rotation, world_pos)
	var results: Array[Dictionary] = space.intersect_shape(_ghost_params_cached, 1)
	if results.size() > 0:
		return true
	if _placing_id in COASTAL_BUILDINGS and not _is_coastal(world_pos, _ghost_shape_cached):
		return true
	if _placing_id in OCEAN_BUILDINGS and not _is_fully_ocean(world_pos, _ghost_shape_cached):
		return true
	return false

# Returns true if the dock footprint touches both ocean and land —
# at least one cardinal probe is ocean AND at least one is non-ocean.
func _is_coastal(world_pos: Vector2, shape: RectangleShape2D) -> bool:
	var half: Vector2 = shape.size * 0.5 + Vector2(8.0, 8.0)
	var probes: Array[Vector2] = [
		world_pos + Vector2(0.0,  half.y),
		world_pos + Vector2(0.0, -half.y),
		world_pos + Vector2( half.x, 0.0),
		world_pos + Vector2(-half.x, 0.0),
	]
	var has_ocean: bool = false
	var has_land:  bool = false
	for p: Vector2 in probes:
		if TerrainManager.is_ocean(p):
			has_ocean = true
		else:
			has_land = true
	return has_ocean and has_land

func _is_fully_ocean(world_pos: Vector2, shape: RectangleShape2D) -> bool:
	var half: Vector2 = shape.size * 0.5
	var probes: Array[Vector2] = [
		world_pos,
		world_pos + Vector2(half.x,  half.y),
		world_pos + Vector2(-half.x, half.y),
		world_pos + Vector2(half.x, -half.y),
		world_pos + Vector2(-half.x, -half.y),
	]
	for p: Vector2 in probes:
		if not TerrainManager.is_ocean(p):
			return false
	return true

func _get_ghost_shape() -> RectangleShape2D:
	for child: Node in _ghost.get_children():
		if child is CollisionShape2D:
			var cs: CollisionShape2D = child as CollisionShape2D
			if cs.shape is RectangleShape2D:
				return cs.shape as RectangleShape2D
	return null

func _confirm_placement(world_pos: Vector2) -> void:
	if _placement_overlaps(world_pos):
		return
	var costs: Dictionary = BUILDING_COSTS.get(_placing_id, {})
	if not ResourceManager.spend_resource(0, costs):
		_cancel_placement()
		return

	var scene: PackedScene = load(BUILDING_SCENES[_placing_id]) as PackedScene
	var building: Node2D = scene.instantiate() as Node2D
	building.global_position = world_pos
	building.rotation = _ghost_rotation
	building.set("player_id", 0)
	building.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	building.set_meta("building_id", _placing_id)
	buildings_layer.add_child(building)
	AudioManager.play("build_place")
	EventBus.building_placed.emit(building, 0)

	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_build"):
			unit.order_build(building)

	if Input.is_key_pressed(KEY_SHIFT):
		# Keep placement mode active for the same building type.
		var keep_id: String = _placing_id
		_cancel_placement()
		_start_placement(keep_id)
	else:
		_cancel_placement()

func _cancel_placement() -> void:
	_placing_building = false
	_placing_id = ""
	_ghost_rotation = 0.0
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_shape_cached = null
	_ghost_params_cached = null
	_wall_drag_active = false
	_wall_drag_start = Vector2.ZERO
	for g: Node2D in _wall_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_wall_ghosts.clear()
	if is_instance_valid(_wall_cost_label):
		_wall_cost_label.queue_free()
	_wall_cost_label = null
	if is_instance_valid(_wall_cost_layer):
		_wall_cost_layer.queue_free()
	_wall_cost_layer = null

func _wall_segment_positions(start: Vector2, end: Vector2, step: float) -> Array[Vector2]:
	var delta: Vector2 = end - start
	var dist: float = delta.length()
	if dist < step * 0.5:
		return []
	var dir: Vector2 = delta.normalized()
	var count: int = maxi(1, int(dist / step))
	var result: Array[Vector2] = []
	for i: int in range(count):
		result.append(start + dir * (step * 0.5 + i * step))
	return result

func _update_wall_drag_preview(end_pos: Vector2) -> void:
	for g: Node2D in _wall_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_wall_ghosts.clear()

	const WALL_STEP: float = 16.0
	var positions: Array[Vector2] = _wall_segment_positions(_wall_drag_start, end_pos, WALL_STEP)

	for pos: Vector2 in positions:
		var ghost: Node2D = Node2D.new()
		ghost.global_position = pos
		var rect: ColorRect = ColorRect.new()
		rect.size = Vector2(16.0, 16.0)
		rect.position = Vector2(-8.0, -8.0)
		rect.color = Color(0.4, 0.7, 1.0, 0.45)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.add_child(rect)
		ghost.z_index = 5
		buildings_layer.add_child(ghost)
		_wall_ghosts.append(ghost)

	var cost_per: int = BUILDING_COSTS.get("wall_segment", {}).get("stone", 0) as int
	var total_cost: int = positions.size() * cost_per

	if not is_instance_valid(_wall_cost_layer):
		_wall_cost_layer = CanvasLayer.new()
		_wall_cost_layer.layer = 10
		add_child(_wall_cost_layer)
		_wall_cost_label = Label.new()
		_wall_cost_label.add_theme_font_size_override("font_size", 14)
		_wall_cost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 1.0))
		_wall_cost_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		_wall_cost_label.add_theme_constant_override("shadow_offset_x", 1)
		_wall_cost_label.add_theme_constant_override("shadow_offset_y", 1)
		_wall_cost_layer.add_child(_wall_cost_label)

	_wall_cost_label.text = "Stone: %d" % total_cost
	var vp_mouse: Vector2 = get_viewport().get_mouse_position()
	_wall_cost_label.position = vp_mouse + Vector2(16.0, -24.0)

func _confirm_wall_drag(end_pos: Vector2) -> void:
	const WALL_STEP: float = 16.0
	var positions: Array[Vector2] = _wall_segment_positions(_wall_drag_start, end_pos, WALL_STEP)
	if positions.is_empty():
		_cancel_placement()
		return

	var costs: Dictionary = BUILDING_COSTS.get("wall_segment", {})
	var scene: PackedScene = load(BUILDING_SCENES["wall_segment"]) as PackedScene
	var placed_count: int = 0

	for seg_pos: Vector2 in positions:
		if not ResourceManager.can_afford(0, costs):
			break
		if not ResourceManager.spend_resource(0, costs):
			break
		var building: Node2D = scene.instantiate() as Node2D
		building.global_position = seg_pos
		building.set("player_id", 0)
		building.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
		building.set_meta("building_id", "wall_segment")
		buildings_layer.add_child(building)
		EventBus.building_placed.emit(building, 0)
		for unit: Node in _selected_units:
			if is_instance_valid(unit) and unit.has_method("order_build"):
				unit.order_build(building)
		placed_count += 1

	if placed_count > 0:
		AudioManager.play("build_place")

	var keep_id: String = _placing_id
	_cancel_placement()
	if Input.is_key_pressed(KEY_SHIFT):
		_start_placement(keep_id)

func _request_nav_rebake() -> void:
	_nav_rebake_pending = true
	_nav_rebake_timer = NAV_REBAKE_DELAY

func _do_nav_rebake() -> void:
	if not is_instance_valid(_nav_region):
		return
	var nav_poly: NavigationPolygon = _nav_region.navigation_polygon
	if nav_poly == null:
		return
	var source: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(PackedVector2Array([
		Vector2(-3000.0, -3000.0), Vector2(3000.0, -3000.0),
		Vector2(3000.0,  3000.0), Vector2(-3000.0,  3000.0),
	]))
	for b: Node in buildings_layer.get_children():
		if not is_instance_valid(b) or not b.has_method("get_nav_obstacle_polygon"):
			continue
		var sv: Variant = b.get("state")
		if sv != null and (sv as int) == BuildingBase.BuildingState.DESTROYED:
			continue
		source.add_obstruction_outline(b.call("get_nav_obstacle_polygon") as PackedVector2Array)
	if is_instance_valid(drop_off) and drop_off.has_method("get_nav_obstacle_polygon"):
		source.add_obstruction_outline(drop_off.call("get_nav_obstacle_polygon") as PackedVector2Array)
	for rn: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(rn) or not rn.has_method("get_nav_obstacle_polygon"):
			continue
		source.add_obstruction_outline(rn.call("get_nav_obstacle_polygon") as PackedVector2Array)
	NavigationServer2D.bake_from_source_geometry_data_async(
		nav_poly, source, Callable(self, "_on_nav_bake_done"))

func _on_nav_bake_done() -> void:
	if is_instance_valid(_nav_region):
		_nav_region.navigation_polygon = _nav_region.navigation_polygon

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
				if _selected_building is TownCenter or _selected_building is TownCenterBuilding:
					_selected_building.order_train()
		"train:militia":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train("militia")
		"train:archer":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train("archer")
		"train:pikeman":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train("pikeman")
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

func _on_game_over(_winner: int) -> void:
	AudioManager.stop_music()
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	# Freeze units and buildings without pausing the whole tree
	# (pausing the tree stops building production queues too)
	for unit: Node in units_layer.get_children():
		if is_instance_valid(unit):
			(unit as Node).set_process(false)
			(unit as Node).set_physics_process(false)
	for building: Node in buildings_layer.get_children():
		if is_instance_valid(building):
			(building as Node).set_process(false)
	if is_instance_valid(drop_off):
		drop_off.set_process(false)
	if is_instance_valid(_ai_town_center):
		_ai_town_center.set_process(false)

func _setup_ai_debug_overlay() -> void:
	var overlay: AIDebugOverlay = AIDebugOverlay.new()
	add_child(overlay)
	for child: Node in get_children():
		if child.get_script() != null and (child.get_script() as Script).resource_path.contains("ai_player"):
			overlay.register_ai(child)

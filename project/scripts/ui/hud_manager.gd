extends CanvasLayer

signal action_requested(action_id: String)
signal follow_requested()
## Emitted for actions that require a follow-up map click (move_to, attack_move).
signal pending_action_started(action_id: String)
signal pending_action_cancelled()

@export var local_player_id: int = 0

@onready var _food_display: ResourceDisplay = %FoodDisplay
@onready var _wood_display: ResourceDisplay = %WoodDisplay
@onready var _gold_display: ResourceDisplay = %GoldDisplay
@onready var _stone_display: ResourceDisplay = %StoneDisplay
@onready var _population_label: Label = %PopulationDisplay
@onready var _age_label: Label = %AgeDisplay
@onready var _clock_label: Label = %GameClock
@onready var _unit_portraits_grid: GridContainer = %UnitPortraitsGrid
@onready var _unit_name_label: Label = %UnitNameLabel
@onready var _unit_hp_bar: ProgressBar = %UnitHPBar
@onready var _unit_status_label: Label = %UnitStatusLabel
@onready var _action_grid: GridContainer = %ActionButtonsGrid
@onready var _train_queue_row: HBoxContainer = %TrainQueueRow
@onready var _pause_overlay: ColorRect = %PauseOverlay

const DESTROY_ACTION: Dictionary = {"id": "destroy", "label": "ACTION_DESTROY", "color": Color(0.55, 0.05, 0.05), "cost": {}, "key": KEY_DELETE, "description": "TOOLTIP_DESTROY"}

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "ACTION_WOOD",         "color": Color(0.20, 0.55, 0.15), "cost": {}, "key": KEY_C, "description": "TOOLTIP_GATHER_WOOD"},
	{"id": "gather_gold",  "label": "ACTION_GOLD",         "color": Color(0.75, 0.65, 0.10), "cost": {}, "key": KEY_G, "description": "TOOLTIP_GATHER_GOLD"},
	{"id": "gather_stone", "label": "ACTION_STONE",        "color": Color(0.55, 0.55, 0.55), "cost": {}, "key": KEY_T, "description": "TOOLTIP_GATHER_STONE"},
	{"id": "gather_food",  "label": "ACTION_FOOD",         "color": Color(0.60, 0.20, 0.15), "cost": {}, "key": KEY_H, "description": "TOOLTIP_GATHER_FOOD"},
	{"id": "build_menu",   "label": "ACTION_BUILD",        "color": Color(0.20, 0.30, 0.60), "cost": {}, "key": KEY_B, "description": "TOOLTIP_BUILD_MENU"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",      "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE",  "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "stop",         "label": "ACTION_STOP",         "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	{"id": "show_path",    "label": "ACTION_SHOW_PATH",    "color": Color(0.15, 0.45, 0.55), "cost": {}, "key": KEY_P, "description": "TOOLTIP_SHOW_PATH"},
	DESTROY_ACTION,
]

const BUILD_ACTIONS: Array = [
	{"id": "build:house",         "label": "ACTION_HOUSE",        "color": Color(0.50, 0.38, 0.22), "cost": {"wood": 25},  "key": KEY_H, "description": "TOOLTIP_BUILD_HOUSE",    "min_age": 0},
	{"id": "build:barracks",       "label": "ACTION_BARRACKS",       "color": Color(0.45, 0.22, 0.18), "cost": {"wood": 175}, "key": KEY_B, "description": "TOOLTIP_BUILD_BARRACKS",       "min_age": 0},
	{"id": "build:archery_range", "label": "ACTION_ARCHERY_RANGE",  "color": Color(0.25, 0.45, 0.20), "cost": {"wood": 175}, "key": KEY_A, "description": "TOOLTIP_BUILD_ARCHERY_RANGE", "min_age": 1},
	{"id": "build:blacksmith",    "label": "ACTION_BLACKSMITH",   "color": Color(0.55, 0.40, 0.20), "cost": {"wood": 150}, "key": KEY_K, "description": "TOOLTIP_BUILD_BLACKSMITH","min_age": 1},
	{"id": "build:stable",        "label": "ACTION_STABLE",       "color": Color(0.40, 0.30, 0.15), "cost": {"wood": 175}, "key": KEY_J, "description": "TOOLTIP_BUILD_STABLE",   "min_age": 1},
	{"id": "build:lumber_camp",   "label": "ACTION_LUMBER",       "color": Color(0.30, 0.20, 0.08), "cost": {"wood": 100}, "key": KEY_L, "description": "TOOLTIP_BUILD_LUMBER",   "min_age": 0},
	{"id": "build:mining_camp",   "label": "ACTION_MINING",       "color": Color(0.50, 0.46, 0.34), "cost": {"wood": 100}, "key": KEY_N, "description": "TOOLTIP_BUILD_MINING",   "min_age": 0},
	{"id": "build:farm",          "label": "ACTION_FARM",         "color": Color(0.60, 0.52, 0.18), "cost": {"wood": 60},  "key": KEY_F, "description": "TOOLTIP_BUILD_FARM",     "min_age": 0},
	{"id": "build:wall_segment",  "label": "ACTION_WALL",         "color": Color(0.55, 0.52, 0.48), "cost": {"stone": 5},  "key": KEY_Q, "description": "TOOLTIP_BUILD_WALL",     "min_age": 0},
	{"id": "build:gate",          "label": "ACTION_GATE",         "color": Color(0.42, 0.30, 0.12), "cost": {"wood": 30},  "key": KEY_G, "description": "TOOLTIP_BUILD_GATE",       "min_age": 0},
	{"id": "build:watch_tower",   "label": "ACTION_WATCH_TOWER",  "color": Color(0.45, 0.42, 0.38), "cost": {"stone": 125}, "key": KEY_O, "description": "TOOLTIP_WATCH_TOWER",    "min_age": 1},
	{"id": "build:dock",          "label": "ACTION_DOCK",         "color": Color(0.18, 0.32, 0.55), "cost": {"wood": 150}, "key": KEY_C, "description": "TOOLTIP_BUILD_DOCK",     "min_age": 0},
	{"id": "build:market",        "label": "ACTION_MARKET",       "color": Color(0.65, 0.50, 0.10), "cost": {"wood": 175}, "key": KEY_R, "description": "TOOLTIP_BUILD_MARKET",   "min_age": 1},
	{"id": "build:university",      "label": "ACTION_UNIVERSITY",     "color": Color(0.20, 0.30, 0.50), "cost": {"wood": 200}, "key": KEY_U, "description": "TOOLTIP_BUILD_UNIVERSITY",    "min_age": 2},
	{"id": "build:temple",          "label": "ACTION_TEMPLE",         "color": Color(0.50, 0.30, 0.55), "cost": {"wood": 175}, "key": KEY_T, "description": "TOOLTIP_BUILD_TEMPLE",       "min_age": 2},
	{"id": "build:siege_workshop",  "label": "ACTION_SIEGE_WORKSHOP", "color": Color(0.42, 0.32, 0.18), "cost": {"wood": 200}, "key": KEY_I, "description": "TOOLTIP_BUILD_SIEGE_WORKSHOP","min_age": 2},
	{"id": "build:town_center",     "label": "ACTION_TOWN_CENTER",    "color": Color(0.55, 0.18, 0.12), "cost": {"wood": 275}, "key": KEY_Y, "description": "TOOLTIP_BUILD_TOWN_CENTER",  "min_age": 2},
	{"id": "build:wonder",          "label": "ACTION_WONDER",         "color": Color(0.75, 0.62, 0.12), "cost": {"wood": 2500, "food": 2500, "stone": 2500, "gold": 5000}, "key": KEY_V, "description": "TOOLTIP_BUILD_WONDER", "min_age": 3},
	{"id": "back",                "label": "ACTION_BACK",         "color": Color(0.25, 0.25, 0.25), "cost": {},            "key": KEY_ESCAPE, "description": "TOOLTIP_BUILD_BACK"},
]

const STABLE_UNIT_DEFS: Array[Dictionary] = [
	{"id": "scout",       "label": "ACTION_SCOUT",       "color": Color(0.25, 0.65, 0.30), "cost": {"food": 80},            "age": 0, "description": "TOOLTIP_SCOUT"},
	{"id": "heavy_scout", "label": "ACTION_HEAVY_SCOUT", "color": Color(0.55, 0.40, 0.15), "cost": {"food": 80, "gold": 30}, "age": 1, "description": "TOOLTIP_HEAVY_SCOUT"},
	{"id": "knight",      "label": "ACTION_KNIGHT",      "color": Color(0.25, 0.30, 0.55), "cost": {"food": 60, "gold": 75}, "age": 2, "description": "TOOLTIP_KNIGHT"},
]

const TOWN_CENTER_ACTIONS: Array = [
	{"id": "train:villager", "label": "ACTION_VILLAGER", "color": Color(0.20, 0.45, 0.20), "cost": {"food": 50}, "key": KEY_V, "description": "TOOLTIP_TRAIN_VILLAGER"},
]

const UNIT_ACTIONS: Array = [
	{"id": "move_to",      "label": "ACTION_MOVE_TO",      "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE",  "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "stop",         "label": "ACTION_STOP",         "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	{"id": "show_path",    "label": "ACTION_SHOW_PATH",    "color": Color(0.15, 0.45, 0.55), "cost": {}, "key": KEY_P, "description": "TOOLTIP_SHOW_PATH"},
	DESTROY_ACTION,
]

const ANIMAL_ACTIONS: Array = [
	{"id": "move_to", "label": "ACTION_MOVE_TO", "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
]

const TRANSPORT_ACTIONS: Array = [
	{"id": "unload",  "label": "UI_UNLOAD",      "color": Color(0.20, 0.45, 0.65), "cost": {}, "key": KEY_U, "description": "TOOLTIP_UNLOAD"},
	{"id": "stop",    "label": "ACTION_STOP",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	DESTROY_ACTION,
]

const BUILDING_ACTIONS: Array = [
	DESTROY_ACTION,
]

const DOCK_UNIT_DEFS: Array = [
	{"id": "fishing_boat",   "label": "ACTION_FISHING_BOAT",   "color": Color(0.20, 0.50, 0.65), "cost": {"wood": 75},            "age": 0, "description": "TOOLTIP_FISHING_BOAT"},
	{"id": "transport_ship", "label": "ACTION_TRANSPORT_SHIP", "color": Color(0.55, 0.45, 0.20), "cost": {"wood": 125},           "age": 1, "description": "TOOLTIP_TRANSPORT_SHIP"},
	{"id": "war_galley",     "label": "ACTION_WAR_GALLEY",     "color": Color(0.65, 0.18, 0.18), "cost": {"wood": 75, "gold": 35}, "age": 1, "description": "TOOLTIP_WAR_GALLEY"},
]

const GATE_ACTIONS: Array = [
	{"id": "gate_lock", "label": "UI_GATE_LOCK", "color": Color(0.55, 0.15, 0.10), "cost": {}, "key": KEY_O, "description": "TOOLTIP_GATE_LOCK"},
	DESTROY_ACTION,
]

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _idle_villager_check_timer: float = 0.0
var _in_build_menu: bool = false
var _selected_building: Node = null
var _selected_unit: Node = null   # tracked for transport garrison refresh
var _status_unit: Node = null
var _active_actions: Array = []
var _follow_btn: Button = null
var _following: bool = false
var _idle_villager_btn: Button = null
var _idle_villager_index: int = 0  # cycles through idle villagers on repeated presses
var _idle_military_btn: Button = null
var _idle_military_index: int = 0
var _dpad: Control = null
var _dpad_dir: Vector2 = Vector2.ZERO
var _pending_action: String = ""  # action waiting for a map click
var _age_advance_bar: ProgressBar = null
var _hero_respawn_bar: ProgressBar = null
var _hero_respawn_label: Label = null
var _research_bar: ProgressBar = null
var _research_label: Label = null
var _pause_menu: Control = null
var _wonder_label: Label = null
var _hero_alert_overlay: ColorRect = null

const ACTION_COLS: int = 5
const ACTION_ROWS: int = 2
const PAGE_SIZE: int = ACTION_COLS * ACTION_ROWS  # 10
var _action_page: int = 0
var _page_prev_btn: Button = null
var _page_next_btn: Button = null

# --- Gatherer counts ---
var _gatherer_counts: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}

# --- Stats tracking ---
var _stat_units_trained: int = 0
var _stat_buildings_built: int = 0
var _stat_enemies_killed: int = 0
var _stat_resources_gathered: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}

# Rival stats — indexed by player_id (supports any number of rivals)
# Kept as separate vars for compatibility with snapshot/chart code (player_id 1)
var _ai_stat_units_trained: int = 0
var _ai_stat_buildings_built: int = 0
var _ai_stat_units_lost: int = 0
var _ai_stat_resources_gathered: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}
var _ai_last_resources: Dictionary = {}

# Extended per-rival stats: rival_player_id → stat dict
var _rival_stats: Dictionary = {}       # int → Dictionary
var _rival_last_res: Dictionary = {}    # int → Dictionary

func _init_rival_stats(rival_id: int) -> void:
	_rival_stats[rival_id] = {
		"units_trained": 0, "buildings_built": 0,
		"units_lost": 0,
		"resources": {"food": 0, "wood": 0, "gold": 0, "stone": 0},
	}
	_rival_last_res[rival_id] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.gatherer_changed.connect(_on_gatherer_changed)
	EventBus.technology_researched.connect(_on_technology_researched)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.train_queue_changed.connect(_on_train_queue_changed)
	EventBus.resource_node_selected.connect(_on_resource_node_selected)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	EventBus.age_advance_started.connect(_on_age_advance_started)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_paused.connect(toggle_pause)
	GameManager.game_over.connect(_on_game_over)
	EventBus.camera_follow_cancelled.connect(func() -> void: _set_follow_active(false))
	EventBus.hero_respawned.connect(_on_hero_respawned)
	EventBus.hero_low_hp.connect(_on_hero_low_hp)
	EventBus.garrison_changed.connect(_on_garrison_changed)
	EventBus.market_rate_changed.connect(_on_market_rate_changed)
	EventBus.unit_spawned.connect(_on_stat_unit_spawned)
	EventBus.building_construction_complete.connect(_on_stat_building_complete)
	EventBus.building_construction_complete.connect(_on_building_construction_complete)
	EventBus.unit_died.connect(_on_stat_unit_died)
	ResourceManager.resources_updated.connect(_on_stat_resources_updated)
	_pause_overlay.visible = false
	_clock_label.text = "00:00"
	_unit_name_label.text = ""
	_unit_hp_bar.value = 0.0
	_build_follow_button()
	_build_notifications()
	_build_pause_menu_button()
	_build_idle_villager_button()
	_build_idle_military_button()

	_build_dpad()
	WeatherManager.weather_changed.connect(_on_weather_changed)
	WeatherManager.weather_cleared.connect(hide_weather)

func _on_weather_changed(weather_id: String, _intensity: float) -> void:
	if weather_id != "clear":
		show_weather(weather_id)

func _process(delta: float) -> void:
	_idle_villager_check_timer += delta
	if _idle_villager_check_timer >= 0.5:
		_idle_villager_check_timer = 0.0
		_update_idle_villager_button()
		_update_idle_military_button()
	if _dpad_dir != Vector2.ZERO:
		var world: Node = get_tree().get_nodes_in_group("world").front()
		if world != null:
			var cam: Camera2D = world.get_node_or_null("Camera2D") as Camera2D
			if cam != null:
				cam.position += _dpad_dir * 600.0 * delta
	if _clock_running:
		_elapsed_seconds += delta
		var total_secs: int = int(_elapsed_seconds)
		_clock_label.text = "%02d:%02d" % [total_secs / 60, total_secs % 60]
		_snapshot_timer += delta
		if _snapshot_timer >= SNAPSHOT_INTERVAL:
			_snapshot_timer = 0.0
			_take_snapshot()
	if is_instance_valid(_status_unit):
		_unit_status_label.text = _get_unit_status(_status_unit)
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.value = AgeManager.get_advance_progress(local_player_id) * 100.0
	_update_train_queue_progress()
	if is_instance_valid(_research_bar) and is_instance_valid(_selected_building):
		_research_bar.value = TechManager.get_research_progress(_selected_building) * 100.0
		if TechManager.get_researching_tech(_selected_building) == null:
			if is_instance_valid(_research_bar):
				_research_bar.queue_free()
				_research_bar = null
			if is_instance_valid(_research_label):
				_research_label.queue_free()
				_research_label = null
	if is_instance_valid(_hero_respawn_bar) and is_instance_valid(_selected_building):
		var tc: Variant = _selected_building
		if tc.has_method("get_hero_respawn_fraction"):
			_hero_respawn_bar.value = (tc.get_hero_respawn_fraction() as float) * 100.0
			var secs: int = tc.get_hero_respawn_remaining() as int
			if is_instance_valid(_hero_respawn_label):
				_hero_respawn_label.text = tr("UI_HERO_RESPAWNING") % secs if secs > 0 else tr("UI_HERO_READY")
	# Update hero ability button cooldown in real time
	if is_instance_valid(_selected_unit) and _selected_unit is HeroUnit:
		var hero: HeroUnit = _selected_unit as HeroUnit
		var udata: UnitResource = hero.unit_data
		if udata != null and not udata.hero_ability_id.is_empty():
			for child: Node in _action_grid.get_children():
				if not (child is ActionButton):
					continue
				var btn: ActionButton = child as ActionButton
				if btn.action_id != "hero_ability":
					continue
				var cd_frac: float = hero.get_cooldown_fraction()
				var ability_name: String = tr("HERO_%s_ABILITY" % udata.hero_ability_id.to_upper())
				var key_hint: String = "[Q] "
				if cd_frac <= 0.0:
					btn.text = key_hint + ability_name + "\n" + tr("HERO_ABILITY_READY")
					btn.modulate = Color(1.0, 1.0, 1.0)
				else:
					var cd_secs: int = int(udata.hero_ability_cooldown * cd_frac)
					btn.text = key_hint + ability_name + "\n" + tr("HERO_ABILITY_COOLDOWN") % cd_secs
					btn.modulate = Color(0.65, 0.65, 0.65)
	_update_weather_pill()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		if is_instance_valid(_pause_menu):
			_close_pause_menu()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _active_actions.is_empty():
		return
	for entry: Variant in _active_actions:
		var data: Dictionary = entry as Dictionary
		var mapped: int = data.get("key", -1) as int
		if mapped == key.keycode or mapped == key.physical_keycode:
			_on_action_button_pressed(data["id"] as String)
			get_viewport().set_input_as_handled()
			return

func update_resources(player_id: int, resources: Dictionary) -> void:
	if player_id != local_player_id:
		return
	_food_display.set_amount(int(resources.get("food", 0)))
	_wood_display.set_amount(int(resources.get("wood", 0)))
	_gold_display.set_amount(int(resources.get("gold", 0)))
	_stone_display.set_amount(int(resources.get("stone", 0)))

func update_selection(units: Array) -> void:
	cancel_pending()
	for child: Node in _unit_portraits_grid.get_children():
		child.queue_free()
	_clear_action_buttons()
	_in_build_menu = false

	if units.is_empty():
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		_unit_status_label.text = ""
		_status_unit = null
		return

	var capped: Array = units.slice(0, 40)
	for unit: Variant in capped:
		if not is_instance_valid(unit):
			continue
		var portrait: UnitPortrait = UnitPortrait.new()
		_unit_portraits_grid.add_child(portrait)
		portrait.setup(unit)

	var first: Node = capped[0]
	if is_instance_valid(first):
		var display_name: String = tr("UI_UNIT")
		var unit_data: Variant = first.get("unit_data")
		if unit_data != null:
			var name_val: Variant = (unit_data as Resource).get("display_name")
			if name_val != null:
				display_name = name_val as String
		elif first is Animal:
			var aname: Variant = first.get("animal_name")
			display_name = aname as String if aname != null else tr("UI_ANIMAL")
		_unit_name_label.text = display_name

		var hp_variant: Variant = first.get("health")
		var hp: float = hp_variant as float if hp_variant != null else 100.0
		var max_hp: float = 100.0
		if unit_data != null:
			var max_hp_v: Variant = (unit_data as Resource).get("max_health")
			if max_hp_v != null:
				max_hp = max_hp_v as float
		elif first is Animal:
			var mhp: Variant = first.get("max_health")
			if mhp != null:
				max_hp = mhp as float
		if max_hp > 0.0:
			_unit_hp_bar.value = (hp / max_hp) * 100.0

		_status_unit = first if (first.has_method("order_gather") or first is FishingBoat) else null

		if first is Animal:
			var astate: Variant = first.get("current_state")
			var owned: bool = astate != null and (astate as int) == Animal.AnimalState.OWNED
			_unit_status_label.text = tr("UI_STATUS_YOURS") if owned else tr("UI_STATUS_WILD")
			_populate_buttons(ANIMAL_ACTIONS if owned else [])
		elif first is HeroUnit:
			_populate_hero_buttons(first as HeroUnit)
		elif first is TransportShip:
			_populate_transport_buttons(first as TransportShip)
		elif first is Trebuchet:
			_populate_trebuchet_buttons(first as Trebuchet)
		elif first is Scout:
			_populate_scout_buttons(first as Scout)
		elif first.has_method("order_gather"):
			_populate_buttons(VILLAGER_ACTIONS)
			_apply_tutorial_villager_gates()
		else:
			_populate_buttons(UNIT_ACTIONS)

func update_age(age: int) -> void:
	_age_label.text = tr(["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"][clampi(age, 0, 3)])

func toggle_pause(is_paused: bool) -> void:
	_pause_overlay.visible = is_paused

# --- Private ---

func _clear_action_buttons() -> void:
	_active_actions = []
	_action_page = 0
	for child: Node in _action_grid.get_children():
		child.queue_free()
	for child: Node in _train_queue_row.get_children():
		child.queue_free()
	if is_instance_valid(_page_prev_btn):
		_page_prev_btn.queue_free()
		_page_prev_btn = null
	if is_instance_valid(_page_next_btn):
		_page_next_btn.queue_free()
		_page_next_btn = null
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.queue_free()
		_age_advance_bar = null
	if is_instance_valid(_hero_respawn_bar):
		_hero_respawn_bar.queue_free()
		_hero_respawn_bar = null
	if is_instance_valid(_hero_respawn_label):
		_hero_respawn_label.queue_free()
		_hero_respawn_label = null
	if is_instance_valid(_research_bar):
		_research_bar.queue_free()
		_research_bar = null
	if is_instance_valid(_research_label):
		_research_label.queue_free()
		_research_label = null

func _key_label(keycode: int) -> String:
	match keycode:
		KEY_DELETE: return "Del"
		KEY_ESCAPE: return "Esc"
		_: return char(keycode)

func _populate_buttons(actions: Array) -> void:
	_clear_action_buttons()
	_active_actions = actions
	_action_grid.columns = ACTION_COLS
	_render_action_page()

func _render_action_page() -> void:
	for child: Node in _action_grid.get_children():
		child.queue_free()
	if is_instance_valid(_page_prev_btn):
		_page_prev_btn.queue_free()
		_page_prev_btn = null
	if is_instance_valid(_page_next_btn):
		_page_next_btn.queue_free()
		_page_next_btn = null

	var total: int = _active_actions.size()
	var needs_paging: bool = total > PAGE_SIZE
	# Reserve last 2 slots on the last row for pagination buttons when needed
	var slots: int = PAGE_SIZE - (2 if needs_paging else 0)
	var start: int = _action_page * slots
	var page_actions: Array = _active_actions.slice(start, start + slots)

	for entry: Variant in page_actions:
		var data: Dictionary = entry as Dictionary
		var btn: ActionButton = ActionButton.new()
		btn.custom_minimum_size = Vector2(64.0, 56.0)
		btn.action_id = data["id"] as String
		var key_int: int = data.get("key", -1) as int
		var key_hint: String = ("[%s] " % _key_label(key_int)) if key_int > 0 else ""
		var raw: bool = data.get("raw_label", false) as bool
		var translated_label: String = (data["label"] as String) if raw else tr(data["label"] as String)
		btn.text = key_hint + translated_label
		var color: Color = data["color"] as Color
		var cost: Dictionary = data.get("cost", {}) as Dictionary
		btn.set_meta("cost", cost)
		btn.set_meta("base_color", color)
		btn.set_meta("base_label", translated_label)
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(local_player_id, cost)
		var locked: bool = (data.get("locked", false) as bool) \
			or (btn.action_id == "destroy" and _tutorial_gates_active)
		var enabled: bool = can_pay and not locked
		var effective_color: Color = color if enabled else Color(0.25, 0.25, 0.25)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = effective_color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		var is_upgrade: bool = data.get("is_upgrade", false) as bool
		btn.set_meta("is_upgrade", is_upgrade)
		if is_upgrade:
			style.border_color = Color(0.85, 0.72, 0.10)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		btn.add_theme_stylebox_override("normal", style)
		var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		hover_style.bg_color = effective_color.lightened(0.25)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.disabled = not enabled
		var desc: String = data.get("description", "") as String
		if not desc.is_empty():
			btn.tooltip_text = tr(desc)
		btn.action_pressed.connect(_on_action_button_pressed)
		_action_grid.add_child(btn)

	if needs_paging:
		# Pad so ◀ ▶ always land on the last two slots of the grid (positions 8 and 9)
		var filled: int = page_actions.size()
		var spacers_needed: int = slots - filled
		for _i: int in range(maxi(0, spacers_needed)):
			var spacer: Control = Control.new()
			spacer.custom_minimum_size = Vector2(64.0, 56.0)
			_action_grid.add_child(spacer)

		var max_page: int = ceili(float(total) / float(slots)) - 1
		_page_prev_btn = _make_page_btn("◀")
		_page_prev_btn.disabled = _action_page <= 0
		_page_prev_btn.pressed.connect(func() -> void:
			_action_page = maxi(0, _action_page - 1)
			_render_action_page()
			_refresh_button_states())
		_action_grid.add_child(_page_prev_btn)

		_page_next_btn = _make_page_btn("▶")
		_page_next_btn.disabled = _action_page >= max_page
		_page_next_btn.pressed.connect(func() -> void:
			_action_page = mini(_action_page + 1, max_page)
			_render_action_page()
			_refresh_button_states())
		_action_grid.add_child(_page_next_btn)

func _make_page_btn(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(64.0, 56.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.20, 0.28, 0.95)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)
	var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.30, 0.30, 0.40, 0.95)
	btn.add_theme_stylebox_override("hover", hover_style)
	return btn

func _get_queue_size() -> int:
	if not is_instance_valid(_selected_building):
		return 0
	if _selected_building.has_method("get_queue"):
		return (_selected_building.get_queue() as Array).size()
	return 0

func _get_max_queue() -> int:
	if not is_instance_valid(_selected_building):
		return 0
	if _selected_building.has_method("get_max_queue"):
		return _selected_building.get_max_queue() as int
	return 0

func _refresh_button_states() -> void:
	var queue_size: int = _get_queue_size()
	var max_queue: int = _get_max_queue()
	var queue_full: bool = max_queue > 0 and queue_size >= max_queue
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var cost: Dictionary = btn.get_meta("cost", {}) as Dictionary
		var base_color: Color = btn.get_meta("base_color", Color(0.3, 0.3, 0.3)) as Color
		var is_train: bool = btn.action_id.begins_with("train:")
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(local_player_id, cost)
		var enabled: bool = can_pay and (not is_train or not queue_full)
		btn.disabled = not enabled
		var effective_color: Color = base_color if enabled else Color(0.25, 0.25, 0.25)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = effective_color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		if btn.get_meta("is_upgrade", false) as bool:
			style.border_color = Color(0.85, 0.72, 0.10)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		btn.add_theme_stylebox_override("normal", style)
		var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		hover_style.bg_color = effective_color.lightened(0.25)
		btn.add_theme_stylebox_override("hover", hover_style)

func _on_action_button_pressed(action_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if child is ActionButton and (child as ActionButton).action_id == action_id:
			var cost: Dictionary = (child as ActionButton).get_meta("cost", {}) as Dictionary
			if not cost.is_empty() and not ResourceManager.can_afford(local_player_id, cost):
				AudioManager.play("ui_error")
				return
			break
	if action_id == "build_menu":
		AudioManager.play("ui_click")
		_in_build_menu = true
		_populate_buttons(_filtered_build_actions())
		return
	if action_id == "back":
		AudioManager.play("ui_click")
		_in_build_menu = false
		_populate_buttons(VILLAGER_ACTIONS)
		_apply_tutorial_villager_gates()
		return
	# Actions that wait for a map click before executing
	if action_id == "move_to" or action_id == "attack_move":
		AudioManager.play("ui_click")
		_set_pending_action(action_id)
		return
	if action_id.begins_with("train:"):
		AudioManager.play("train_queue")
	elif action_id == "advance_age":
		AudioManager.play("age_advance")
		_disable_action_button("advance_age")
	elif action_id.begins_with("research:"):
		AudioManager.play("ui_click")
	elif action_id.begins_with("market:"):
		AudioManager.play("ui_click")
	else:
		AudioManager.play("ui_click")
	action_requested.emit(action_id)

func _set_pending_action(action_id: String) -> void:
	_pending_action = action_id
	_highlight_pending_button(action_id)
	pending_action_started.emit(action_id)

func cancel_pending() -> void:
	if _pending_action.is_empty():
		return
	_pending_action = ""
	_highlight_pending_button("")
	pending_action_cancelled.emit()

func _disable_action_button(target_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id == target_id:
			btn.disabled = true
			var grey: StyleBoxFlat = StyleBoxFlat.new()
			grey.bg_color = Color(0.25, 0.25, 0.25)
			grey.corner_radius_top_left = 4
			grey.corner_radius_top_right = 4
			grey.corner_radius_bottom_left = 4
			grey.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", grey)
			btn.add_theme_stylebox_override("hover", grey)
			break

func _highlight_pending_button(active_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var base_color: Color = btn.get_meta("base_color", Color(0.3, 0.3, 0.3)) as Color
		var is_active: bool = btn.action_id == active_id and not active_id.is_empty()
		var effective_color: Color = base_color.lightened(0.45) if is_active else base_color
		if btn.disabled:
			effective_color = Color(0.25, 0.25, 0.25)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = effective_color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", style)
		var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		hover_style.bg_color = effective_color.lightened(0.25)
		btn.add_theme_stylebox_override("hover", hover_style)

func _on_game_started() -> void:
	_elapsed_seconds = 0.0
	_clock_running = true
	update_age(AgeManager.get_age(local_player_id))
	var starting: Dictionary = ResourceManager.get_resources(local_player_id)
	update_resources(local_player_id, starting)
	_last_resources = starting.duplicate()
	for rival_id: int in MatchConfig.get_rival_player_ids():
		_init_rival_stats(rival_id)
		_snap_pop_rivals[rival_id]          = []
		_snap_res_rivals[rival_id]          = []
		_snap_age_rivals[rival_id]          = []
		_snap_kills_rivals[rival_id]        = []
		_snap_kills_rivals_prev[rival_id]   = 0
		_offense_snaps_rivals[rival_id]     = []
	if MatchConfig.launch_tutorial:
		MatchConfig.launch_tutorial = false
		call_deferred("_start_tutorial")

func _on_resource_changed(player_id: int, resource: String, amount: int) -> void:
	if player_id != local_player_id:
		return
	match resource:
		"food":  _food_display.set_amount(amount)
		"wood":  _wood_display.set_amount(amount)
		"gold":  _gold_display.set_amount(amount)
		"stone": _stone_display.set_amount(amount)
	_refresh_button_states()

func _on_gatherer_changed(player_id: int, resource: String, delta: int) -> void:
	if player_id != local_player_id:
		return
	if not _gatherer_counts.has(resource):
		return
	_gatherer_counts[resource] = maxi(0, (_gatherer_counts[resource] as int) + delta)
	var count: int = _gatherer_counts[resource] as int
	match resource:
		"food":  _food_display.set_gatherer_count(count)
		"wood":  _wood_display.set_gatherer_count(count)
		"gold":  _gold_display.set_gatherer_count(count)
		"stone": _stone_display.set_gatherer_count(count)

func _on_technology_researched(player_id: int, _tech_id: String) -> void:
	if player_id != local_player_id:
		return
	if not is_instance_valid(_selected_building):
		return
	if _selected_building is Barracks:
		_populate_barracks_actions(_selected_building as Barracks)
	elif _selected_building is ArcheryRange:
		_populate_archery_range_actions(_selected_building as ArcheryRange)
	elif _selected_building is Stable:
		_populate_stable_actions(_selected_building as Stable)
	elif _selected_building is Blacksmith:
		_populate_blacksmith_actions(_selected_building as Blacksmith)
	elif _selected_building is University:
		_populate_research_only_actions(_selected_building, TechnologyResource.ResearchBuilding.UNIVERSITY)
	elif _selected_building is Temple:
		_populate_research_only_actions(_selected_building, TechnologyResource.ResearchBuilding.MONASTERY)

func _on_unit_selected(units: Array) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null
	_selected_unit = units[0] if units.size() == 1 else null
	_set_follow_active(false)
	update_selection(units)
	if is_instance_valid(_follow_btn):
		_follow_btn.visible = not units.is_empty()
	if not units.is_empty():
		var lead: Node = units[0] as Node
		var sound: String = "select_generic"
		if lead.has_method("get_selection_sound"):
			sound = lead.call("get_selection_sound") as String
		AudioManager.play(sound, -4.0)

func _on_building_selected(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = building
	if is_instance_valid(building) and building.has_method("set_selected"):
		building.set_selected(true)
	_set_follow_active(false)
	if is_instance_valid(_follow_btn):
		_follow_btn.visible = false
	for child: Node in _unit_portraits_grid.get_children():
		child.queue_free()
	_clear_action_buttons()
	_in_build_menu = false

	_status_unit = null
	if not is_instance_valid(building):
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		_unit_status_label.text = ""
		return

	var display_name: String = tr("UI_BUILDING")
	var bdata: Variant = building.get("building_data")
	if bdata != null:
		var dname: Variant = (bdata as Resource).get("display_name")
		if dname != null:
			display_name = dname as String
	_unit_name_label.text = display_name

	var hp_v: Variant = building.get("health")
	var hp: float = hp_v as float if hp_v != null else 0.0
	var max_hp: float = 0.0
	if bdata != null:
		var mhp_v: Variant = (bdata as Resource).get("max_health")
		if mhp_v != null:
			max_hp = mhp_v as float
	if max_hp <= 0.0:
		var mhp_direct: Variant = building.get("max_health")
		if mhp_direct != null:
			max_hp = mhp_direct as float
	if max_hp > 0.0:
		_unit_hp_bar.value = (hp / max_hp) * 100.0

	var bpid: Variant = building.get("player_id")
	if bpid != null and (bpid as int) != 0:
		return

	var bstate: Variant = building.get("state")
	if bstate != null and (bstate as int) != BuildingBase.BuildingState.COMPLETE:
		_populate_buttons([DESTROY_ACTION])
		return

	if building.has_method("is_respawning_hero") or building is TownCenterBuildable:
		_unit_name_label.text = tr("UI_TOWN_CENTER")
		var tc_hp: Variant = building.get("health")
		var tc_max: Variant = building.get("max_health")
		if tc_hp != null and tc_max != null and (tc_max as float) > 0.0:
			_unit_hp_bar.value = ((tc_hp as float) / (tc_max as float)) * 100.0
		_populate_tc_actions()
		if building.has_method("get_queue"):
			_on_train_queue_changed(building, building.get_queue() as Array, building.get_max_queue() as int)
	elif building is Blacksmith:
		_populate_blacksmith_actions(building as Blacksmith)
	elif building is Stable:
		_populate_stable_actions(building as Stable)
		var st: Stable = building as Stable
		_on_train_queue_changed(building, st.get_queue(), st.get_max_queue())
	elif building is University:
		_populate_research_only_actions(building, TechnologyResource.ResearchBuilding.UNIVERSITY)
	elif building is Market:
		_populate_market_actions(building as Market)
	elif building is Temple:
		_populate_research_only_actions(building, TechnologyResource.ResearchBuilding.MONASTERY)
	elif building is Barracks:
		_populate_barracks_actions(building as Barracks)
		var br: Barracks = building as Barracks
		_on_train_queue_changed(building, br.get_queue(), br.get_max_queue())
	elif building is ArcheryRange:
		_populate_archery_range_actions(building as ArcheryRange)
		var ar: ArcheryRange = building as ArcheryRange
		_on_train_queue_changed(building, ar.get_queue(), ar.get_max_queue())
	elif building is Dock:
		_populate_dock_actions(building as Dock)
		var dk: Dock = building as Dock
		_on_train_queue_changed(building, dk.get_queue(), dk.get_max_queue())
	elif building is SiegeWorkshop:
		_populate_siege_workshop_actions(building as SiegeWorkshop)
		var sw: SiegeWorkshop = building as SiegeWorkshop
		_on_train_queue_changed(building, sw.get_queue(), sw.get_max_queue())
	elif building is Gate:
		var gate: Gate = building as Gate
		_populate_buttons(GATE_ACTIONS)
		_refresh_gate_toggle_label(gate)
		_unit_status_label.text = tr("UI_GATE_LOCKED") if gate.locked else (tr("UI_GATE_OPEN") if gate.is_open else tr("UI_GATE_CLOSED"))
		if not gate.gate_toggled.is_connected(_on_gate_toggled):
			gate.gate_toggled.connect(_on_gate_toggled)
	else:
		_populate_buttons(BUILDING_ACTIONS)

func _on_gate_toggled(_is_open: bool) -> void:
	if is_instance_valid(_selected_building) and _selected_building is Gate:
		var gate: Gate = _selected_building as Gate
		_refresh_gate_toggle_label(gate)
		_unit_status_label.text = tr("UI_GATE_LOCKED") if gate.locked else (tr("UI_GATE_OPEN") if gate.is_open else tr("UI_GATE_CLOSED"))

func _refresh_gate_toggle_label(gate: Gate) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id != "gate_lock":
			continue
		btn.text = "[O] " + (tr("UI_GATE_UNLOCK") if gate.locked else tr("UI_GATE_LOCK"))

func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id != local_player_id:
		return
	_population_label.text = tr("UI_POP") % [current, cap]
	if current >= cap:
		_population_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
		var tw: Tween = create_tween()
		tw.tween_property(_population_label, "modulate:a", 0.3, 0.25)
		tw.tween_property(_population_label, "modulate:a", 1.0, 0.25)
		tw.tween_property(_population_label, "modulate:a", 0.3, 0.25)
		tw.tween_property(_population_label, "modulate:a", 1.0, 0.25)
	else:
		_population_label.remove_theme_color_override("font_color")
	# Refresh queue display so the blocked indicator updates when pop frees up
	if is_instance_valid(_selected_building) and _selected_building.has_method("get_queue"):
		_on_train_queue_changed(_selected_building,
			_selected_building.get_queue() as Array,
			_selected_building.get_max_queue() as int)

func _on_age_advance_started(player_id: int, _target_age: int) -> void:
	if player_id != local_player_id:
		return
	# If TC is selected, refresh buttons to replace advance button with progress bar
	if is_instance_valid(_selected_building) and _selected_building.has_method("is_respawning_hero"):
		_populate_tc_actions()

func _on_age_advance_complete(player_id: int, new_age: int) -> void:
	if player_id != local_player_id:
		return
	update_age(new_age)
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.queue_free()
		_age_advance_bar = null
	# Refresh TC or barracks actions to show newly unlocked units
	if is_instance_valid(_selected_building):
		if is_instance_valid(_selected_building) and _selected_building.has_method("is_respawning_hero"):
			_populate_tc_actions()
		elif _selected_building is Blacksmith:
			_populate_blacksmith_actions(_selected_building as Blacksmith)
		elif _selected_building is Stable:
			_populate_stable_actions(_selected_building as Stable)
		elif _selected_building is University:
			_populate_research_only_actions(_selected_building, TechnologyResource.ResearchBuilding.UNIVERSITY)
		elif _selected_building is Temple:
			_populate_research_only_actions(_selected_building, TechnologyResource.ResearchBuilding.MONASTERY)
		elif _selected_building is Barracks:
			_populate_barracks_actions(_selected_building as Barracks)
		elif _selected_building is ArcheryRange:
			_populate_archery_range_actions(_selected_building as ArcheryRange)
		elif _selected_building is Dock:
			_populate_dock_actions(_selected_building as Dock)
		elif _selected_building is SiegeWorkshop:
			_populate_siege_workshop_actions(_selected_building as SiegeWorkshop)

func _populate_hero_buttons(hero: HeroUnit) -> void:
	_clear_action_buttons()
	var actions: Array = [
		{"id": "move_to",     "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
		{"id": "attack_move", "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
		{"id": "stop",        "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
		DESTROY_ACTION,
	]
	var udata: UnitResource = hero.unit_data
	if udata != null and not udata.hero_ability_id.is_empty():
		var cd_frac: float = hero.get_cooldown_fraction()
		var cd_secs: int = int(udata.hero_ability_cooldown * cd_frac)
		var ability_name: String = tr("HERO_%s_ABILITY" % udata.hero_ability_id.to_upper())
		var status: String = tr("HERO_ABILITY_READY") if cd_frac <= 0.0 else tr("HERO_ABILITY_COOLDOWN") % cd_secs
		actions.insert(0, {
			"id": "hero_ability",
			"label": ability_name + "\n" + status,
			"color": Color(0.55, 0.20, 0.55) if cd_frac <= 0.0 else Color(0.25, 0.25, 0.30),
			"cost": {},
			"key": KEY_Q,
			"raw_label": true,
			"description": udata.hero_ability_description,
		})
	_populate_buttons(actions)

func _populate_transport_buttons(ship: TransportShip) -> void:
	var garrison: Array = ship.get_garrison()
	var cap: int = ship.get_capacity()

	# Fill portrait grid with garrisoned units; each portrait is clickable to unload that unit.
	for child: Node in _unit_portraits_grid.get_children():
		child.queue_free()
	for i: int in range(garrison.size()):
		var garrisoned: Node = garrison[i] as Node
		var portrait: UnitPortrait = UnitPortrait.new()
		_unit_portraits_grid.add_child(portrait)
		portrait.setup(garrisoned)
		var idx: int = i
		portrait.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					action_requested.emit("unload_unit:%d" % idx)
		)

	var actions: Array = []
	if not garrison.is_empty():
		actions.append({
			"id": "unload",
			"label": tr("UI_UNLOAD") + " (%d/%d)" % [garrison.size(), cap],
			"color": Color(0.20, 0.45, 0.65),
			"cost": {},
			"key": KEY_U,
			"raw_label": true,
		})
	actions.append({"id": "stop", "label": "ACTION_STOP", "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_unit_status_label.text = tr("UI_GARRISON_STATUS") % [garrison.size(), cap]

func _on_garrison_changed(ship: Node, _current: int, _capacity: int) -> void:
	if is_instance_valid(_selected_unit) and _selected_unit == ship:
		_populate_transport_buttons(ship as TransportShip)

func _populate_tc_actions() -> void:
	var current_age: int = AgeManager.get_age(local_player_id)
	var actions: Array = TOWN_CENTER_ACTIONS.duplicate()

	var is_tutorial: bool = _tutorial_gates_active
	if current_age < GameManager.Age.IMPERIAL:
		var advancing: bool = AgeManager.is_advancing(local_player_id)
		var next_age: int = current_age + 1
		var costs: Dictionary = AgeManager.ADVANCE_COSTS[next_age]
		var cost_str: String = ""
		for k: Variant in costs:
			cost_str += "\n%d%s" % [(costs[k] as int), (k as String).substr(0, 1).to_upper()]
		var advance_color: Color
		match next_age:
			1: advance_color = Color(0.65, 0.55, 0.20)
			2: advance_color = Color(0.25, 0.40, 0.65)
			_: advance_color = Color(0.55, 0.20, 0.55)
		const AGE_NAME_KEYS: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]
		actions.append({
			"id": "advance_age",
			"label": tr("UI_ADVANCE") + " " + tr(AGE_NAME_KEYS[next_age]) + "\n" + cost_str.strip_edges(),
			"color": advance_color,
			"cost": costs,
			"key": KEY_E,
			"raw_label": true,
			"locked": advancing or (is_tutorial and _tutorial_step < 7),
		})

	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)

	if AgeManager.is_advancing(local_player_id):
		_build_age_advance_bar()

	if is_instance_valid(_selected_building) and _selected_building.has_method("is_respawning_hero"):
		if _selected_building.is_respawning_hero() as bool:
			_build_hero_respawn_bar()

func _populate_barracks_actions(barracks: Barracks) -> void:
	var actions: Array = []
	for def: Dictionary in barracks.get_available_units():
		var uid: String = def["id"] as String
		var data: UnitResource = load(def["data"] as String) as UnitResource
		var cost_parts: Array[String] = []
		if data.cost_food  > 0: cost_parts.append("%dF" % data.cost_food)
		if data.cost_wood  > 0: cost_parts.append("%dW" % data.cost_wood)
		if data.cost_gold  > 0: cost_parts.append("%dG" % data.cost_gold)
		var cost_label: String = " ".join(PackedStringArray(cost_parts))
		var costs: Dictionary = {}
		if data.cost_food  > 0: costs["food"] = data.cost_food
		if data.cost_wood  > 0: costs["wood"] = data.cost_wood
		if data.cost_gold  > 0: costs["gold"] = data.cost_gold
		actions.append({
			"id": "train:" + uid,
			"label": data.display_name + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": _barracks_key_for(uid),
		})
	var techs: Array[TechnologyResource] = TechManager.get_available_techs(local_player_id, TechnologyResource.ResearchBuilding.BARRACKS)
	for tech: TechnologyResource in techs:
		var cost_str: String = ""
		if tech.cost_food > 0: cost_str += "\n%dF" % tech.cost_food
		if tech.cost_wood > 0: cost_str += "\n%dW" % tech.cost_wood
		if tech.cost_gold > 0: cost_str += "\n%dG" % tech.cost_gold
		var tech_costs: Dictionary = {}
		if tech.cost_food > 0: tech_costs["food"] = tech.cost_food
		if tech.cost_wood > 0: tech_costs["wood"] = tech.cost_wood
		if tech.cost_gold > 0: tech_costs["gold"] = tech.cost_gold
		var is_upgrade: bool = tech.upgrade_from_unit_id != ""
		actions.append({
			"id": "research:%s" % tech.id,
			"label": ("▲ " if is_upgrade else "") + tech.display_name + cost_str,
			"color": Color(0.45, 0.32, 0.10) if is_upgrade else Color(0.25, 0.45, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
			"is_upgrade": is_upgrade,
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_build_research_bar(barracks)

func _populate_archery_range_actions(archery_range: ArcheryRange) -> void:
	var actions: Array = []
	for def: Dictionary in archery_range.get_available_units():
		var uid: String = def["id"] as String
		var data: UnitResource = load(def["data"] as String) as UnitResource
		var cost_parts: Array[String] = []
		if data.cost_food  > 0: cost_parts.append("%dF" % data.cost_food)
		if data.cost_wood  > 0: cost_parts.append("%dW" % data.cost_wood)
		if data.cost_gold  > 0: cost_parts.append("%dG" % data.cost_gold)
		var cost_label: String = " ".join(PackedStringArray(cost_parts))
		var costs: Dictionary = {}
		if data.cost_food  > 0: costs["food"] = data.cost_food
		if data.cost_wood  > 0: costs["wood"] = data.cost_wood
		if data.cost_gold  > 0: costs["gold"] = data.cost_gold
		actions.append({
			"id": "train:" + uid,
			"label": data.display_name + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": _archery_range_key_for(uid),
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_build_research_bar(archery_range)

func _archery_range_key_for(uid: String) -> Key:
	var key_map: Dictionary = {
		"archer":        KEY_R,
		"ravine_archer": KEY_U,
		"longbowman":    KEY_U,
	}
	return key_map.get(uid, KEY_NONE) as Key

func _barracks_key_for(uid: String) -> Key:
	var key_map: Dictionary = {
		"militia": KEY_M,
		"archer": KEY_R,
		"pikeman": KEY_P,
		"menceyes_guard": KEY_U,
		"ravine_archer": KEY_U,
		"longbowman": KEY_U,
		"conquistador": KEY_U,
		"tidecaller": KEY_U,
	}
	return key_map.get(uid, KEY_NONE) as Key

func _populate_blacksmith_actions(blacksmith: Blacksmith) -> void:
	var actions: Array = []
	var active_tech: TechnologyResource = TechManager.get_researching_tech(blacksmith)
	var techs: Array[TechnologyResource] = TechManager.get_available_techs(local_player_id, TechnologyResource.ResearchBuilding.BLACKSMITH)
	for tech: TechnologyResource in techs:
		var cost_str: String = ""
		if tech.cost_food > 0: cost_str += "\n%dF" % tech.cost_food
		if tech.cost_wood > 0: cost_str += "\n%dW" % tech.cost_wood
		if tech.cost_gold > 0: cost_str += "\n%dG" % tech.cost_gold
		var tech_costs: Dictionary = {}
		if tech.cost_food > 0: tech_costs["food"] = tech.cost_food
		if tech.cost_wood > 0: tech_costs["wood"] = tech.cost_wood
		if tech.cost_gold > 0: tech_costs["gold"] = tech.cost_gold
		var is_active: bool = active_tech != null and active_tech.id == tech.id
		actions.append({
			"id": "research:%s" % tech.id,
			"label": tech.display_name + cost_str,
			"color": Color(0.25, 0.45, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
			"locked": is_active,
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_build_research_bar(blacksmith)

func _populate_stable_actions(stable: Stable) -> void:
	var actions: Array = []
	for def: Dictionary in stable.get_available_units():
		var uid: String = def["id"] as String
		var data: UnitResource = load(def["data"] as String) as UnitResource
		var cost_parts: Array[String] = []
		if data.cost_food  > 0: cost_parts.append("%dF" % data.cost_food)
		if data.cost_wood  > 0: cost_parts.append("%dW" % data.cost_wood)
		if data.cost_gold  > 0: cost_parts.append("%dG" % data.cost_gold)
		var cost_label: String = " ".join(PackedStringArray(cost_parts))
		var costs: Dictionary = {}
		if data.cost_food  > 0: costs["food"] = data.cost_food
		if data.cost_wood  > 0: costs["wood"] = data.cost_wood
		if data.cost_gold  > 0: costs["gold"] = data.cost_gold
		var key_map: Dictionary = {"heavy_scout": KEY_H, "knight": KEY_K, "sand_raider": KEY_U, "chevalier_normand": KEY_U}
		actions.append({
			"id": "train:" + uid,
			"label": data.display_name + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": key_map.get(uid, KEY_NONE) as Key,
		})
	var techs: Array[TechnologyResource] = TechManager.get_available_techs(local_player_id, TechnologyResource.ResearchBuilding.STABLE)
	for tech: TechnologyResource in techs:
		var cost_str: String = ""
		if tech.cost_food > 0: cost_str += "\n%dF" % tech.cost_food
		if tech.cost_wood > 0: cost_str += "\n%dW" % tech.cost_wood
		if tech.cost_gold > 0: cost_str += "\n%dG" % tech.cost_gold
		var tech_costs: Dictionary = {}
		if tech.cost_food > 0: tech_costs["food"] = tech.cost_food
		if tech.cost_wood > 0: tech_costs["wood"] = tech.cost_wood
		if tech.cost_gold > 0: tech_costs["gold"] = tech.cost_gold
		var is_upgrade: bool = tech.upgrade_from_unit_id != ""
		actions.append({
			"id": "research:%s" % tech.id,
			"label": ("▲ " if is_upgrade else "") + tech.display_name + cost_str,
			"color": Color(0.45, 0.32, 0.10) if is_upgrade else Color(0.25, 0.45, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
			"is_upgrade": is_upgrade,
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_build_research_bar(stable)

func _populate_research_only_actions(building: Node, research_type: TechnologyResource.ResearchBuilding) -> void:
	var actions: Array = []
	var active_tech: TechnologyResource = TechManager.get_researching_tech(building)
	var techs: Array[TechnologyResource] = TechManager.get_available_techs(local_player_id, research_type)
	for tech: TechnologyResource in techs:
		var cost_str: String = ""
		if tech.cost_food > 0: cost_str += "\n%dF" % tech.cost_food
		if tech.cost_wood > 0: cost_str += "\n%dW" % tech.cost_wood
		if tech.cost_gold > 0: cost_str += "\n%dG" % tech.cost_gold
		var tech_costs: Dictionary = {}
		if tech.cost_food > 0: tech_costs["food"] = tech.cost_food
		if tech.cost_wood > 0: tech_costs["wood"] = tech.cost_wood
		if tech.cost_gold > 0: tech_costs["gold"] = tech.cost_gold
		var is_active: bool = active_tech != null and active_tech.id == tech.id
		actions.append({
			"id": "research:%s" % tech.id,
			"label": tech.display_name + cost_str,
			"color": Color(0.25, 0.42, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
			"locked": is_active,
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_build_research_bar(building)

func _populate_market_actions(market: Market) -> void:
	var sr_f: int = market.get_sell_rate(local_player_id, "food")
	var sr_w: int = market.get_sell_rate(local_player_id, "wood")
	var sr_s: int = market.get_sell_rate(local_player_id, "stone")
	var br_f: int = market.get_buy_rate(local_player_id, "food")
	var br_w: int = market.get_buy_rate(local_player_id, "wood")
	var br_s: int = market.get_buy_rate(local_player_id, "stone")
	var actions: Array = [
		{"id": "market:sell:food",  "label": "Sell Food\n(%d→1G)" % sr_f,  "color": Color(0.60, 0.30, 0.15), "cost": {"food":  sr_f}, "key": KEY_NONE, "raw_label": true},
		{"id": "market:sell:wood",  "label": "Sell Wood\n(%d→1G)" % sr_w,  "color": Color(0.30, 0.55, 0.20), "cost": {"wood":  sr_w}, "key": KEY_NONE, "raw_label": true},
		{"id": "market:sell:stone", "label": "Sell Stone\n(%d→1G)" % sr_s, "color": Color(0.55, 0.55, 0.55), "cost": {"stone": sr_s}, "key": KEY_NONE, "raw_label": true},
		{"id": "market:buy:food",   "label": "Buy Food\n(1G→%d)" % br_f,   "color": Color(0.65, 0.20, 0.10), "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true},
		{"id": "market:buy:wood",   "label": "Buy Wood\n(1G→%d)" % br_w,   "color": Color(0.20, 0.45, 0.15), "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true},
		{"id": "market:buy:stone",  "label": "Buy Stone\n(1G→%d)" % br_s,  "color": Color(0.45, 0.45, 0.45), "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true},
		DESTROY_ACTION,
	]
	_populate_buttons(actions)

func _on_market_rate_changed(pid: int, market: Market) -> void:
	if pid != local_player_id:
		return
	if not (is_instance_valid(_selected_building) and _selected_building == market):
		return
	_populate_market_actions(market)

func _populate_dock_actions(dock: Dock) -> void:
	var current_age: int = AgeManager.get_age(local_player_id)
	var actions: Array = []
	for def: Dictionary in DOCK_UNIT_DEFS:
		if (def["age"] as int) > current_age:
			continue
		var uid: String = def["id"] as String
		var costs: Dictionary = def["cost"] as Dictionary
		var cost_parts: Array[String] = []
		if costs.get("food", 0) > 0: cost_parts.append("%dF" % costs["food"])
		if costs.get("wood", 0) > 0: cost_parts.append("%dW" % costs["wood"])
		if costs.get("gold", 0) > 0: cost_parts.append("%dG" % costs["gold"])
		var cost_label: String = " ".join(PackedStringArray(cost_parts))
		var key_map: Dictionary = {"fishing_boat": KEY_F, "transport_ship": KEY_T, "war_galley": KEY_G, "trireme": KEY_U}
		actions.append({
			"id": "train:" + uid,
			"label": tr("ACTION_" + uid.to_upper()) + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": key_map.get(uid, KEY_NONE) as Key,
			"raw_label": true,
		})
	actions.append({
		"id": "build:fish_trap",
		"label": tr("ACTION_FISH_TRAP") + "\n75W",
		"color": Color(0.15, 0.40, 0.55),
		"cost": {"wood": 75},
		"key": KEY_P,
		"raw_label": true,
	})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)

func _populate_trebuchet_buttons(treb: Trebuchet) -> void:
	var deploy_label: String = tr("ACTION_TREBUCHET_UNDEPLOY") if treb.is_deployed else tr("ACTION_TREBUCHET_DEPLOY")
	var deploy_color: Color = Color(0.20, 0.45, 0.20) if treb.is_deployed else Color(0.45, 0.35, 0.12)
	var actions: Array = [
		{"id": "move_to",        "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
		{"id": "attack_move",    "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
		{"id": "stop",           "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
		{"id": "trebuchet_deploy", "label": deploy_label, "color": deploy_color, "cost": {}, "key": KEY_F, "raw_label": true},
		DESTROY_ACTION,
	]
	_populate_buttons(actions)

func _populate_scout_buttons(scout: Scout) -> void:
	var actions: Array = [
		{"id": "move_to",     "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
		{"id": "attack_move", "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
		{"id": "stop",        "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	]
	if scout.is_exploring():
		actions.append({"id": "scout_explore_stop", "label": "ACTION_SCOUT_EXPLORE_STOP", "color": Color(0.65, 0.35, 0.10), "cost": {}, "key": KEY_E, "description": "TOOLTIP_SCOUT_EXPLORE_STOP"})
	else:
		actions.append({"id": "scout_explore", "label": "ACTION_SCOUT_EXPLORE", "color": Color(0.15, 0.55, 0.25), "cost": {}, "key": KEY_E, "description": "TOOLTIP_SCOUT_EXPLORE"})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)

func _populate_siege_workshop_actions(workshop: SiegeWorkshop) -> void:
	var actions: Array = []
	for def: Dictionary in workshop.get_available_units():
		var uid: String = def["id"] as String
		var data: UnitResource = load(def["data"] as String) as UnitResource
		var cost_parts: Array[String] = []
		if data.cost_food  > 0: cost_parts.append("%dF" % data.cost_food)
		if data.cost_wood  > 0: cost_parts.append("%dW" % data.cost_wood)
		if data.cost_gold  > 0: cost_parts.append("%dG" % data.cost_gold)
		var cost_label: String = " ".join(PackedStringArray(cost_parts))
		var costs: Dictionary = {}
		if data.cost_food  > 0: costs["food"] = data.cost_food
		if data.cost_wood  > 0: costs["wood"] = data.cost_wood
		if data.cost_gold  > 0: costs["gold"] = data.cost_gold
		var key_map: Dictionary = {"battering_ram": KEY_B, "mangonel": KEY_M, "trebuchet": KEY_T}
		actions.append({
			"id": "train:" + uid,
			"label": data.display_name + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": key_map.get(uid, KEY_NONE) as Key,
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)

func _build_age_advance_bar() -> void:
	if is_instance_valid(_age_advance_bar):
		return
	var detail_panel: Node = get_node_or_null("HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow/UnitDetailPanel")
	if detail_panel == null:
		return
	_age_advance_bar = ProgressBar.new()
	_age_advance_bar.min_value = 0.0
	_age_advance_bar.max_value = 100.0
	_age_advance_bar.value = 0.0
	_age_advance_bar.show_percentage = false
	_age_advance_bar.custom_minimum_size = Vector2(0, 12)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.70, 0.60, 0.15)
	_age_advance_bar.add_theme_stylebox_override("fill", fill)
	detail_panel.add_child(_age_advance_bar)

func _build_hero_respawn_bar() -> void:
	if is_instance_valid(_hero_respawn_bar):
		return
	var detail_panel: Node = get_node_or_null("HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow/UnitDetailPanel")
	if detail_panel == null:
		return
	_hero_respawn_label = Label.new()
	_hero_respawn_label.add_theme_font_size_override("font_size", 15)
	_hero_respawn_label.add_theme_color_override("font_color", Color(0.90, 0.75, 0.25))
	_hero_respawn_label.text = ""
	detail_panel.add_child(_hero_respawn_label)
	_hero_respawn_bar = ProgressBar.new()
	_hero_respawn_bar.min_value = 0.0
	_hero_respawn_bar.max_value = 100.0
	_hero_respawn_bar.value = 0.0
	_hero_respawn_bar.show_percentage = false
	_hero_respawn_bar.custom_minimum_size = Vector2(0, 12)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.55, 0.10)
	_hero_respawn_bar.add_theme_stylebox_override("fill", fill)
	detail_panel.add_child(_hero_respawn_bar)

func _build_research_bar(building: Node) -> void:
	if not is_instance_valid(building):
		return
	var tech: TechnologyResource = TechManager.get_researching_tech(building)
	if tech == null:
		return
	var detail_panel: Node = get_node_or_null("HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow/UnitDetailPanel")
	if detail_panel == null:
		return
	if not is_instance_valid(_research_label):
		_research_label = Label.new()
		_research_label.add_theme_font_size_override("font_size", 15)
		_research_label.add_theme_color_override("font_color", Color(0.55, 0.80, 0.90))
		detail_panel.add_child(_research_label)
	_research_label.text = tr("UI_RESEARCHING") % tech.display_name if tr("UI_RESEARCHING") != "UI_RESEARCHING" else ("Researching: " + tech.display_name)
	if not is_instance_valid(_research_bar):
		_research_bar = ProgressBar.new()
		_research_bar.min_value = 0.0
		_research_bar.max_value = 100.0
		_research_bar.value = 0.0
		_research_bar.show_percentage = false
		_research_bar.custom_minimum_size = Vector2(0, 12)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color(0.25, 0.55, 0.75)
		_research_bar.add_theme_stylebox_override("fill", fill)
		detail_panel.add_child(_research_bar)

func _on_hero_low_hp(player_id: int) -> void:
	if player_id != 0:
		return
	_flash_hero_alert()

func _flash_hero_alert() -> void:
	if not is_instance_valid(_hero_alert_overlay):
		_hero_alert_overlay = ColorRect.new()
		_hero_alert_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hero_alert_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hero_alert_overlay.color = Color(0.85, 0.0, 0.0, 0.0)
		_hero_alert_overlay.z_index = 100
		get_node("HUDRoot").add_child(_hero_alert_overlay)
	_hero_alert_overlay.color = Color(0.85, 0.0, 0.0, 0.55)
	var tw: Tween = create_tween()
	tw.tween_property(_hero_alert_overlay, "color:a", 0.0, 1.2)

func _on_hero_respawned(_respawn_player_id: int) -> void:
	if is_instance_valid(_hero_respawn_bar):
		_hero_respawn_bar.queue_free()
		_hero_respawn_bar = null
	if is_instance_valid(_hero_respawn_label):
		_hero_respawn_label.queue_free()
		_hero_respawn_label = null

func _get_unit_status(unit: Node) -> String:
	var state_v: Variant = unit.get("current_state")
	if state_v == null:
		return ""
	var state: int = state_v as int
	match state:
		1: # MOVING
			return tr("UI_STATUS_MOVING")
		2: # ATTACKING
			return tr("UI_STATUS_ATTACKING")
		3: # GATHERING
			if unit is FishingBoat:
				var fb: FishingBoat = unit as FishingBoat
				return tr("UI_STATUS_GATHERING_RES") % ["Fish", int(fb.carried_amount), int(FishingBoat.CARRY_CAPACITY)]
			var resource: Variant = unit.get("carried_resource")
			var amount: Variant = unit.get("carried_amount")
			if resource != null and amount != null:
				var r: String = resource as String
				var a: float = amount as float
				if r.is_empty():
					return tr("UI_STATUS_GATHERING")
				return tr("UI_STATUS_GATHERING_RES") % [r.capitalize(), int(a),
					int((unit.get("carry_capacity") as float) if unit.get("carry_capacity") != null else 10.0)]
			return tr("UI_STATUS_GATHERING")
		4: # RETURNING
			if unit is FishingBoat:
				var fb: FishingBoat = unit as FishingBoat
				return tr("UI_STATUS_RETURNING_RES") % ["Fish", int(fb.carried_amount)]
			var resource: Variant = unit.get("carried_resource")
			var amount: Variant = unit.get("carried_amount")
			if resource != null and amount != null:
				return tr("UI_STATUS_RETURNING_RES") % [(resource as String).capitalize(), int(amount as float)]
			return tr("UI_STATUS_RETURNING")
		5: # BUILDING
			return tr("UI_STATUS_BUILDING")
		6: # DEAD
			return tr("UI_STATUS_DEAD")
	return ""

func _on_resource_node_selected(node: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null
	_status_unit = null
	for child: Node in _unit_portraits_grid.get_children():
		child.queue_free()
	_clear_action_buttons()
	var rn: ResourceNode = node as ResourceNode
	var res_name: String = rn.get_resource_name().capitalize()
	_unit_name_label.text = res_name
	_unit_hp_bar.value = (rn.remaining_amount / rn.initial_amount) * 100.0
	_unit_status_label.text = "%d / %d" % [int(rn.remaining_amount), int(rn.initial_amount)]

func _on_cancel_train_slot(index: int) -> void:
	if not is_instance_valid(_selected_building):
		return
	if _selected_building.has_method("order_cancel_train"):
		_selected_building.order_cancel_train(index)

func _on_train_queue_changed(building: Node, queue: Array, max_queue: int) -> void:
	if building != _selected_building:
		return
	# Update train button label with queue count
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var aid: String = btn.action_id
		if not aid.begins_with("train:"):
			continue
		var base_label: String = btn.get_meta("base_label", btn.text) as String
		btn.text = base_label + "\n%d/%d" % [queue.size(), max_queue]
	_refresh_button_states()
	# Rebuild the visual queue row
	for slot: Node in _train_queue_row.get_children():
		slot.queue_free()
	var pop_blocked: bool = not queue.is_empty() and PopulationManager.at_cap(local_player_id)
	for i: int in range(queue.size()):
		var entry: Dictionary = queue[i] as Dictionary
		var slot: TrainQueueSlot = TrainQueueSlot.new()
		_train_queue_row.add_child(slot)
		slot.setup(i, entry["label"] as String, entry["color"] as Color, i == 0, i == 0 and pop_blocked)
		slot.cancel_requested.connect(_on_cancel_train_slot)

func _update_train_queue_progress() -> void:
	if not is_instance_valid(_selected_building):
		return
	if not _selected_building.has_method("get_train_progress"):
		return
	var p: float = _selected_building.get_train_progress() as float
	var first_slot: Node = _train_queue_row.get_child(0) if _train_queue_row.get_child_count() > 0 else null
	if first_slot is TrainQueueSlot:
		(first_slot as TrainQueueSlot).set_progress(p)

func _on_building_destroyed(building: Node, _player_id: int) -> void:
	if building == _selected_building:
		if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
			_selected_building.set_selected(false)
		_selected_building = null
		_on_building_selected(null)

func _on_unit_died(unit: Node, _player_id: int) -> void:
	_status_unit = null

func _build_notifications() -> void:
	var nd: NotificationDisplay = NotificationDisplay.new()
	get_node("HUDRoot").add_child(nd)

func _build_follow_button() -> void:
	var detail_panel: Node = get_node_or_null("HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow/UnitDetailPanel")
	if detail_panel == null:
		return
	_follow_btn = Button.new()
	_follow_btn.text = "📷 Seguir"
	_follow_btn.focus_mode = Control.FOCUS_NONE
	_follow_btn.visible = false
	_follow_btn.custom_minimum_size = Vector2(0, 24)
	_follow_btn.add_theme_font_size_override("font_size", 15)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.25, 0.45, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_follow_btn.add_theme_stylebox_override("normal", style)
	var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.25, 0.40, 0.65, 0.9)
	_follow_btn.add_theme_stylebox_override("hover", hover_style)
	_follow_btn.pressed.connect(_on_follow_pressed)
	detail_panel.add_child(_follow_btn)

func _on_follow_pressed() -> void:
	_set_follow_active(not _following)
	follow_requested.emit()

func _set_follow_active(active: bool) -> void:
	_following = active
	if not is_instance_valid(_follow_btn):
		return
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.55, 0.20, 0.9) if active else Color(0.15, 0.25, 0.45, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_follow_btn.add_theme_stylebox_override("normal", style)
	var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover_style.bg_color = style.bg_color.lightened(0.2)
	_follow_btn.add_theme_stylebox_override("hover", hover_style)
	_follow_btn.text = ("📷 Siguiendo" if active else "📷 Seguir")

# --- Stats signal handlers ---

func _on_stat_unit_spawned(_unit: Node, player_id: int) -> void:
	if not _clock_running:
		return
	if player_id == local_player_id:
		_stat_units_trained += 1
	else:
		if player_id == 1:
			_ai_stat_units_trained += 1
		if _rival_stats.has(player_id):
			(_rival_stats[player_id] as Dictionary)["units_trained"] = \
				((_rival_stats[player_id] as Dictionary)["units_trained"] as int) + 1

func _on_stat_building_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid == null:
		return
	if (pid as int) == local_player_id:
		_stat_buildings_built += 1
	else:
		if (pid as int) == 1:
			_ai_stat_buildings_built += 1
		if _rival_stats.has(pid as int):
			(_rival_stats[pid as int] as Dictionary)["buildings_built"] = \
				((_rival_stats[pid as int] as Dictionary)["buildings_built"] as int) + 1

func _on_building_construction_complete(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building == building:
		_on_building_selected(building)

func _on_stat_unit_died(unit: Node, player_id: int) -> void:
	var udata: Variant = unit.get("unit_data")
	if udata == null:
		return
	if player_id != local_player_id:
		_stat_enemies_killed += 1
		if player_id == 1:
			_ai_stat_units_lost += 1
		if _rival_stats.has(player_id):
			(_rival_stats[player_id] as Dictionary)["units_lost"] = \
				((_rival_stats[player_id] as Dictionary)["units_lost"] as int) + 1
	else:
		if _rival_stats.has(1):
			(_rival_stats[1] as Dictionary)["units_lost"] = \
				((_rival_stats[1] as Dictionary)["units_lost"] as int) + 1

var _last_resources: Dictionary = {}

# --- Timeline snapshots (sampled every SNAPSHOT_INTERVAL seconds) ---
const SNAPSHOT_INTERVAL: float = 15.0
var _snapshot_timer: float = 0.0

var _snap_pop_a:       Array = []   # player population
var _snap_res_a:       Array = []   # player total resources gathered
var _snap_age_a:       Array = []   # player age (0-3)
var _snap_kills_a:      Array = []  # kills per interval
var _snap_kills_a_prev: int = 0
var _offense_snaps_a: Array = []

# Per-rival snapshot data: rival_id (int) → Array[float]
var _snap_pop_rivals:    Dictionary = {}
var _snap_res_rivals:    Dictionary = {}
var _snap_age_rivals:    Dictionary = {}
var _snap_kills_rivals:  Dictionary = {}
var _snap_kills_rivals_prev: Dictionary = {}
var _offense_snaps_rivals:   Dictionary = {}

const OFFENSE_THRESHOLD: int = 2   # kills in one interval to count as an offensive

func _take_snapshot() -> void:
	# Player
	var pop_a: Dictionary = PopulationManager.get_population(local_player_id)
	_snap_pop_a.append(float(pop_a.get("current", 0) as int))
	var total_a: int = 0
	for k: String in ["food", "wood", "gold", "stone"]:
		total_a += _stat_resources_gathered.get(k, 0) as int
	_snap_res_a.append(float(total_a))
	_snap_age_a.append(float(AgeManager.get_age(local_player_id)))
	var kills_delta_a: int = _stat_enemies_killed - _snap_kills_a_prev
	_snap_kills_a.append(float(kills_delta_a))
	var snap_idx: int = _snap_kills_a.size() - 1
	if kills_delta_a >= OFFENSE_THRESHOLD:
		_offense_snaps_a.append(snap_idx)
	_snap_kills_a_prev = _stat_enemies_killed

	# Per-rival
	for rival_id: int in MatchConfig.get_rival_player_ids():
		var pop_r: Dictionary = PopulationManager.get_population(rival_id)
		(_snap_pop_rivals[rival_id] as Array).append(float(pop_r.get("current", 0) as int))

		var rival_res_dict: Dictionary = {}
		if _rival_stats.has(rival_id):
			rival_res_dict = (_rival_stats[rival_id] as Dictionary).get("resources", {}) as Dictionary
		var total_r: int = 0
		for k: String in ["food", "wood", "gold", "stone"]:
			total_r += rival_res_dict.get(k, 0) as int
		(_snap_res_rivals[rival_id] as Array).append(float(total_r))

		(_snap_age_rivals[rival_id] as Array).append(float(AgeManager.get_age(rival_id)))

		var prev_kills_r: int = _snap_kills_rivals_prev.get(rival_id, 0) as int
		var rival_lost: int = 0
		if _rival_stats.has(rival_id):
			rival_lost = (_rival_stats[rival_id] as Dictionary).get("units_lost", 0) as int
		var kills_delta_r: int = rival_lost - prev_kills_r
		(_snap_kills_rivals[rival_id] as Array).append(float(kills_delta_r))
		var snap_idx_r: int = (_snap_kills_rivals[rival_id] as Array).size() - 1
		if kills_delta_r >= OFFENSE_THRESHOLD:
			(_offense_snaps_rivals[rival_id] as Array).append(snap_idx_r)
		_snap_kills_rivals_prev[rival_id] = rival_lost

func _on_stat_resources_updated(player_id: int, resources: Dictionary) -> void:
	for res: String in ["food", "wood", "gold", "stone"]:
		var current: float = resources.get(res, 0.0) as float
		if player_id == local_player_id:
			var last: float = _last_resources.get(res, current) as float
			if current > last:
				_stat_resources_gathered[res] = (_stat_resources_gathered[res] as int) + int(current - last)
			_last_resources[res] = current
		else:
			# Legacy player_id 1 path
			if player_id == 1:
				var last: float = _ai_last_resources.get(res, current) as float
				if current > last:
					_ai_stat_resources_gathered[res] = (_ai_stat_resources_gathered[res] as int) + int(current - last)
				_ai_last_resources[res] = current
			# Generic rival path
			if _rival_stats.has(player_id):
				var rival_last: Dictionary = _rival_last_res.get(player_id, {}) as Dictionary
				var last_r: float = rival_last.get(res, current) as float
				if current > last_r:
					var rival_res: Dictionary = (_rival_stats[player_id] as Dictionary)["resources"] as Dictionary
					rival_res[res] = (rival_res.get(res, 0) as int) + int(current - last_r)
				if not _rival_last_res.has(player_id):
					_rival_last_res[player_id] = {}
				(_rival_last_res[player_id] as Dictionary)[res] = current

# --- Game over screen ---

func _make_panel_style(bg: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	return s

func _on_game_over(winner_player_id: int) -> void:
	_clock_running = false
	_take_snapshot()

	var root: Node = get_node("HUDRoot")

	# Dark overlay — blocks clicks on world but NOT on our panel
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(overlay)

	# Centred panel
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.10, 0.97)))
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("GAMEOVER_VICTORY") if winner_player_id == 0 else tr("GAMEOVER_DEFEAT")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	var title_col: Color = Color(0.25, 1.0, 0.35) if winner_player_id == 0 else Color(1.0, 0.25, 0.25)
	title.add_theme_color_override("font_color", title_col)
	vbox.add_child(title)

	# Separator
	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# Stats header
	var stats_header: Label = Label.new()
	stats_header.text = tr("GAMEOVER_SUMMARY")
	stats_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_header.add_theme_font_size_override("font_size", 22)
	stats_header.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(stats_header)

	# Stats grid — 3 columns: stat label | player value | rival value
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	var total_secs: int = int(_elapsed_seconds)
	var time_str: String = "%02d:%02d" % [total_secs / 60, total_secs % 60]
	var age_keys: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]

	var rival_ids: Array[int] = MatchConfig.get_rival_player_ids()
	var total_cols: int = 1 + rival_ids.size()   # player + rivals
	grid.columns = 1 + total_cols

	# Helper: get display name for a civ_id
	var _get_civ_display: Callable = func(civ_id: String) -> String:
		var res: CivilizationResource = load(
			"res://resources/civilizations/%s.tres" % civ_id) as CivilizationResource
		return res.display_name if res != null else civ_id

	# Column headers
	var _blank: Label = Label.new()
	grid.add_child(_blank)

	# Player column
	var player_col: VBoxContainer = VBoxContainer.new()
	player_col.add_theme_constant_override("separation", 1)
	var ph: Label = Label.new()
	ph.text = tr("GAMEOVER_PLAYER")
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ph.add_theme_font_size_override("font_size", 17)
	ph.add_theme_color_override("font_color", PlayerColors.get_color(local_player_id))
	player_col.add_child(ph)
	var pc: Label = Label.new()
	pc.text = _get_civ_display.call(MatchConfig.player_civ_id) as String
	pc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pc.add_theme_font_size_override("font_size", 15)
	pc.add_theme_color_override("font_color", PlayerColors.get_color(local_player_id).lightened(0.3))
	player_col.add_child(pc)
	grid.add_child(player_col)

	# Rival columns
	for ri: int in range(rival_ids.size()):
		var rid: int = rival_ids[ri]
		var rcol: VBoxContainer = VBoxContainer.new()
		rcol.add_theme_constant_override("separation", 1)
		var rh: Label = Label.new()
		var rival_label: String = tr("GAMEOVER_RIVAL") if rival_ids.size() == 1 \
			else tr("GAMEOVER_RIVAL") + " %d" % (ri + 1)
		rh.text = rival_label
		rh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rh.add_theme_font_size_override("font_size", 17)
		var rcol_color: Color = PlayerColors.get_color(rid)
		rh.add_theme_color_override("font_color", rcol_color)
		rcol.add_child(rh)
		var rcc: Label = Label.new()
		rcc.text = _get_civ_display.call(MatchConfig.get_rival_civ_id(rid)) as String
		rcc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rcc.add_theme_font_size_override("font_size", 15)
		rcc.add_theme_color_override("font_color", rcol_color.lightened(0.3))
		rcol.add_child(rcc)
		grid.add_child(rcol)

	# Helper: get rival stat value string
	var _rival_val: Callable = func(rid: int, key: String) -> String:
		if _rival_stats.has(rid):
			return str((_rival_stats[rid] as Dictionary).get(key, 0))
		# Fallback to legacy player_id 1 vars
		match key:
			"units_trained":   return str(_ai_stat_units_trained)
			"buildings_built": return str(_ai_stat_buildings_built)
			"units_lost":      return str(_ai_stat_units_lost)
		return "0"

	var _rival_res_val: Callable = func(rid: int, res: String) -> String:
		if _rival_stats.has(rid):
			var r: Dictionary = (_rival_stats[rid] as Dictionary).get("resources", {}) as Dictionary
			return str(r.get(res, 0))
		return str(_ai_stat_resources_gathered.get(res, 0))

	# Build stat rows — first element is label, then one value per column
	var stat_defs: Array = [
		{"label": tr("GAMEOVER_TIME"),
			"player": time_str,
			"rival_fn": func(_rid: int) -> String: return time_str},
		{"label": tr("GAMEOVER_AGE"),
			"player": tr(age_keys[clampi(AgeManager.get_age(local_player_id), 0, 3)]),
			"rival_fn": func(rid: int) -> String: return tr(age_keys[clampi(AgeManager.get_age(rid), 0, 3)])},
		{"label": tr("GAMEOVER_UNITS"),
			"player": str(_stat_units_trained),
			"rival_fn": func(rid: int) -> String: return _rival_val.call(rid, "units_trained") as String},
		{"label": tr("GAMEOVER_BUILDINGS"),
			"player": str(_stat_buildings_built),
			"rival_fn": func(rid: int) -> String: return _rival_val.call(rid, "buildings_built") as String},
		{"label": tr("GAMEOVER_KILLS"),
			"player": str(_stat_enemies_killed),
			"rival_fn": func(rid: int) -> String: return _rival_val.call(rid, "units_lost") as String},
		{"label": tr("GAMEOVER_FOOD"),
			"player": str(_stat_resources_gathered.get("food", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "food") as String},
		{"label": tr("GAMEOVER_WOOD"),
			"player": str(_stat_resources_gathered.get("wood", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "wood") as String},
		{"label": tr("GAMEOVER_GOLD"),
			"player": str(_stat_resources_gathered.get("gold", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "gold") as String},
		{"label": tr("GAMEOVER_STONE"),
			"player": str(_stat_resources_gathered.get("stone", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "stone") as String},
	]

	for stat: Dictionary in stat_defs:
		var key_lbl: Label = Label.new()
		key_lbl.text = stat["label"] as String
		key_lbl.add_theme_font_size_override("font_size", 18)
		key_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
		grid.add_child(key_lbl)

		var player_val: Label = Label.new()
		player_val.text = stat["player"] as String
		player_val.add_theme_font_size_override("font_size", 18)
		player_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		player_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(player_val)

		for rid: int in rival_ids:
			var rival_val: Label = Label.new()
			rival_val.text = (stat["rival_fn"] as Callable).call(rid) as String
			rival_val.add_theme_font_size_override("font_size", 18)
			rival_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			rival_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(rival_val)

	# Separator
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	# Buttons row
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	# "Ver mapa" button — closes stats panel and adds a persistent corner exit button
	var hud_root: Node = get_node("HUDRoot")
	var map_btn: Button = Button.new()
	map_btn.text = tr("GAMEOVER_VIEW_MAP")
	map_btn.custom_minimum_size = Vector2(150.0, 36.0)
	map_btn.add_theme_font_size_override("font_size", 20)
	map_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.15, 0.30, 0.50, 0.95)))
	map_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.25, 0.45, 0.70, 0.95)))

	var exit_btn: Button = Button.new()
	exit_btn.text = tr("GAMEOVER_EXIT")
	exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	exit_btn.offset_left   = -160.0
	exit_btn.offset_right  =    0.0
	exit_btn.offset_top    =    8.0
	exit_btn.offset_bottom =   40.0
	exit_btn.add_theme_font_size_override("font_size", 18)
	exit_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.15, 0.15, 0.15, 0.92)))
	exit_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.35, 0.15, 0.15, 0.92)))
	exit_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/game/main_menu.tscn")
	)

	map_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		center.queue_free()
		hud_root.add_child(exit_btn)
		var world: Node = get_tree().get_nodes_in_group("world").front()
		if world == null:
			world = get_tree().current_scene
		for child: Node in world.get_children():
			if child is FogOfWar:
				(child as FogOfWar).reveal_all()
				break
	)
	btn_row.add_child(map_btn)

	# "Ver gráficas" button — opens timeline charts overlay
	var charts_btn: Button = Button.new()
	charts_btn.text = tr("GAMEOVER_CHARTS")
	charts_btn.custom_minimum_size = Vector2(150.0, 36.0)
	charts_btn.add_theme_font_size_override("font_size", 20)
	charts_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.22, 0.20, 0.38, 0.95)))
	charts_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.36, 0.32, 0.60, 0.95)))
	charts_btn.pressed.connect(func() -> void:
		_show_charts_panel(root)
	)
	btn_row.add_child(charts_btn)

	# "Volver al menú" button
	var menu_btn: Button = Button.new()
	menu_btn.text = tr("GAMEOVER_BACK_MENU")
	menu_btn.custom_minimum_size = Vector2(150.0, 36.0)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.15, 0.15, 0.15, 0.95)))
	menu_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.30, 0.30, 0.30, 0.95)))
	menu_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/game/main_menu.tscn")
	)
	btn_row.add_child(menu_btn)

# --- Match timeline charts ---

func _show_charts_panel(parent: Node) -> void:
	# Full-screen overlay
	var ov: ColorRect = ColorRect.new()
	ov.color = Color(0.0, 0.0, 0.0, 0.80)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(ov)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	ov.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.07, 0.10, 0.98)))
	card.custom_minimum_size = Vector2(700.0, 0.0)
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Title
	var title_lbl: Label = Label.new()
	title_lbl.text = tr("GAMEOVER_CHARTS")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title_lbl)

	var rival_ids: Array[int] = MatchConfig.get_rival_player_ids()

	# Legend row
	var legend: HBoxContainer = HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 24)
	vbox.add_child(legend)

	var legend_entries: Array = [[tr("GAMEOVER_PLAYER"), PlayerColors.get_color(local_player_id)]]
	for ri: int in range(rival_ids.size()):
		var label_text: String = tr("GAMEOVER_RIVAL") if rival_ids.size() == 1 \
			else tr("GAMEOVER_RIVAL") + " %d" % (ri + 1)
		legend_entries.append([label_text, PlayerColors.get_color(rival_ids[ri])])

	for ldata: Array in legend_entries:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		legend.add_child(row)
		var swatch: ColorRect = ColorRect.new()
		swatch.color = ldata[1] as Color
		swatch.custom_minimum_size = Vector2(18, 10)
		row.add_child(swatch)
		var ll: Label = Label.new()
		ll.text = ldata[0] as String
		ll.add_theme_font_size_override("font_size", 17)
		ll.add_theme_color_override("font_color", ldata[1] as Color)
		row.add_child(ll)

	vbox.add_child(HSeparator.new())

	# Build series_b (first rival) and extra_series (remaining rivals)
	var first_rid: int = rival_ids[0] if rival_ids.size() > 0 else 1
	var series_b_pop:    Array = _snap_pop_rivals.get(first_rid, []) as Array
	var series_b_res:    Array = _snap_res_rivals.get(first_rid, []) as Array
	var series_b_age:    Array = _snap_age_rivals.get(first_rid, []) as Array
	var series_b_kills:  Array = _snap_kills_rivals.get(first_rid, []) as Array
	var spikes_b_kills:  Array = _offense_snaps_rivals.get(first_rid, []) as Array

	var extra_pop:   Array = []
	var extra_res:   Array = []
	var extra_age:   Array = []
	var extra_kills: Array = []
	var extra_cols:  Array = []
	for ri: int in range(1, rival_ids.size()):
		var rid: int = rival_ids[ri]
		extra_pop.append(_snap_pop_rivals.get(rid, []))
		extra_res.append(_snap_res_rivals.get(rid, []))
		extra_age.append(_snap_age_rivals.get(rid, []))
		extra_kills.append(_snap_kills_rivals.get(rid, []))
		extra_cols.append(PlayerColors.get_color(rid))

	# Charts definition: [title, series_a, series_b, extra_series, extra_colors, spikes_a, spikes_b, mode]
	var chart_defs: Array = [
		[tr("CHART_POPULATION"), _snap_pop_a,   series_b_pop,   extra_pop,   extra_cols, [],              [],             MatchChart.Mode.LINES],
		[tr("CHART_RESOURCES"),  _snap_res_a,   series_b_res,   extra_res,   extra_cols, [],              [],             MatchChart.Mode.LINES],
		[tr("CHART_AGE"),        _snap_age_a,   series_b_age,   extra_age,   extra_cols, [],              [],             MatchChart.Mode.STEPS],
		[tr("CHART_OFFENSIVES"), _snap_kills_a, series_b_kills, extra_kills, extra_cols, _offense_snaps_a, spikes_b_kills, MatchChart.Mode.BARS],
	]

	for cdef: Array in chart_defs:
		var chart: MatchChart = MatchChart.new()
		chart.chart_title   = cdef[0] as String
		chart.series_a      = cdef[1] as Array
		chart.series_b      = cdef[2] as Array
		chart.extra_series  = cdef[3] as Array
		chart.extra_colors  = cdef[4] as Array
		chart.spikes_a      = cdef[5] as Array
		chart.spikes_b      = cdef[6] as Array
		chart.mode          = cdef[7] as int
		chart.total_time    = _elapsed_seconds
		chart.color_a       = PlayerColors.get_color(local_player_id)
		chart.color_b       = PlayerColors.get_color(first_rid)
		chart.custom_minimum_size = Vector2(0.0, 90.0)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(chart)

	vbox.add_child(HSeparator.new())

	# Close button
	var close_btn: Button = Button.new()
	close_btn.text = tr("GAMEOVER_CHARTS_CLOSE")
	close_btn.custom_minimum_size = Vector2(160.0, 36.0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.20, 0.20, 0.25, 0.95)))
	close_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.35, 0.35, 0.42, 0.95)))
	close_btn.pressed.connect(func() -> void: ov.queue_free())
	vbox.add_child(close_btn)

# ── In-game pause menu ──────────────────────────────────────────────────────

var _tutorial_overlay: TutorialOverlay = null
var _tutorial_res_baseline: Dictionary = {}
var _tutorial_step: int = 0       # highest step reached; used to gate tutorial-mode actions
var _tutorial_gates_active: bool = false  # true only in tutorial mode; false after skip

# build ids unlocked per tutorial step (cumulative)
const _TUTORIAL_BUILD_UNLOCK: Dictionary = {
	3: ["build:lumber_camp", "build:mining_camp"],
	4: ["build:house"],
	6: ["build:barracks"],
	7: [],  # all remaining buildings unlocked after age-advance step
}

func _start_tutorial() -> void:
	_tutorial_gates_active = true
	_tutorial_overlay = TutorialOverlay.new()
	get_node("HUDRoot").add_child(_tutorial_overlay)
	_tutorial_overlay.finished.connect(_on_tutorial_finished)
	_tutorial_overlay.completed.connect(func() -> void: _on_game_over(0))
	_tutorial_overlay.step_changed.connect(_on_tutorial_step_changed)
	_tutorial_overlay.start()
	_wire_tutorial_signals()

func _wire_tutorial_signals() -> void:
	EventBus.camera_moved.connect(_on_tutorial_camera_moved)
	EventBus.unit_selected.connect(_on_tutorial_unit_selected)
	EventBus.unit_command_issued.connect(_on_tutorial_unit_command)
	EventBus.resource_changed.connect(_on_tutorial_resource_changed)
	EventBus.building_placed.connect(_on_tutorial_building_placed)
	EventBus.building_construction_complete.connect(_on_tutorial_building_complete)
	EventBus.unit_spawned.connect(_on_tutorial_unit_spawned)
	EventBus.age_advance_complete.connect(_on_tutorial_age_complete)
	EventBus.hero_ability_used.connect(_on_tutorial_hero_ability)
	EventBus.enemy_unit_spotted.connect(_on_tutorial_enemy_spotted)
	EventBus.map_explored.connect(_on_tutorial_map_explored)
	EventBus.unit_attacked.connect(_on_tutorial_unit_attacked)

func _on_tutorial_finished() -> void:
	_tutorial_overlay = null
	_tutorial_gates_active = false
	# Refresh whichever panel is currently open
	if _in_build_menu:
		_populate_buttons(_filtered_build_actions())
	elif is_instance_valid(_selected_building):
		var scr: Script = _selected_building.get_script() as Script
		if scr != null and "town_center" in (scr.resource_path as String).to_lower():
			_populate_tc_actions()
	elif is_instance_valid(_selected_unit) and _selected_unit.has_method("order_gather"):
		_populate_buttons(VILLAGER_ACTIONS)
		_apply_tutorial_villager_gates()

func _tutorial_notify(condition: String) -> void:
	if _tutorial_overlay == null or not is_instance_valid(_tutorial_overlay):
		return
	if _tutorial_overlay.current_condition() == condition:
		_tutorial_overlay.unlock_current()

func _on_tutorial_camera_moved() -> void:
	_tutorial_notify("camera_moved")

func _on_tutorial_unit_selected(units: Array) -> void:
	_tutorial_notify("unit_selected")

func _on_tutorial_unit_command(_units: Array, _cmd: Dictionary) -> void:
	_tutorial_notify("unit_moved")

const _TUTORIAL_MINIMUMS: Dictionary = {
	"resource_gathered":   {"wood": 0},
	"camp_complete":        {"wood": 100},
	"house_complete":       {"wood": 25},
	"militia_trained":     {"wood": 60, "food": 180},
	"age_advance_complete": {"food": 500},
	"unit_attacked":       {"food": 60, "wood": 20},
}

func _on_tutorial_step_changed(step: int, condition: String) -> void:
	_tutorial_step = maxi(_tutorial_step, step)
	# Refresh open panels so newly unlocked actions appear
	if _in_build_menu:
		_populate_buttons(_filtered_build_actions())
	elif is_instance_valid(_selected_building):
		var scr: Script = _selected_building.get_script() as Script
		if scr != null and "town_center" in (scr.resource_path as String).to_lower():
			_populate_tc_actions()
	elif is_instance_valid(_selected_unit) and _selected_unit.has_method("order_gather"):
		_populate_buttons(VILLAGER_ACTIONS)
		_apply_tutorial_villager_gates()
	if condition == "camera_moved":
		EventBus.tutorial_reset_camera_flag.emit()
	if condition == "resource_gathered":
		_tutorial_res_baseline = ResourceManager.get_resources(local_player_id).duplicate()
	if condition == "map_explored":
		var world: Node = get_tree().get_nodes_in_group("world").front()
		if world == null:
			world = get_tree().current_scene
		var fog: FogOfWar = null
		for child: Node in world.get_children():
			if child is FogOfWar:
				fog = child as FogOfWar
				break
		if fog != null:
			fog.start_explore_tracking()
	var minimums: Dictionary = _TUTORIAL_MINIMUMS.get(condition, {}) as Dictionary
	for res: String in minimums:
		var needed: int = minimums[res] as int
		var have: int = ResourceManager.get_resources(local_player_id).get(res, 0) as int
		if have < needed:
			ResourceManager.add_resource(local_player_id, res, needed - have)
	if condition == "unit_attacked":
		var world: Node = get_tree().get_nodes_in_group("world").front()
		if world == null:
			world = get_tree().current_scene
		var tc_node: Node2D = world.get_node_or_null("DropOffNode") as Node2D
		var tc_pos: Vector2 = tc_node.global_position if tc_node != null else Vector2.ZERO
		EventBus.tutorial_spawn_enemy_scout.emit(tc_pos)
	if condition == "hero_ability_used":
		EventBus.tutorial_highlight_unit.emit("hero")
	if condition == "map_explored":
		EventBus.tutorial_highlight_unit.emit("scout")

func _on_tutorial_resource_changed(player_id: int, res: String, amt: int) -> void:
	if player_id != local_player_id:
		return
	var baseline: float = _tutorial_res_baseline.get(res, -1.0) as float
	if baseline >= 0.0 and (amt as float) > baseline:
		_tutorial_notify("resource_gathered")

func _on_tutorial_building_placed(building: Node, player_id: int) -> void:
	if player_id != local_player_id:
		return
	_tutorial_notify("building_placed")
	var bid: String = building.get_meta("building_id", "") as String
	if bid.is_empty():
		# Fallback: derive type from script path
		var script: Script = building.get_script() as Script
		if script != null:
			bid = script.resource_path.to_lower()
	bid = bid.to_lower()
	if "lumber_camp" in bid or "mining_camp" in bid:
		_tutorial_notify("camp_built")
	if "house" in bid:
		_tutorial_notify("house_built")
	if "barracks" in bid:
		_tutorial_notify("barracks_built")

func _on_tutorial_unit_spawned(unit: Node, player_id: int) -> void:
	if player_id != local_player_id:
		return
	var script: Script = unit.get_script() as Script
	if script == null:
		return
	var path: String = script.resource_path.to_lower()
	if "militia" in path:
		_tutorial_notify("militia_trained")
	elif unit.has_method("order_gather"):
		_tutorial_notify("villager_trained")

func _on_tutorial_building_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid == null or (pid as int) != local_player_id:
		return
	var bid: String = building.get_meta("building_id", "") as String
	if bid.is_empty():
		var script: Script = building.get_script() as Script
		if script != null:
			bid = script.resource_path.to_lower()
	bid = bid.to_lower()
	if "lumber_camp" in bid or "mining_camp" in bid:
		_tutorial_notify("camp_complete")
	if "house" in bid:
		_tutorial_notify("house_complete")

func _on_tutorial_age_complete(player_id: int, _new_age: int) -> void:
	if player_id == local_player_id:
		_tutorial_notify("age_advance_complete")

func _on_tutorial_hero_ability(player_id: int) -> void:
	if player_id == local_player_id:
		_tutorial_notify("hero_ability_used")

func _on_tutorial_enemy_spotted(_unit: Node) -> void:
	_tutorial_notify("enemy_spotted")

func _on_tutorial_map_explored(_cells: int) -> void:
	_tutorial_notify("map_explored")

func _on_tutorial_unit_attacked(attacker: Node, _target: Node) -> void:
	var pid: Variant = attacker.get("player_id")
	if pid != null and (pid as int) == local_player_id:
		_tutorial_notify("unit_attacked")

func _build_pause_menu_button() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	var btn: Button = Button.new()
	btn.text = "☰"
	btn.custom_minimum_size = Vector2(36, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	btn.tooltip_text = "Menu (Esc)"
	# Anchor to top-right corner
	btn.anchor_left   = 1.0
	btn.anchor_top    = 0.0
	btn.anchor_right  = 1.0
	btn.anchor_bottom = 0.0
	btn.offset_left   = -69.0
	btn.offset_top    =  31.0
	btn.offset_right  = -31.0
	btn.offset_bottom =  67.0
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.12, 0.18, 0.92)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.28, 0.28, 0.42, 0.97)
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(_open_pause_menu)
	hud_root.add_child(btn)

func _build_idle_villager_button() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	_idle_villager_btn = Button.new()
	_idle_villager_btn.text = "👷"
	_idle_villager_btn.custom_minimum_size = Vector2(36, 36)
	_idle_villager_btn.focus_mode = Control.FOCUS_NONE
	_idle_villager_btn.add_theme_font_size_override("font_size", 22)
	_idle_villager_btn.tooltip_text = tr("UI_IDLE_VILLAGER")
	# Anchor to bottom-right, above minimap top (220px), flush with minimap left edge (220px from right)
	_idle_villager_btn.anchor_left   = 1.0
	_idle_villager_btn.anchor_top    = 1.0
	_idle_villager_btn.anchor_right  = 1.0
	_idle_villager_btn.anchor_bottom = 1.0
	_idle_villager_btn.offset_left   = -256.0
	_idle_villager_btn.offset_top    = -260.0
	_idle_villager_btn.offset_right  = -220.0
	_idle_villager_btn.offset_bottom = -224.0
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.20, 0.40, 0.12, 0.92)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	_idle_villager_btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.32, 0.58, 0.18, 0.97)
	_idle_villager_btn.add_theme_stylebox_override("hover", sh)
	_idle_villager_btn.pressed.connect(_on_idle_villager_pressed)
	hud_root.add_child(_idle_villager_btn)

func _get_idle_villagers() -> Array[Node]:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		return []
	var units_layer: Node = world.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return []
	var result: Array[Node] = []
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit.get("player_id") != local_player_id:
			continue
		if not unit.has_method("order_gather"):
			continue
		var state: Variant = unit.get("current_state")
		if state != null and (state as int) == UnitBase.UnitState.IDLE:
			result.append(unit)
	return result

func _update_idle_villager_button() -> void:
	if not is_instance_valid(_idle_villager_btn):
		return
	var idle: Array[Node] = _get_idle_villagers()
	_idle_villager_btn.disabled = idle.is_empty()
	_idle_villager_btn.tooltip_text = tr("UI_IDLE_VILLAGER") + " (%d)" % idle.size()

func _on_idle_villager_pressed() -> void:
	var idle: Array[Node] = _get_idle_villagers()
	if idle.is_empty():
		return
	_idle_villager_index = _idle_villager_index % idle.size()
	var villager: Node = idle[_idle_villager_index]
	_idle_villager_index = (_idle_villager_index + 1) % idle.size()
	SelectionManager.select([villager])
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world != null:
		var cam: Camera2D = world.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			cam.position = (villager as Node2D).global_position

func _build_idle_military_button() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	_idle_military_btn = Button.new()
	_idle_military_btn.text = "⚔"
	_idle_military_btn.custom_minimum_size = Vector2(36, 36)
	_idle_military_btn.focus_mode = Control.FOCUS_NONE
	_idle_military_btn.add_theme_font_size_override("font_size", 22)
	_idle_military_btn.tooltip_text = tr("UI_IDLE_MILITARY")
	# Anchor to bottom-right, same row as villager button, 4px to the left of it
	_idle_military_btn.anchor_left   = 1.0
	_idle_military_btn.anchor_top    = 1.0
	_idle_military_btn.anchor_right  = 1.0
	_idle_military_btn.anchor_bottom = 1.0
	_idle_military_btn.offset_left   = -296.0
	_idle_military_btn.offset_top    = -260.0
	_idle_military_btn.offset_right  = -260.0
	_idle_military_btn.offset_bottom = -224.0
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.40, 0.12, 0.12, 0.92)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	_idle_military_btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.60, 0.18, 0.18, 0.97)
	_idle_military_btn.add_theme_stylebox_override("hover", sh)
	_idle_military_btn.pressed.connect(_on_idle_military_pressed)
	hud_root.add_child(_idle_military_btn)

func _get_idle_military() -> Array[Node]:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		return []
	var units_layer: Node = world.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return []
	var result: Array[Node] = []
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit.get("player_id") != local_player_id:
			continue
		if unit.get("unit_data") == null:
			continue
		if unit.has_method("order_gather"):
			continue
		if unit is Animal or unit is ShipBase:
			continue
		var state: Variant = unit.get("current_state")
		if state != null and (state as int) == UnitBase.UnitState.IDLE:
			result.append(unit)
	return result

func _update_idle_military_button() -> void:
	if not is_instance_valid(_idle_military_btn):
		return
	var idle: Array[Node] = _get_idle_military()
	_idle_military_btn.disabled = idle.is_empty()
	_idle_military_btn.tooltip_text = tr("UI_IDLE_MILITARY") + " (%d)" % idle.size()

func _on_idle_military_pressed() -> void:
	var idle: Array[Node] = _get_idle_military()
	if idle.is_empty():
		return
	_idle_military_index = _idle_military_index % idle.size()
	var unit: Node = idle[_idle_military_index]
	_idle_military_index = (_idle_military_index + 1) % idle.size()
	SelectionManager.select([unit])
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world != null:
		var cam: Camera2D = world.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			cam.position = (unit as Node2D).global_position

func _build_dpad() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	_dpad = Control.new()
	_dpad.anchor_left   = 0.0
	_dpad.anchor_top    = 1.0
	_dpad.anchor_right  = 0.0
	_dpad.anchor_bottom = 1.0
	const OFFSET_BOTTOM: float = -(175.0 + 8.0)
	const CELL: float = 96.0
	const GAP: float = 6.0
	const GRID_W: float = CELL * 3.0 + GAP * 2.0
	const GRID_H: float = CELL * 3.0 + GAP * 2.0
	_dpad.offset_left   = 8.0
	_dpad.offset_bottom = OFFSET_BOTTOM
	_dpad.offset_right  = 8.0 + GRID_W
	_dpad.offset_top    = OFFSET_BOTTOM - GRID_H
	_dpad.visible       = GameSettings.show_dpad
	hud_root.add_child(_dpad)

	var dirs: Array[Dictionary] = [
		{"label": "↑", "row": 0, "col": 1, "dir": Vector2(0.0, -1.0)},
		{"label": "←", "row": 1, "col": 0, "dir": Vector2(-1.0, 0.0)},
		{"label": "→", "row": 1, "col": 2, "dir": Vector2(1.0, 0.0)},
		{"label": "↓", "row": 2, "col": 1, "dir": Vector2(0.0, 1.0)},
	]
	for entry: Dictionary in dirs:
		var btn: Button = Button.new()
		btn.text             = entry["label"] as String
		btn.focus_mode       = Control.FOCUS_NONE
		btn.mouse_filter     = Control.MOUSE_FILTER_STOP
		btn.custom_minimum_size = Vector2(CELL, CELL)
		var col: int = entry["col"] as int
		var row: int = entry["row"] as int
		btn.position = Vector2(col * (CELL + GAP), row * (CELL + GAP))
		btn.size     = Vector2(CELL, CELL)
		btn.add_theme_font_size_override("font_size", 40)
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.12, 0.18, 0.85)
		s.corner_radius_top_left     = 6
		s.corner_radius_top_right    = 6
		s.corner_radius_bottom_left  = 6
		s.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", s)
		var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
		sh.bg_color = Color(0.22, 0.22, 0.32, 0.95)
		btn.add_theme_stylebox_override("hover", sh)
		_dpad.add_child(btn)
		var move_dir: Vector2 = entry["dir"] as Vector2
		btn.button_down.connect(func() -> void: _dpad_dir += move_dir)
		btn.button_up.connect(func() -> void: _dpad_dir -= move_dir)

func _open_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		return
	if GameManager.state == GameManager.GameState.GAME_OVER:
		return
	GameManager.toggle_pause()

	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_pause_menu = overlay

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 0)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.12, 0.97)))
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("MENU_SETTINGS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var resume_btn: Button = _make_pause_btn(tr("PAUSEMENU_RESUME"), Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	resume_btn.pressed.connect(_close_pause_menu)
	vbox.add_child(resume_btn)

	var settings_btn: Button = _make_pause_btn(tr("MENU_SETTINGS"), Color(0.20, 0.20, 0.28, 0.95), Color(0.32, 0.32, 0.45, 0.95))
	settings_btn.pressed.connect(_open_ingame_settings)
	vbox.add_child(settings_btn)

	var how_to_play_btn: Button = _make_pause_btn(tr("MENU_HOW_TO_PLAY"), Color(0.22, 0.35, 0.45, 0.95), Color(0.32, 0.50, 0.62, 0.95))
	how_to_play_btn.disabled = _tutorial_overlay != null and is_instance_valid(_tutorial_overlay)
	how_to_play_btn.pressed.connect(func() -> void:
		_close_pause_menu()
		_start_tutorial()
	)
	vbox.add_child(how_to_play_btn)

	var save_btn: Button = _make_pause_btn(tr("PAUSEMENU_SAVE"), Color(0.16, 0.28, 0.44, 0.95), Color(0.24, 0.42, 0.62, 0.95))
	save_btn.pressed.connect(_on_save_game)
	vbox.add_child(save_btn)

	vbox.add_child(HSeparator.new())

	var surrender_btn: Button = _make_pause_btn(tr("PAUSEMENU_SURRENDER"), Color(0.48, 0.12, 0.08, 0.95), Color(0.65, 0.18, 0.10, 0.95))
	surrender_btn.pressed.connect(_on_surrender)
	vbox.add_child(surrender_btn)

	var quit_btn: Button = _make_pause_btn(tr("PAUSEMENU_QUIT"), Color(0.22, 0.10, 0.10, 0.95), Color(0.38, 0.15, 0.12, 0.95))
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_btn)

func _close_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
		_pause_menu = null
	if GameManager.state == GameManager.GameState.PAUSED:
		GameManager.toggle_pause()

func _on_save_game() -> void:
	_open_save_slot_picker()

func _open_save_slot_picker() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 0)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.12, 0.97)))
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("SAVE_PICKER_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	vbox.add_child(scroll)

	var slot_list: VBoxContainer = VBoxContainer.new()
	slot_list.add_theme_constant_override("separation", 6)
	slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(slot_list)

	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world == null:
		world = get_tree().current_scene

	var _rebuild_slots: Callable
	_rebuild_slots = func() -> void:
		if not is_instance_valid(slot_list):
			return
		for c: Node in slot_list.get_children():
			c.queue_free()
		# "New save" row
		var new_row: HBoxContainer = HBoxContainer.new()
		new_row.add_theme_constant_override("separation", 6)
		slot_list.add_child(new_row)
		var new_btn: Button = Button.new()
		new_btn.text = tr("SAVE_NEW_SLOT")
		new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		new_btn.focus_mode = Control.FOCUS_NONE
		new_btn.add_theme_font_size_override("font_size", 19)
		new_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.16, 0.30, 0.16, 0.95)))
		new_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.24, 0.46, 0.24, 0.95)))
		new_row.add_child(new_btn)
		new_btn.pressed.connect(func() -> void:
			var ok: bool = SaveManager.save_game(world, -1)
			overlay.queue_free()
			_close_pause_menu()
			_show_save_notification(ok)
		)
		# Existing slots
		var saves: Array[Dictionary] = SaveManager.list_saves()
		for meta: Dictionary in saves:
			var slot: int = meta.get("slot", 0) as int
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			slot_list.add_child(row)
			var slot_btn: Button = Button.new()
			slot_btn.text = _format_save_label(meta)
			slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot_btn.focus_mode = Control.FOCUS_NONE
			slot_btn.add_theme_font_size_override("font_size", 18)
			slot_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.16, 0.20, 0.32, 0.95)))
			slot_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.24, 0.32, 0.50, 0.95)))
			row.add_child(slot_btn)
			var captured_slot: int = slot
			slot_btn.pressed.connect(func() -> void:
				var ok: bool = SaveManager.save_game(world, captured_slot)
				overlay.queue_free()
				_close_pause_menu()
				_show_save_notification(ok)
			)
			var del_btn: Button = Button.new()
			del_btn.text = tr("SAVE_DELETE")
			del_btn.custom_minimum_size = Vector2(36, 0)
			del_btn.focus_mode = Control.FOCUS_NONE
			del_btn.add_theme_font_size_override("font_size", 18)
			del_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.38, 0.10, 0.10, 0.95)))
			del_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.60, 0.15, 0.15, 0.95)))
			row.add_child(del_btn)
			del_btn.pressed.connect(func() -> void:
				SaveManager.delete_save(captured_slot)
				if is_instance_valid(slot_list) and slot_list.has_meta("rebuild"):
					(slot_list.get_meta("rebuild") as Callable).call()
			)

	slot_list.set_meta("rebuild", _rebuild_slots)
	_rebuild_slots.call()

	vbox.add_child(HSeparator.new())
	var cancel_btn: Button = _make_pause_btn(tr("SAVE_CANCEL"), Color(0.22, 0.10, 0.10, 0.95), Color(0.38, 0.15, 0.12, 0.95))
	cancel_btn.pressed.connect(func() -> void: overlay.queue_free())
	vbox.add_child(cancel_btn)

func _format_save_label(meta: Dictionary) -> String:
	var name: String = str(meta.get("display_name", ""))
	if name.is_empty():
		var civ: String = str(meta.get("civ", "?")).capitalize()
		var ts: int = meta.get("timestamp", 0) as int
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
		name = "%s — %02d/%02d %02d:%02d" % [civ,
			dt.get("day", 0), dt.get("month", 0),
			dt.get("hour", 0), dt.get("minute", 0)]
	return name

func _show_save_notification(success: bool) -> void:
	var lbl: Label = Label.new()
	lbl.text = tr("SAVE_SUCCESS") if success else tr("SAVE_FAILED")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color",
		Color(0.4, 1.0, 0.5) if success else Color(1.0, 0.4, 0.4))
	lbl.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 150.0, 80.0)
	lbl.custom_minimum_size = Vector2(300.0, 0.0)
	add_child(lbl)
	var tw: Tween = create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free()
	)

func _open_ingame_settings() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.12, 0.97)))
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("SETTINGS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Music
	var music_lbl: Label = Label.new()
	music_lbl.text = tr("SETTINGS_MUSIC")
	music_lbl.add_theme_font_size_override("font_size", 19)
	music_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(music_lbl)
	var music_slider: HSlider = _make_settings_slider(GameSettings.music_volume)
	vbox.add_child(music_slider)
	var music_pct: Label = _make_settings_pct_label(GameSettings.music_volume)
	vbox.add_child(music_pct)
	music_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.music_volume = v
		music_pct.text = "%d%%" % int(v * 100.0)
		AudioManager.apply_settings()
	)

	# SFX
	var sfx_lbl: Label = Label.new()
	sfx_lbl.text = tr("SETTINGS_SFX")
	sfx_lbl.add_theme_font_size_override("font_size", 19)
	sfx_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(sfx_lbl)
	var sfx_slider: HSlider = _make_settings_slider(GameSettings.sfx_volume)
	vbox.add_child(sfx_slider)
	var sfx_pct: Label = _make_settings_pct_label(GameSettings.sfx_volume)
	vbox.add_child(sfx_pct)
	sfx_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.sfx_volume = v
		sfx_pct.text = "%d%%" % int(v * 100.0)
		AudioManager.apply_settings()
	)

	vbox.add_child(HSeparator.new())

	# Language
	var lang_lbl: Label = Label.new()
	lang_lbl.text = tr("SETTINGS_LANGUAGE")
	lang_lbl.add_theme_font_size_override("font_size", 19)
	lang_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(lang_lbl)
	var lang_row: HBoxContainer = HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vbox.add_child(lang_row)
	var lang_codes: Array[String] = ["en", "es"]
	var lang_names: Array[String] = ["English", "Español"]
	var lang_btns: Array[Button] = []
	for li: int in range(2):
		var lb: Button = Button.new()
		lb.text = lang_names[li]
		lb.custom_minimum_size = Vector2(100, 36)
		lb.focus_mode = Control.FOCUS_NONE
		lb.add_theme_font_size_override("font_size", 19)
		lang_row.add_child(lb)
		lang_btns.append(lb)
	var refresh_lang: Callable = func() -> void:
		for li: int in range(2):
			var active: bool = GameSettings.language == lang_codes[li]
			var sl: StyleBoxFlat = _make_panel_style(Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.18, 0.18, 0.22, 0.9))
			lang_btns[li].add_theme_stylebox_override("normal", sl)
			lang_btns[li].add_theme_stylebox_override("pressed", sl)
	refresh_lang.call()
	for li: int in range(2):
		var captured_li: int = li
		lang_btns[li].pressed.connect(func() -> void:
			GameSettings.language = lang_codes[captured_li]
			GameSettings.apply_language()
			GameSettings.save_settings()
			refresh_lang.call()
		)

	vbox.add_child(HSeparator.new())

	# Zoom
	var zoom_lbl: Label = Label.new()
	zoom_lbl.text = "Zoom"
	zoom_lbl.add_theme_font_size_override("font_size", 19)
	zoom_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(zoom_lbl)
	var worlds: Array = get_tree().get_nodes_in_group("world")
	var initial_zoom: float = 1.0
	if not worlds.is_empty():
		initial_zoom = (worlds[0] as Node).call("get_zoom") as float
	var zoom_slider: HSlider = HSlider.new()
	zoom_slider.min_value = 0.5
	zoom_slider.max_value = 2.0
	zoom_slider.step = 0.1
	zoom_slider.value = initial_zoom
	zoom_slider.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(zoom_slider)
	var zoom_pct: Label = Label.new()
	zoom_pct.text = "%d%%" % int(initial_zoom * 100.0)
	zoom_pct.add_theme_font_size_override("font_size", 15)
	zoom_pct.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	vbox.add_child(zoom_pct)
	zoom_slider.value_changed.connect(func(v: float) -> void:
		zoom_pct.text = "%d%%" % int(v * 100.0)
		if not worlds.is_empty():
			(worlds[0] as Node).call("set_zoom", v)
	)

	vbox.add_child(HSeparator.new())

	var ctrl_lbl: Label = Label.new()
	ctrl_lbl.text = tr("SETTINGS_CONTROLS")
	ctrl_lbl.add_theme_font_size_override("font_size", 19)
	ctrl_lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(ctrl_lbl)

	var dpad_row: Button = _make_toggle_row(vbox, tr("SETTINGS_SHOW_DPAD"), GameSettings.show_dpad)
	dpad_row.pressed.connect(func() -> void:
		GameSettings.show_dpad = not GameSettings.show_dpad
		_style_toggle_btn(dpad_row, GameSettings.show_dpad)
		if is_instance_valid(_dpad):
			_dpad.visible = GameSettings.show_dpad
	)

	var edge_row: Button = _make_toggle_row(vbox, tr("SETTINGS_EDGE_SCROLL"), GameSettings.edge_scroll_enabled)
	edge_row.pressed.connect(func() -> void:
		GameSettings.edge_scroll_enabled = not GameSettings.edge_scroll_enabled
		_style_toggle_btn(edge_row, GameSettings.edge_scroll_enabled)
	)

	vbox.add_child(HSeparator.new())

	var close_btn: Button = Button.new()
	close_btn.text = tr("SETTINGS_SAVE")
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.20, 0.35, 0.55, 0.95)))
	close_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.30, 0.50, 0.75, 0.95)))
	vbox.add_child(close_btn)
	close_btn.pressed.connect(func() -> void:
		GameSettings.save_settings()
		overlay.queue_free()
	)

func _make_toggle_row(parent: VBoxContainer, label_text: String, initial: bool) -> Button:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	row.add_child(lbl)
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(72, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	_style_toggle_btn(btn, initial)
	row.add_child(btn)
	return btn

func _style_toggle_btn(btn: Button, active: bool) -> void:
	btn.text = tr("SETTINGS_ON") if active else tr("SETTINGS_OFF")
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.22, 0.45, 0.22, 0.95) if active else Color(0.35, 0.12, 0.12, 0.92)
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate() as StyleBoxFlat
	sh.bg_color = s.bg_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)

func _make_settings_slider(initial: float) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = initial
	s.custom_minimum_size = Vector2(0, 24)
	return s

func _make_settings_pct_label(initial: float) -> Label:
	var lbl: Label = Label.new()
	lbl.text = "%d%%" % int(initial * 100.0)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	return lbl

func _on_surrender() -> void:
	_close_pause_menu()
	GameManager.declare_winner(1)

func _make_pause_btn(label_text: String, normal_col: Color, hover_col: Color) -> Button:
	var btn: Button = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(240, 42)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("normal", _make_panel_style(normal_col))
	var hs: StyleBoxFlat = _make_panel_style(hover_col)
	btn.add_theme_stylebox_override("hover", hs)
	return btn

func _filtered_build_actions() -> Array:
	var current_age: int = AgeManager.get_age(local_player_id)
	var wonder_visible: bool = MatchConfig.victory_mode == MatchConfig.VictoryMode.WONDER \
		and current_age >= GameManager.Age.IMPERIAL
	var is_tutorial: bool = _tutorial_gates_active

	# Collect which build ids are unlocked so far in tutorial
	var unlocked: Array[String] = []
	if is_tutorial:
		for step_key: Variant in _TUTORIAL_BUILD_UNLOCK:
			if _tutorial_step >= (step_key as int):
				for bid: Variant in (_TUTORIAL_BUILD_UNLOCK[step_key] as Array):
					unlocked.append(bid as String)

	var result: Array = []
	for entry: Variant in BUILD_ACTIONS:
		var data: Dictionary = entry as Dictionary
		var bid: String = data.get("id", "") as String
		if bid == "back":
			result.append(data)
			continue
		# Wonder only shown in wonder-victory games at Imperial age
		if bid == "build:wonder" and not wonder_visible:
			continue
		# Hide buildings that require a higher age than the player currently has
		var min_age: int = data.get("min_age", 0) as int
		if current_age < min_age:
			continue
		# In tutorial, lock buildings not yet introduced
		if is_tutorial and _tutorial_step < 7 and bid not in unlocked:
			result.append(data.merged({"locked": true}, true))
		else:
			result.append(data)
	return result

func _apply_tutorial_villager_gates() -> void:
	if not _tutorial_gates_active:
		return
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id == "build_menu" and _tutorial_step < 3:
			btn.disabled = true
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color(0.25, 0.25, 0.25)
			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)

func show_wonder_timer(owner_pid: int) -> void:
	if not is_instance_valid(_wonder_label):
		_wonder_label = Label.new()
		_wonder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wonder_label.add_theme_font_size_override("font_size", 26)
		_wonder_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.20))
		_wonder_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_wonder_label.offset_top = 8.0
		_wonder_label.offset_bottom = 40.0
		add_child(_wonder_label)
	var who: String = tr("WONDER_TIMER_YOU") if owner_pid == 0 else tr("WONDER_TIMER_ENEMY")
	_wonder_label.text = who + " — 4:00"

func hide_wonder_timer() -> void:
	if is_instance_valid(_wonder_label):
		_wonder_label.queue_free()
		_wonder_label = null

func update_wonder_timer(seconds_left: float) -> void:
	if not is_instance_valid(_wonder_label):
		return
	var mins: int = int(seconds_left) / 60
	var secs: int = int(seconds_left) % 60
	_wonder_label.text = _wonder_label.text.split(" — ")[0] + " — %d:%02d" % [mins, secs]

# ── Weather HUD ───────────────────────────────────────────────────────────────

# Banner: big centered announcement that fades out after a few seconds
var _weather_banner: Label = null
var _weather_banner_tween: Tween = null

# Persistent pill: small label under the top bar showing name + countdown
var _weather_pill: Label = null

const WEATHER_LABELS: Dictionary = {
	"calima":          "☁ Calima",
	"atlantic_storm":  "⛈ Tormenta atlántica",
	"sea_fog":         "🌫 Niebla marina",
	"trade_winds":     "💨 Vientos alisios",
	"volcanic_ash":    "🌋 Ceniza volcánica",
}

const WEATHER_COLORS: Dictionary = {
	"calima":          Color(0.85, 0.62, 0.18),
	"atlantic_storm":  Color(0.35, 0.55, 0.80),
	"sea_fog":         Color(0.70, 0.80, 0.88),
	"trade_winds":     Color(0.55, 0.80, 0.95),
	"volcanic_ash":    Color(0.55, 0.40, 0.30),
}

func show_weather(weather_id: String) -> void:
	var text: String = WEATHER_LABELS.get(weather_id, weather_id) as String
	var color: Color = WEATHER_COLORS.get(weather_id, Color.WHITE) as Color

	# CanvasLayer children must be positioned with absolute px coords, not anchors.
	# --- announcement banner: full-width, centred vertically at ~130 px from top ---
	if not is_instance_valid(_weather_banner):
		_weather_banner = Label.new()
		_weather_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_weather_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_weather_banner.add_theme_font_size_override("font_size", 36)
		_weather_banner.position = Vector2(0.0, 110.0)
		_weather_banner.size = Vector2(1920.0, 60.0)
		_weather_banner.modulate.a = 0.0
		add_child(_weather_banner)
	_weather_banner.text = text
	_weather_banner.add_theme_color_override("font_color", color)
	if is_instance_valid(_weather_banner_tween):
		_weather_banner_tween.kill()
	_weather_banner_tween = create_tween()
	_weather_banner_tween.tween_property(_weather_banner, "modulate:a", 1.0, 0.5)
	_weather_banner_tween.tween_interval(3.0)
	_weather_banner_tween.tween_property(_weather_banner, "modulate:a", 0.0, 1.2)

	# --- persistent pill: just below the top bar (~44 px) ---
	if not is_instance_valid(_weather_pill):
		_weather_pill = Label.new()
		_weather_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_weather_pill.add_theme_font_size_override("font_size", 15)
		_weather_pill.position = Vector2(0.0, 44.0)
		_weather_pill.size = Vector2(1920.0, 22.0)
		_weather_pill.modulate.a = 0.0
		add_child(_weather_pill)
	_weather_pill.add_theme_color_override("font_color", color)
	var tw: Tween = create_tween()
	tw.tween_property(_weather_pill, "modulate:a", 1.0, 0.8)

func hide_weather() -> void:
	# Banner: kill any pending tween and hide immediately (it may already be fading)
	if is_instance_valid(_weather_banner):
		if is_instance_valid(_weather_banner_tween):
			_weather_banner_tween.kill()
		var tw_b: Tween = create_tween()
		tw_b.tween_property(_weather_banner, "modulate:a", 0.0, 0.6)
		tw_b.tween_callback(func() -> void:
			if is_instance_valid(_weather_banner):
				_weather_banner.queue_free()
				_weather_banner = null)

	# Pill: fade out then free
	if is_instance_valid(_weather_pill):
		var tw_p: Tween = create_tween()
		tw_p.tween_property(_weather_pill, "modulate:a", 0.0, 1.5)
		tw_p.tween_callback(func() -> void:
			if is_instance_valid(_weather_pill):
				_weather_pill.queue_free()
				_weather_pill = null)

func _update_weather_pill() -> void:
	if not is_instance_valid(_weather_pill):
		return
	var secs: float = WeatherManager.get_remaining_seconds()
	if secs <= 0.0:
		return
	var mins: int = int(secs) / 60
	var s: int = int(secs) % 60
	var name_text: String = WEATHER_LABELS.get(WeatherManager.get_weather_id(), "") as String
	_weather_pill.text = "%s  %d:%02d" % [name_text, mins, s]

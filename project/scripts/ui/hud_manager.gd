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

## Destroy shows a skull for units and a crumbling building for structures.
const DESTROY_ACTION: Dictionary = {"id": "destroy", "label": "ACTION_DESTROY", "glyph": "destroy_unit", "cost": {}, "key": KEY_DELETE, "description": "TOOLTIP_DESTROY"}
const DESTROY_BUILDING_ACTION: Dictionary = {"id": "destroy", "label": "ACTION_DESTROY", "glyph": "destroy", "cost": {}, "key": KEY_DELETE, "description": "TOOLTIP_DESTROY"}

## Command id -> UiIcons glyph. Entity actions (train:/build:/market:hire:)
## use IconBaker miniatures instead; anything else falls back to a short
## text abbreviation. Per-action dicts may override with a "glyph" key.
const ACTION_GLYPHS: Dictionary = {
	"gather_wood": "gather_wood",
	"gather_gold": "gather_gold",
	"gather_stone": "gather_stone",
	"gather_food": "gather_food",
	"build_menu": "build",
	"repair": "repair",
	"move_to": "move",
	"stop": "stop",
	"attack_move": "attack",
	"attack_ground": "attack_ground",
	"cover_fire": "cover_fire",
	"show_path": "patrol_route",
	"scout_explore": "patrol_route",
	"scout_explore_stop": "patrol_route",
	"advance_age": "age_up",
	"hero_ability": "ability",
	"unload": "unload",
	"ungarrison": "unload",
	"garrison_into": "garrison_into",
	"town_bell": "town_bell",
	"stance:aggressive": "stance_aggressive",
	"stance:defensive": "stance_defensive",
	"stance:stand_ground": "stance_stand_ground",
	"stance:passive": "stance_passive",
	"formation:line": "formation_line",
	"formation:box": "formation_box",
	"formation:spread": "formation_spread",
	"formation:rings": "formation_rings",
	"back": "page_prev",
	"gate_lock": "gate_lock",
}

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "ACTION_WOOD",         "color": Color(0.20, 0.55, 0.15), "cost": {}, "key": KEY_C, "description": "TOOLTIP_GATHER_WOOD"},
	{"id": "gather_gold",  "label": "ACTION_GOLD",         "color": Color(0.75, 0.65, 0.10), "cost": {}, "key": KEY_G, "description": "TOOLTIP_GATHER_GOLD"},
	{"id": "gather_stone", "label": "ACTION_STONE",        "color": Color(0.55, 0.55, 0.55), "cost": {}, "key": KEY_T, "description": "TOOLTIP_GATHER_STONE"},
	{"id": "gather_food",  "label": "ACTION_FOOD",         "color": Color(0.60, 0.20, 0.15), "cost": {}, "key": KEY_H, "description": "TOOLTIP_GATHER_FOOD"},
	{"id": "build_menu",   "label": "ACTION_BUILD",        "color": Color(0.20, 0.30, 0.60), "cost": {}, "key": KEY_B, "description": "TOOLTIP_BUILD_MENU"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",      "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE",  "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "stop",         "label": "ACTION_STOP",         "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	{"id": "garrison_into", "label": "ACTION_GARRISON",    "color": Color(0.45, 0.38, 0.20), "cost": {}, "key": KEY_E, "description": "TOOLTIP_GARRISON"},
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
	{"id": "town_bell", "label": "ACTION_TOWN_BELL", "color": Color(0.70, 0.55, 0.15), "cost": {}, "key": KEY_G, "description": "TOOLTIP_TOWN_BELL"},
]

const UNIT_ACTIONS: Array = [
	{"id": "move_to",      "label": "ACTION_MOVE_TO",      "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE",  "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "stop",         "label": "ACTION_STOP",         "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	{"id": "show_path",    "label": "ACTION_SHOW_PATH",    "color": Color(0.15, 0.45, 0.55), "cost": {}, "key": KEY_P, "description": "TOOLTIP_SHOW_PATH"},
	DESTROY_ACTION,
]

const RANGED_ACTIONS: Array = [
	{"id": "cover_fire",   "label": "ACTION_COVER_FIRE",  "color": Color(0.60, 0.45, 0.10), "cost": {}, "key": KEY_C, "description": "TOOLTIP_COVER_FIRE"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "stop",         "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	DESTROY_ACTION,
]

const SIEGE_ACTIONS: Array = [
	{"id": "cover_fire",   "label": "ACTION_COVER_FIRE",  "color": Color(0.65, 0.40, 0.08), "cost": {}, "key": KEY_C, "description": "TOOLTIP_COVER_FIRE"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "stop",         "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	DESTROY_ACTION,
]

const ANIMAL_ACTIONS: Array = [
	{"id": "move_to", "label": "ACTION_MOVE_TO", "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
]

## AoE2 stances + formations, appended to every military selection. Stances
## submit a command per selected unit; the formation buttons only set which
## layout the NEXT group move fans out into (local UI state).
const COMBAT_MODE_ACTIONS: Array = [
	{"id": "stance:aggressive",   "label": "ACTION_STANCE_AGGRESSIVE",   "color": Color(0.55, 0.16, 0.10), "cost": {}, "description": "TOOLTIP_STANCE_AGGRESSIVE"},
	{"id": "stance:defensive",    "label": "ACTION_STANCE_DEFENSIVE",    "color": Color(0.16, 0.35, 0.55), "cost": {}, "description": "TOOLTIP_STANCE_DEFENSIVE"},
	{"id": "stance:stand_ground", "label": "ACTION_STANCE_STAND_GROUND", "color": Color(0.35, 0.32, 0.18), "cost": {}, "description": "TOOLTIP_STANCE_STAND_GROUND"},
	{"id": "stance:passive",      "label": "ACTION_STANCE_PASSIVE",      "color": Color(0.30, 0.30, 0.34), "cost": {}, "description": "TOOLTIP_STANCE_PASSIVE"},
	{"id": "formation:line",   "label": "ACTION_FORMATION_LINE",   "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_LINE"},
	{"id": "formation:box",    "label": "ACTION_FORMATION_BOX",    "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_BOX"},
	{"id": "formation:spread", "label": "ACTION_FORMATION_SPREAD", "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_SPREAD"},
	{"id": "formation:rings",  "label": "ACTION_FORMATION_RINGS",  "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_RINGS"},
]

const TRANSPORT_ACTIONS: Array = [
	{"id": "unload",  "label": "UI_UNLOAD",      "color": Color(0.20, 0.45, 0.65), "cost": {}, "key": KEY_U, "description": "TOOLTIP_UNLOAD"},
	{"id": "stop",    "label": "ACTION_STOP",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	DESTROY_ACTION,
]

const BUILDING_ACTIONS: Array = [
	DESTROY_BUILDING_ACTION,
]

const DOCK_UNIT_DEFS: Array = [
	{"id": "fishing_boat",   "label": "ACTION_FISHING_BOAT",   "color": Color(0.20, 0.50, 0.65), "cost": {"wood": 75},            "age": 0, "description": "TOOLTIP_FISHING_BOAT"},
	{"id": "transport_ship", "label": "ACTION_TRANSPORT_SHIP", "color": Color(0.55, 0.45, 0.20), "cost": {"wood": 125},           "age": 1, "description": "TOOLTIP_TRANSPORT_SHIP"},
	{"id": "war_galley",     "label": "ACTION_WAR_GALLEY",     "color": Color(0.65, 0.18, 0.18), "cost": {"wood": 75, "gold": 35}, "age": 1, "description": "TOOLTIP_WAR_GALLEY"},
]

const GATE_ACTIONS: Array = [
	{"id": "gate_lock", "label": "UI_GATE_LOCK", "cost": {}, "key": KEY_O, "description": "TOOLTIP_GATE_LOCK"},
	DESTROY_BUILDING_ACTION,
]

var _mercenary_cooldown_refresh_timer: float = 0.0
var _in_build_menu: bool = false
var _selected_building: Node = null
var _selected_unit: Node = null   # tracked for transport garrison refresh
var _hp_bar_unit: Node = null     # unit/building whose HP drives the main HP bar
var _hp_bar_max: float = 100.0    # cached max HP for the current hp_bar_unit
var _hp_text: Label = null        # numeric "450 / 550" overlay on the HP bar
var _status_unit: Node = null
var _active_actions: Array = []
var _follow_btn: Button = null
var _following: bool = false
var _pending_action: String = ""  # action waiting for a map click
var _age_advance_bar: ProgressBar = null
var _hero_respawn_bar: ProgressBar = null
var _hero_respawn_label: Label = null
var _research_bar: ProgressBar = null
var _research_label: Label = null
var _menus: HudMenus = null
var _controls: HudControls = null
var _wonder_label: Label = null
var _hero_alert_overlay: ColorRect = null
var _weather: HudWeather = null
var _match_stats: HudMatchStats = null
var _resource_bar: HudResourceBar = null
var _hero_widget: HudHeroWidget = null
var _detail_panel: VBoxContainer = null
var _stats_row: HBoxContainer = null    # compact stat chips for a single-selected unit
var _stats_unit: Node = null
var _stat_labels: Dictionary = {}       # stat id -> Label inside _stats_row
var _carry_chip: HBoxContainer = null
var _carry_icon: TextureRect = null
var _stats_timer: float = 0.0

const DETAIL_PANEL_PATH: String = "HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow/UnitDetailPanel"
const STATS_REFRESH_INTERVAL: float = 0.5
const RESOURCE_DISPLAY_NAMES: Dictionary = {
	"food": "Food", "wood": "Wood", "gold": "Gold", "stone": "Stone",
}

const ACTION_COLS: int = 5
const ACTION_ROWS: int = 2
const PAGE_SIZE: int = ACTION_COLS * ACTION_ROWS  # 10
var _action_page: int = 0
var _page_prev_btn: ActionButton = null
var _page_next_btn: ActionButton = null

func _ready() -> void:
	local_player_id = NetworkSession.local_player_id
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.resource_changed.connect(_on_resource_changed)
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
	EventBus.camera_follow_cancelled.connect(func() -> void: _set_follow_active(false))
	EventBus.hero_respawned.connect(_on_hero_respawned)
	EventBus.hero_low_hp.connect(_on_hero_low_hp)
	EventBus.garrison_changed.connect(_on_garrison_changed)
	EventBus.research_state_changed.connect(_on_research_state_changed)
	EventBus.market_rate_changed.connect(_on_market_rate_changed)
	EventBus.mercenary_hired.connect(_on_mercenary_hired)
	EventBus.building_construction_complete.connect(_on_building_construction_complete)
	_pause_overlay.visible = false
	_clock_label.text = "00:00"
	_unit_name_label.text = ""
	_unit_hp_bar.value = 0.0
	_resource_bar = HudResourceBar.new()
	_resource_bar.init(local_player_id, _food_display, _wood_display, _gold_display,
		_stone_display, _population_label, _age_label)
	add_child(_resource_bar)
	_controls = HudControls.new()
	_controls.init(local_player_id, get_node("HUDRoot"))
	add_child(_controls)
	_hero_widget = HudHeroWidget.new()
	_hero_widget.init(local_player_id, get_node("HUDRoot"))
	add_child(_hero_widget)
	var control_groups: HudControlGroups = HudControlGroups.new()
	control_groups.init(local_player_id, get_node("HUDRoot"))
	add_child(control_groups)
	_menus = HudMenus.new()
	_menus.init(
		_start_tutorial,
		func() -> bool: return _tutorial_overlay != null and is_instance_valid(_tutorial_overlay),
		func(visible: bool) -> void: _controls.set_dpad_visible(visible))
	add_child(_menus)
	_detail_panel = get_node_or_null(DETAIL_PANEL_PATH) as VBoxContainer
	_build_follow_button()
	_build_notifications()
	_build_pause_menu_button()
	_weather = HudWeather.new()
	add_child(_weather)
	_match_stats = HudMatchStats.new()
	_match_stats.init(local_player_id, _clock_label, get_node("HUDRoot"))
	add_child(_match_stats)
	if NetworkSession.is_online():
		var chat: HudChat = HudChat.new()
		chat.init(get_node("HUDRoot"))
		add_child(chat)
	_style_command_bar()

func _style_command_bar() -> void:
	var bottom_bar: PanelContainer = get_node_or_null("HUDRoot/BottomBar") as PanelContainer
	if bottom_bar != null:
		bottom_bar.add_theme_stylebox_override("panel", HudStyle.command_bar())
		HudStyle.add_top_sheen(bottom_bar)
	var selection_panel: Panel = get_node_or_null(
		"HUDRoot/BottomBar/BottomLayout/SelectionPanel") as Panel
	if selection_panel != null:
		selection_panel.add_theme_stylebox_override("panel", HudStyle.command_well())

## Maps an entity-creating action to the scene it spawns; icons come from
## rendering that real scene (IconBaker), so they follow the player's civ style.
func _action_icon_scene(action_id: String) -> String:
	var path: String = ""
	if action_id.begins_with("train:"):
		path = "res://scenes/units/%s.tscn" % action_id.trim_prefix("train:")
	elif action_id.begins_with("build:"):
		path = "res://scenes/buildings/%s.tscn" % action_id.trim_prefix("build:")
	elif action_id.begins_with("market:hire:"):
		path = "res://scenes/units/%s.tscn" % action_id.trim_prefix("market:hire:")
	else:
		return ""
	return path if ResourceLoader.exists(path) else ""

## Thin accent edge colour by action category: economy green, combat red,
## production gold, everything else utility blue.
func _accent_for_action(action_id: String) -> Color:
	if action_id.begins_with("market:hire:") or action_id.begins_with("train:") \
			or action_id.begins_with("research:") or action_id == "advance_age":
		return HudStyle.ACCENT_PRODUCTION
	if action_id.begins_with("gather_") or action_id.begins_with("build") \
			or action_id.begins_with("market:") or action_id == "repair":
		return HudStyle.ACCENT_ECONOMY
	if action_id in ["attack_move", "attack_ground", "cover_fire", "stop",
			"destroy", "hero_ability"]:
		return HudStyle.ACCENT_COMBAT
	return HudStyle.ACCENT_UTILITY

## Short fallback code for glyph-less actions: word initials, or the first
## three letters of a single-word name. The full name lives in the tooltip.
func _abbreviate(title: String) -> String:
	var words: PackedStringArray = title.strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return words[0].substr(0, 3).to_upper()
	var abbr: String = ""
	for w: String in words.slice(0, 3):
		abbr += w.substr(0, 1).to_upper()
	return abbr

func _process(delta: float) -> void:
	if MatchConfig.player_civ_id == "fenicios" and is_instance_valid(_selected_building) and _selected_building is Market:
		_mercenary_cooldown_refresh_timer += delta
		if _mercenary_cooldown_refresh_timer >= 1.0:
			_mercenary_cooldown_refresh_timer = 0.0
			_populate_market_actions(_selected_building as Market)
	if is_instance_valid(_status_unit):
		_unit_status_label.text = _get_unit_status(_status_unit)
	_stats_timer += delta
	if _stats_timer >= STATS_REFRESH_INTERVAL:
		_stats_timer = 0.0
		_refresh_stats_row()
	_poll_hp_bars()
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
				if cd_frac <= 0.0:
					btn.set_badge("")
					btn.modulate = Color(1.0, 1.0, 1.0)
				else:
					var cd_secs: int = int(udata.hero_ability_cooldown * cd_frac)
					btn.set_badge("%ds" % cd_secs)
					btn.modulate = Color(0.65, 0.65, 0.65)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		if _menus.is_pause_open():
			_menus.close_pause_menu()
		else:
			_menus.open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _active_actions.is_empty():
		return
	for entry: Variant in _active_actions:
		var data: Dictionary = entry as Dictionary
		var mapped: int = data.get("key", -1) as int
		# macOS keyboards: the big "delete" key is BACKSPACE (KEY_DELETE is
		# fn+delete) — without the alias the destroy hotkey was dead on Mac.
		var is_match: bool = mapped == key.keycode or mapped == key.physical_keycode \
			or (mapped == KEY_DELETE and (key.keycode == KEY_BACKSPACE
				or key.physical_keycode == KEY_BACKSPACE))
		if is_match:
			_on_action_button_pressed(data["id"] as String)
			get_viewport().set_input_as_handled()
			return

func update_resources(player_id: int, resources: Dictionary) -> void:
	_resource_bar.update_resources(player_id, resources)

## queue_free'd children still occupy container layout for the rest of the
## frame; detach first so stale rows can never inflate the band's minimum size.
func _free_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func update_selection(units: Array) -> void:
	cancel_pending()
	_free_children(_unit_portraits_grid)
	_clear_action_buttons()
	_clear_stats_row()
	_in_build_menu = false

	if units.is_empty():
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		_unit_status_label.text = ""
		_status_unit = null
		_hp_bar_unit = null
		return

	var capped: Array = units.slice(0, 40)
	var compact: bool = capped.size() > 10
	_unit_portraits_grid.columns = 20 if compact else 10
	for unit: Variant in capped:
		if not is_instance_valid(unit):
			continue
		var portrait: UnitPortrait = UnitPortrait.new()
		portrait.compact = compact
		_unit_portraits_grid.add_child(portrait)
		portrait.setup(unit)

	var first: Node = capped[0]
	if is_instance_valid(first):
		var display_name: String = tr("UI_UNIT")
		var unit_data: Variant = first.get("unit_data")
		if unit_data != null:
			var name_val: String = EntityNames.unit_name(unit_data as Resource)
			if not name_val.is_empty():
				display_name = name_val
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
			_hp_bar_unit = first
			_hp_bar_max = max_hp

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
		elif first is Mangonel:
			_populate_buttons(SIEGE_ACTIONS + COMBAT_MODE_ACTIONS)
		elif first is Archer or first is Longbowman:
			_populate_buttons(RANGED_ACTIONS + COMBAT_MODE_ACTIONS)
		elif first is Scout:
			_populate_scout_buttons(first as Scout)
		elif first.has_method("order_gather"):
			_populate_buttons(VILLAGER_ACTIONS)
			_apply_tutorial_villager_gates()
		else:
			_populate_buttons(UNIT_ACTIONS + COMBAT_MODE_ACTIONS)

		if capped.size() == 1 and unit_data != null:
			_build_stats_row(first)

func update_age(age: int) -> void:
	_resource_bar.update_age(age)

func toggle_pause(is_paused: bool) -> void:
	_pause_overlay.visible = is_paused

# --- Private ---

func _clear_action_buttons() -> void:
	_active_actions = []
	_action_page = 0
	_free_children(_action_grid)
	_free_children(_train_queue_row)
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
	_free_children(_action_grid)
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
		btn.action_id = data["id"] as String
		var key_int: int = data.get("key", -1) as int
		var key_hint: String = _key_label(key_int) if key_int > 0 else ""
		var raw: bool = data.get("raw_label", false) as bool
		var translated_label: String = (data["label"] as String) if raw else tr(data["label"] as String)
		var lines: PackedStringArray = translated_label.split("\n")
		var title: String = lines[0].strip_edges()
		var extra: String = " ".join(lines.slice(1)).strip_edges() if lines.size() > 1 else ""
		var cost: Dictionary = data.get("cost", {}) as Dictionary
		btn.set_meta("cost", cost)
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(local_player_id, cost)
		var locked: bool = (data.get("locked", false) as bool) \
			or (btn.action_id == "destroy" and _tutorial_gates_active)
		btn.set_meta("locked", locked)
		btn.set_hotkey(key_hint)
		btn.set_accent(_accent_for_action(btn.action_id))
		# Icon-first button: full name, hotkey, costs and description live here.
		var tooltip: String = title if key_hint.is_empty() else "%s  [%s]" % [title, key_hint]
		# Raw "500F 175W" cost tokens are replaced by the hover cost strip plus a
		# readable plain-text line (accessibility fallback); other extras stay.
		if not extra.is_empty() and not _is_cost_tokens(extra):
			tooltip += "\n" + extra
		var desc: String = data.get("description", "") as String
		if not desc.is_empty():
			tooltip += "\n" + tr(desc)
		btn.tooltip_text = tooltip
		# Costs render as a glyph row inside the button's own tooltip popup
		# (ActionButton._make_custom_tooltip).
		btn.action_costs = cost
		var icon_scene: String = _action_icon_scene(btn.action_id)
		var glyph: String = data.get("glyph", ACTION_GLYPHS.get(btn.action_id, "")) as String
		if not icon_scene.is_empty():
			btn.set_entity_icon(IconBaker.get_icon(icon_scene, local_player_id))
		elif not glyph.is_empty():
			btn.set_glyph(UiIcons.get_icon(glyph))
		else:
			btn.set_abbreviation(data.get("abbr", _abbreviate(title)) as String)
		var badge: String = data.get("badge", "") as String
		if not badge.is_empty():
			btn.set_badge(badge)
		var is_upgrade: bool = data.get("is_upgrade", false) as bool
		btn.set_meta("is_upgrade", is_upgrade)
		btn.set_upgrade(is_upgrade)
		var toggled: bool = data.get("active", false) as bool
		btn.set_meta("toggled", toggled)
		btn.set_active(toggled)
		btn.set_enabled(can_pay and not locked)
		btn.action_pressed.connect(_on_action_button_pressed)
		_action_grid.add_child(btn)

	if needs_paging:
		# Pad so prev/next always land on the last two slots of the grid.
		var filled: int = page_actions.size()
		var spacers_needed: int = slots - filled
		for _i: int in range(maxi(0, spacers_needed)):
			var spacer: Control = Control.new()
			spacer.custom_minimum_size = ActionButton.BTN_SIZE
			_action_grid.add_child(spacer)

		var max_page: int = ceili(float(total) / float(slots)) - 1
		_page_prev_btn = _make_page_btn("page_prev")
		_page_prev_btn.set_enabled(_action_page > 0)
		_page_prev_btn.pressed.connect(func() -> void:
			_action_page = maxi(0, _action_page - 1)
			_render_action_page()
			_refresh_button_states())
		_action_grid.add_child(_page_prev_btn)

		_page_next_btn = _make_page_btn("page_next")
		_page_next_btn.set_enabled(_action_page < max_page)
		_page_next_btn.pressed.connect(func() -> void:
			_action_page = mini(_action_page + 1, max_page)
			_render_action_page()
			_refresh_button_states())
		_action_grid.add_child(_page_next_btn)
	_refresh_mode_highlights()

func _make_page_btn(glyph: String) -> ActionButton:
	var btn: ActionButton = ActionButton.new()
	btn.set_glyph(UiIcons.get_icon(glyph))
	btn.set_accent(HudStyle.ACCENT_UTILITY)
	btn.tooltip_text = tr("UI_PAGE_PREV") if glyph == "page_prev" else tr("UI_PAGE_NEXT")
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
		if btn == _page_prev_btn or btn == _page_next_btn:
			continue
		var cost: Dictionary = btn.get_meta("cost", {}) as Dictionary
		var is_train: bool = btn.action_id.begins_with("train:")
		var locked: bool = btn.get_meta("locked", false) as bool
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(local_player_id, cost)
		btn.set_enabled(can_pay and not locked and (not is_train or not queue_full))

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
	if action_id == "move_to" or action_id == "attack_move" or action_id == "cover_fire" \
			or action_id == "garrison_into":
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
	# The stance/formation state just changed synchronously during the emit;
	# re-light the toggle frames so the choice is visible immediately.
	if action_id.begins_with("stance:") or action_id.begins_with("formation:"):
		call_deferred("_refresh_mode_highlights")

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
			btn.set_meta("locked", true)
			btn.set_enabled(false)
			break

## Persistent feedback for the mode toggles: the current formation choice and
## the first selected unit's stance keep a lit frame on their button — before
## this, pressing Defensive or Box changed the simulation with zero visual echo.
func _refresh_mode_highlights() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var commands: Variant = world.get("_commands")
	var formation: String = ""
	if commands != null:
		formation = commands.get("_formation") as String
	var stance_id: String = _first_selected_stance(world)
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id.begins_with("formation:"):
			btn.set_active(btn.action_id.trim_prefix("formation:") == formation)
		elif btn.action_id.begins_with("stance:"):
			btn.set_active(btn.action_id.trim_prefix("stance:") == stance_id)

const STANCE_NAMES: Array[String] = ["aggressive", "defensive", "stand_ground", "passive"]

func _first_selected_stance(world: Node) -> String:
	var units: Variant = world.get("_selected_units")
	if units is Array and not (units as Array).is_empty():
		var unit: Variant = (units as Array)[0]
		if is_instance_valid(unit):
			var s: Variant = (unit as Node).get("stance")
			if s != null and (s as int) >= 0 and (s as int) < STANCE_NAMES.size():
				return STANCE_NAMES[s as int]
	return ""

func _highlight_pending_button(active_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var is_pending: bool = btn.action_id == active_id and not active_id.is_empty()
		# Persistent toggles (e.g. scout auto-explore) keep their lit frame.
		btn.set_active(is_pending or (btn.get_meta("toggled", false) as bool))

func _on_game_started() -> void:
	IconBaker.clear_cache()   # civ picks can change between matches
	_controls.set_game_speed(1)
	update_age(AgeManager.get_age(local_player_id))
	var starting: Dictionary = ResourceManager.get_resources(local_player_id)
	update_resources(local_player_id, starting)
	if MatchConfig.launch_tutorial:
		MatchConfig.launch_tutorial = false
		call_deferred("_start_tutorial")

func _on_resource_changed(player_id: int, _resource: String, _amount: int) -> void:
	# HudResourceBar updates the counters; the action menu only needs an
	# affordability refresh when the local player's stockpile changes.
	if player_id != local_player_id:
		return
	_refresh_button_states()

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
	_free_children(_unit_portraits_grid)
	_clear_action_buttons()
	_clear_stats_row()
	_in_build_menu = false

	_status_unit = null
	_hp_bar_unit = null
	if not is_instance_valid(building):
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		_unit_status_label.text = ""
		return

	var display_name: String = tr("UI_BUILDING")
	var bdata: Variant = building.get("building_data")
	if bdata != null:
		var dname: String = EntityNames.building_name(bdata as Resource)
		if not dname.is_empty():
			display_name = dname
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
		_hp_bar_unit = building
		_hp_bar_max = max_hp

	var bpid: Variant = building.get("player_id")
	if bpid != null and (bpid as int) != local_player_id:
		return

	var bstate: Variant = building.get("state")
	if bstate != null and (bstate as int) != BuildingBase.BuildingState.COMPLETE:
		_populate_buttons([DESTROY_BUILDING_ACTION])
		return

	if building.has_method("is_respawning_hero") or building is TownCenterBuildable:
		_unit_name_label.text = tr("UI_TOWN_CENTER")
		var tc_hp: Variant = building.get("health")
		var tc_max: Variant = building.get("max_health")
		if tc_hp != null and tc_max != null and (tc_max as float) > 0.0:
			_unit_hp_bar.value = ((tc_hp as float) / (tc_max as float)) * 100.0
			_hp_bar_unit = building
			_hp_bar_max = tc_max as float
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
	_refresh_garrison_ui(building)
	_refresh_research_slot()
	_append_group_count()

## "Cuartel  ×4" when a double click selected the whole building type: the
## panel shows the primary, the suffix says how many share the orders.
func _append_group_count() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var group: Variant = world.get("_selected_buildings")
	if group is Array and (group as Array).size() > 1:
		_unit_name_label.text += "  ×%d" % (group as Array).size()

## Garrisonable buildings (TC, towers) get an eject button and an occupancy
## readout appended to whatever the type dispatch above built.
func _refresh_garrison_ui(building: Node) -> void:
	if not building.has_method("garrison_capacity") \
			or (building.garrison_capacity() as int) <= 0:
		return
	var garrison: Array = building.get_garrison() as Array
	var cap: int = building.garrison_capacity() as int
	# "Garrisoned", not the ships' "crew" wording — a Town Center has no crew.
	_unit_status_label.text = tr("UI_GARRISONED") % [garrison.size(), cap]
	if garrison.is_empty():
		return
	_active_actions.append({
		"id": "ungarrison",
		"label": tr("UI_UNGARRISON") + " (%d/%d)" % [garrison.size(), cap],
		"cost": {},
		"key": KEY_U,
		"raw_label": true,
		"badge": str(garrison.size()),
		"description": "TOOLTIP_UNGARRISON",
	})
	_render_action_page()

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
		# The glyph shows the action to perform: closed padlock = lock it.
		btn.set_glyph(UiIcons.get_icon("gate_unlock" if gate.locked else "gate_lock"))
		btn.tooltip_text = "%s  [O]" % (tr("UI_GATE_UNLOCK") if gate.locked else tr("UI_GATE_LOCK"))

func _on_population_changed(player_id: int, _current: int, _cap: int) -> void:
	# HudResourceBar updates the population label; the action menu refreshes the
	# train queue so the pop-blocked indicator updates when population frees up.
	if player_id != local_player_id:
		return
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

func _on_age_advance_complete(player_id: int, _new_age: int) -> void:
	# HudResourceBar updates the age label; the action menu replaces the
	# advance progress bar and refreshes newly unlocked build/train options.
	if player_id != local_player_id:
		return
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
	_free_children(_unit_portraits_grid)
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
			"cost": {},
			"key": KEY_U,
			"raw_label": true,
			"badge": str(garrison.size()),
		})
	actions.append({"id": "stop", "label": "ACTION_STOP", "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_unit_status_label.text = tr("UI_GARRISON_STATUS") % [garrison.size(), cap]

func _on_garrison_changed(holder: Node, _current: int, _capacity: int) -> void:
	if is_instance_valid(_selected_unit) and _selected_unit == holder:
		_populate_transport_buttons(holder as TransportShip)
	elif is_instance_valid(_selected_building) and _selected_building == holder:
		_on_building_selected(holder)

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

	actions.append(DESTROY_BUILDING_ACTION)
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
			"label": EntityNames.unit_name(data) + "\n" + cost_label,
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
			"label": tech.display_name + cost_str,
			"color": Color(0.45, 0.32, 0.10) if is_upgrade else Color(0.25, 0.45, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
			"is_upgrade": is_upgrade,
		})
	actions.append(DESTROY_BUILDING_ACTION)
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
			"label": EntityNames.unit_name(data) + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": _archery_range_key_for(uid),
		})
	actions.append(DESTROY_BUILDING_ACTION)
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
	actions.append(DESTROY_BUILDING_ACTION)
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
			"label": EntityNames.unit_name(data) + "\n" + cost_label,
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
			"label": tech.display_name + cost_str,
			"color": Color(0.45, 0.32, 0.10) if is_upgrade else Color(0.25, 0.45, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
			"is_upgrade": is_upgrade,
		})
	actions.append(DESTROY_BUILDING_ACTION)
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
	actions.append(DESTROY_BUILDING_ACTION)
	_populate_buttons(actions)
	_build_research_bar(building)

const MERCENARY_UNIT_DEFS: Array[Dictionary] = [
	{"id": "militia",     "display": "Militia",     "age": 0},
	{"id": "scout",       "display": "Scout",       "age": 0},
	{"id": "archer",      "display": "Archer",      "age": 1},
	{"id": "heavy_scout", "display": "Heavy Scout", "age": 1},
	{"id": "knight",      "display": "Knight",      "age": 2},
	{"id": "mangonel",    "display": "Mangonel",    "age": 2},
]

func _populate_market_actions(market: Market) -> void:
	var sr_f: int = market.get_sell_rate(local_player_id, "food")
	var sr_w: int = market.get_sell_rate(local_player_id, "wood")
	var sr_s: int = market.get_sell_rate(local_player_id, "stone")
	var br_f: int = market.get_buy_rate(local_player_id, "food")
	var br_w: int = market.get_buy_rate(local_player_id, "wood")
	var br_s: int = market.get_buy_rate(local_player_id, "stone")
	var actions: Array = [
		{"id": "market:sell:food",  "label": "Sell Food\n(%d→1G)" % sr_f,  "abbr": "-F", "cost": {"food":  sr_f}, "key": KEY_NONE, "raw_label": true},
		{"id": "market:sell:wood",  "label": "Sell Wood\n(%d→1G)" % sr_w,  "abbr": "-W", "cost": {"wood":  sr_w}, "key": KEY_NONE, "raw_label": true},
		{"id": "market:sell:stone", "label": "Sell Stone\n(%d→1G)" % sr_s, "abbr": "-S", "cost": {"stone": sr_s}, "key": KEY_NONE, "raw_label": true},
		{"id": "market:buy:food",   "label": "Buy Food\n(1G→%d)" % br_f,   "abbr": "+F", "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true},
		{"id": "market:buy:wood",   "label": "Buy Wood\n(1G→%d)" % br_w,   "abbr": "+W", "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true},
		{"id": "market:buy:stone",  "label": "Buy Stone\n(1G→%d)" % br_s,  "abbr": "+S", "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true},
	]
	if MatchConfig.player_civ_id == "fenicios":
		var current_age: int = AgeManager.get_age(local_player_id)
		for def: Dictionary in MERCENARY_UNIT_DEFS:
			if (def["age"] as int) > current_age:
				continue
			var uid: String = def["id"] as String
			var scene_path: String = "res://scenes/units/%s.tscn" % uid
			if not ResourceLoader.exists(scene_path):
				continue
			var gold_cost: int = market.get_mercenary_cost(uid)
			var cooldown_remaining: float = market.get_mercenary_cooldown_fraction(uid) * market.MERCENARY_COOLDOWN
			var on_cooldown: bool = cooldown_remaining > 0.0
			var label: String
			if on_cooldown:
				label = "Hire %s\n(%ds)" % [def["display"] as String, int(ceil(cooldown_remaining))]
			else:
				label = "Hire %s\n(%dG)" % [def["display"] as String, gold_cost]
			actions.append({
				"id": "market:hire:%s" % uid,
				"label": label,
				"cost": {"gold": gold_cost},
				"key": KEY_NONE,
				"raw_label": true,
				"locked": on_cooldown,
				"badge": ("%ds" % int(ceil(cooldown_remaining))) if on_cooldown else "",
			})
	actions.append(DESTROY_BUILDING_ACTION)
	_active_actions = actions
	_action_grid.columns = ACTION_COLS
	_render_action_page()

func _on_market_rate_changed(pid: int, market: Market) -> void:
	if pid != local_player_id:
		return
	if not (is_instance_valid(_selected_building) and _selected_building == market):
		return
	_populate_market_actions(market)

func _on_mercenary_hired(_pid: int, _unit_id: String, market: Market) -> void:
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
	actions.append(DESTROY_BUILDING_ACTION)
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
		# Same looping-path glyph; the lit frame marks auto-explore as engaged.
		actions.append({"id": "scout_explore_stop", "label": "ACTION_SCOUT_EXPLORE_STOP", "cost": {}, "key": KEY_E, "description": "TOOLTIP_SCOUT_EXPLORE_STOP", "active": true})
	else:
		actions.append({"id": "scout_explore", "label": "ACTION_SCOUT_EXPLORE", "cost": {}, "key": KEY_E, "description": "TOOLTIP_SCOUT_EXPLORE"})
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
			"label": EntityNames.unit_name(data) + "\n" + cost_label,
			"color": def["color"] as Color,
			"cost": costs,
			"key": key_map.get(uid, KEY_NONE) as Key,
		})
	actions.append(DESTROY_BUILDING_ACTION)
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

## Live refresh: starting/finishing/cancelling research rebuilds the selected
## building's panel — before this, the "Researching…" bar and the queue slot
## only appeared when the building was re-selected.
func _on_research_state_changed(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building == building:
		_on_building_selected(building)

## Research shows in the SAME queue row as unit training, as a slot with a
## progress veil and a cancel button (full refund), so the building's "what is
## it making" reads identically for units and technologies.
func _refresh_research_slot() -> void:
	if not is_instance_valid(_train_queue_row):
		return
	var old: Node = _train_queue_row.get_node_or_null("ResearchSlot")
	if old != null:
		old.name = "ResearchSlotFreeing"   # frees end-of-frame; keep the name free
		old.queue_free()
	if not is_instance_valid(_selected_building):
		return
	var tech: TechnologyResource = TechManager.get_researching_tech(_selected_building)
	if tech == null:
		return
	var initials: String = ""
	for part: String in tech.display_name.split(" "):
		if not part.is_empty():
			initials += part[0]
	var slot: TrainQueueSlot = TrainQueueSlot.new()
	slot.name = "ResearchSlot"
	_train_queue_row.add_child(slot)
	slot.setup(0, initials.left(2).to_upper(), Color(0.25, 0.55, 0.75), true, false, null)
	slot.tooltip_text = tech.display_name
	slot.set_progress(TechManager.get_research_progress(_selected_building))
	slot.cancel_requested.connect(func(_idx: int) -> void:
		if is_instance_valid(_selected_building):
			CommandBus.submit(ProductionCommand.make(0, "cancel_research",
				EntityRegistry.id_of(_selected_building))))

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

func _poll_hp_bars() -> void:
	if _hp_text == null:
		_hp_text = Label.new()
		_hp_text.add_theme_font_size_override("font_size", 10)
		_hp_text.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
		HudStyle.add_text_outline(_hp_text, 3)
		_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_unit_hp_bar.add_child(_hp_text)
		_hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid(_hp_bar_unit) and _hp_bar_max > 0.0:
		var hp_v: Variant = _hp_bar_unit.get("health")
		if hp_v != null:
			_unit_hp_bar.value = (hp_v as float) / _hp_bar_max * 100.0
			# Numbers, not just a bar: on a 1200 HP building a few sword hits
			# move the bar less than a pixel and damage LOOKED like it never
			# landed.
			_hp_text.text = "%d / %d" % [ceili(hp_v as float), roundi(_hp_bar_max)]
	# An empty detail panel otherwise renders a bare "0%" bar.
	_unit_hp_bar.visible = _unit_hp_bar.value > 0.0
	_hp_text.visible = _unit_hp_bar.visible and is_instance_valid(_hp_bar_unit)
	for child: Node in _unit_portraits_grid.get_children():
		if child is UnitPortrait:
			(child as UnitPortrait).refresh()

# ── Unit stats row ───────────────────────────────────────────────────────────

## True when a label extra is nothing but "500F 175W"-style cost tokens, which
## the cost strip and the plain-text tooltip line now cover.
func _is_cost_tokens(text: String) -> bool:
	var parts: PackedStringArray = text.split(" ", false)
	if parts.is_empty():
		return false
	for p: String in parts:
		if p.length() < 2:
			return false
		# English (Food/Wood/Gold/Stone) and Spanish (Comida/Madera/Oro/
		# Piedra) label suffixes — the Spanish "50C" was leaking into
		# tooltips next to the glyph cost row.
		if p.substr(p.length() - 1) not in ["F", "W", "G", "S", "C", "M", "O", "P"]:
			return false
		if not p.substr(0, p.length() - 1).is_valid_int():
			return false
	return true

func _clear_stats_row() -> void:
	_stats_unit = null
	_stat_labels = {}
	_carry_chip = null
	_carry_icon = null
	if is_instance_valid(_stats_row):
		_stats_row.queue_free()
	_stats_row = null

## Compact stat chips (attack / armor m|p / range / speed) for a single-selected
## unit; villagers additionally get a carried-resource chip.
func _build_stats_row(unit: Node) -> void:
	_clear_stats_row()
	if _detail_panel == null or not is_instance_valid(unit):
		return
	var udata: UnitResource = unit.get("unit_data") as UnitResource
	if udata == null:
		return
	_stats_row = HBoxContainer.new()
	_stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_row.add_theme_constant_override("separation", 10)
	for stat: String in ["attack", "armor", "range", "speed"]:
		# Melee reach tops out at 1.5 tiles; only true ranged units get the chip.
		if stat == "range" and udata.attack_range <= 2.0:
			continue
		var chip: HBoxContainer = UiIcons.amount_chip("stat_" + stat, "")
		_stat_labels[stat] = chip.get_child(1) as Label
		_stats_row.add_child(chip)
	if unit.get("carried_resource") != null and unit.get("carried_amount") != null:
		_carry_chip = UiIcons.amount_chip("res_food", "")
		_carry_icon = _carry_chip.get_child(0) as TextureRect
		_stat_labels["carry"] = _carry_chip.get_child(1) as Label
		_carry_chip.visible = false
		_stats_row.add_child(_carry_chip)
	_detail_panel.add_child(_stats_row)
	# Sits right under the name / HP bar / status trio from the scene.
	_detail_panel.move_child(_stats_row, 3)
	_stats_unit = unit
	_refresh_stats_row()

func _refresh_stats_row() -> void:
	if not is_instance_valid(_stats_row) or not is_instance_valid(_stats_unit):
		return
	var udata: UnitResource = _stats_unit.get("unit_data") as UnitResource
	if udata == null:
		return
	var pid_v: Variant = _stats_unit.get("player_id")
	var pid: int = pid_v as int if pid_v != null else 0
	var uid: String = udata.id
	if _stat_labels.has("attack"):
		var atk: float = udata.attack * CivBonusManager.get_unit_attack_multiplier(pid, uid)
		(_stat_labels["attack"] as Label).text = str(int(roundf(atk)))
	if _stat_labels.has("armor"):
		var armor_m: float = udata.armor_melee + CivBonusManager.get_unit_armor_bonus(pid)
		var armor_p: float = udata.armor_pierce + CivBonusManager.get_archer_armor_pierce_bonus(pid)
		(_stat_labels["armor"] as Label).text = "%d/%d" % [int(armor_m), int(armor_p)]
	if _stat_labels.has("range"):
		var rng: float = udata.attack_range * CivBonusManager.get_archer_range_multiplier(pid) \
			+ CivBonusManager.get_archer_range_flat(pid)
		(_stat_labels["range"] as Label).text = str(int(roundf(rng)))
	if _stat_labels.has("speed"):
		var spd: float = udata.move_speed * CivBonusManager.get_unit_speed_multiplier(pid, uid) \
			* CivBonusManager.get_unit_move_speed_multiplier(pid)
		(_stat_labels["speed"] as Label).text = "%.0f" % spd
	if _stat_labels.has("carry") and is_instance_valid(_carry_chip):
		var res: String = _stats_unit.get("carried_resource") as String
		var amount: float = _stats_unit.get("carried_amount") as float
		if res.is_empty() or amount <= 0.0:
			_carry_chip.visible = false
		else:
			if UiIcons.has_glyph("res_" + res):
				_carry_icon.texture = UiIcons.get_icon("res_" + res)
			(_stat_labels["carry"] as Label).text = str(int(amount))
			_carry_chip.visible = true

func _on_hero_low_hp(player_id: int) -> void:
	if player_id != local_player_id:
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
	_free_children(_unit_portraits_grid)
	_clear_action_buttons()
	_clear_stats_row()
	_hp_bar_unit = null
	var rn: ResourceNode = node as ResourceNode
	var res_name: String = rn.get_resource_name().capitalize()
	_unit_name_label.text = res_name
	_unit_hp_bar.value = (rn.remaining_amount / rn.initial_amount) * 100.0
	_unit_status_label.text = "%d / %d" % [int(rn.remaining_amount), int(rn.initial_amount)]

func _on_cancel_train_slot(index: int) -> void:
	if not is_instance_valid(_selected_building):
		return
	if _selected_building.has_method("order_cancel_train"):
		CommandBus.submit(ProductionCommand.make(0, "cancel_train",
			EntityRegistry.id_of(_selected_building), "", index))

## How many entries of each unit_id a training queue holds — pure, tested.
static func queued_per_unit(queue: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Variant in queue:
		var uid: String = (entry as Dictionary).get("unit_id", "") as String
		counts[uid] = (counts.get(uid, 0) as int) + 1
	return counts

func _on_train_queue_changed(building: Node, queue: Array, max_queue: int) -> void:
	if building != _selected_building:
		return
	# Per-unit-type queue badge: a building that trains several unit types
	# (Barracks, Stable, Dock…) must show each button ITS OWN queued count —
	# the old total-size badge incremented every train button at once.
	var counts: Dictionary = queued_per_unit(queue)
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var aid: String = btn.action_id
		if not aid.begins_with("train:"):
			continue
		btn.set_train_queue_badge(
			counts.get(aid.trim_prefix("train:"), 0) as int, max_queue)
	_refresh_button_states()
	# Rebuild the visual queue row
	for slot: Node in _train_queue_row.get_children():
		slot.queue_free()
	var pop_blocked: bool = not queue.is_empty() and PopulationManager.at_cap(local_player_id)
	for i: int in range(queue.size()):
		var entry: Dictionary = queue[i] as Dictionary
		var slot: TrainQueueSlot = TrainQueueSlot.new()
		_train_queue_row.add_child(slot)
		# Queue slots show the entity's baked icon (like the selection
		# portraits); entries without a scene fall back to the letter.
		var scene_path: String = entry.get("scene", "") as String
		var icon: Texture2D = IconBaker.get_icon(scene_path, local_player_id) \
			if not scene_path.is_empty() else null
		slot.setup(i, entry["label"] as String, entry["color"] as Color,
			i == 0, i == 0 and pop_blocked, icon)
		slot.cancel_requested.connect(_on_cancel_train_slot)
	_refresh_research_slot()

func _update_train_queue_progress() -> void:
	if not is_instance_valid(_selected_building):
		return
	var research_slot: Node = _train_queue_row.get_node_or_null("ResearchSlot")
	if research_slot is TrainQueueSlot:
		(research_slot as TrainQueueSlot).set_progress(
			TechManager.get_research_progress(_selected_building))
	if not _selected_building.has_method("get_train_progress"):
		return
	var p: float = _selected_building.get_train_progress() as float
	var first_slot: Node = _train_queue_row.get_child(0) if _train_queue_row.get_child_count() > 0 else null
	if first_slot is TrainQueueSlot and first_slot.name != &"ResearchSlot":
		(first_slot as TrainQueueSlot).set_progress(p)

func _on_building_destroyed(building: Node, _player_id: int) -> void:
	if building == _selected_building:
		if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
			_selected_building.set_selected(false)
		_selected_building = null
		_on_building_selected(null)

func _on_unit_died(unit: Node, _player_id: int) -> void:
	_status_unit = null
	if unit == _hp_bar_unit or unit == _selected_unit:
		update_selection([])
		_selected_unit = null
		_hp_bar_unit = null
		return
	for child: Node in _unit_portraits_grid.get_children():
		if child is UnitPortrait and (child as UnitPortrait).unit_ref == unit:
			update_selection([])
			_selected_unit = null
			_hp_bar_unit = null
			return

func _build_notifications() -> void:
	var nd: NotificationDisplay = NotificationDisplay.new()
	get_node("HUDRoot").add_child(nd)

func _build_follow_button() -> void:
	var top_row: Node = get_node_or_null("HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow")
	if top_row == null:
		return
	# Square icon button: binoculars glyph, same command-button chrome as the
	# action grid. The lit frame marks camera-follow as engaged. Sits as its own
	# column right of the detail stack so it costs the band no vertical space.
	_follow_btn = Button.new()
	_follow_btn.focus_mode = Control.FOCUS_NONE
	_follow_btn.visible = false
	_follow_btn.custom_minimum_size = Vector2(38.0, 34.0)
	_follow_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_follow_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_follow_btn.add_child(UiIcons.icon_rect("follow", 4.0))
	_apply_follow_style(false)
	_follow_btn.pressed.connect(_on_follow_pressed)
	top_row.add_child(_follow_btn)

func _on_follow_pressed() -> void:
	_set_follow_active(not _following)
	follow_requested.emit()

func _set_follow_active(active: bool) -> void:
	_following = active
	if not is_instance_valid(_follow_btn):
		return
	_apply_follow_style(active)

func _apply_follow_style(active: bool) -> void:
	var accent: Color = HudStyle.ACCENT_UTILITY
	_follow_btn.add_theme_stylebox_override("normal",
		HudStyle.command_button(accent, "active" if active else "normal"))
	_follow_btn.add_theme_stylebox_override("hover",
		HudStyle.command_button(accent, "active" if active else "hover"))
	_follow_btn.add_theme_stylebox_override("pressed", HudStyle.command_button(accent, "pressed"))
	_follow_btn.tooltip_text = tr("UI_FOLLOWING") if active else tr("UI_FOLLOW_CAMERA")

func _on_building_construction_complete(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building == building:
		_on_building_selected(building)

# ── Tutorial ─────────────────────────────────────────────────────────────────

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
	_tutorial_overlay.completed.connect(func() -> void: GameManager.declare_winner(0))
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
	"villager_trained":    {"food": 60},
	# The step asks for a Barracks (175 wood) AND "queue up several" militia
	# (60 food + 20 wood each) — the old 60 wood could not even start it.
	"militia_trained":     {"wood": 260, "food": 240},
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
	if pid == null or (pid as int) != local_player_id:
		return
	# Auto-retaliation used to complete the step while the player just
	# watched — only an attack THEY ordered counts as learning it.
	if attacker.get("_auto_engaged") == true:
		return
	_tutorial_notify("unit_attacked")

func _build_pause_menu_button() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(36, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = tr("UI_MENU")
	btn.add_child(UiIcons.icon_rect("menu", 5.0))
	# Anchor to top-right corner
	btn.anchor_left   = 1.0
	btn.anchor_top    = 0.0
	btn.anchor_right  = 1.0
	btn.anchor_bottom = 0.0
	btn.offset_left   = -69.0
	btn.offset_top    =  31.0
	btn.offset_right  = -31.0
	btn.offset_bottom =  67.0
	btn.add_theme_stylebox_override("normal",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "normal"))
	btn.add_theme_stylebox_override("hover",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "hover"))
	btn.add_theme_stylebox_override("pressed",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "pressed"))
	btn.pressed.connect(_menus.open_pause_menu)
	hud_root.add_child(btn)

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
			btn.set_meta("locked", true)
			btn.set_enabled(false)

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
	var who: String = tr("WONDER_TIMER_YOU") if owner_pid == local_player_id else tr("WONDER_TIMER_ENEMY")
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
# Delegated to HudWeather (scripts/ui/hud/hud_weather.gd). Kept as thin
# forwarders for any external caller (game_world.gd) that still references them.

func show_weather(weather_id: String) -> void:
	if is_instance_valid(_weather):
		_weather.show_weather(weather_id)

func hide_weather() -> void:
	if is_instance_valid(_weather):
		_weather.hide_weather()

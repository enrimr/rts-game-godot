extends CanvasLayer

signal action_requested(action_id: String)
signal follow_requested()

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

const DESTROY_ACTION: Dictionary = {"id": "destroy", "label": "ACTION_DESTROY", "color": Color(0.55, 0.05, 0.05), "cost": {}, "key": KEY_DELETE}

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "ACTION_WOOD",    "color": Color(0.20, 0.55, 0.15), "cost": {}, "key": KEY_C},
	{"id": "gather_gold",  "label": "ACTION_GOLD",    "color": Color(0.75, 0.65, 0.10), "cost": {}, "key": KEY_G},
	{"id": "gather_stone", "label": "ACTION_STONE",   "color": Color(0.55, 0.55, 0.55), "cost": {}, "key": KEY_T},
	{"id": "gather_food",  "label": "ACTION_FOOD",    "color": Color(0.60, 0.20, 0.15), "cost": {}, "key": KEY_H},
	{"id": "build_menu",   "label": "ACTION_BUILD",   "color": Color(0.20, 0.30, 0.60), "cost": {}, "key": KEY_B},
	{"id": "stop",         "label": "ACTION_STOP",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X},
	DESTROY_ACTION,
]

const BUILD_ACTIONS: Array = [
	{"id": "build:house",         "label": "ACTION_HOUSE",      "color": Color(0.50, 0.38, 0.22), "cost": {"wood": 25},  "key": KEY_H},
	{"id": "build:barracks",      "label": "ACTION_BARRACKS",   "color": Color(0.45, 0.22, 0.18), "cost": {"wood": 175}, "key": KEY_B},
	{"id": "build:lumber_camp",   "label": "ACTION_LUMBER",     "color": Color(0.30, 0.20, 0.08), "cost": {"wood": 100}, "key": KEY_L},
	{"id": "build:mining_camp",   "label": "ACTION_MINING",     "color": Color(0.50, 0.46, 0.34), "cost": {"wood": 100}, "key": KEY_N},
	{"id": "build:farm",          "label": "ACTION_FARM",       "color": Color(0.60, 0.52, 0.18), "cost": {"wood": 60},  "key": KEY_F},
	{"id": "build:wall_segment",  "label": "ACTION_WALL",       "color": Color(0.55, 0.52, 0.48), "cost": {"stone": 5},  "key": KEY_W},
	{"id": "build:gate",          "label": "ACTION_GATE",       "color": Color(0.42, 0.30, 0.12), "cost": {"wood": 30},  "key": KEY_G},
	{"id": "build:dock",          "label": "ACTION_DOCK",       "color": Color(0.18, 0.32, 0.55), "cost": {"wood": 150}, "key": KEY_D},
	{"id": "back",                "label": "ACTION_BACK",       "color": Color(0.25, 0.25, 0.25), "cost": {},            "key": KEY_ESCAPE},
]

const TOWN_CENTER_ACTIONS: Array = [
	{"id": "train:villager", "label": "ACTION_VILLAGER", "color": Color(0.20, 0.45, 0.20), "cost": {"food": 50}, "key": KEY_V},
]

const UNIT_ACTIONS: Array = [
	{"id": "stop",    "label": "ACTION_STOP",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X},
	DESTROY_ACTION,
]

const TRANSPORT_ACTIONS: Array = [
	{"id": "unload",  "label": "UI_UNLOAD",      "color": Color(0.20, 0.45, 0.65), "cost": {}, "key": KEY_U},
	{"id": "stop",    "label": "ACTION_STOP",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X},
	DESTROY_ACTION,
]

const BUILDING_ACTIONS: Array = [
	DESTROY_ACTION,
]

const DOCK_UNIT_DEFS: Array = [
	{"id": "fishing_boat",   "label": "ACTION_FISHING_BOAT",   "color": Color(0.20, 0.50, 0.65), "cost": {"wood": 75},            "age": 0},
	{"id": "transport_ship", "label": "ACTION_TRANSPORT_SHIP", "color": Color(0.55, 0.45, 0.20), "cost": {"wood": 125},           "age": 1},
	{"id": "war_galley",     "label": "ACTION_WAR_GALLEY",     "color": Color(0.65, 0.18, 0.18), "cost": {"wood": 75, "gold": 35}, "age": 1},
]

const GATE_ACTIONS: Array = [
	{"id": "gate_lock", "label": "UI_GATE_LOCK", "color": Color(0.55, 0.15, 0.10), "cost": {}, "key": KEY_O},
	DESTROY_ACTION,
]

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _in_build_menu: bool = false
var _selected_building: Node = null
var _selected_unit: Node = null   # tracked for transport garrison refresh
var _status_unit: Node = null
var _active_actions: Array = []
var _follow_btn: Button = null
var _following: bool = false
var _age_advance_bar: ProgressBar = null
var _hero_respawn_bar: ProgressBar = null
var _hero_respawn_label: Label = null
var _research_bar: ProgressBar = null
var _research_label: Label = null
var _pause_menu: Control = null

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
	EventBus.garrison_changed.connect(_on_garrison_changed)
	EventBus.unit_spawned.connect(_on_stat_unit_spawned)
	EventBus.building_construction_complete.connect(_on_stat_building_complete)
	EventBus.unit_died.connect(_on_stat_unit_died)
	ResourceManager.resources_updated.connect(_on_stat_resources_updated)
	_pause_overlay.visible = false
	_clock_label.text = "00:00"
	_unit_name_label.text = ""
	_unit_hp_bar.value = 0.0
	_build_follow_button()
	_build_notifications()
	_build_pause_menu_button()

func _process(delta: float) -> void:
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
			_populate_buttons([])
		elif first is HeroUnit:
			_populate_hero_buttons(first as HeroUnit)
		elif first is TransportShip:
			_populate_transport_buttons(first as TransportShip)
		elif first.has_method("order_gather"):
			_populate_buttons(VILLAGER_ACTIONS)
		else:
			_populate_buttons(UNIT_ACTIONS)

func update_age(age: int) -> void:
	_age_label.text = tr(["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"][clampi(age, 0, 3)])

func toggle_pause(is_paused: bool) -> void:
	_pause_overlay.visible = is_paused

# --- Private ---

func _clear_action_buttons() -> void:
	_active_actions = []
	for child: Node in _action_grid.get_children():
		child.queue_free()
	for child: Node in _train_queue_row.get_children():
		child.queue_free()
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
	for entry: Variant in actions:
		var data: Dictionary = entry as Dictionary
		var btn: ActionButton = ActionButton.new()
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
		var effective_color: Color = color if can_pay else Color(0.25, 0.25, 0.25)
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
		btn.disabled = not can_pay
		btn.action_pressed.connect(_on_action_button_pressed)
		_action_grid.add_child(btn)

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
		btn.add_theme_stylebox_override("normal", style)
		var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		hover_style.bg_color = effective_color.lightened(0.25)
		btn.add_theme_stylebox_override("hover", hover_style)

func _on_action_button_pressed(action_id: String) -> void:
	if action_id == "build_menu":
		AudioManager.play("ui_click")
		_in_build_menu = true
		_populate_buttons(BUILD_ACTIONS)
		return
	if action_id == "back":
		AudioManager.play("ui_click")
		_in_build_menu = false
		_populate_buttons(VILLAGER_ACTIONS)
		return
	if action_id.begins_with("train:"):
		AudioManager.play("train_queue")
	elif action_id == "advance_age":
		AudioManager.play("age_advance")
	elif action_id.begins_with("research:"):
		AudioManager.play("ui_click")
	else:
		AudioManager.play("ui_click")
	action_requested.emit(action_id)

func _on_game_started() -> void:
	_elapsed_seconds = 0.0
	_clock_running = true
	update_age(AgeManager.get_age(local_player_id))
	var starting: Dictionary = ResourceManager.get_resources(local_player_id)
	update_resources(local_player_id, starting)
	_last_resources = starting.duplicate()
	for rival_id: int in MatchConfig.get_rival_player_ids():
		_init_rival_stats(rival_id)

func _on_resource_changed(player_id: int, resource: String, amount: int) -> void:
	if player_id != local_player_id:
		return
	match resource:
		"food":  _food_display.set_amount(amount)
		"wood":  _wood_display.set_amount(amount)
		"gold":  _gold_display.set_amount(amount)
		"stone": _stone_display.set_amount(amount)
	_refresh_button_states()

func _on_unit_selected(units: Array) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null
	_selected_unit = units[0] if units.size() == 1 else null
	_set_follow_active(false)
	update_selection(units)
	if is_instance_valid(_follow_btn):
		_follow_btn.visible = not units.is_empty()

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
	var max_hp: float = 100.0
	if bdata != null:
		var mhp_v: Variant = (bdata as Resource).get("max_health")
		if mhp_v != null:
			max_hp = mhp_v as float
	if max_hp > 0.0:
		_unit_hp_bar.value = (hp / max_hp) * 100.0

	if building.has_method("is_respawning_hero"):
		_unit_name_label.text = tr("UI_TOWN_CENTER")
		var tc_hp: Variant = building.get("health")
		var tc_max: Variant = building.get("max_health")
		if tc_hp != null and tc_max != null and (tc_max as float) > 0.0:
			_unit_hp_bar.value = ((tc_hp as float) / (tc_max as float)) * 100.0
		_populate_tc_actions()
		if building.has_method("get_queue"):
			_on_train_queue_changed(building, building.get_queue() as Array, building.get_max_queue() as int)
	elif building is Barracks:
		_populate_barracks_actions(building as Barracks)
		var br: Barracks = building as Barracks
		_on_train_queue_changed(building, br.get_queue(), br.get_max_queue())
	elif building is Dock:
		_populate_dock_actions(building as Dock)
		var dk: Dock = building as Dock
		_on_train_queue_changed(building, dk.get_queue(), dk.get_max_queue())
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
		elif _selected_building is Barracks:
			_populate_barracks_actions(_selected_building as Barracks)
		elif _selected_building is Dock:
			_populate_dock_actions(_selected_building as Dock)

func _populate_hero_buttons(hero: HeroUnit) -> void:
	_clear_action_buttons()
	var actions: Array = [DESTROY_ACTION]
	var udata: UnitResource = hero.unit_data
	if udata != null and not udata.hero_ability_id.is_empty():
		var cd_frac: float = hero.get_cooldown_fraction()
		var cd_secs: int = int(udata.hero_ability_cooldown * cd_frac)
		var label: String
		if cd_frac <= 0.0:
			label = tr("HERO_ABILITY_READY")
		else:
			label = tr("HERO_ABILITY_COOLDOWN") % cd_secs
		actions.insert(0, {
			"id": "hero_ability",
			"label": label,
			"color": Color(0.55, 0.20, 0.55) if cd_frac <= 0.0 else Color(0.25, 0.25, 0.30),
			"cost": {},
			"key": KEY_Q,
			"raw_label": true,
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

	if current_age < GameManager.Age.IMPERIAL and not AgeManager.is_advancing(local_player_id):
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
		actions.append({
			"id": "advance_age",
			"label": tr("UI_ADVANCE") + "\n" + cost_str.strip_edges(),
			"color": advance_color,
			"cost": costs,
			"key": KEY_A,
			"raw_label": true,
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
			"key": (KEY_M if uid == "militia" else (KEY_A if uid == "archer" else KEY_P)),
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
		actions.append({
			"id": "research:%s" % tech.id,
			"label": tech.display_name + cost_str,
			"color": Color(0.25, 0.45, 0.55),
			"cost": tech_costs,
			"key": 0,
			"raw_label": true,
		})
	actions.append(DESTROY_ACTION)
	_populate_buttons(actions)
	_build_research_bar(barracks)

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
		var key_map: Dictionary = {"fishing_boat": KEY_F, "transport_ship": KEY_T, "war_galley": KEY_G}
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
	_hero_respawn_label.add_theme_font_size_override("font_size", 11)
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
		_research_label.add_theme_font_size_override("font_size", 11)
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
	for i: int in range(queue.size()):
		var entry: Dictionary = queue[i] as Dictionary
		var slot: TrainQueueSlot = TrainQueueSlot.new()
		_train_queue_row.add_child(slot)
		slot.setup(i, entry["label"] as String, entry["color"] as Color, i == 0)
		slot.cancel_requested.connect(_on_cancel_train_slot)

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
	_follow_btn.add_theme_font_size_override("font_size", 11)
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
var _snap_pop_b:       Array = []   # AI population
var _snap_res_a:       Array = []   # player total resources gathered
var _snap_res_b:       Array = []   # AI total resources gathered
var _snap_age_a:       Array = []   # player age (0-3)
var _snap_age_b:       Array = []   # AI age (0-3)

var _snap_kills_a_prev: int = 0     # enemies killed at last snapshot
var _snap_kills_b_prev: int = 0
var _snap_kills_a:      Array = []  # kills per interval
var _snap_kills_b:      Array = []

# indices (in the above arrays) where an offensive happened (kills delta > threshold)
var _offense_snaps_a: Array = []
var _offense_snaps_b: Array = []

const OFFENSE_THRESHOLD: int = 2   # kills in one interval to count as an offensive

func _take_snapshot() -> void:
	var pop_a: Dictionary = PopulationManager.get_population(local_player_id)
	var pop_b: Dictionary = PopulationManager.get_population(1)
	_snap_pop_a.append(float(pop_a.get("current", 0) as int))
	_snap_pop_b.append(float(pop_b.get("current", 0) as int))

	var total_a: int = 0
	var total_b: int = 0
	for k: String in ["food", "wood", "gold", "stone"]:
		total_a += _stat_resources_gathered.get(k, 0) as int
		total_b += _ai_stat_resources_gathered.get(k, 0) as int
	_snap_res_a.append(float(total_a))
	_snap_res_b.append(float(total_b))

	_snap_age_a.append(float(AgeManager.get_age(local_player_id)))
	_snap_age_b.append(float(AgeManager.get_age(1)))

	var kills_delta_a: int = _stat_enemies_killed - _snap_kills_a_prev
	var kills_delta_b: int = _ai_stat_units_lost   - _snap_kills_b_prev
	_snap_kills_a.append(float(kills_delta_a))
	_snap_kills_b.append(float(kills_delta_b))
	var snap_idx: int = _snap_kills_a.size() - 1
	if kills_delta_a >= OFFENSE_THRESHOLD:
		_offense_snaps_a.append(snap_idx)
	if kills_delta_b >= OFFENSE_THRESHOLD:
		_offense_snaps_b.append(snap_idx)
	_snap_kills_a_prev = _stat_enemies_killed
	_snap_kills_b_prev = _ai_stat_units_lost

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
	title.add_theme_font_size_override("font_size", 56)
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
	stats_header.add_theme_font_size_override("font_size", 18)
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

	var rival_colors: Array[Color] = [
		Color(1.0, 0.45, 0.45), Color(1.0, 0.75, 0.25), Color(0.65, 0.45, 1.0),
	]

	# Player column
	var player_col: VBoxContainer = VBoxContainer.new()
	player_col.add_theme_constant_override("separation", 1)
	var ph: Label = Label.new()
	ph.text = tr("GAMEOVER_PLAYER")
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ph.add_theme_font_size_override("font_size", 13)
	ph.add_theme_color_override("font_color", Color(0.40, 0.70, 1.0))
	player_col.add_child(ph)
	var pc: Label = Label.new()
	pc.text = _get_civ_display.call(MatchConfig.player_civ_id) as String
	pc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pc.add_theme_font_size_override("font_size", 11)
	pc.add_theme_color_override("font_color", Color(0.40, 0.70, 1.0).lightened(0.3))
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
		rh.add_theme_font_size_override("font_size", 13)
		var rcol_color: Color = rival_colors[mini(ri, rival_colors.size() - 1)]
		rh.add_theme_color_override("font_color", rcol_color)
		rcol.add_child(rh)
		var rcc: Label = Label.new()
		rcc.text = _get_civ_display.call(MatchConfig.get_rival_civ_id(rid)) as String
		rcc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rcc.add_theme_font_size_override("font_size", 11)
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
		key_lbl.add_theme_font_size_override("font_size", 14)
		key_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
		grid.add_child(key_lbl)

		var player_val: Label = Label.new()
		player_val.text = stat["player"] as String
		player_val.add_theme_font_size_override("font_size", 14)
		player_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		player_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(player_val)

		for rid: int in rival_ids:
			var rival_val: Label = Label.new()
			rival_val.text = (stat["rival_fn"] as Callable).call(rid) as String
			rival_val.add_theme_font_size_override("font_size", 14)
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
	map_btn.add_theme_font_size_override("font_size", 16)
	map_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.15, 0.30, 0.50, 0.95)))
	map_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.25, 0.45, 0.70, 0.95)))

	var exit_btn: Button = Button.new()
	exit_btn.text = tr("GAMEOVER_EXIT")
	exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	exit_btn.offset_left   = -160.0
	exit_btn.offset_right  =    0.0
	exit_btn.offset_top    =    8.0
	exit_btn.offset_bottom =   40.0
	exit_btn.add_theme_font_size_override("font_size", 14)
	exit_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.15, 0.15, 0.15, 0.92)))
	exit_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.35, 0.15, 0.15, 0.92)))
	exit_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/game/main_menu.tscn")
	)

	map_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		center.queue_free()
		hud_root.add_child(exit_btn)
	)
	btn_row.add_child(map_btn)

	# "Ver gráficas" button — opens timeline charts overlay
	var charts_btn: Button = Button.new()
	charts_btn.text = tr("GAMEOVER_CHARTS")
	charts_btn.custom_minimum_size = Vector2(150.0, 36.0)
	charts_btn.add_theme_font_size_override("font_size", 16)
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
	menu_btn.add_theme_font_size_override("font_size", 16)
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
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title_lbl)

	# Legend row
	var legend: HBoxContainer = HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 24)
	vbox.add_child(legend)
	for ldata: Array in [[tr("GAMEOVER_PLAYER"), Color(0.40, 0.70, 1.0)], [tr("GAMEOVER_RIVAL"), Color(1.0, 0.45, 0.45)]]:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		legend.add_child(row)
		var swatch: ColorRect = ColorRect.new()
		swatch.color = ldata[1] as Color
		swatch.custom_minimum_size = Vector2(18, 10)
		row.add_child(swatch)
		var ll: Label = Label.new()
		ll.text = ldata[0] as String
		ll.add_theme_font_size_override("font_size", 13)
		ll.add_theme_color_override("font_color", ldata[1] as Color)
		row.add_child(ll)

	vbox.add_child(HSeparator.new())

	# Charts definition: [title_key, series_a, series_b, spikes_a, spikes_b, mode]
	var chart_defs: Array = [
		[tr("CHART_POPULATION"), _snap_pop_a, _snap_pop_b, [], [], MatchChart.Mode.LINES],
		[tr("CHART_RESOURCES"),  _snap_res_a, _snap_res_b, [], [], MatchChart.Mode.LINES],
		[tr("CHART_AGE"),        _snap_age_a, _snap_age_b, [], [], MatchChart.Mode.STEPS],
		[tr("CHART_OFFENSIVES"), _snap_kills_a, _snap_kills_b, _offense_snaps_a, _offense_snaps_b, MatchChart.Mode.BARS],
	]

	for cdef: Array in chart_defs:
		var chart: MatchChart = MatchChart.new()
		chart.chart_title  = cdef[0] as String
		chart.series_a     = cdef[1] as Array
		chart.series_b     = cdef[2] as Array
		chart.spikes_a     = cdef[3] as Array
		chart.spikes_b     = cdef[4] as Array
		chart.mode         = cdef[5] as int
		chart.total_time   = _elapsed_seconds
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
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.20, 0.20, 0.25, 0.95)))
	close_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.35, 0.35, 0.42, 0.95)))
	close_btn.pressed.connect(func() -> void: ov.queue_free())
	vbox.add_child(close_btn)

# ── In-game pause menu ──────────────────────────────────────────────────────

func _build_pause_menu_button() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	var btn: Button = Button.new()
	btn.text = "☰"
	btn.custom_minimum_size = Vector2(36, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	btn.tooltip_text = "Menu (Esc)"
	# Anchor to top-right corner
	btn.anchor_left   = 1.0
	btn.anchor_top    = 0.0
	btn.anchor_right  = 1.0
	btn.anchor_bottom = 0.0
	btn.offset_left   = -44.0
	btn.offset_top    =   6.0
	btn.offset_right  =  -6.0
	btn.offset_bottom =  42.0
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
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var resume_btn: Button = _make_pause_btn(tr("PAUSEMENU_RESUME"), Color(0.18, 0.38, 0.18, 0.95), Color(0.28, 0.55, 0.28, 0.95))
	resume_btn.pressed.connect(_close_pause_menu)
	vbox.add_child(resume_btn)

	var settings_btn: Button = _make_pause_btn(tr("MENU_SETTINGS"), Color(0.20, 0.20, 0.28, 0.95), Color(0.32, 0.32, 0.45, 0.95))
	settings_btn.pressed.connect(_open_ingame_settings)
	vbox.add_child(settings_btn)

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
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Music
	var music_lbl: Label = Label.new()
	music_lbl.text = tr("SETTINGS_MUSIC")
	music_lbl.add_theme_font_size_override("font_size", 15)
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
	sfx_lbl.add_theme_font_size_override("font_size", 15)
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
	lang_lbl.add_theme_font_size_override("font_size", 15)
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
		lb.add_theme_font_size_override("font_size", 15)
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

	var close_btn: Button = Button.new()
	close_btn.text = tr("SETTINGS_SAVE")
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.20, 0.35, 0.55, 0.95)))
	close_btn.add_theme_stylebox_override("hover",  _make_panel_style(Color(0.30, 0.50, 0.75, 0.95)))
	vbox.add_child(close_btn)
	close_btn.pressed.connect(func() -> void:
		GameSettings.save_settings()
		overlay.queue_free()
	)

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
	lbl.add_theme_font_size_override("font_size", 13)
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
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_stylebox_override("normal", _make_panel_style(normal_col))
	var hs: StyleBoxFlat = _make_panel_style(hover_col)
	btn.add_theme_stylebox_override("hover", hs)
	return btn

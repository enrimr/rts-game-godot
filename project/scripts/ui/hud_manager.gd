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
	{"id": "back",                "label": "ACTION_BACK",       "color": Color(0.25, 0.25, 0.25), "cost": {},            "key": KEY_ESCAPE},
]

const TOWN_CENTER_ACTIONS: Array = [
	{"id": "train:villager", "label": "ACTION_VILLAGER", "color": Color(0.20, 0.45, 0.20), "cost": {"food": 50}, "key": KEY_V},
]

const UNIT_ACTIONS: Array = [
	{"id": "stop",    "label": "ACTION_STOP",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X},
	DESTROY_ACTION,
]

const BUILDING_ACTIONS: Array = [
	DESTROY_ACTION,
]

const GATE_ACTIONS: Array = [
	{"id": "gate_lock", "label": "UI_GATE_LOCK", "color": Color(0.55, 0.15, 0.10), "cost": {}, "key": KEY_O},
	DESTROY_ACTION,
]

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _in_build_menu: bool = false
var _selected_building: Node = null
var _status_unit: Node = null
var _active_actions: Array = []
var _follow_btn: Button = null
var _following: bool = false
var _age_advance_bar: ProgressBar = null

# --- Stats tracking ---
var _stat_units_trained: int = 0
var _stat_buildings_built: int = 0
var _stat_enemies_killed: int = 0
var _stat_resources_gathered: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}

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

func _process(delta: float) -> void:
	if _clock_running:
		_elapsed_seconds += delta
		var total_secs: int = int(_elapsed_seconds)
		_clock_label.text = "%02d:%02d" % [total_secs / 60, total_secs % 60]
	if is_instance_valid(_status_unit):
		_unit_status_label.text = _get_unit_status(_status_unit)
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.value = AgeManager.get_advance_progress(local_player_id) * 100.0

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo or _active_actions.is_empty():
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

		_status_unit = first if first.has_method("order_gather") else null

		if first is Animal:
			var astate: Variant = first.get("current_state")
			var owned: bool = astate != null and (astate as int) == Animal.AnimalState.OWNED
			_unit_status_label.text = tr("UI_STATUS_YOURS") if owned else tr("UI_STATUS_WILD")
			_populate_buttons([])
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

	if building is TownCenter or building is TownCenterBuilding:
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
	if is_instance_valid(_selected_building) and (_selected_building is TownCenter or _selected_building is TownCenterBuilding):
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
		if _selected_building is TownCenter or _selected_building is TownCenterBuilding:
			_populate_tc_actions()
		elif _selected_building is Barracks:
			_populate_barracks_actions(_selected_building as Barracks)

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
	if player_id == local_player_id and _clock_running:
		_stat_units_trained += 1

func _on_stat_building_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid != null and (pid as int) == local_player_id:
		_stat_buildings_built += 1

func _on_stat_unit_died(unit: Node, player_id: int) -> void:
	# Count enemy kills (enemy unit dies)
	if player_id != local_player_id:
		var udata: Variant = unit.get("unit_data")
		if udata != null:
			_stat_enemies_killed += 1

var _last_resources: Dictionary = {}

func _on_stat_resources_updated(player_id: int, resources: Dictionary) -> void:
	if player_id != local_player_id:
		return
	for res: String in ["food", "wood", "gold", "stone"]:
		var current: float = resources.get(res, 0.0) as float
		var last: float = _last_resources.get(res, current) as float
		if current > last:
			_stat_resources_gathered[res] = (_stat_resources_gathered[res] as int) + int(current - last)
		_last_resources[res] = current

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

	# Stats grid
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	var total_secs: int = int(_elapsed_seconds)
	var time_str: String = "%02d:%02d" % [total_secs / 60, total_secs % 60]
	var final_age: String = tr(["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"][clampi(AgeManager.get_age(local_player_id), 0, 3)])

	var stat_rows: Array = [
		[tr("GAMEOVER_TIME"),      time_str],
		[tr("GAMEOVER_AGE"),       final_age],
		[tr("GAMEOVER_UNITS"),     str(_stat_units_trained)],
		[tr("GAMEOVER_BUILDINGS"), str(_stat_buildings_built)],
		[tr("GAMEOVER_KILLS"),     str(_stat_enemies_killed)],
		[tr("GAMEOVER_FOOD"),      str(_stat_resources_gathered.get("food", 0))],
		[tr("GAMEOVER_WOOD"),      str(_stat_resources_gathered.get("wood", 0))],
		[tr("GAMEOVER_GOLD"),      str(_stat_resources_gathered.get("gold", 0))],
		[tr("GAMEOVER_STONE"),     str(_stat_resources_gathered.get("stone", 0))],
	]
	for row: Array in stat_rows:
		var key_lbl: Label = Label.new()
		key_lbl.text = row[0] as String
		key_lbl.add_theme_font_size_override("font_size", 15)
		key_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
		grid.add_child(key_lbl)
		var val_lbl: Label = Label.new()
		val_lbl.text = row[1] as String
		val_lbl.add_theme_font_size_override("font_size", 15)
		val_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val_lbl)

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

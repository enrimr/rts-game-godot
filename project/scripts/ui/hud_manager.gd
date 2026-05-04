extends CanvasLayer

const AGE_NAMES: Array = ["Dark Age", "Feudal Age", "Castle Age", "Imperial Age"]

signal action_requested(action_id: String)

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

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "Chop\nWood",    "color": Color(0.20, 0.55, 0.15), "cost": {}},
	{"id": "gather_gold",  "label": "Mine\nGold",    "color": Color(0.75, 0.65, 0.10), "cost": {}},
	{"id": "gather_stone", "label": "Mine\nStone",   "color": Color(0.55, 0.55, 0.55), "cost": {}},
	{"id": "gather_food",  "label": "Hunt\nFood",    "color": Color(0.60, 0.20, 0.15), "cost": {}},
	{"id": "build_menu",   "label": "Build...",      "color": Color(0.20, 0.30, 0.60), "cost": {}},
	{"id": "stop",         "label": "Stop",          "color": Color(0.50, 0.10, 0.10), "cost": {}},
]

const BUILD_ACTIONS: Array = [
	{"id": "build:house",        "label": "House\n25W",       "color": Color(0.50, 0.38, 0.22), "cost": {"wood": 25}},
	{"id": "build:barracks",     "label": "Barracks\n175W",   "color": Color(0.45, 0.22, 0.18), "cost": {"wood": 175}},
	{"id": "build:lumber_camp",  "label": "Lumber\n100W",     "color": Color(0.30, 0.20, 0.08), "cost": {"wood": 100}},
	{"id": "build:mining_camp",  "label": "Mining\n100W",     "color": Color(0.50, 0.46, 0.34), "cost": {"wood": 100}},
	{"id": "build:farm",         "label": "Farm\n60W",        "color": Color(0.60, 0.52, 0.18), "cost": {"wood": 60}},
	{"id": "back",               "label": "← Back",           "color": Color(0.25, 0.25, 0.25), "cost": {}},
]

const BARRACKS_ACTIONS: Array = [
	{"id": "train:militia", "label": "Train\nMilitia\n60F 20W", "color": Color(0.5, 0.2, 0.1), "cost": {"food": 60, "wood": 20}},
]

const TOWN_CENTER_ACTIONS: Array = [
	{"id": "train:villager", "label": "Train\nVillager\n50F", "color": Color(0.20, 0.45, 0.20), "cost": {"food": 50}},
]

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _in_build_menu: bool = false
var _selected_building: Node = null
var _status_unit: Node = null

func _ready() -> void:
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.train_queue_changed.connect(_on_train_queue_changed)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_paused.connect(toggle_pause)
	_pause_overlay.visible = false
	_clock_label.text = "00:00"
	_unit_name_label.text = ""
	_unit_hp_bar.value = 0.0

func _process(delta: float) -> void:
	if _clock_running:
		_elapsed_seconds += delta
		var total_secs: int = int(_elapsed_seconds)
		_clock_label.text = "%02d:%02d" % [total_secs / 60, total_secs % 60]
	if is_instance_valid(_status_unit):
		_unit_status_label.text = _get_unit_status(_status_unit)

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
		var display_name: String = "Unit"
		var unit_data: Variant = first.get("unit_data")
		if unit_data != null:
			var name_val: Variant = (unit_data as Resource).get("display_name")
			if name_val != null:
				display_name = name_val as String
		_unit_name_label.text = display_name

		var hp_variant: Variant = first.get("health")
		var hp: float = hp_variant as float if hp_variant != null else 100.0
		var max_hp: float = 100.0
		if unit_data != null:
			var max_hp_v: Variant = (unit_data as Resource).get("max_health")
			if max_hp_v != null:
				max_hp = max_hp_v as float
		if max_hp > 0.0:
			_unit_hp_bar.value = (hp / max_hp) * 100.0

		_status_unit = first if first.has_method("order_gather") else null

		if first.has_method("order_gather"):
			_populate_buttons(VILLAGER_ACTIONS)

func update_age(age: int) -> void:
	_age_label.text = AGE_NAMES[clampi(age, 0, AGE_NAMES.size() - 1)]

func toggle_pause(is_paused: bool) -> void:
	_pause_overlay.visible = is_paused

# --- Private ---

func _clear_action_buttons() -> void:
	for child: Node in _action_grid.get_children():
		child.queue_free()
	for child: Node in _train_queue_row.get_children():
		child.queue_free()

func _populate_buttons(actions: Array) -> void:
	_clear_action_buttons()
	for entry: Variant in actions:
		var data: Dictionary = entry as Dictionary
		var btn: ActionButton = ActionButton.new()
		btn.action_id = data["id"] as String
		btn.text = data["label"] as String
		var color: Color = data["color"] as Color
		var cost: Dictionary = data.get("cost", {}) as Dictionary
		btn.set_meta("cost", cost)
		btn.set_meta("base_color", color)
		btn.set_meta("base_label", btn.text)
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

func _refresh_button_states() -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var cost: Dictionary = btn.get_meta("cost", {}) as Dictionary
		var base_color: Color = btn.get_meta("base_color", Color(0.3, 0.3, 0.3)) as Color
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(local_player_id, cost)
		btn.disabled = not can_pay
		var effective_color: Color = base_color if can_pay else Color(0.25, 0.25, 0.25)
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
		_in_build_menu = true
		_populate_buttons(BUILD_ACTIONS)
		return
	if action_id == "back":
		_in_build_menu = false
		_populate_buttons(VILLAGER_ACTIONS)
		return
	action_requested.emit(action_id)

func _on_game_started() -> void:
	_elapsed_seconds = 0.0
	_clock_running = true

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
	_selected_building = null
	update_selection(units)

func _on_building_selected(building: Node) -> void:
	_selected_building = building
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

	var display_name: String = "Building"
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

	if building is TownCenter:
		_unit_name_label.text = "Town Center"
		_unit_hp_bar.value = 0.0
		_populate_buttons(TOWN_CENTER_ACTIONS)
		var tc: TownCenter = building as TownCenter
		_on_train_queue_changed(building, tc.get_queue(), tc.get_max_queue())
	elif building is Barracks:
		_populate_buttons(BARRACKS_ACTIONS)
		var br: Barracks = building as Barracks
		_on_train_queue_changed(building, br.get_queue(), br.get_max_queue())

func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id != local_player_id:
		return
	_population_label.text = "Pop: %d/%d" % [current, cap]

func _on_age_advance_complete(player_id: int, new_age: int) -> void:
	if player_id != local_player_id:
		return
	update_age(new_age)

func _get_unit_status(unit: Node) -> String:
	var state_v: Variant = unit.get("current_state")
	if state_v == null:
		return ""
	var state: int = state_v as int
	match state:
		1: # MOVING
			return "Moving"
		2: # ATTACKING
			return "Attacking"
		3: # GATHERING
			var resource: Variant = unit.get("carried_resource")
			var amount: Variant = unit.get("carried_amount")
			if resource != null and amount != null:
				var r: String = resource as String
				var a: float = amount as float
				if r.is_empty():
					return "Gathering"
				return "Gathering %s  %d / %d" % [r.capitalize(), int(a),
					int((unit.get("carry_capacity") as float) if unit.get("carry_capacity") != null else 10.0)]
			return "Gathering"
		4: # RETURNING
			var resource: Variant = unit.get("carried_resource")
			var amount: Variant = unit.get("carried_amount")
			if resource != null and amount != null:
				return "Returning  %s %d" % [(resource as String).capitalize(), int(amount as float)]
			return "Returning"
		5: # BUILDING
			return "Building"
		6: # DEAD
			return "Dead"
	return ""

func _on_cancel_train_slot(index: int) -> void:
	if not is_instance_valid(_selected_building):
		return
	if _selected_building.has_method("order_cancel_train"):
		_selected_building.order_cancel_train(index)

func _on_train_queue_changed(building: Node, queue: Array, max_queue: int) -> void:
	if building != _selected_building:
		return
	_refresh_button_states()
	# Update train button label with queue count
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var aid: String = btn.action_id
		if aid != "train:militia" and aid != "train:villager":
			continue
		var base_label: String = btn.get_meta("base_label", btn.text) as String
		btn.set_meta("base_label", base_label)
		var queued: int = queue.size()
		btn.text = base_label + "\n%d/%d" % [queued, max_queue]
		if queued >= max_queue:
			btn.disabled = true
	# Rebuild the visual queue row
	for slot: Node in _train_queue_row.get_children():
		slot.queue_free()
	for i: int in range(queue.size()):
		var entry: Dictionary = queue[i] as Dictionary
		var slot: TrainQueueSlot = TrainQueueSlot.new()
		_train_queue_row.add_child(slot)
		slot.setup(i, entry["label"] as String, entry["color"] as Color, i == 0)
		slot.cancel_requested.connect(_on_cancel_train_slot)

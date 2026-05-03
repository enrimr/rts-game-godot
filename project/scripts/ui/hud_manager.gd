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
@onready var _action_grid: GridContainer = %ActionButtonsGrid
@onready var _pause_overlay: ColorRect = %PauseOverlay

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "Chop\nWood",    "color": Color(0.20, 0.55, 0.15)},
	{"id": "gather_gold",  "label": "Mine\nGold",    "color": Color(0.75, 0.65, 0.10)},
	{"id": "gather_stone", "label": "Mine\nStone",   "color": Color(0.55, 0.55, 0.55)},
	{"id": "gather_food",  "label": "Hunt\nFood",    "color": Color(0.60, 0.20, 0.15)},
	{"id": "build_menu",   "label": "Build...",      "color": Color(0.20, 0.30, 0.60)},
	{"id": "stop",         "label": "Stop",          "color": Color(0.50, 0.10, 0.10)},
]

const BUILD_ACTIONS: Array = [
	{"id": "build:house",        "label": "House\n25W",       "color": Color(0.50, 0.38, 0.22)},
	{"id": "build:barracks",     "label": "Barracks\n175W",   "color": Color(0.45, 0.22, 0.18)},
	{"id": "build:lumber_camp",  "label": "Lumber\n100W",     "color": Color(0.30, 0.20, 0.08)},
	{"id": "build:mining_camp",  "label": "Mining\n100W",     "color": Color(0.50, 0.46, 0.34)},
	{"id": "build:farm",         "label": "Farm\n60W",        "color": Color(0.60, 0.52, 0.18)},
	{"id": "back",               "label": "← Back",           "color": Color(0.25, 0.25, 0.25)},
]

const BARRACKS_ACTIONS: Array = [
	{"id": "train:militia", "label": "Train\nMilitia\n60F 20W", "color": Color(0.5, 0.2, 0.1)},
]

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _in_build_menu: bool = false
var _selected_building: Node = null

func _ready() -> void:
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_paused.connect(toggle_pause)
	_pause_overlay.visible = false
	_clock_label.text = "00:00"
	_unit_name_label.text = ""
	_unit_hp_bar.value = 0.0

func _process(delta: float) -> void:
	if not _clock_running:
		return
	_elapsed_seconds += delta
	var total_secs: int = int(_elapsed_seconds)
	_clock_label.text = "%02d:%02d" % [total_secs / 60, total_secs % 60]

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

func _populate_buttons(actions: Array) -> void:
	_clear_action_buttons()
	for entry: Variant in actions:
		var data: Dictionary = entry as Dictionary
		var btn: ActionButton = ActionButton.new()
		btn.action_id = data["id"] as String
		btn.text = data["label"] as String
		var color: Color = data["color"] as Color
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", style)
		var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		hover_style.bg_color = color.lightened(0.25)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.action_pressed.connect(_on_action_button_pressed)
		_action_grid.add_child(btn)

func _on_action_button_pressed(action_id: String) -> void:
	if action_id == "build_menu":
		_in_build_menu = true
		_populate_buttons(BUILD_ACTIONS)
		return
	if action_id == "back":
		_in_build_menu = false
		_populate_buttons(VILLAGER_ACTIONS)
		return
	if action_id == "train:militia":
		if is_instance_valid(_selected_building) and _selected_building is Barracks:
			(_selected_building as Barracks).order_train()
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

func _on_unit_selected(units: Array) -> void:
	_selected_building = null
	update_selection(units)

func _on_building_selected(building: Node) -> void:
	_selected_building = building
	for child: Node in _unit_portraits_grid.get_children():
		child.queue_free()
	_clear_action_buttons()
	_in_build_menu = false

	if not is_instance_valid(building):
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
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

	if building is Barracks:
		_populate_buttons(BARRACKS_ACTIONS)

func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id != local_player_id:
		return
	_population_label.text = "Pop: %d/%d" % [current, cap]

func _on_age_advance_complete(player_id: int, new_age: int) -> void:
	if player_id != local_player_id:
		return
	update_age(new_age)

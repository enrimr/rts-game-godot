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

const DESTROY_ACTION: Dictionary = {"id": "destroy", "label": "Destroy", "color": Color(0.55, 0.05, 0.05), "cost": {}, "key": KEY_DELETE}

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "Wood",    "color": Color(0.20, 0.55, 0.15), "cost": {}, "key": KEY_C},
	{"id": "gather_gold",  "label": "Gold",    "color": Color(0.75, 0.65, 0.10), "cost": {}, "key": KEY_G},
	{"id": "gather_stone", "label": "Stone",   "color": Color(0.55, 0.55, 0.55), "cost": {}, "key": KEY_T},
	{"id": "gather_food",  "label": "Food",    "color": Color(0.60, 0.20, 0.15), "cost": {}, "key": KEY_H},
	{"id": "build_menu",   "label": "Build",   "color": Color(0.20, 0.30, 0.60), "cost": {}, "key": KEY_B},
	{"id": "stop",         "label": "Stop",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X},
	DESTROY_ACTION,
]

const BUILD_ACTIONS: Array = [
	{"id": "build:house",         "label": "House\n25W",      "color": Color(0.50, 0.38, 0.22), "cost": {"wood": 25},  "key": KEY_H},
	{"id": "build:barracks",      "label": "Barracks\n175W",  "color": Color(0.45, 0.22, 0.18), "cost": {"wood": 175}, "key": KEY_B},
	{"id": "build:lumber_camp",   "label": "Lumber\n100W",    "color": Color(0.30, 0.20, 0.08), "cost": {"wood": 100}, "key": KEY_L},
	{"id": "build:mining_camp",   "label": "Mining\n100W",    "color": Color(0.50, 0.46, 0.34), "cost": {"wood": 100}, "key": KEY_N},
	{"id": "build:farm",          "label": "Farm\n60W",       "color": Color(0.60, 0.52, 0.18), "cost": {"wood": 60},  "key": KEY_F},
	{"id": "build:wall_segment",  "label": "Wall\n5S",        "color": Color(0.55, 0.52, 0.48), "cost": {"stone": 5},  "key": KEY_W},
	{"id": "build:gate",          "label": "Gate\n30W",       "color": Color(0.42, 0.30, 0.12), "cost": {"wood": 30},  "key": KEY_G},
	{"id": "back",                "label": "← Back",          "color": Color(0.25, 0.25, 0.25), "cost": {},            "key": KEY_ESCAPE},
]

const BARRACKS_ACTIONS: Array = [
	{"id": "train:militia", "label": "Militia\n60F 20W", "color": Color(0.5, 0.2, 0.1), "cost": {"food": 60, "wood": 20}, "key": KEY_M},
	DESTROY_ACTION,
]

const TOWN_CENTER_ACTIONS: Array = [
	{"id": "train:villager", "label": "Villager\n50F", "color": Color(0.20, 0.45, 0.20), "cost": {"food": 50}, "key": KEY_V},
]

const UNIT_ACTIONS: Array = [
	{"id": "stop",    "label": "Stop",    "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X},
	DESTROY_ACTION,
]

const BUILDING_ACTIONS: Array = [
	DESTROY_ACTION,
]

const GATE_ACTIONS: Array = [
	{"id": "gate_lock", "label": "Lock", "color": Color(0.55, 0.15, 0.10), "cost": {}, "key": KEY_O},
	DESTROY_ACTION,
]

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _in_build_menu: bool = false
var _selected_building: Node = null
var _status_unit: Node = null
var _active_actions: Array = []

func _ready() -> void:
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.train_queue_changed.connect(_on_train_queue_changed)
	EventBus.resource_node_selected.connect(_on_resource_node_selected)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_paused.connect(toggle_pause)
	GameManager.game_over.connect(_on_game_over)
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
		var display_name: String = "Unit"
		var unit_data: Variant = first.get("unit_data")
		if unit_data != null:
			var name_val: Variant = (unit_data as Resource).get("display_name")
			if name_val != null:
				display_name = name_val as String
		elif first is Animal:
			var aname: Variant = first.get("animal_name")
			display_name = aname as String if aname != null else "Animal"
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
			_unit_status_label.text = "Yours" if owned else "Wild"
			_populate_buttons([])
		elif first.has_method("order_gather"):
			_populate_buttons(VILLAGER_ACTIONS)
		else:
			_populate_buttons(UNIT_ACTIONS)

func update_age(age: int) -> void:
	_age_label.text = AGE_NAMES[clampi(age, 0, AGE_NAMES.size() - 1)]

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
		btn.text = key_hint + (data["label"] as String)
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
	elif building is Gate:
		var gate: Gate = building as Gate
		_populate_buttons(GATE_ACTIONS)
		_refresh_gate_toggle_label(gate)
		_unit_status_label.text = "LOCKED" if gate.locked else ("Open" if gate.is_open else "Closed")
		if not gate.gate_toggled.is_connected(_on_gate_toggled):
			gate.gate_toggled.connect(_on_gate_toggled)
	else:
		_populate_buttons(BUILDING_ACTIONS)

func _on_gate_toggled(_is_open: bool) -> void:
	if is_instance_valid(_selected_building) and _selected_building is Gate:
		var gate: Gate = _selected_building as Gate
		_refresh_gate_toggle_label(gate)
		_unit_status_label.text = "LOCKED" if gate.locked else ("Open" if gate.is_open else "Closed")

func _refresh_gate_toggle_label(gate: Gate) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id != "gate_lock":
			continue
		btn.text = "[O] " + ("Unlock" if gate.locked else "Lock")

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

func _on_resource_node_selected(node: Node) -> void:
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
		_selected_building = null
		_on_building_selected(null)

func _on_unit_died(unit: Node, _player_id: int) -> void:
	_status_unit = null

func _on_game_over(winner_player_id: int) -> void:
	_clock_running = false
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	get_node("HUDRoot").add_child(overlay)

	var lbl: Label = Label.new()
	lbl.text = "VICTORIA!" if winner_player_id == 0 else "DERROTA"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 96)
	var col: Color = Color(0.2, 1.0, 0.3) if winner_player_id == 0 else Color(1.0, 0.2, 0.2)
	lbl.add_theme_color_override("font_color", col)
	overlay.add_child(lbl)

	var sub: Label = Label.new()
	sub.text = "Pulsa Escape para salir"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.offset_top = -80.0
	sub.offset_bottom = -40.0
	sub.offset_left = -300.0
	sub.offset_right = 300.0
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	overlay.add_child(sub)

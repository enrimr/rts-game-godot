extends CanvasLayer

const AGE_NAMES: Array = ["Dark Age", "Feudal Age", "Castle Age", "Imperial Age"]

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
@onready var _pause_overlay: ColorRect = %PauseOverlay

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false

func _ready() -> void:
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.unit_selected.connect(_on_unit_selected)
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
	var mins: int = total_secs / 60
	var secs: int = total_secs % 60
	_clock_label.text = "%02d:%02d" % [mins, secs]

func update_resources(player_id: int, resources: Dictionary) -> void:
	if player_id != local_player_id:
		return
	_food_display.set_amount(int(resources.get("food", 0)))
	_wood_display.set_amount(int(resources.get("wood", 0)))
	_gold_display.set_amount(int(resources.get("gold", 0)))
	_stone_display.set_amount(int(resources.get("stone", 0)))

func update_selection(units: Array) -> void:
	for child in _unit_portraits_grid.get_children():
		child.queue_free()

	if units.is_empty():
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		return

	var capped: Array = units.slice(0, 40)
	for unit in capped:
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
			display_name = (unit_data as Resource).get("display_name") as String
			if display_name.is_empty():
				display_name = "Unit"
		_unit_name_label.text = display_name

		var hp_variant: Variant = first.get("health")
		var hp: float = hp_variant as float if hp_variant != null else 100.0
		var max_hp: float = 100.0
		if unit_data != null:
			var max_hp_variant: Variant = (unit_data as Resource).get("max_health")
			if max_hp_variant != null:
				max_hp = max_hp_variant as float
		if max_hp > 0.0:
			_unit_hp_bar.value = (hp / max_hp) * 100.0

func update_age(age: int) -> void:
	var clamped_age: int = clampi(age, 0, AGE_NAMES.size() - 1)
	_age_label.text = AGE_NAMES[clamped_age]

func toggle_pause(is_paused: bool) -> void:
	_pause_overlay.visible = is_paused

func _on_game_started() -> void:
	_elapsed_seconds = 0.0
	_clock_running = true

func _on_resource_changed(player_id: int, resource: String, amount: int) -> void:
	if player_id != local_player_id:
		return
	match resource:
		"food":
			_food_display.set_amount(amount)
		"wood":
			_wood_display.set_amount(amount)
		"gold":
			_gold_display.set_amount(amount)
		"stone":
			_stone_display.set_amount(amount)

func _on_unit_selected(units: Array) -> void:
	update_selection(units)

func _on_age_advance_complete(player_id: int, new_age: int) -> void:
	if player_id != local_player_id:
		return
	update_age(new_age)

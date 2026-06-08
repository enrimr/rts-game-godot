class_name HudResourceBar
extends Node

## Top-bar readouts: the four ResourceDisplay counters (food/wood/gold/stone)
## with their gatherer sub-counts, the population label (with at-cap flash),
## and the age label. Self-wires to the relevant EventBus signals; updates only
## its own labels. The action menu listens to the same signals independently for
## button-affordability refreshes, so this component stays display-only.

var local_player_id: int = 0
var _food_display: ResourceDisplay = null
var _wood_display: ResourceDisplay = null
var _gold_display: ResourceDisplay = null
var _stone_display: ResourceDisplay = null
var _population_label: Label = null
var _age_label: Label = null

var _gatherer_counts: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}

func init(player_id: int, food: ResourceDisplay, wood: ResourceDisplay, gold: ResourceDisplay,
		stone: ResourceDisplay, population: Label, age: Label) -> void:
	local_player_id = player_id
	_food_display = food
	_wood_display = wood
	_gold_display = gold
	_stone_display = stone
	_population_label = population
	_age_label = age

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.gatherer_changed.connect(_on_gatherer_changed)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)

func update_resources(player_id: int, resources: Dictionary) -> void:
	if player_id != local_player_id:
		return
	_food_display.set_amount(int(resources.get("food", 0)))
	_wood_display.set_amount(int(resources.get("wood", 0)))
	_gold_display.set_amount(int(resources.get("gold", 0)))
	_stone_display.set_amount(int(resources.get("stone", 0)))

func update_age(age: int) -> void:
	_age_label.text = tr(["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"][clampi(age, 0, 3)])

func _on_resource_changed(player_id: int, resource: String, amount: int) -> void:
	if player_id != local_player_id:
		return
	match resource:
		"food":  _food_display.set_amount(amount)
		"wood":  _wood_display.set_amount(amount)
		"gold":  _gold_display.set_amount(amount)
		"stone": _stone_display.set_amount(amount)

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

func _on_age_advance_complete(player_id: int, new_age: int) -> void:
	if player_id != local_player_id:
		return
	update_age(new_age)

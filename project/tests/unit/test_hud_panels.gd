extends GutTest

## HUD action-panel contract after the HudActionMenu extraction: selecting a
## production building yields its train/research buttons, every price shown
## comes from the same data the simulation charges (.tres via HudActionDefs /
## WorldPlacement.building_costs — never a hardcoded table), and the build
## menu matches the placement cost table entry by entry.
##
## Runs the REAL hud.tscn headlessly: buttons are created synchronously by
## HudActionMenu.populate, so the grid can be asserted without awaits.

var _hud: CanvasLayer = null

func before_each() -> void:
	MatchConfig.replay_path = ""
	NetworkSession.local_player_id = 0
	ResourceManager.init_player(0,
		{"food": 9999, "wood": 9999, "gold": 9999, "stone": 9999})
	AgeManager.init_player(0, GameManager.Age.IMPERIAL)
	TechManager.init_player(0)
	CivBonusManager.init_player(0, "guanches")
	_hud = (load("res://scenes/ui/hud/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	add_child_autofree(_hud)

func _select_building(scene: String) -> Node:
	var building: Node2D = (load(scene) as PackedScene).instantiate() as Node2D
	building.set("player_id", 0)
	add_child_autofree(building)
	building.call("force_complete")
	_hud.call("_on_building_selected", building)
	return building

## action_id -> cost meta for every ActionButton in the grid.
func _grid_costs() -> Dictionary:
	var out: Dictionary = {}
	var grid: GridContainer = _hud.get_node("%ActionButtonsGrid") as GridContainer
	for child: Node in grid.get_children():
		if child is ActionButton:
			out[(child as ActionButton).action_id] = child.get_meta("cost", {})
	return out

func test_barracks_train_buttons_price_from_tres() -> void:
	_select_building("res://scenes/buildings/barracks.tscn")
	var costs: Dictionary = _grid_costs()
	assert_true(costs.has("train:militia"), "barracks trains militia")
	var militia: UnitResource = load("res://resources/units/militia_data.tres") as UnitResource
	assert_eq(costs["train:militia"], HudActionDefs.unit_costs(militia),
		"the button charges exactly what the .tres says")
	assert_true(costs.has("destroy"))

func test_mill_panel_has_dog_and_research_from_data() -> void:
	_select_building("res://scenes/buildings/mill.tscn")
	var costs: Dictionary = _grid_costs()
	var dog: UnitResource = load("res://resources/units/presa_canario_data.tres") as UnitResource
	assert_true(costs.has("train:presa_canario"), "mill trains the Presa Canario")
	assert_eq(costs["train:presa_canario"], HudActionDefs.unit_costs(dog))
	assert_true(costs.has("research:horse_collar"), "mill offers the food line")

func test_temple_trains_harimaguada_priced_from_tres() -> void:
	_select_building("res://scenes/buildings/temple.tscn")
	var costs: Dictionary = _grid_costs()
	var hari: UnitResource = load("res://resources/units/harimaguada_data.tres") as UnitResource
	assert_true(costs.has("train:harimaguada"))
	assert_eq(costs["train:harimaguada"], HudActionDefs.unit_costs(hari))

func test_town_center_villager_priced_from_tres() -> void:
	_select_building("res://scenes/buildings/town_center.tscn")
	var costs: Dictionary = _grid_costs()
	var villager: UnitResource = load("res://resources/units/villager_data.tres") as UnitResource
	assert_true(costs.has("train:villager"))
	assert_eq(costs["train:villager"], HudActionDefs.unit_costs(villager))
	assert_true(costs.has("town_bell"))
	assert_false(costs.has("advance_age"), "no advance button at Imperial")

func test_lumber_camp_offers_wood_line() -> void:
	_select_building("res://scenes/buildings/lumber_camp.tscn")
	var costs: Dictionary = _grid_costs()
	assert_true(costs.has("research:double_bit_axe"),
		"the camp opens its economy line")

func test_build_menu_prices_match_placement_table() -> void:
	var menu: HudActionMenu = _hud.get("_menu") as HudActionMenu
	var checked: int = 0
	for entry: Variant in menu._filtered_build_actions():
		var data: Dictionary = entry as Dictionary
		var bid: String = data.get("id", "") as String
		if not bid.begins_with("build:"):
			continue
		var expected: Dictionary = WorldPlacement.building_costs(bid.trim_prefix("build:"))
		assert_false(expected.is_empty(), "%s must have a .tres price" % bid)
		assert_eq(data.get("cost"), expected,
			"%s button must charge the placement table price" % bid)
		checked += 1
	assert_gt(checked, 12, "the whole build menu was audited")

func test_tutorial_grant_flows_through_event_bus() -> void:
	# The HUD never touches a stockpile: lesson top-ups are emitted for the
	# world to apply (game_world connects tutorial_grant_resources).
	var granted: Array = []
	var handler: Callable = func(pid: int, res: String, amount: int) -> void:
		granted.append([pid, res, amount])
	EventBus.tutorial_grant_resources.connect(handler)
	ResourceManager.init_player(0, {"food": 0, "wood": 0, "gold": 0, "stone": 0})
	var tut: HudTutorial = _hud.get("_tutorial") as HudTutorial
	tut._on_step_changed(5, "age_advance_complete")   # lesson needs 500 food
	EventBus.tutorial_grant_resources.disconnect(handler)
	assert_eq(granted, [[0, "food", 500]])

func test_replay_shows_info_but_no_action_buttons() -> void:
	# A replay is recorded history: selecting your own building must show the
	# info panel but offer NO commands (buttons or hotkeys).
	MatchConfig.replay_path = "user://replays/some_replay.calrep"
	_select_building("res://scenes/buildings/barracks.tscn")
	assert_eq(_grid_costs(), {}, "no buttons over a recording")
	var menu: HudActionMenu = _hud.get("_menu") as HudActionMenu
	assert_eq((menu.get("_active_actions") as Array).size(), 0,
		"no hotkeys either — the action list stays empty")
	MatchConfig.replay_path = ""

func test_enemy_building_shows_no_action_buttons() -> void:
	var building: Node2D = (load("res://scenes/buildings/barracks.tscn") as PackedScene)\
		.instantiate() as Node2D
	building.set("player_id", 1)
	add_child_autofree(building)
	building.call("force_complete")
	_hud.call("_on_building_selected", building)
	assert_eq(_grid_costs(), {}, "an enemy building offers you nothing")

extends GutTest

## Research lifecycle for the queue UI: start emits research_state_changed,
## cancel refunds in full and clears the active research, and the whole flow
## routes through ProductionCommand like every other production order.

class StubBuilding extends Node2D:
	var player_id: int = 0

var _building: StubBuilding = null
var _events: Array[Node] = []

func before_each() -> void:
	_building = StubBuilding.new()
	add_child_autofree(_building)
	TechManager.init_player(0)
	ResourceManager.init_player(0, {"food": 999, "wood": 999, "gold": 999, "stone": 999})
	_events.clear()
	EventBus.research_state_changed.connect(_capture)

func after_each() -> void:
	EventBus.research_state_changed.disconnect(_capture)
	TechManager.cancel_research(_building)

func _capture(building: Node) -> void:
	_events.append(building)

## Any Dark-Age tech without prerequisites works for the lifecycle checks.
func _pick_starter_tech() -> TechnologyResource:
	for tech_id: String in TechManager._all_techs.keys():
		var tech: TechnologyResource = TechManager._all_techs[tech_id] as TechnologyResource
		if tech.required_age == 0 and tech.prerequisites.is_empty():
			return tech
	return null

func test_start_emits_state_change_for_the_building() -> void:
	var tech: TechnologyResource = _pick_starter_tech()
	assert_not_null(tech)
	assert_true(TechManager.start_research(0, tech.id, _building))
	assert_eq(_events, [_building] as Array[Node],
		"the HUD needs the signal to show the research slot immediately")
	assert_eq(TechManager.get_researching_tech(_building), tech)

func test_cancel_refunds_in_full_and_clears() -> void:
	var tech: TechnologyResource = _pick_starter_tech()
	var before: Dictionary = ResourceManager.get_resources(0).duplicate()
	TechManager.start_research(0, tech.id, _building)
	assert_true(TechManager.cancel_research(_building))
	var after: Dictionary = ResourceManager.get_resources(0)
	for res: String in before:
		assert_almost_eq(float(after.get(res, -1.0)), float(before[res]), 0.01,
			"cancelling refunds the %s the research charged" % res)
	assert_null(TechManager.get_researching_tech(_building), "nothing left in progress")
	assert_eq(_events.size(), 2, "start + cancel both notified the HUD")

func test_cancel_without_active_research_is_a_noop() -> void:
	assert_false(TechManager.cancel_research(_building))

func test_cancel_research_command_routes_ownership() -> void:
	var holder: Node2D = Node2D.new()
	add_child_autofree(holder)
	CommandBus.start_match(holder)
	var tech: TechnologyResource = _pick_starter_tech()
	TechManager.start_research(0, tech.id, _building)
	# Foreign player must not cancel our research…
	CommandBus.submit(ProductionCommand.make(1, "cancel_research",
		EntityRegistry.id_of(_building)))
	assert_not_null(TechManager.get_researching_tech(_building),
		"another player's cancel command is rejected by the ownership gate")
	# …but our own command does.
	CommandBus.submit(ProductionCommand.make(0, "cancel_research",
		EntityRegistry.id_of(_building)))
	assert_null(TechManager.get_researching_tech(_building))
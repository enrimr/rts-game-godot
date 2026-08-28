extends GutTest

## ActionButton._make_custom_tooltip: the rich hover popup carries the plain
## text plus a glyph cost row; buttons without costs keep the default tooltip.

func test_costs_produce_rich_tooltip() -> void:
	var btn: ActionButton = ActionButton.new()
	add_child_autofree(btn)
	btn.action_costs = {"wood": 25}
	var tip: Control = btn._make_custom_tooltip("Casa  [H]") as Control
	assert_not_null(tip, "cost buttons build a rich tooltip")
	autofree(tip)
	var labels: int = 0
	var has_cost_row: bool = false
	for child: Node in tip.get_children():
		if child is Label:
			labels += 1
		elif child is HBoxContainer:
			has_cost_row = true
	assert_gt(labels, 0, "the plain text is kept in the popup")
	assert_true(has_cost_row, "the glyph cost row is embedded")

func test_no_costs_fall_back_to_default() -> void:
	var btn: ActionButton = ActionButton.new()
	add_child_autofree(btn)
	assert_null(btn._make_custom_tooltip("Parar  [X]"),
		"cost-less buttons keep the engine's default text tooltip")

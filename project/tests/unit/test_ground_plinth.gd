extends GutTest

## S2b gap 2 — the team-colour ownership marker under units must be a thin
## ground-ring OUTLINE that is visible ONLY while the unit is selected (the
## old always-on filled disc made units look like they stood in ponds and
## drowned the selection state).
##
## Covered:
##   1. add_ground_plinth creates a Line2D ring named PlayerColorStripe
##   2. ring starts hidden when the parent is unselected (or has no
##      is_selected property at all — e.g. wild animals)
##   3. ring starts visible when the parent is already selected
##   4. re-calling recolours the same ring for the new owner
##   5. a legacy filled Polygon2D plinth is replaced by the ring

class FakeUnit extends Node2D:
	var is_selected: bool = false

func _make_unit(selected: bool) -> FakeUnit:
	var u: FakeUnit = FakeUnit.new()
	u.is_selected = selected
	add_child_autofree(u)
	return u

func test_plinth_is_a_ring_outline() -> void:
	var u: FakeUnit = _make_unit(false)
	VisualFx.add_ground_plinth(u, 0, 10.0, 5.0)
	var ring: Line2D = u.get_node_or_null("PlayerColorStripe") as Line2D
	assert_not_null(ring, "ownership marker should be a Line2D ring")
	assert_true(ring.closed, "ring should be a closed outline")

func test_plinth_hidden_while_unselected() -> void:
	var u: FakeUnit = _make_unit(false)
	VisualFx.add_ground_plinth(u, 0, 10.0, 5.0)
	var ring: Line2D = u.get_node("PlayerColorStripe") as Line2D
	assert_false(ring.visible, "ring must stay hidden while unselected")

func test_plinth_hidden_when_parent_has_no_selection_property() -> void:
	var plain: Node2D = Node2D.new()
	add_child_autofree(plain)
	VisualFx.add_ground_plinth(plain, 2, 8.0, 4.0)
	var ring: Line2D = plain.get_node("PlayerColorStripe") as Line2D
	assert_false(ring.visible, "no is_selected property -> treat as unselected")

func test_plinth_visible_while_selected() -> void:
	var u: FakeUnit = _make_unit(true)
	VisualFx.add_ground_plinth(u, 1, 10.0, 5.0)
	var ring: Line2D = u.get_node("PlayerColorStripe") as Line2D
	assert_true(ring.visible, "ring must show while selected")

func test_plinth_recolours_same_ring_on_owner_change() -> void:
	var u: FakeUnit = _make_unit(false)
	VisualFx.add_ground_plinth(u, 0, 10.0, 5.0)
	var first: Line2D = u.get_node("PlayerColorStripe") as Line2D
	VisualFx.add_ground_plinth(u, 1, 10.0, 5.0)
	var second: Line2D = u.get_node("PlayerColorStripe") as Line2D
	assert_same(first, second, "re-call must reuse the existing ring")
	var expected: Color = PlayerColors.get_color(1)
	expected.a = 0.9
	assert_eq(second.default_color, expected, "ring recoloured to new owner")

func test_legacy_filled_plinth_is_replaced() -> void:
	var u: FakeUnit = _make_unit(false)
	var legacy: Polygon2D = Polygon2D.new()
	legacy.name = "PlayerColorStripe"
	u.add_child(legacy)
	VisualFx.add_ground_plinth(u, 0, 10.0, 5.0)
	var ring: Line2D = u.get_node_or_null("PlayerColorStripe") as Line2D
	assert_not_null(ring, "legacy filled plinth must be replaced by the ring")

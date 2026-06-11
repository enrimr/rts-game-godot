extends GutTest

## Regression guard for the freeze caused by AIEconomy.find_nearest_drop_off
## returning a previously-freed Town Center: _ai.drop_off is only reassigned on
## TC rebuild, so after the TC is destroyed it dangles. The query must never
## hand back a freed instance — it returns null instead.

const ECON := preload("res://scripts/ai/ai_economy.gd")

# Minimal AIPlayer stand-in: AIEconomy only reads these off _ai.
class FakeAI:
	extends RefCounted
	var player_id: int = 1
	var drop_off: Node2D = null
	var town_center: Node2D = null
	var world: WorldQuery
	func _init() -> void:
		# Empty layers -> own_buildings returns [], so find_nearest_drop_off
		# falls through to the base drop-off branch we want to exercise.
		world = WorldQuery.new(null, null)

func _econ() -> AIEconomy:
	var e: AIEconomy = ECON.new()
	var ai: FakeAI = FakeAI.new()
	e._ai = ai
	return e

# 1 — a valid drop-off is returned as-is
func test_valid_drop_off_returned() -> void:
	var e: AIEconomy = _econ()
	var tc: Node2D = autofree(Node2D.new())
	e._ai.drop_off = tc
	assert_eq(e._base_drop_off(), tc, "valid drop-off passes through")
	assert_eq(e.find_nearest_drop_off(ResourceNode.ResourceType.FOOD_BERRY), tc,
		"food gather falls back to the valid base drop-off")

# 2 — a freed drop-off yields null, never the dangling instance
func test_freed_drop_off_returns_null() -> void:
	var e: AIEconomy = _econ()
	var tc: Node2D = Node2D.new()
	e._ai.drop_off = tc
	tc.free()   # simulate the Town Center being destroyed mid-match
	assert_false(is_instance_valid(e._ai.drop_off), "precondition: drop_off now dangles")
	assert_null(e._base_drop_off(), "_base_drop_off must not return a freed instance")
	assert_null(e.find_nearest_drop_off(ResourceNode.ResourceType.WOOD),
		"wood drop-off search with no camps + freed TC returns null, not a freed node")

# 3 — null drop-off is handled
func test_null_drop_off() -> void:
	var e: AIEconomy = _econ()
	e._ai.drop_off = null
	assert_null(e._base_drop_off())

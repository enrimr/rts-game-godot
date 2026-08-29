extends GutTest

## Tests for the AIPlayer building-cost fix.
##
## What is covered:
##   1.  BuildingResource.get_cost_dict() returns only non-zero entries
##   2.  get_cost_dict() on a wood-only building omits food/stone/gold keys
##   3.  get_cost_dict() on the Wonder returns all four resource keys
##   4.  AIPlayer._load_building_costs() populates _building_costs for barracks
##   5.  _building_costs["barracks"] matches the barracks.tres values exactly
##   6.  _building_costs is populated for every key in BUILDING_SCENES
##   7.  Changing cost_wood on a BuildingResource changes get_cost_dict() output
##   8.  A building with all-zero costs returns an empty dict (no phantom keys)
##
## What is NOT covered:
##   - can_afford / spend_resource round-trips — tested separately via ResourceManager.
##   - AI decision logic — these tests only cover the data-loading layer.
##
## Setup notes:
##   - Tests 4-6 add an AIPlayer node with add_child_autofree so _ready() fires
##     and _load_building_costs() runs. BUILDING_SCENES paths must resolve inside
##     the Godot project filesystem (res://), which they do in GUT's headless runner.
##   - Tests 1-3, 7-8 operate only on BuildingResource instances and need no scene tree.


# ---------------------------------------------------------------------------
# 1. get_cost_dict() omits zero-cost resources
# ---------------------------------------------------------------------------

func test_get_cost_dict_omits_zero_entries() -> void:
	var res: BuildingResource = BuildingResource.new()
	res.cost_wood  = 100
	res.cost_stone = 0
	res.cost_gold  = 0
	res.cost_food  = 0

	var d: Dictionary = res.get_cost_dict()

	assert_true(d.has("wood"),
		"get_cost_dict must include 'wood' when cost_wood > 0")
	assert_false(d.has("stone"),
		"get_cost_dict must omit 'stone' when cost_stone == 0")
	assert_false(d.has("gold"),
		"get_cost_dict must omit 'gold' when cost_gold == 0")
	assert_false(d.has("food"),
		"get_cost_dict must omit 'food' when cost_food == 0")


# ---------------------------------------------------------------------------
# 2. get_cost_dict() on a wood-only building returns just {"wood": N}
# ---------------------------------------------------------------------------

func test_get_cost_dict_wood_only_building() -> void:
	var res: BuildingResource = BuildingResource.new()
	res.cost_wood = 175

	var d: Dictionary = res.get_cost_dict()

	assert_eq(d.size(), 1,
		"A wood-only building must produce a dict with exactly one key")
	assert_eq(d.get("wood", 0), 175,
		"The 'wood' value must match cost_wood")


# ---------------------------------------------------------------------------
# 3. get_cost_dict() on the Wonder includes all four resources
# ---------------------------------------------------------------------------

func test_get_cost_dict_wonder_includes_all_four_resources() -> void:
	var wonder_path: String = "res://resources/buildings/wonder.tres"
	if not ResourceLoader.exists(wonder_path):
		pending("wonder.tres not found — skipping")
		return

	var res: BuildingResource = load(wonder_path) as BuildingResource
	assert_not_null(res, "wonder.tres must load as BuildingResource")

	var d: Dictionary = res.get_cost_dict()

	assert_true(d.has("wood"),  "Wonder cost dict must contain 'wood'")
	assert_true(d.has("stone"), "Wonder cost dict must contain 'stone'")
	assert_true(d.has("gold"),  "Wonder cost dict must contain 'gold'")
	assert_true(d.has("food"),  "Wonder cost dict must contain 'food'")


# ---------------------------------------------------------------------------
# 4. AIPlayer._load_building_costs() populates _building_costs
# ---------------------------------------------------------------------------

func test_ai_load_building_costs_populates_barracks() -> void:
	var ai: AIPlayer = AIPlayer.new()
	add_child_autofree(ai)
	# _ready() fires on add_child; _load_building_costs() runs inside it.

	assert_true(ai._building_costs.has("barracks"),
		"_building_costs must contain 'barracks' after _ready()")


# ---------------------------------------------------------------------------
# 5. _building_costs["barracks"] matches barracks.tres exactly
# ---------------------------------------------------------------------------

func test_ai_building_costs_barracks_matches_tres() -> void:
	var barracks_path: String = "res://resources/buildings/barracks.tres"
	if not ResourceLoader.exists(barracks_path):
		pending("barracks.tres not found — skipping")
		return

	var expected: BuildingResource = load(barracks_path) as BuildingResource
	assert_not_null(expected, "barracks.tres must load as BuildingResource")

	var ai: AIPlayer = AIPlayer.new()
	add_child_autofree(ai)

	var ai_cost: Dictionary = ai._building_costs.get("barracks", {}) as Dictionary
	var res_cost: Dictionary = expected.get_cost_dict()

	assert_eq(ai_cost, res_cost,
		"AI barracks cost dict must match the dict produced by barracks.tres")


# ---------------------------------------------------------------------------
# 6. _building_costs is populated for every id in BUILDING_SCENES
# ---------------------------------------------------------------------------

func test_ai_building_costs_covers_all_building_scenes() -> void:
	var ai: AIPlayer = AIPlayer.new()
	add_child_autofree(ai)

	var missing: Array[String] = []
	for building_id: String in AIPlayer.BUILDING_SCENES.keys():
		var res_path: String = "res://resources/buildings/%s.tres" % building_id
		if not ResourceLoader.exists(res_path):
			# .tres doesn't exist yet — that's a content gap, not an AI bug.
			continue
		if not ai._building_costs.has(building_id):
			missing.append(building_id)

	assert_eq(missing.size(), 0,
		"_building_costs must contain an entry for every BUILDING_SCENES id that has a .tres file. Missing: %s" % str(missing))


# ---------------------------------------------------------------------------
# 6b. Player and AI pay the SAME price: WorldPlacement.building_costs is the
#     single .tres-backed table both placement paths resolve at execute time
# ---------------------------------------------------------------------------

func test_player_costs_match_ai_costs_for_every_building() -> void:
	var ai: AIPlayer = AIPlayer.new()
	add_child_autofree(ai)
	for building_id: String in ai._building_costs.keys():
		assert_eq(WorldPlacement.building_costs(building_id),
			ai._building_costs[building_id] as Dictionary,
			"player and AI must pay the same for '%s'" % building_id)

func test_no_placeable_building_is_free() -> void:
	## The regression: university/market/temple were missing from the player's
	## hand-written cost table, so the player placed them for FREE while the
	## HUD showed a price and the AI paid it.
	for building_id: String in WorldPlacement.BUILDING_SCENES.keys():
		assert_false(WorldPlacement.building_costs(building_id).is_empty(),
			"'%s' must have a placement cost" % building_id)
	assert_eq(WorldPlacement.building_costs("university"), {"wood": 200})
	assert_eq(WorldPlacement.building_costs("market"), {"wood": 175})
	assert_eq(WorldPlacement.building_costs("temple"), {"wood": 175})

func test_ai_rebuilt_tc_shares_the_town_center_price() -> void:
	assert_eq(WorldPlacement.building_costs("town_center_ai"),
		WorldPlacement.building_costs("town_center"))


# ---------------------------------------------------------------------------
# 7. Changing cost_wood on a resource changes get_cost_dict() output
# ---------------------------------------------------------------------------

func test_get_cost_dict_reflects_changed_cost_wood() -> void:
	var res: BuildingResource = BuildingResource.new()
	res.cost_wood = 175

	var before: int = res.get_cost_dict().get("wood", 0) as int

	res.cost_wood = 150

	var after: int = res.get_cost_dict().get("wood", 0) as int

	assert_eq(before, 175, "Before change: wood cost must be 175")
	assert_eq(after,  150, "After change: wood cost must reflect the new value 150")


# ---------------------------------------------------------------------------
# 8. A building with all-zero costs returns an empty dict
# ---------------------------------------------------------------------------

func test_get_cost_dict_all_zero_returns_empty() -> void:
	var res: BuildingResource = BuildingResource.new()
	# All cost fields default to 0 in BuildingResource.

	var d: Dictionary = res.get_cost_dict()

	assert_eq(d.size(), 0,
		"A building with all zero costs must return an empty cost dict")

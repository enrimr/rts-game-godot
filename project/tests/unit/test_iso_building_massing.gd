extends GutTest

## Contract tests for the procedural isometric building massing: projection
## math, generated Body volumes, team-accent naming, scaffold state and
## overlay (label/bar) placement.

const EPS: float = 0.001

func test_gp_projects_square_to_two_to_one_diamond() -> void:
	var right: Vector2 = IsoBuildingMassing.gp(24.0, -24.0)
	var bottom: Vector2 = IsoBuildingMassing.gp(24.0, 24.0)
	assert_almost_eq(right.y, 0.0, EPS, "right diamond corner sits on the anchor row")
	assert_almost_eq(bottom.x, 0.0, EPS, "bottom diamond corner sits on the anchor column")
	assert_almost_eq(right.x / bottom.y, 2.0, EPS, "footprint diamond must be 2:1")

func test_gp_height_moves_straight_up_in_screen_space() -> void:
	var ground: Vector2 = IsoBuildingMassing.gp(10.0, 20.0)
	var lifted: Vector2 = IsoBuildingMassing.gp(10.0, 20.0, 15.0)
	assert_almost_eq(lifted.x, ground.x, EPS)
	assert_almost_eq(ground.y - lifted.y, 15.0, EPS)

func _instance_house() -> Node2D:
	var house: Node2D = (load("res://scenes/buildings/house.tscn") as PackedScene).instantiate() as Node2D
	return house

func test_apply_builds_walls_roof_and_footprint() -> void:
	var house: Node2D = _instance_house()
	add_child_autofree(house)
	var body: Node2D = house.get_node("Body") as Node2D
	var prefixes: Dictionary = {}
	for child: Node in body.get_children():
		prefixes[String(child.name).split("_")[0]] = true
	assert_true(prefixes.has("Footprint"), "massing has a ground footprint diamond")
	assert_true(prefixes.has("WallL"), "massing has the front-left wall face")
	assert_true(prefixes.has("WallR"), "massing has the front-right wall face")
	assert_true(prefixes.has("TeamRoof"), "roof plane is named for the team-accent pass")
	assert_true(prefixes.has("TeamRoofDark"), "shaded roof plane keeps the Dark accent variant")

func test_apply_records_massing_extents_meta() -> void:
	var house: Node2D = _instance_house()
	add_child_autofree(house)
	assert_true(house.has_meta("massing_top_y"))
	assert_true(house.has_meta("massing_bot_y"))
	assert_lt(house.get_meta("massing_top_y") as float, 0.0, "volume rises above the anchor")
	assert_gt(house.get_meta("massing_bot_y") as float, 0.0, "footprint drops below the anchor")

func test_name_label_sits_above_massing() -> void:
	var house: Node2D = _instance_house()
	add_child_autofree(house)
	var label: Label = house.get_node("NameLabel") as Label
	assert_lte(label.offset_bottom, house.get_meta("massing_top_y") as float,
		"label must not overlap the building volume")

func test_scaffold_only_visible_under_construction() -> void:
	var complete: Node2D = _instance_house()
	add_child_autofree(complete)
	complete.call("force_complete")
	var rig: Node2D = complete.get_node("ScaffoldRig") as Node2D
	assert_not_null(rig, "massing generates a scaffold rig")
	assert_false(rig.visible, "scaffold hidden once complete")

	var site: Node2D = _instance_house()
	site.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	add_child_autofree(site)
	site.call("add_construction", 10.0)
	assert_true((site.get_node("ScaffoldRig") as Node2D).visible,
		"scaffold shown while under construction")
	site.call("add_construction", 100.0)
	assert_false((site.get_node("ScaffoldRig") as Node2D).visible,
		"scaffold hidden when construction finishes")

func test_flat_ground_buildings_keep_authored_art() -> void:
	var farm: Node2D = (load("res://scenes/buildings/farm.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(farm)
	assert_false(farm.has_meta("massing_top_y"), "farm keeps its flat authored field")
	assert_not_null(farm.get_node("Body/Soil"), "authored farm plots untouched")

extends GutTest

## The minimap players overlay: one row per player (you + every rival) with
## civ, age and a score that actually moves when the game does.

func test_one_row_per_player_and_score_reacts() -> void:
	MatchConfig.player_civ_id = "guanches"
	MatchConfig.rival_count = 2
	MatchConfig.rival_civ_ids = ["castellanos", "atlantes"] as Array[String]
	var panel: HudPlayersPanel = HudPlayersPanel.new()
	add_child_autofree(panel)
	panel.call("_refresh")
	var rows: VBoxContainer = panel.get("_rows_box") as VBoxContainer
	assert_eq(rows.get_child_count(), 3, "you + two rivals")

	var base: int = panel.call("_score", 0, 0, 0) as int
	ResourceManager.init_player(0, {"food": 9999})
	assert_eq(panel.call("_score", 0, 0, 0) as int, base,
		"hoarded stockpile does NOT move the score — spending on army does")
	assert_gt(panel.call("_score", 0, 5, 2) as int, base,
		"units and buildings move it")

func after_each() -> void:
	MatchConfig.rival_count = 1
	MatchConfig.rival_civ_ids = ["castellanos"] as Array[String]
	ResourceManager.init_player(0, {})

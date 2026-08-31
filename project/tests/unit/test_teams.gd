extends GutTest

## Teams & alliances: GameManager.are_allied is the single diplomacy choke
## point — auto-acquisition, the AI's world queries and victory all read it.

func after_each() -> void:
	MatchConfig.player_teams.clear()

func _spawn_militia(pid: int) -> Node2D:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	unit.set("player_id", pid)
	add_child_autofree(unit)
	return unit

func test_are_allied_rules() -> void:
	assert_true(GameManager.are_allied(1, 1), "everyone is allied with themselves")
	assert_false(GameManager.are_allied(0, 1), "no teams -> free for all")
	MatchConfig.player_teams = {0: 1, 1: 1, 2: 2}
	assert_true(GameManager.are_allied(0, 1), "same team allies")
	assert_false(GameManager.are_allied(0, 2), "different team is hostile")
	assert_false(GameManager.are_allied(2, 3), "team vs teamless is hostile")
	MatchConfig.player_teams = {0: 0, 1: 0}
	assert_false(GameManager.are_allied(0, 1), "team 0 means NO team, never an alliance")

func test_auto_acquisition_skips_allies() -> void:
	MatchConfig.player_teams = {0: 1, 1: 1}
	var mine: Node2D = _spawn_militia(0)
	var ally: Node2D = _spawn_militia(1)
	mine.call("_on_enemy_entered_range", ally)
	assert_null(mine.get("attack_target"), "an allied unit in range is ignored")
	MatchConfig.player_teams.clear()
	mine.call("_on_enemy_entered_range", ally)
	assert_eq(mine.get("attack_target"), ally, "the same unit is hostile without teams")

func test_world_query_enemy_excludes_allies() -> void:
	MatchConfig.player_teams = {1: 3, 2: 3}
	var layer: Node2D = autofree(Node2D.new())
	add_child(layer)
	var friendly: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	friendly.set("player_id", 2)
	layer.add_child(friendly)
	var hostile: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	hostile.set("player_id", 0)
	layer.add_child(hostile)
	var q: WorldQuery = WorldQuery.new(layer, autofree(Node2D.new()))
	var enemies: Array = q._collect(layer, 1, false, false)
	assert_eq(enemies.size(), 1, "the team-mate is not an enemy")
	assert_eq(enemies[0], hostile)

func test_teams_survive_the_start_config() -> void:
	var cfg: Dictionary = NetworkSession.snapshot_config()
	cfg["player_teams"] = {0: 1, "1": "1", 2: 2}
	NetworkSession.apply_config(cfg)
	assert_true(GameManager.are_allied(0, 1),
		"teams normalize even when JSON stringified the keys/values")
	assert_false(GameManager.are_allied(0, 2))

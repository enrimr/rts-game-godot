extends GutTest

## Smoke test: the main gameplay scenes load with their full dependency
## chain (scripts, sub-scenes, resources). Catches broken ext_resource ids /
## load_steps after hand-editing .tscn files. Loading only — instantiating
## game_world would start a full match.

func test_game_world_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/game/game_world.tscn") as PackedScene
	assert_not_null(scene, "game_world.tscn must load with all dependencies")

func test_hud_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/ui/hud/hud.tscn") as PackedScene
	assert_not_null(scene, "hud.tscn must load with all dependencies")

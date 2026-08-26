extends GutTest

## IconBaker — runtime-baked HUD entity icons.
##
## Covered:
##   1. get_icon is headless-safe: returns a valid ICON_SIZE texture at once
##      (placeholder until/unless the offscreen render lands)
##   2. cache hit: same (scene, civ) key returns the SAME texture instance
##   3. cache key is per-civilization: two players of different civs get
##      different textures for the same scene
##   4. clear_cache forces a fresh instance
##   5. baking leaves no zombie members in gameplay groups ("buildings",
##      "animals") — a leak there would corrupt victory-condition checks

const VILLAGER_SCENE: String = "res://scenes/units/villager.tscn"
const BARRACKS_SCENE: String = "res://scenes/buildings/barracks.tscn"
const SHEEP_SCENE: String = "res://scenes/units/sheep.tscn"

var _prev_player_civ: String
var _prev_rival_civ: String

func before_each() -> void:
	_prev_player_civ = MatchConfig.player_civ_id
	_prev_rival_civ = MatchConfig.get_rival_civ_id(1)
	MatchConfig.player_civ_id = "mahos"
	IconBaker.clear_cache()

func after_each() -> void:
	MatchConfig.player_civ_id = _prev_player_civ
	_set_first_rival_civ(_prev_rival_civ)
	IconBaker.clear_cache()

func _set_first_rival_civ(civ_id: String) -> void:
	if MatchConfig.rival_civ_ids.is_empty():
		MatchConfig.rival_civ_ids.append(civ_id)
	else:
		MatchConfig.rival_civ_ids[0] = civ_id

func test_returns_valid_texture_immediately_headless() -> void:
	var tex: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	assert_not_null(tex, "get_icon must return a texture synchronously")
	assert_eq(tex.get_width(), IconBaker.ICON_SIZE)
	assert_eq(tex.get_height(), IconBaker.ICON_SIZE)

func test_cache_hit_returns_same_instance() -> void:
	var first: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	var second: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	assert_same(first, second, "same (scene, civ) key must reuse the cached texture")

func test_cache_key_is_per_civilization() -> void:
	_set_first_rival_civ("britons")
	var player_icon: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	var rival_icon: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 1)
	assert_ne(player_icon, rival_icon,
		"different civs must bake distinct icons for the same scene")

func test_same_civ_players_share_icon() -> void:
	_set_first_rival_civ("mahos")
	var player_icon: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	var rival_icon: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 1)
	assert_same(player_icon, rival_icon,
		"players of the same civ share one cache entry")

func test_clear_cache_forces_new_instance() -> void:
	var first: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	IconBaker.clear_cache()
	var second: Texture2D = IconBaker.get_icon(VILLAGER_SCENE, 0)
	assert_ne(first, second, "clear_cache must drop cached textures")

func test_bake_leaks_no_gameplay_group_members() -> void:
	var buildings_before: int = get_tree().get_nodes_in_group("buildings").size()
	var animals_before: int = get_tree().get_nodes_in_group("animals").size()

	IconBaker.get_icon(BARRACKS_SCENE, 0)
	IconBaker.get_icon(VILLAGER_SCENE, 0)
	IconBaker.get_icon(SHEEP_SCENE, 0)

	# Mid-bake the props must already be stripped from gameplay groups so a
	# concurrent victory check never counts them.
	await wait_process_frames(1)
	assert_eq(get_tree().get_nodes_in_group("buildings").size(), buildings_before,
		"baking props must never appear in the buildings group")
	assert_eq(get_tree().get_nodes_in_group("animals").size(), animals_before,
		"baking props must never appear in the animals group")

	# After the bake completes nothing may linger.
	await wait_process_frames(20)
	assert_eq(get_tree().get_nodes_in_group("buildings").size(), buildings_before,
		"no zombie buildings after baking")
	assert_eq(get_tree().get_nodes_in_group("animals").size(), animals_before,
		"no zombie animals after baking")

func test_unknown_scene_returns_placeholder_without_crash() -> void:
	var tex: Texture2D = IconBaker.get_icon("res://scenes/units/does_not_exist.tscn", 0)
	assert_not_null(tex)
	await wait_process_frames(10)
	assert_eq(tex.get_width(), IconBaker.ICON_SIZE)

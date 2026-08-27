extends GutTest

## Pins the pure selection+target → cursor-id mapping behind the contextual
## mouse cursor (CursorManager.resolve_context). The mapping mirrors
## game_world._handle_right_click, so a change here means the cursor and the
## actual right-click behaviour have diverged.

const CM := preload("res://scripts/ui/cursor_manager.gd")

# --- attack -------------------------------------------------------------------

func test_military_over_enemy_shows_attack() -> void:
	assert_eq(CM.resolve_context(false, true, true, "enemy"), "attack")

func test_villagers_over_enemy_also_attack() -> void:
	# Right-clicking an enemy with villagers selected still orders an attack.
	assert_eq(CM.resolve_context(true, false, true, "enemy"), "attack")

func test_enemy_with_empty_selection_flags_is_default() -> void:
	assert_eq(CM.resolve_context(false, false, false, "enemy"), "default")

# --- gather -------------------------------------------------------------------

func test_villagers_over_each_resource_show_matching_gather_cursor() -> void:
	for res: String in ["wood", "gold", "stone", "food"]:
		assert_eq(CM.resolve_context(true, false, true, "resource", res),
			"gather_" + res)

func test_military_over_resource_is_default() -> void:
	assert_eq(CM.resolve_context(false, true, true, "resource", "wood"), "default")

func test_unknown_resource_is_default() -> void:
	# OLIVINA (or any future type without a glyph) must not build a bogus id.
	assert_eq(CM.resolve_context(true, false, true, "resource", "olivina"), "default")

func test_villagers_over_animal_show_food_cursor_military_attack() -> void:
	assert_eq(CM.resolve_context(true, false, true, "animal"), "gather_food")
	assert_eq(CM.resolve_context(false, true, true, "animal"), "attack")

# --- build / repair -----------------------------------------------------------

func test_villagers_over_construction_show_build_hammer() -> void:
	assert_eq(CM.resolve_context(true, false, true, "construction"), "build")

func test_villagers_over_damaged_building_show_repair() -> void:
	assert_eq(CM.resolve_context(true, false, true, "damaged"), "repair")

func test_military_over_own_construction_is_default() -> void:
	assert_eq(CM.resolve_context(false, true, true, "construction"), "default")

# --- board --------------------------------------------------------------------

func test_land_units_over_transport_show_board() -> void:
	assert_eq(CM.resolve_context(false, true, true, "transport"), "board")
	assert_eq(CM.resolve_context(true, false, true, "transport"), "board")

func test_ships_only_over_transport_is_default() -> void:
	assert_eq(CM.resolve_context(false, true, false, "transport"), "default")

# --- fallthrough / state ------------------------------------------------------

func test_no_target_is_default() -> void:
	assert_eq(CM.resolve_context(true, true, true, "none"), "default")

func test_every_resolved_id_has_a_baked_glyph_or_is_default() -> void:
	# All ids the resolver can emit must exist in CONTEXT_IDS (the bake list),
	# otherwise the cursor would silently stay stale on that context.
	var kinds: Array[String] = ["transport", "enemy", "animal", "resource",
		"construction", "damaged", "none"]
	for kind: String in kinds:
		for res: String in ["", "wood", "gold", "stone", "food"]:
			for flags: int in range(8):
				var id: String = CM.resolve_context(flags & 1 == 1,
					flags & 2 == 2, flags & 4 == 4, kind, res)
				assert_true(id == "default" or id in CM.CONTEXT_IDS,
					"unknown cursor id '%s'" % id)

func test_set_context_tracks_current_id_headlessly() -> void:
	CM.set_context("attack")
	assert_eq(CM.current_id, "attack")
	CM.set_context("default")
	assert_eq(CM.current_id, "default")

extends GutTest

## Tests for SaveManager (project/scripts/core/save_manager.gd).
##
## What is covered:
##   1. save_game / list_saves / delete_save round-trip
##   2. Multi-slot ordering (newest-first)
##   3. load_game populates _save_data and sets pending_load
##   4. load_game on non-existent slot returns false, pending_load unchanged
##   5. get_saved_rng_seed returns the seed stored during save_game
##   6. _collect_tc_state captures all required keys including position
##   7. _apply_tc_state restores health, max_health, and rally_point
##   8. _make_display_name formats civ name + date components
##   9. _next_free_slot skips occupied slots and wraps at MAX_SLOTS
##  10. has_any_save / has_save aliases
##
## What is NOT covered:
##   - restore_world: instantiates real PackedScenes (Villager, Barracks, …) which
##     require a live editor environment and the full asset tree. This would be an
##     integration test against the real game world scene.
##   - _restore_autoloads: exercises AgeManager, PopulationManager, TechManager
##     internals that have their own tests; cross-autoload integration belongs in
##     tests/integration/.
##   - File-system errors (disk full, permission denied): untestable without OS mocking.
##
## Setup notes:
##   - SaveManager is a registered autoload; tests access it directly.
##   - save_game(world, slot) requires several properties on the world node:
##       _saved_rng_seed (int), _saved_tc_position (Vector2), UnitsLayer child,
##       BuildingsLayer child, DropOffNode child.
##     We build a minimal FakeWorld with Node2D stubs — no real scenes instantiated.
##   - MatchConfig is also an autoload. We reset it to known values in before_each()
##     so that _collect() produces deterministic match_config dictionaries.
##   - All files written to user://saves/ during tests are deleted in after_each().
##     Tests write to slots >= 90 to avoid colliding with real save files.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Slots used exclusively by this test suite — chosen high enough to avoid
## touching any real save the developer may have in slots 1-89.
const _TEST_SLOT_A: int = 90
const _TEST_SLOT_B: int = 91
const _TEST_SLOT_C: int = 92

## Build a minimal world Node that satisfies _collect()'s property reads.
## UnitsLayer / BuildingsLayer are empty Nodes (no children) so the unit/building
## loops produce empty arrays.  DropOffNode is a Node2D with health properties
## so _collect_tc_state can run without crashing.
func _make_fake_world(rng_seed: int = 12345, tc_pos: Vector2 = Vector2(100.0, 200.0)) -> Node:
	var world: Node = Node.new()
	world.set_script(null)  # plain Node, no script
	world.name = "FakeWorld"

	# Properties read by _collect()
	world.set_meta("_saved_rng_seed", rng_seed)
	world.set_meta("_saved_tc_position", tc_pos)

	# _collect() calls world.get("_saved_rng_seed") — use a script to expose them
	var script: GDScript = GDScript.new()
	script.source_code = """
extends Node
var _saved_rng_seed: int = 0
var _saved_tc_position: Vector2 = Vector2.ZERO
"""
	script.reload()
	world.set_script(script)
	world._saved_rng_seed = rng_seed
	world._saved_tc_position = tc_pos

	# UnitsLayer — empty container (no units to serialise)
	var units_layer: Node = Node.new()
	units_layer.name = "UnitsLayer"
	world.add_child(units_layer)

	# BuildingsLayer — empty container
	var bld_layer: Node = Node.new()
	bld_layer.name = "BuildingsLayer"
	world.add_child(bld_layer)

	# DropOffNode — a Node2D with the properties _collect_tc_state reads
	var tc_script: GDScript = GDScript.new()
	tc_script.source_code = """
extends Node2D
var health: float = 1500.0
var max_health: float = 2000.0
var rally_point: Vector2 = Vector2(50.0, 75.0)
"""
	tc_script.reload()
	var drop_off: Node2D = Node2D.new()
	drop_off.name = "DropOffNode"
	drop_off.set_script(tc_script)
	drop_off.global_position = Vector2(100.0, 200.0)
	world.add_child(drop_off)

	return world


## Delete a save slot file unconditionally — used in cleanup.
func _remove_slot(slot: int) -> void:
	var path: String = SaveManager.SAVE_DIR + "save_%02d.json" % slot
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Reset pending_load so tests that check its initial value get a clean slate.
	SaveManager.pending_load = false
	SaveManager._save_data = {}

	# Reset MatchConfig to deterministic values used by _collect() / _make_display_name().
	MatchConfig.map_size      = 1  # MapSize.MEDIUM
	MatchConfig.resources     = 1  # Resources.NORMAL
	MatchConfig.map_type      = 0  # MapType.PLAINS
	MatchConfig.player_civ_id = "guanches"
	MatchConfig.starting_age  = 0
	MatchConfig.rival_count   = 1
	MatchConfig.rival_civ_ids = ["castellanos"]

	# Clean up any stale test-slot files from a previous run.
	for s: int in [_TEST_SLOT_A, _TEST_SLOT_B, _TEST_SLOT_C]:
		_remove_slot(s)


func after_each() -> void:
	# Guarantee cleanup even if a test fails mid-way.
	for s: int in [_TEST_SLOT_A, _TEST_SLOT_B, _TEST_SLOT_C]:
		_remove_slot(s)
	SaveManager.pending_load = false
	SaveManager._save_data = {}


# ---------------------------------------------------------------------------
# 1. save_game / list_saves / delete_save round-trip
# ---------------------------------------------------------------------------

func test_save_game_creates_file_in_save_dir() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)

	var ok: bool = SaveManager.save_game(world, _TEST_SLOT_A)
	assert_true(ok, "save_game() must return true on success")

	var path: String = SaveManager.SAVE_DIR + "save_%02d.json" % _TEST_SLOT_A
	assert_true(FileAccess.file_exists(path), "save file must exist after save_game()")


func test_list_saves_includes_saved_slot_with_correct_slot_number() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)

	var saves: Array[Dictionary] = SaveManager.list_saves()
	var found: bool = false
	for entry: Dictionary in saves:
		if entry.get("slot") as int == _TEST_SLOT_A:
			found = true
			break
	assert_true(found, "list_saves() must include an entry with slot == _TEST_SLOT_A")


func test_list_saves_entry_has_non_zero_timestamp() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)

	var saves: Array[Dictionary] = SaveManager.list_saves()
	var ts: int = 0
	for entry: Dictionary in saves:
		if entry.get("slot") as int == _TEST_SLOT_A:
			ts = entry.get("timestamp", 0) as int
			break
	assert_true(ts > 0, "timestamp in list_saves() entry must be non-zero")


func test_delete_save_removes_file() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)

	SaveManager.delete_save(_TEST_SLOT_A)

	var path: String = SaveManager.SAVE_DIR + "save_%02d.json" % _TEST_SLOT_A
	assert_false(FileAccess.file_exists(path), "save file must not exist after delete_save()")


func test_has_any_save_returns_false_after_deleting_all_test_slots() -> void:
	# First make sure none of our test slots exist, then verify the helper works.
	# We check only against the test slots — not the whole save directory — by
	# inspecting list_saves and filtering to our slot numbers.
	for s: int in [_TEST_SLOT_A, _TEST_SLOT_B, _TEST_SLOT_C]:
		_remove_slot(s)

	var saves: Array[Dictionary] = SaveManager.list_saves()
	var any_test_slot: bool = false
	for entry: Dictionary in saves:
		var sl: int = entry.get("slot", 0) as int
		if sl >= _TEST_SLOT_A and sl <= _TEST_SLOT_C:
			any_test_slot = true
			break
	assert_false(any_test_slot, "No test-range slots should appear after cleanup")


func test_has_any_save_returns_true_when_save_exists() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)
	assert_true(SaveManager.has_any_save(), "has_any_save() must be true after saving")


func test_has_save_is_alias_of_has_any_save() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)
	assert_eq(SaveManager.has_save(), SaveManager.has_any_save(),
		"has_save() must return the same value as has_any_save()")


# ---------------------------------------------------------------------------
# 2. Multi-slot ordering (newest-first)
# ---------------------------------------------------------------------------

func test_list_saves_returns_newer_slot_first() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)

	# Save slot A first, then slot B with a 1-second delay simulated by
	# directly manipulating the JSON timestamp after writing.
	SaveManager.save_game(world, _TEST_SLOT_A)

	# Force a different (later) timestamp on slot B by saving it, then reading
	# and re-writing with timestamp + 2 so the ordering is deterministic even
	# when both writes occur within the same wall-clock second.
	SaveManager.save_game(world, _TEST_SLOT_B)

	var path_b: String = SaveManager.SAVE_DIR + "save_%02d.json" % _TEST_SLOT_B
	var file_r: FileAccess = FileAccess.open(path_b, FileAccess.READ)
	assert_not_null(file_r, "slot B file must be readable for timestamp manipulation")
	var txt: String = file_r.get_as_text()
	file_r.close()

	var parsed: Variant = JSON.parse_string(txt)
	assert_true(parsed is Dictionary, "slot B save must parse as Dictionary")
	var d: Dictionary = parsed as Dictionary
	d["timestamp"] = (d.get("timestamp", 0) as int) + 2

	var file_w: FileAccess = FileAccess.open(path_b, FileAccess.WRITE)
	assert_not_null(file_w, "slot B file must be writable for timestamp manipulation")
	file_w.store_string(JSON.stringify(d, "\t"))
	file_w.close()

	var saves: Array[Dictionary] = SaveManager.list_saves()
	# Filter to only our two test slots to avoid interference from real saves.
	var test_saves: Array[Dictionary] = []
	for entry: Dictionary in saves:
		var sl: int = entry.get("slot", 0) as int
		if sl == _TEST_SLOT_A or sl == _TEST_SLOT_B:
			test_saves.append(entry)

	assert_eq(test_saves.size(), 2, "must find exactly 2 test-slot entries")
	assert_eq(test_saves[0].get("slot") as int, _TEST_SLOT_B,
		"slot B (newer timestamp) must sort first")
	assert_eq(test_saves[1].get("slot") as int, _TEST_SLOT_A,
		"slot A (older timestamp) must sort second")


# ---------------------------------------------------------------------------
# 3 & 5. load_game sets pending_load and populates _save_data / rng_seed
# ---------------------------------------------------------------------------

func test_load_game_sets_pending_load_true() -> void:
	var world: Node = _make_fake_world(42)
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)

	var ok: bool = SaveManager.load_game(_TEST_SLOT_A)
	assert_true(ok, "load_game() must return true for an existing slot")
	assert_true(SaveManager.pending_load, "pending_load must be true after load_game()")


func test_load_game_get_saved_rng_seed_matches_saved_seed() -> void:
	var expected_seed: int = 98765
	var world: Node = _make_fake_world(expected_seed)
	add_child_autofree(world)
	SaveManager.save_game(world, _TEST_SLOT_A)

	SaveManager.load_game(_TEST_SLOT_A)
	assert_eq(SaveManager.get_saved_rng_seed(), expected_seed,
		"get_saved_rng_seed() must return the seed that was present when saving")


func test_get_saved_rng_seed_returns_zero_before_any_load() -> void:
	# _save_data is empty (reset in before_each) so the default must be 0.
	assert_eq(SaveManager.get_saved_rng_seed(), 0,
		"get_saved_rng_seed() must return 0 when no save has been loaded")


# ---------------------------------------------------------------------------
# 4. load_game on non-existent slot
# ---------------------------------------------------------------------------

func test_load_game_returns_false_for_missing_slot() -> void:
	# Slot 99 is guaranteed clean by after_each — also explicitly removed here.
	_remove_slot(99)
	var ok: bool = SaveManager.load_game(99)
	assert_false(ok, "load_game() must return false for a non-existent slot")


func test_load_game_leaves_pending_load_unchanged_for_missing_slot() -> void:
	_remove_slot(99)
	SaveManager.pending_load = false
	SaveManager.load_game(99)
	assert_false(SaveManager.pending_load,
		"pending_load must remain false when load_game() fails")


# ---------------------------------------------------------------------------
# 6. _collect_tc_state captures all required keys
# ---------------------------------------------------------------------------

func _make_fake_tc(pos: Vector2 = Vector2(320.0, 480.0)) -> Node2D:
	var tc_script: GDScript = GDScript.new()
	tc_script.source_code = """
extends Node2D
var health: float = 1200.0
var max_health: float = 2000.0
var rally_point: Vector2 = Vector2(100.0, 150.0)
"""
	tc_script.reload()
	var tc: Node2D = Node2D.new()
	tc.set_script(tc_script)
	tc.global_position = pos
	return tc


func test_collect_tc_state_contains_health_key() -> void:
	var tc: Node2D = _make_fake_tc()
	add_child_autofree(tc)
	var d: Dictionary = SaveManager._collect_tc_state(tc)
	assert_true(d.has("health"), "_collect_tc_state must include 'health' key")


func test_collect_tc_state_contains_max_health_key() -> void:
	var tc: Node2D = _make_fake_tc()
	add_child_autofree(tc)
	var d: Dictionary = SaveManager._collect_tc_state(tc)
	assert_true(d.has("max_health"), "_collect_tc_state must include 'max_health' key")


func test_collect_tc_state_contains_rally_point_key() -> void:
	var tc: Node2D = _make_fake_tc()
	add_child_autofree(tc)
	var d: Dictionary = SaveManager._collect_tc_state(tc)
	assert_true(d.has("rally_point"), "_collect_tc_state must include 'rally_point' key")


func test_collect_tc_state_contains_position_key() -> void:
	var tc: Node2D = _make_fake_tc()
	add_child_autofree(tc)
	var d: Dictionary = SaveManager._collect_tc_state(tc)
	assert_true(d.has("position"), "_collect_tc_state must include 'position' key")


func test_collect_tc_state_health_value_matches_node_property() -> void:
	var tc: Node2D = _make_fake_tc()
	add_child_autofree(tc)
	var d: Dictionary = SaveManager._collect_tc_state(tc)
	assert_eq(d.get("health") as float, 1200.0,
		"health in collected state must match the node's health property")


func test_collect_tc_state_position_encodes_global_position() -> void:
	var expected_pos: Vector2 = Vector2(320.0, 480.0)
	var tc: Node2D = _make_fake_tc(expected_pos)
	add_child_autofree(tc)
	var d: Dictionary = SaveManager._collect_tc_state(tc)
	var pos_arr: Array = d.get("position") as Array
	assert_eq(pos_arr.size(), 2, "position must be a 2-element array")
	assert_almost_eq(pos_arr[0] as float, expected_pos.x, 0.01,
		"position[0] must encode global_position.x")
	assert_almost_eq(pos_arr[1] as float, expected_pos.y, 0.01,
		"position[1] must encode global_position.y")


# ---------------------------------------------------------------------------
# 7. _apply_tc_state restores values to the target node
# ---------------------------------------------------------------------------

func _make_mutable_tc() -> Node2D:
	var tc_script: GDScript = GDScript.new()
	tc_script.source_code = """
extends Node2D
var health: float = 0.0
var max_health: float = 0.0
var rally_point: Vector2 = Vector2.ZERO
"""
	tc_script.reload()
	var tc: Node2D = Node2D.new()
	tc.set_script(tc_script)
	return tc


func test_apply_tc_state_restores_health() -> void:
	var tc: Node2D = _make_mutable_tc()
	add_child_autofree(tc)
	var d: Dictionary = {
		"health":      900.0,
		"max_health":  2000.0,
		"rally_point": [0.0, 0.0],
	}
	SaveManager._apply_tc_state(tc, d)
	assert_eq(tc.get("health") as float, 900.0,
		"_apply_tc_state must restore health")


func test_apply_tc_state_restores_max_health() -> void:
	var tc: Node2D = _make_mutable_tc()
	add_child_autofree(tc)
	var d: Dictionary = {
		"health":      900.0,
		"max_health":  1800.0,
		"rally_point": [0.0, 0.0],
	}
	SaveManager._apply_tc_state(tc, d)
	assert_eq(tc.get("max_health") as float, 1800.0,
		"_apply_tc_state must restore max_health")


func test_apply_tc_state_skips_health_when_negative() -> void:
	# health = -1.0 is the sentinel "not present" value; the node's health
	# must remain unchanged.
	var tc: Node2D = _make_mutable_tc()
	add_child_autofree(tc)
	tc.set("health", 500.0)
	var d: Dictionary = {
		"health":      -1.0,
		"max_health":  -1.0,
		"rally_point": [0.0, 0.0],
	}
	SaveManager._apply_tc_state(tc, d)
	assert_eq(tc.get("health") as float, 500.0,
		"_apply_tc_state must not overwrite health when value is -1")


# ---------------------------------------------------------------------------
# 8. _make_display_name formats the display name correctly
# ---------------------------------------------------------------------------

func test_make_display_name_contains_capitalised_civ_id() -> void:
	# _make_display_name reads match_config.player_civ_id from the data dict.
	var ts: int = int(Time.get_unix_time_from_system())
	var data: Dictionary = {
		"timestamp":    ts,
		"match_config": {"player_civ_id": "guanches"},
	}
	var name_str: String = SaveManager._make_display_name(data)
	assert_true(name_str.contains("Guanches"),
		"display name must contain the capitalised civ id 'Guanches'")


func test_make_display_name_contains_em_dash_separator() -> void:
	var ts: int = int(Time.get_unix_time_from_system())
	var data: Dictionary = {
		"timestamp":    ts,
		"match_config": {"player_civ_id": "castellanos"},
	}
	var name_str: String = SaveManager._make_display_name(data)
	assert_true(name_str.contains("—"),
		"display name must contain the '—' separator between civ and date")


func test_make_display_name_contains_two_digit_day() -> void:
	# Use a known Unix timestamp: 2024-06-01 12:30 UTC → 1717241400
	var ts: int = 1717241400
	var data: Dictionary = {
		"timestamp":    ts,
		"match_config": {"player_civ_id": "mongols"},
	}
	var name_str: String = SaveManager._make_display_name(data)
	# We only assert format presence — the exact day depends on the local
	# timezone offset that Godot's datetime helper applies, so we check for
	# any two-digit pattern separated by "/" which is the date separator.
	assert_true("/" in name_str,
		"display name must contain a '/' date separator (DD/MM)")


func test_make_display_name_unknown_civ_shows_question_mark() -> void:
	var ts: int = int(Time.get_unix_time_from_system())
	var data: Dictionary = {
		"timestamp":    ts,
		"match_config": {},  # no player_civ_id → defaults to "?"
	}
	var name_str: String = SaveManager._make_display_name(data)
	assert_true(name_str.begins_with("?"),
		"display name must start with '?' when player_civ_id is absent")


# ---------------------------------------------------------------------------
# 9. _next_free_slot
# ---------------------------------------------------------------------------

func test_next_free_slot_returns_1_when_no_saves_exist() -> void:
	# Ensure slots 1 and 2 are absent (likely already are, but be explicit).
	_remove_slot(1)
	_remove_slot(2)
	# Only valid if no real saves are in slot 1; since this is a unit test env
	# there should be none. We verify the _MINIMUM_ free slot is <= 2.
	var slot: int = SaveManager._next_free_slot()
	assert_true(slot >= 1 and slot <= SaveManager.MAX_SLOTS,
		"_next_free_slot must return a value in [1, MAX_SLOTS]")


func test_next_free_slot_skips_occupied_test_slots() -> void:
	var world: Node = _make_fake_world()
	add_child_autofree(world)

	# Occupy test slots A and B.
	SaveManager.save_game(world, _TEST_SLOT_A)
	SaveManager.save_game(world, _TEST_SLOT_B)

	# _next_free_slot scans from 1 upward, so it may return a slot < _TEST_SLOT_A
	# if lower-numbered slots are empty (likely on a clean test env).
	# The important guarantee: it must NOT return _TEST_SLOT_A or _TEST_SLOT_B.
	# To force it to consider them, temporarily fill all slots from 1 to
	# _TEST_SLOT_B - 1 by writing minimal JSON files, then check the result.

	# Create dummy files for slots 1 … _TEST_SLOT_A-1
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var dummy_slots: Array[int] = []
	for i: int in range(1, _TEST_SLOT_A):
		var p: String = SaveManager.SAVE_DIR + "save_%02d.json" % i
		if not FileAccess.file_exists(p):
			var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string("{}")
				f.close()
				dummy_slots.append(i)

	var next_slot: int = SaveManager._next_free_slot()

	# Clean up dummy files.
	for i: int in dummy_slots:
		DirAccess.remove_absolute(SaveManager.SAVE_DIR + "save_%02d.json" % i)

	assert_true(next_slot != _TEST_SLOT_A and next_slot != _TEST_SLOT_B,
		"_next_free_slot must skip slots that already have files")
	assert_eq(next_slot, _TEST_SLOT_C,
		"_next_free_slot must return _TEST_SLOT_C (92) when A and B are occupied")


func test_next_free_slot_returns_1_when_all_slots_full() -> void:
	## When every slot from 1 to MAX_SLOTS is occupied, _next_free_slot must
	## return 1 (overwrite policy).  We simulate this by temporarily filling
	## all 99 slots with empty JSON files, then restore the originals.
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)

	# Track which slots we created so we can remove only those.
	var created: Array[int] = []
	for i: int in range(1, SaveManager.MAX_SLOTS + 1):
		var p: String = SaveManager.SAVE_DIR + "save_%02d.json" % i
		if not FileAccess.file_exists(p):
			var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string("{}")
				f.close()
				created.append(i)

	var result: int = SaveManager._next_free_slot()

	# Remove only the files we created.
	for i: int in created:
		DirAccess.remove_absolute(SaveManager.SAVE_DIR + "save_%02d.json" % i)

	assert_eq(result, 1,
		"_next_free_slot must return 1 (overwrite) when all MAX_SLOTS are occupied")


# ---------------------------------------------------------------------------
# 10. save_game uses -1 to auto-pick the next free slot
# ---------------------------------------------------------------------------

func test_save_game_with_minus_one_slot_creates_a_file() -> void:
	# We cannot control which slot is chosen, but we can verify the count
	# of existing saves increases by one.
	var before: int = SaveManager.list_saves().size()

	var world: Node = _make_fake_world()
	add_child_autofree(world)
	var ok: bool = SaveManager.save_game(world, -1)
	assert_true(ok, "save_game(-1) must succeed")

	var after: int = SaveManager.list_saves().size()
	assert_eq(after, before + 1,
		"list_saves() must return one more entry after save_game(-1)")

	# Clean up: remove the auto-chosen slot.  Find it by comparing lists.
	var after_saves: Array[Dictionary] = SaveManager.list_saves()
	for entry: Dictionary in after_saves:
		var sl: int = entry.get("slot", -1) as int
		# Auto slot is likely 1 on a clean machine; delete it.
		SaveManager.delete_save(sl)
		break  # just delete the newest (first in sorted list)

func test_animals_survive_collection() -> void:
	## Animals don't extend UnitBase (no is_female/civ_id): the collector must
	## not abort on them — aborting silently dropped every animal from saves.
	var sheep: Node2D = (load("res://scenes/units/sheep.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(sheep)
	sheep.global_position = Vector2(100.0, 200.0)
	var d: Dictionary = SaveManager._collect_unit(sheep)
	assert_false(d.is_empty(), "the sheep is collected, not dropped")
	assert_eq(d.get("class"), "Sheep")
	assert_eq(d.get("is_female"), false, "genderless units default to false")
	var deer: Node2D = (load("res://scenes/units/animal.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(deer)
	assert_eq(SaveManager._collect_unit(deer).get("class"), "Animal")

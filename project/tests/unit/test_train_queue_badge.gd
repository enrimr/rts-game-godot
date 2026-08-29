extends GutTest

## Per-unit-type train-queue badges (HudManager.queued_per_unit).
##
## The regression: the HUD stamped queue.size() — the TOTAL — on every
## train button of the selected building, so queueing a militia also bumped
## the pikeman and unique-unit counters on a Barracks. Each button must show
## only its own unit's queued count.

const HudManagerScript: GDScript = preload("res://scripts/ui/hud_manager.gd")

func test_counts_are_split_per_unit_type() -> void:
	var queue: Array = [
		{"unit_id": "militia"}, {"unit_id": "pikeman"},
		{"unit_id": "militia"}, {"unit_id": "militia"},
	]
	var counts: Dictionary = HudManagerScript.queued_per_unit(queue)
	assert_eq(counts.get("militia", 0), 3, "three militia queued")
	assert_eq(counts.get("pikeman", 0), 1, "one pikeman queued")
	assert_eq(counts.get("menceyes_guard", 0), 0,
		"a type not in the queue shows no badge — the old code showed 4 on it")

func test_single_type_queue_matches_total() -> void:
	var queue: Array = [{"unit_id": "villager"}, {"unit_id": "villager"}]
	assert_eq(HudManagerScript.queued_per_unit(queue), {"villager": 2})

func test_empty_queue_counts_nothing() -> void:
	assert_eq(HudManagerScript.queued_per_unit([]), {})

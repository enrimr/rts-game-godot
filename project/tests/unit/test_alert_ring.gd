extends GutTest

## AlertRing powers the SPACE jump-to-last-event hotkey: it keeps the newest
## MAX_ENTRIES alert positions, jumps to the newest first and cycles backwards
## through older alerts while presses stay inside CYCLE_WINDOW seconds.

var _ring: AlertRing = null

func before_each() -> void:
	_ring = AlertRing.new()

func test_empty_ring_has_no_entries() -> void:
	assert_false(_ring.has_entries())
	assert_eq(_ring.size(), 0)

func test_first_jump_targets_newest_alert() -> void:
	_ring.record(Vector2(100.0, 0.0))
	_ring.record(Vector2(900.0, 0.0))
	assert_eq(_ring.next_target(10.0), Vector2(900.0, 0.0))

func test_press_within_window_cycles_to_older_alert() -> void:
	_ring.record(Vector2(100.0, 0.0))
	_ring.record(Vector2(900.0, 0.0))
	assert_eq(_ring.next_target(10.0), Vector2(900.0, 0.0))
	assert_eq(_ring.next_target(11.0), Vector2(100.0, 0.0))

func test_cycle_wraps_back_to_newest() -> void:
	_ring.record(Vector2(100.0, 0.0))
	_ring.record(Vector2(900.0, 0.0))
	_ring.next_target(10.0)
	_ring.next_target(11.0)
	assert_eq(_ring.next_target(12.0), Vector2(900.0, 0.0))

func test_press_after_window_resets_to_newest() -> void:
	_ring.record(Vector2(100.0, 0.0))
	_ring.record(Vector2(900.0, 0.0))
	_ring.next_target(10.0)
	# Past the 4 s window: back to the newest alert, not the older one.
	assert_eq(_ring.next_target(10.0 + AlertRing.CYCLE_WINDOW + 0.1), Vector2(900.0, 0.0))

func test_capacity_keeps_only_newest_five() -> void:
	for i: int in range(7):
		_ring.record(Vector2(float(i) * 1000.0, 0.0))
	assert_eq(_ring.size(), AlertRing.MAX_ENTRIES)
	assert_eq(_ring.next_target(10.0), Vector2(6000.0, 0.0))
	var oldest: Vector2 = Vector2.ZERO
	for i: int in range(AlertRing.MAX_ENTRIES - 1):
		oldest = _ring.next_target(10.5 + float(i))
	assert_eq(oldest, Vector2(2000.0, 0.0))

func test_nearby_alert_merges_into_newest_entry() -> void:
	_ring.record(Vector2(100.0, 0.0))
	_ring.record(Vector2(100.0 + AlertRing.MERGE_RADIUS * 0.5, 0.0))
	assert_eq(_ring.size(), 1)
	assert_eq(_ring.next_target(10.0), Vector2(100.0 + AlertRing.MERGE_RADIUS * 0.5, 0.0))

func test_new_alert_restarts_cycling_at_newest() -> void:
	_ring.record(Vector2(100.0, 0.0))
	_ring.record(Vector2(900.0, 0.0))
	_ring.next_target(10.0)
	_ring.record(Vector2(5000.0, 0.0))
	assert_eq(_ring.next_target(10.5), Vector2(5000.0, 0.0))

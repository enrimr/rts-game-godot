class_name AlertRing
extends RefCounted

## Small ring buffer of recent "under attack" world positions, powering the
## SPACE jump-to-last-event hotkey. Pure logic (time is injected) so it stays
## unit-testable: record() keeps the newest MAX_ENTRIES alerts, next_target()
## returns the newest one — or, when pressed again within CYCLE_WINDOW
## seconds, cycles backwards through the older entries.

const MAX_ENTRIES: int = 5
const CYCLE_WINDOW: float = 4.0
## Alerts closer than this to the newest entry update it in place, so one
## ongoing battle does not flood the whole ring.
const MERGE_RADIUS: float = 120.0

var _entries: Array[Vector2] = []  # oldest first, newest last
var _cursor: int = -1
var _last_jump_time: float = -1000.0

func record(pos: Vector2) -> void:
	if not _entries.is_empty() and _entries[_entries.size() - 1].distance_to(pos) < MERGE_RADIUS:
		_entries[_entries.size() - 1] = pos
	else:
		_entries.append(pos)
		if _entries.size() > MAX_ENTRIES:
			_entries.pop_front()
	# A fresh alert restarts cycling at the newest entry.
	_cursor = -1

func has_entries() -> bool:
	return not _entries.is_empty()

func size() -> int:
	return _entries.size()

## Position for a jump requested at time `now` (seconds). First press (or a
## press after the cycle window lapsed) targets the newest alert; repeated
## presses inside the window walk back through older ones, wrapping around.
func next_target(now: float) -> Vector2:
	if _entries.is_empty():
		return Vector2.ZERO
	if _cursor < 0 or now - _last_jump_time > CYCLE_WINDOW:
		_cursor = _entries.size() - 1
	else:
		_cursor -= 1
		if _cursor < 0:
			_cursor = _entries.size() - 1
	_last_jump_time = now
	return _entries[_cursor]

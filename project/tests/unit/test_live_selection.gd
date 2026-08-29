extends GutTest

## GameWorld.live_selection() — the read barrier over the shared selection list.
##
## Units die on their own schedule and nothing removes them from
## `_selected_units`, so the list can hold freed instances. Every controller
## reaches it through the untyped `_world` reference, which makes GDScript
## validate each element against the loop's declared type at runtime: a freed
## entry then raises "Trying to assign invalid previously freed instance" and
## aborts the loop *before* the is_instance_valid() guard in the body can run
## (it happened every frame in WorldCommands._resolve_cursor_context).

var _world: Node2D = null
var _alive: Array[Node2D] = []

func before_each() -> void:
	_world = (load("res://scripts/game/game_world.gd") as Script).new() as Node2D
	_alive.clear()

func after_each() -> void:
	for n: Node2D in _alive:
		if is_instance_valid(n):
			n.free()
	_alive.clear()
	if is_instance_valid(_world):
		_world.free()

func _select(count: int) -> Array[Node2D]:
	var units: Array[Node2D] = []
	for _i: int in range(count):
		var u: Node2D = Node2D.new()
		units.append(u)
		_alive.append(u)
		_world._selected_units.append(u)
	return units

## Mimics a controller: untyped world reference, typed loop variable.
func _count_through_untyped_world(world: Variant) -> int:
	var seen: int = 0
	for unit: Node in world.live_selection():
		seen += 1
	return seen

func test_freed_units_are_dropped() -> void:
	var units: Array[Node2D] = _select(3)
	units[1].free()

	var live: Array[Node] = _world.live_selection()
	assert_eq(live.size(), 2, "the freed unit is gone")
	assert_true(live.has(units[0]) and live.has(units[2]), "the survivors stay, in order")

func test_pruning_updates_the_shared_list() -> void:
	var units: Array[Node2D] = _select(2)
	units[0].free()
	_world.live_selection()

	assert_eq(_world._selected_units.size(), 1,
		"controllers appending to _selected_units see the pruned list too")

func test_typed_iteration_through_an_untyped_world_is_safe() -> void:
	var units: Array[Node2D] = _select(2)
	units[0].free()

	# Without the barrier this raises an engine error, which GUT reports as a
	# failure — that is the regression being locked.
	assert_eq(_count_through_untyped_world(_world), 1,
		"the per-frame loops iterate the selection without touching freed units")

func test_empty_selection_stays_empty() -> void:
	assert_eq(_world.live_selection().size(), 0)

extends GutTest

## Multi-building selection (double click selects the whole type): the train
## buttons must land each order on the LEAST-LOADED queue of the group, skip
## full queues, and fall back to the primary when everything is full.

class StubProd extends Node2D:
	var player_id: int = 0
	var queue: Array = []
	var cap: int = 3
	func get_queue() -> Array:
		return queue
	func get_max_queue() -> int:
		return cap

class StubWorld extends Node2D:
	var _selected_building: Node = null
	var _selected_buildings: Array[Node] = []
	func live_selected_buildings() -> Array[Node]:
		return _selected_buildings

var _world: StubWorld = null
var _commands: WorldCommands = null

func before_each() -> void:
	_world = StubWorld.new()
	add_child_autofree(_world)
	_commands = WorldCommands.new()
	_commands.setup(_world)

func _prod(queued: int, cap: int = 3) -> StubProd:
	var b: StubProd = StubProd.new()
	for _i: int in range(queued):
		b.queue.append({})
	b.cap = cap
	_world.add_child(b)
	_world._selected_buildings.append(b)
	return b

func test_picks_the_emptiest_queue() -> void:
	var busy: StubProd = _prod(2)
	var idle: StubProd = _prod(0)
	var mid: StubProd = _prod(1)
	_world._selected_building = busy
	var target: Node = _commands._least_loaded_selected(
		func(b: Node) -> bool: return b is StubProd)
	assert_eq(target, idle, "the empty barracks gets the recruit, not the primary")
	assert_ne(target, mid)

func test_full_queues_are_skipped() -> void:
	var full: StubProd = _prod(3, 3)
	var open: StubProd = _prod(2, 3)
	_world._selected_building = full
	var target: Node = _commands._least_loaded_selected(
		func(b: Node) -> bool: return b is StubProd)
	assert_eq(target, open, "a full queue never receives the order")

func test_all_full_falls_back_to_the_primary() -> void:
	var a: StubProd = _prod(3, 3)
	var b: StubProd = _prod(3, 3)
	_world._selected_building = b
	var target: Node = _commands._least_loaded_selected(
		func(bld: Node) -> bool: return bld is StubProd)
	assert_eq(target, b, "order_train's own refusal handles the full group")
	assert_ne(target, a)

func test_destroy_applies_to_the_whole_group() -> void:
	## Delete with a multi-building selection demolishes every one of them,
	## not just the primary. (Stubs lack take_damage, so the delete command
	## falls back to queue_free — same observable outcome.)
	var a: StubProd = _prod(0)
	var b: StubProd = _prod(0)
	_world._selected_building = a
	CommandBus.start_match(_world)
	_commands._on_action_requested("destroy")
	assert_true(a.is_queued_for_deletion(), "the primary goes down")
	assert_true(b.is_queued_for_deletion(), "…and so does the rest of the group")
	assert_null(_world._selected_building, "selection is cleared")
	assert_eq(_world._selected_buildings, [] as Array[Node])

func test_type_filter_excludes_other_buildings() -> void:
	_prod(0)
	_world._selected_building = null
	var target: Node = _commands._least_loaded_selected(
		func(b: Node) -> bool: return b is Barracks)
	assert_null(target, "a stub is not a Barracks — nothing matches")
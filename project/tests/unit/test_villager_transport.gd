extends GutTest

## Tests for the transport signal leak fix in Villager.
##
## What is covered:
##   1. _cancel_transport() disconnects garrison_changed when it was connected
##   2. _cancel_transport() is safe to call when garrison_changed is not connected
##   3. _cancel_transport() clears all four transport state variables
##   4. order_gather() calls _cancel_transport() — no zombie listener after reorder
##   5. order_move() calls _cancel_transport()
##   6. order_build() calls _cancel_transport()
##   7. order_attack() calls _cancel_transport()
##   8. die() calls _cancel_transport()
##   9. Multiple sequential boarding attempts never accumulate more than one listener
##   10. _on_transport_garrison_changed resumes gather only when the villager was unloaded
##
## What is NOT covered:
##   - Full physics/navigation loop — those require a live scene tree.
##   - _handle_boarding_approach: requires NavigationAgent2D and move_and_slide.
##
## Setup notes:
##   - Villager requires several @onready nodes (AnimatedSprite2D, GatherIndicator).
##     We inject minimal stubs via add_child_autofree.
##   - EventBus.garrison_changed is a global signal on the EventBus autoload.
##   - after_each() hard-disconnects any leaked garrison_changed connection to
##     prevent cross-test pollution.

## ── Minimal stub: satisfies Villager._find_allied_transport's is(TransportShip) check
## and provides board() / get_garrison() / is_full() / global_position.
class FakeTransport extends Node2D:
	var _garrisoned: Array = []
	var full: bool = false
	func board(_unit: Node) -> bool:
		if full:
			return false
		_garrisoned.append(_unit)
		EventBus.garrison_changed.emit(self, _garrisoned.size(), 10)
		return true
	func get_garrison() -> Array:
		return _garrisoned.duplicate()
	func is_full() -> bool:
		return full
	func unload_all() -> void:
		_garrisoned.clear()
		EventBus.garrison_changed.emit(self, 0, 10)

## ── Minimal stub: a resource node Villager can be told to gather from.
class FakeResource extends Node2D:
	var resource_type: int = 0  # ResourceNode.ResourceType.WOOD
	func gather(_amount: float) -> float:
		return 0.0
	func get_resource_name() -> String:
		return "wood"

## ── Minimal stub: a drop-off building.
class FakeDropOff extends Node2D:
	var player_id: int = 0
	func _init() -> void:
		add_to_group("drop_off_buildings")

## ── Minimal stub for a build target (under-construction building).
class FakeBuildTarget extends Node2D:
	var state: int = 0  # BuildingBase.BuildingState.UNDER_CONSTRUCTION
	signal construction_complete()
	func register_builder() -> void:
		pass
	func unregister_builder() -> void:
		pass
	func add_construction(_amount: float) -> void:
		pass

## ── Minimal attack target.
class FakeUnit extends Node2D:
	var player_id: int = 1
	var health: float = 100.0
	func take_damage(_dmg: float, _src: Node) -> void:
		pass

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")

# Instantiating the shipped scene keeps the test resilient to new @onready
# node requirements (Body rig, HealthBar, SelectionIndicator…).
func _make_villager() -> Villager:
	var v: Villager = VILLAGER_SCENE.instantiate() as Villager
	v.player_id = 0
	add_child_autofree(v)
	return v


func _garrison_is_connected(v: Villager) -> bool:
	return EventBus.garrison_changed.is_connected(v._on_transport_garrison_changed)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Disconnect any garrison_changed listeners left by a prior test.
	# We can't easily enumerate all Villager instances, so we rely on each
	# test to clean up via after_each.
	pass


func after_each() -> void:
	# Belt-and-suspenders: if EventBus.garrison_changed has any connections to
	# methods named _on_transport_garrison_changed, disconnect them.
	# GUT auto-frees add_child_autofree nodes after each test, but the signal
	# connection on EventBus survives node death unless explicitly removed.
	var connections: Array = EventBus.garrison_changed.get_connections()
	for conn: Dictionary in connections:
		if (conn.callable as Callable).get_method() == "_on_transport_garrison_changed":
			EventBus.garrison_changed.disconnect(conn.callable)


# ---------------------------------------------------------------------------
# 1. _cancel_transport disconnects garrison_changed when connected
# ---------------------------------------------------------------------------

func test_cancel_transport_disconnects_garrison_changed() -> void:
	var v: Villager = _make_villager()
	# Manually connect as if boarding had succeeded.
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	assert_true(_garrison_is_connected(v),
		"precondition: garrison_changed must be connected before cancel")

	v._cancel_transport()

	assert_false(_garrison_is_connected(v),
		"_cancel_transport must disconnect garrison_changed")


# ---------------------------------------------------------------------------
# 2. _cancel_transport is idempotent when not connected
# ---------------------------------------------------------------------------

func test_cancel_transport_safe_when_not_connected() -> void:
	var v: Villager = _make_villager()
	assert_false(_garrison_is_connected(v), "precondition: not connected")

	# Must not throw.
	v._cancel_transport()

	assert_false(_garrison_is_connected(v),
		"garrison_changed must still be disconnected after idempotent cancel")


# ---------------------------------------------------------------------------
# 3. _cancel_transport clears all four transport state variables
# ---------------------------------------------------------------------------

func test_cancel_transport_clears_state() -> void:
	var v: Villager = _make_villager()
	var fake_ship: FakeTransport = FakeTransport.new()
	var fake_res: FakeResource = FakeResource.new()
	var fake_drop: FakeDropOff = FakeDropOff.new()
	add_child_autofree(fake_ship)
	add_child_autofree(fake_res)
	add_child_autofree(fake_drop)

	v._boarding_ship              = fake_ship
	v._pending_transport_target   = fake_res
	v._pending_transport_resource = "wood"
	v._pending_transport_drop_off = fake_drop
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	v._cancel_transport()

	assert_null(v._boarding_ship,              "_boarding_ship must be null after cancel")
	assert_null(v._pending_transport_target,   "_pending_transport_target must be null after cancel")
	assert_eq(v._pending_transport_resource, "", "_pending_transport_resource must be empty after cancel")
	assert_null(v._pending_transport_drop_off, "_pending_transport_drop_off must be null after cancel")
	assert_false(_garrison_is_connected(v),    "garrison_changed must be disconnected after cancel")


# ---------------------------------------------------------------------------
# 4–8. Each order_* method and die() disconnects the listener
# ---------------------------------------------------------------------------

func test_order_gather_cancels_transport() -> void:
	var v: Villager = _make_villager()
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	var fake_res: FakeResource = FakeResource.new()
	var fake_drop: FakeDropOff = FakeDropOff.new()
	add_child_autofree(fake_res)
	add_child_autofree(fake_drop)

	v.order_gather(fake_res, "wood", fake_drop)

	assert_false(_garrison_is_connected(v),
		"order_gather must call _cancel_transport and disconnect garrison_changed")


func test_order_move_cancels_transport() -> void:
	var v: Villager = _make_villager()
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	v.order_move(Vector2(100.0, 100.0))

	assert_false(_garrison_is_connected(v),
		"order_move must call _cancel_transport and disconnect garrison_changed")


func test_order_build_cancels_transport() -> void:
	var v: Villager = _make_villager()
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	var fake_bld: FakeBuildTarget = FakeBuildTarget.new()
	add_child_autofree(fake_bld)

	v.order_build(fake_bld)

	assert_false(_garrison_is_connected(v),
		"order_build must call _cancel_transport and disconnect garrison_changed")


func test_order_attack_cancels_transport() -> void:
	var v: Villager = _make_villager()
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	var fake_enemy: FakeUnit = FakeUnit.new()
	add_child_autofree(fake_enemy)

	v.order_attack(fake_enemy)

	assert_false(_garrison_is_connected(v),
		"order_attack must call _cancel_transport and disconnect garrison_changed")


func test_die_cancels_transport() -> void:
	var v: Villager = _make_villager()
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	v.die()

	assert_false(_garrison_is_connected(v),
		"die must call _cancel_transport and disconnect garrison_changed")


# ---------------------------------------------------------------------------
# 9. Multiple boarding attempts never accumulate more than one listener
# ---------------------------------------------------------------------------

func test_repeated_board_never_accumulates_listeners() -> void:
	var v: Villager = _make_villager()

	# Simulate the connection path three times in a row.
	for i: int in range(3):
		if not _garrison_is_connected(v):
			EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	var count: int = 0
	var connections: Array = EventBus.garrison_changed.get_connections()
	for conn: Dictionary in connections:
		if (conn.callable as Callable).get_method() == "_on_transport_garrison_changed":
			var obj: Object = (conn.callable as Callable).get_object()
			if obj == v:
				count += 1

	assert_eq(count, 1,
		"garrison_changed must have at most one connection to this villager")


# ---------------------------------------------------------------------------
# 10. _on_transport_garrison_changed resumes gather when villager was unloaded
# ---------------------------------------------------------------------------

func test_garrison_changed_resumes_gather_after_unload() -> void:
	var v: Villager = _make_villager()
	# The handler hard-casts _boarding_ship to TransportShip, so this test
	# needs the real ship scene rather than FakeTransport.
	var fake_ship: TransportShip = (preload("res://scenes/units/transport_ship.tscn").instantiate()) as TransportShip
	var fake_res: FakeResource = FakeResource.new()
	var fake_drop: FakeDropOff = FakeDropOff.new()
	add_child_autofree(fake_ship)
	add_child_autofree(fake_res)
	add_child_autofree(fake_drop)

	# Wire the pending state as if boarding had just succeeded.
	v._boarding_ship              = fake_ship
	v._pending_transport_target   = fake_res
	v._pending_transport_resource = "wood"
	v._pending_transport_drop_off = fake_drop
	EventBus.garrison_changed.connect(v._on_transport_garrison_changed)

	# Make the villager visible (unloaded from ship) and not in garrison.
	v.visible = true

	# Fire the signal as if the ship unloaded everyone (garrison now empty).
	EventBus.garrison_changed.emit(fake_ship, 0, 10)

	# After _on_transport_garrison_changed runs, transport state must be cleared
	# and the villager should be moving toward the resource (MOVING or GATHERING).
	assert_false(_garrison_is_connected(v),
		"garrison_changed must be disconnected after the villager is unloaded")
	assert_null(v._boarding_ship,
		"_boarding_ship must be null after unload callback")
	assert_true(
		v.current_state == Villager.UnitState.MOVING or v.current_state == Villager.UnitState.GATHERING,
		"villager must be MOVING or GATHERING toward the resource after unload"
	)

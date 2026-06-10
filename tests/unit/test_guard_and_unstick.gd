extends GutTest

## Regression guard for the "player units move on their own after a while" bug.
##
## Two fixes are pinned here:
##   A) Guard response (ally-under-attack) is now MILITARY-ONLY and uses a
##      tighter radius, so the player's economy no longer runs off to defend:
##        1.  GUARD_RADIUS tightened from the old 600 px.
##        2.  A Militia responds to guard; a Villager / FishingBoat / Transport
##            do not (_responds_to_guard()).
##   B) _unstick no longer teleports the unit; after MAX_STUCK_RETRIES it calls
##      _abandon_movement(), which clears targets and returns to IDLE:
##        3.  _abandon_movement resets state to IDLE and clears attack_target.

func _children(u: UnitBase) -> void:
	var nav: NavigationAgent2D = NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	u.add_child(nav)
	var hbar: ProgressBar = ProgressBar.new()
	hbar.name = "HealthBar"
	u.add_child(hbar)
	var sel: Node2D = Node2D.new()
	sel.name = "SelectionIndicator"
	var circle: Polygon2D = Polygon2D.new()
	circle.name = "SelectionCircle"
	sel.add_child(circle)
	u.add_child(sel)

func _make(klass: Variant, uid: String) -> UnitBase:
	var u: UnitBase = klass.new()
	_children(u)
	u.unit_data = UnitResource.new()
	u.unit_data.id = uid
	u.player_id = 0
	add_child_autofree(u)
	return u

# 1 — radius tightened
func test_guard_radius_tightened() -> void:
	assert_lt(UnitBase.GUARD_RADIUS, 600.0, "GUARD_RADIUS must be tighter than the old 600 px")
	assert_almost_eq(UnitBase.GUARD_RADIUS, 250.0, 0.01, "GUARD_RADIUS is 250 px")

# 2 — only military responds to the guard signal
func test_military_responds_economy_does_not() -> void:
	var militia: Militia = _make(Militia, "militia") as Militia
	var villager: Villager = _make(Villager, "villager") as Villager
	var fisher: FishingBoat = _make(FishingBoat, "fishing_boat") as FishingBoat
	var transport: TransportShip = _make(TransportShip, "transport_ship") as TransportShip
	assert_true(militia._responds_to_guard(),  "Militia should defend")
	assert_false(villager._responds_to_guard(), "Villager should NOT run off to defend")
	assert_false(fisher._responds_to_guard(),   "FishingBoat should NOT defend")
	assert_false(transport._responds_to_guard(),"Transport should NOT defend")

# 3 — _abandon_movement clears state instead of teleporting
func test_abandon_movement_returns_to_idle() -> void:
	var m: Militia = _make(Militia, "militia") as Militia
	var enemy: CharacterBody2D = CharacterBody2D.new()
	add_child_autofree(enemy)
	m.attack_target = enemy
	m.current_state = UnitBase.UnitState.MOVING
	var pos_before: Vector2 = m.global_position
	m._abandon_movement()
	assert_eq(m.current_state, UnitBase.UnitState.IDLE, "abandon returns the unit to IDLE")
	assert_null(m.attack_target, "abandon clears the attack target")
	assert_eq(m.global_position, pos_before, "abandon must NOT teleport the unit")

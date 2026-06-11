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

# 2 — only military responds to the guard signal.
# _responds_to_guard() is pure duck-typing (has_method + self), so we don't add
# the units to the tree — that avoids each subclass's _ready needing its full
# scene rig (ships in particular).
func test_military_responds_economy_does_not() -> void:
	var militia: Militia = autofree(Militia.new())
	var villager: Villager = autofree(Villager.new())
	var fisher: FishingBoat = autofree(FishingBoat.new())
	var transport: TransportShip = autofree(TransportShip.new())
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

# 4 — _edge_distance_to measures to the footprint edge, so build reach scales
#     with building size (regression: villagers couldn't reach large buildings).
func test_edge_distance_to_footprint() -> void:
	var m: Militia = _make(Militia, "militia") as Militia
	# A 72x72 building (Barracks/Stable/Archery Range) centred at (200,0).
	var b: StaticBody2D = StaticBody2D.new()
	var cs: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(72, 72)
	cs.shape = rect
	cs.name = "CollisionShape2D"
	b.add_child(cs)
	b.global_position = Vector2(200, 0)
	add_child_autofree(b)
	# Unit at x=240: 40 px from centre, but only 40-36 = 4 px from the edge.
	m.global_position = Vector2(240, 0)
	assert_almost_eq(m._edge_distance_to(b), 4.0, 0.5, "edge distance ignores the 36 px half-extent")
	# That 4 px is within BUILD_RANGE even though 40 px to centre would have
	# failed an old centre-distance check tuned for small buildings.
	assert_lt(m._edge_distance_to(b), Villager.BUILD_RANGE, "builder is within reach at the edge")

# 5 — BUILD_RANGE must clear the navmesh dead-zone around a building, or the
#     builder physically can't get its centre close enough (regression: after
#     the nav carve grew to 12 px the 24 px reach was too tight to satisfy).
func test_build_range_clears_navmesh_dead_zone() -> void:
	const NAV_CARVE_MARGIN: float = 12.0   # building_base._nav_bake_half_extents
	const NAV_AGENT_RADIUS: float = 10.0   # game_world.tscn NavigationPolygon
	var dead_zone: float = NAV_CARVE_MARGIN + NAV_AGENT_RADIUS
	assert_gt(Villager.BUILD_RANGE, dead_zone,
		"BUILD_RANGE (%d) must exceed the navmesh dead-zone (%d px) with headroom" % [int(Villager.BUILD_RANGE), int(dead_zone)])

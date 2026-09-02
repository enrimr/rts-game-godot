extends GutTest

## Land units must never end up in the sea (the Islands bug: shoreline
## buildings spawned villagers into the water — the spawn spiral only asked
## PHYSICS, and water has no collision body — and nothing healed a body
## shoved off the navmesh at the shoreline).
## Locks both defenses:
##   1. find_spawn_pos rejects candidates on impassable terrain.
##   2. UnitBase._contain_to_passable snaps a beached land unit ashore,
##      while ships (amphibious) are left alone at sea.

var _island: PackedVector2Array = PackedVector2Array([
	Vector2(-500.0, -500.0), Vector2(500.0, -500.0),
	Vector2(500.0, 500.0), Vector2(-500.0, 500.0),
])

func before_each() -> void:
	TerrainManager.reset()
	TerrainManager.set_land_polys([_island], true)

func after_each() -> void:
	TerrainManager.reset()

func test_island_setup_sanity() -> void:
	assert_false(TerrainManager.is_ocean(Vector2.ZERO), "poly center is land")
	assert_true(TerrainManager.is_ocean(Vector2(700.0, 0.0)), "outside is sea")

func test_spawn_spiral_never_picks_the_sea() -> void:
	var host: Node2D = Node2D.new()
	add_child_autofree(host)
	# A producer right on the shoreline: most spiral candidates are water.
	for origin: Vector2 in [Vector2(480.0, 0.0), Vector2(480.0, 480.0), Vector2(0.0, -480.0)]:
		var pos: Vector2 = BuildingBase.find_spawn_pos(
			origin, host.get_world_2d().direct_space_state)
		assert_false(TerrainManager.is_ocean(pos),
			"spawn from %s must land on the island, got %s" % [origin, pos])

func test_containment_snaps_a_beached_land_unit_ashore() -> void:
	var unit: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	add_child_autofree(unit)
	unit.global_position = Vector2(650.0, 0.0)
	unit.call("_contain_to_passable")
	assert_false(TerrainManager.is_ocean(unit.global_position),
		"a land unit standing in the sea must snap back to walkable ground")

func test_ships_at_sea_are_left_alone() -> void:
	var ship: CharacterBody2D = (load("res://scenes/units/war_galley.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	add_child_autofree(ship)
	var at_sea: Vector2 = Vector2(650.0, 0.0)
	ship.global_position = at_sea
	ship.call("_contain_to_passable")
	assert_eq(ship.global_position, at_sea,
		"ships are amphibious — containment must never beach them")

func test_unit_on_land_is_untouched() -> void:
	var unit: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	add_child_autofree(unit)
	var on_land: Vector2 = Vector2(100.0, 100.0)
	unit.global_position = on_land
	unit.call("_contain_to_passable")
	assert_eq(unit.global_position, on_land, "containment is a no-op on land")

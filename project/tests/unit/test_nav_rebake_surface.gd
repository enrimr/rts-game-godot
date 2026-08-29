extends GutTest

## Walkable surface used by the runtime navmesh rebake (`WorldPlacement`).
##
## The rebake re-bakes the land region from scratch whenever a building is
## placed or destroyed. On an Islands map it must bake only the carved land
## polygons: baking the full-map rect erases the carving and gives land units a
## walking route across open sea, which makes transport ships pointless.
## See `project/tools/check_nav_islands.tscn` for the end-to-end check.

var _placement: WorldPlacement = null

func before_each() -> void:
	TerrainManager.reset()
	_placement = WorldPlacement.new()

func after_each() -> void:
	TerrainManager.reset()

func _island(center: Vector2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(16):
		var a: float = TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

func test_land_map_bakes_the_whole_board() -> void:
	var outlines: Array[PackedVector2Array] = _placement._traversable_outlines()
	assert_eq(outlines.size(), 1, "one full-map outline when there is no ocean")
	assert_eq(outlines[0].size(), 4, "and it is a rectangle")

func test_island_map_bakes_only_the_islands() -> void:
	var polys: Array = [
		_island(Vector2(-700.0, 0.0), 500.0),
		_island(Vector2(700.0, 0.0), 500.0),
	]
	TerrainManager.set_land_polys(polys, true)

	var outlines: Array[PackedVector2Array] = _placement._traversable_outlines()
	assert_eq(outlines.size(), 2, "one walkable outline per island, no full-map rect")
	for outline: PackedVector2Array in outlines:
		assert_eq(outline.size(), 16, "island outlines are handed over untouched")
		for pt: Vector2 in outline:
			assert_false(TerrainManager.is_ocean(pt),
				"the walkable surface never includes open sea")

func test_islets_added_after_generation_stay_walkable() -> void:
	var polys: Array = [_island(Vector2.ZERO, 500.0)]
	TerrainManager.set_land_polys(polys, true)
	# EntityPlacer appends islets to the same array TerrainManager holds.
	polys.append(_island(Vector2(1200.0, 0.0), 160.0))

	assert_eq(_placement._traversable_outlines().size(), 2,
		"islets are part of the walkable surface too")

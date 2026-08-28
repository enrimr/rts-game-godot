extends GutTest

## Laurisilva terrain effects (GDD M6 — "high wood yield, reduces vision").
##
## What is covered:
##   1.  TerrainManager.get_vision_mult: reduced under laurisilva, 1.0 anywhere
##       else (grass, other zones).
##   2.  EntityPlacer.spawn_laurisilva_forests fills each laurisilva zone with
##       a tight wood cluster of above-normal yield, inside the zone.
##   3.  Maps without laurisilva zones spawn nothing extra.

# Forest spawning only needs the RNG and the resource multiplier; the painter is
# reached solely by the island/islet paths, so a bare instance is enough here.
func _make_placer(rng_seed: int) -> EntityPlacer:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var painter: TerrainPainter = TerrainPainter.new()
	painter.setup(rng, 1800.0)
	var placer: EntityPlacer = EntityPlacer.new()
	placer.setup(rng, 1800.0, 1.0, painter, [])
	return placer

func before_each() -> void:
	TerrainManager.reset()

func after_each() -> void:
	TerrainManager.reset()

# 1 — vision multiplier
func test_vision_reduced_under_canopy() -> void:
	TerrainManager.add_zone(Vector2.ZERO, 300.0, TerrainManager.TerrainType.LAURISILVA)
	assert_eq(TerrainManager.get_vision_mult(Vector2.ZERO), TerrainManager.LAURISILVA_VISION_MULT,
		"inside the laurel forest LOS shrinks")
	assert_eq(TerrainManager.get_vision_mult(Vector2(500.0, 0.0)), 1.0, "outside is unaffected")

func test_vision_unaffected_by_other_zones() -> void:
	TerrainManager.add_zone(Vector2.ZERO, 300.0, TerrainManager.TerrainType.DUNE)
	assert_eq(TerrainManager.get_vision_mult(Vector2.ZERO), 1.0, "dune does not reduce vision")

# 2 — dense high-yield forest inside laurisilva zones
func test_forest_spawned_inside_zone() -> void:
	var zone_center: Vector2 = Vector2(400.0, -200.0)
	var zone_radius: float = 300.0
	TerrainManager.add_zone(zone_center, zone_radius, TerrainManager.TerrainType.LAURISILVA)

	var parent: Node2D = Node2D.new()
	add_child_autofree(parent)
	_make_placer(12345).spawn_laurisilva_forests(parent)

	var trees: Array[Node] = []
	for child: Node in parent.get_children():
		if (child.get("resource_type") as int) == ResourceNode.ResourceType.WOOD:
			trees.append(child)
	assert_gt(trees.size(), 2, "the zone must hold a forest cluster")
	for tree: Node in trees:
		assert_lt((tree as Node2D).global_position.distance_to(zone_center), zone_radius,
			"every laurisilva tree lies inside its zone")
		assert_gt(tree.get("initial_amount") as float, 180.0,
			"laurel wood yields more than a regular forest tree (180)")

# 3 — no laurisilva, no extra forest
func test_no_zone_spawns_nothing() -> void:
	TerrainManager.add_zone(Vector2.ZERO, 300.0, TerrainManager.TerrainType.MALPAIS)
	var parent: Node2D = Node2D.new()
	add_child_autofree(parent)
	_make_placer(1).spawn_laurisilva_forests(parent)
	assert_eq(parent.get_child_count(), 0)

extends Node2D

## Deterministic map-generation census: runs MapGenerator.generate() for every
## map type with a fixed seed and prints a stable fingerprint of the result
## (TC positions, terrain zones, resource nodes, animals, nav meshes, scene
## node counts). Same seed must always produce the same output, so the census
## doubles as the regression gate for map-generation refactors: capture it
## before a change, diff it after.
## Run: $GODOT --headless --path project res://tools/check_map_gen.tscn
## Env: CALIMA_SEED (default 4242), CALIMA_MAPS ("0,1,2,3,4"), CALIMA_RIVALS (1)

const MAP_NAMES: Array[String] = ["PLAINS", "STANDARD", "VOLCANIC_COAST", "DESERT_COAST", "ISLANDS"]

const TERRAIN_NAMES: Array[String] = ["GRASS", "MALPAIS", "DUNE", "LAURISILVA", "RISCO", "OCEAN", "CALDERA"]

const RES_NAMES: Dictionary = {
	ResourceNode.ResourceType.WOOD:       "WOOD",
	ResourceNode.ResourceType.GOLD:       "GOLD",
	ResourceNode.ResourceType.STONE:      "STONE",
	ResourceNode.ResourceType.FOOD_HUNT:  "FOOD_HUNT",
	ResourceNode.ResourceType.FOOD_FISH:  "FOOD_FISH",
	ResourceNode.ResourceType.FOOD_BERRY: "FOOD_BERRY",
	ResourceNode.ResourceType.OLIVINA:    "OLIVINA",
}

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	var base_seed: int = int(seed_env) if not seed_env.is_empty() else 4242
	var rivals_env: String = OS.get_environment("CALIMA_RIVALS")
	MatchConfig.rival_count = int(rivals_env) if not rivals_env.is_empty() else 1
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	MatchConfig.resources = MatchConfig.Resources.NORMAL
	MatchConfig.player_civ_id = "guanches"

	var maps: Array = []
	var maps_env: String = OS.get_environment("CALIMA_MAPS")
	if maps_env.is_empty():
		maps = [0, 1, 2, 3, 4]
	else:
		for token: String in maps_env.split(",", false):
			maps.append(int(token.strip_edges()))

	print("MAP_GEN census seed=%d rivals=%d" % [base_seed, MatchConfig.rival_count])
	for map_type: int in maps:
		_census_map(map_type as int, base_seed)
	print("MAP_GEN: done")
	get_tree().quit(0)

func _census_map(map_type: int, base_seed: int) -> void:
	MatchConfig.map_type = map_type
	var root: Node2D = _make_world_root()
	add_child(root)
	var units_layer: Node2D = root.get_node("UnitsLayer") as Node2D
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = base_seed

	var data: Dictionary = MapGenerator.generate(root, units_layer, rng)

	print("--- %s ---" % MAP_NAMES[map_type])
	_print_tcs(data)
	_print_zones()
	_print_resources(root)
	_print_animals(units_layer)
	_print_nav(root)
	print("  rng_state=%d" % rng.state)
	print("  scene: root_children=%d units=%d" % [root.get_child_count(), units_layer.get_child_count()])

	root.queue_free()
	remove_child(root)
	TerrainManager.reset()

# Mirrors the parts of game_world.tscn that MapGenerator reads or writes.
func _make_world_root() -> Node2D:
	var root: Node2D = Node2D.new()
	root.name = "World"
	var units: Node2D = Node2D.new()
	units.name = "UnitsLayer"
	root.add_child(units)
	var land: NavigationRegion2D = NavigationRegion2D.new()
	land.name = "NavigationRegion2D"
	root.add_child(land)
	var ocean: NavigationRegion2D = NavigationRegion2D.new()
	ocean.name = "OceanNavigationRegion2D"
	root.add_child(ocean)
	return root

func _print_tcs(data: Dictionary) -> void:
	var out: PackedStringArray = PackedStringArray()
	for tc: Vector2 in (data["tc_positions"] as Array):
		out.append("(%d,%d)" % [roundi(tc.x), roundi(tc.y)])
	print("  tc_positions=%s" % ", ".join(out))

func _print_zones() -> void:
	var by_type: Dictionary = {}
	var checksum: int = 0
	for z: Dictionary in TerrainManager.get_zones():
		var t: int = z["type"] as int
		by_type[t] = (by_type.get(t, 0) as int) + 1
		var c: Vector2 = z["center"] as Vector2
		checksum += roundi(c.x) + roundi(c.y) * 3 + roundi(z["radius"] as float) * 7
	var keys: Array = by_type.keys()
	keys.sort()
	var out: PackedStringArray = PackedStringArray()
	for t: Variant in keys:
		out.append("%s=%d" % [TERRAIN_NAMES[t as int], by_type[t]])
	print("  zones: total=%d %s checksum=%d" % [
		TerrainManager.get_zones().size(), " ".join(out), checksum])

func _print_resources(root: Node2D) -> void:
	var counts: Dictionary = {}
	var amounts: Dictionary = {}
	var pos_checksum: int = 0
	for child: Node in root.get_children():
		var rtype: Variant = child.get("resource_type")
		if rtype == null or child.get("initial_amount") == null:
			continue
		var t: int = rtype as int
		counts[t] = (counts.get(t, 0) as int) + 1
		amounts[t] = (amounts.get(t, 0.0) as float) + (child.get("initial_amount") as float)
		var p: Vector2 = (child as Node2D).global_position
		pos_checksum += roundi(p.x) + roundi(p.y) * 3
	var keys: Array = counts.keys()
	keys.sort()
	var total: int = 0
	for t: Variant in keys:
		total += counts[t] as int
		print("    %-11s n=%-4d amount=%d" % [
			RES_NAMES.get(t, str(t)), counts[t], roundi(amounts[t] as float)])
	print("  resources: total=%d pos_checksum=%d" % [total, pos_checksum])

func _print_animals(units_layer: Node2D) -> void:
	var sheep: int = 0
	var deer: int = 0
	var hp_sum: int = 0
	for child: Node in units_layer.get_children():
		if child is Sheep:
			sheep += 1
		else:
			deer += 1
		hp_sum += roundi(child.get("max_health") as float)
	print("  animals: sheep=%d other=%d hp_sum=%d" % [sheep, deer, hp_sum])

func _print_nav(root: Node2D) -> void:
	var land: NavigationRegion2D = root.get_node("NavigationRegion2D") as NavigationRegion2D
	var ocean: NavigationRegion2D = root.get_node("OceanNavigationRegion2D") as NavigationRegion2D
	# Polygon counts, not outline counts: the source-geometry baker NavMeshBuilder
	# uses produces polygons without keeping the source outlines around.
	var land_polys: int = land.navigation_polygon.get_polygon_count() if land.navigation_polygon != null else 0
	var ocean_polys: int = ocean.navigation_polygon.get_polygon_count() if ocean.navigation_polygon != null else 0
	var obstacles: int = 0
	for child: Node in land.get_children():
		if child is NavigationObstacle2D:
			obstacles += 1
	print("  nav: land_polygons=%d ocean_polygons=%d obstacles=%d" % [
		land_polys, ocean_polys, obstacles])

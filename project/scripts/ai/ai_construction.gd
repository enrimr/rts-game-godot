class_name AIConstruction extends RefCounted

var _ai  # AIPlayer — untyped Variant so dynamic property access works at runtime

var _built: Dictionary = {
	"barracks": 0, "archery_range": 0, "blacksmith": 0, "stable": 0, "house": 0,
	"lumber_camp": 0, "mining_camp": 0, "farm": 0, "dock": 0, "mill": 0,
	"university": 0, "market": 0, "temple": 0, "siege_workshop": 0, "wonder": 0,
	"watch_tower": 0
}
var _building_costs: Dictionary = {}
var _build_fail_counts: Dictionary = {}
var _build_cooldowns: Dictionary = {}

const BUILDING_SCENES: Dictionary = {
	"barracks":       "res://scenes/buildings/barracks.tscn",
	"archery_range":  "res://scenes/buildings/archery_range.tscn",
	"blacksmith":     "res://scenes/buildings/blacksmith.tscn",
	"stable":         "res://scenes/buildings/stable.tscn",
	"house":          "res://scenes/buildings/house.tscn",
	"lumber_camp":    "res://scenes/buildings/lumber_camp.tscn",
	"mining_camp":    "res://scenes/buildings/mining_camp.tscn",
	"mill":           "res://scenes/buildings/mill.tscn",
	"watch_tower":    "res://scenes/buildings/watch_tower.tscn",
	"farm":           "res://scenes/buildings/farm.tscn",
	"dock":           "res://scenes/buildings/dock.tscn",
	"fish_trap":      "res://scenes/buildings/fish_trap.tscn",
	"university":     "res://scenes/buildings/university.tscn",
	"market":         "res://scenes/buildings/market.tscn",
	"temple":         "res://scenes/buildings/temple.tscn",
	"siege_workshop": "res://scenes/buildings/siege_workshop.tscn",
	"wonder":         "res://scenes/buildings/wonder.tscn",
}

const BUILD_FAIL_WIDEN_THRESHOLD: int = 3
const BUILD_FAIL_SKIP_THRESHOLD: int  = 6
const BUILD_FAIL_COOLDOWN: float      = 30.0
const BUILDING_CLEAR: float           = 72.0

# Grid-based placement: buildings snap to multiples of GRID_STEP from TC origin
const GRID_STEP: float = 96.0

# Per-building footprint radius used for clearance (half-diagonal of the sprite)
const BUILDING_FOOTPRINT: Dictionary = {
	"house":          48.0,
	"farm":           52.0,
	"barracks":       56.0,
	"archery_range":  56.0,
	"stable":         56.0,
	"blacksmith":     52.0,
	"university":     52.0,
	"temple":         52.0,
	"market":         56.0,
	"siege_workshop": 60.0,
	"lumber_camp":    52.0,
	"mining_camp":    52.0,
	"mill":           52.0,
	"watch_tower":    36.0,
	"wonder":        110.0,
}

# Watch towers per age: none in the Dark Age, one from Feudal, two from Castle.
func tower_target_for_age(age: int) -> int:
	if age <= GameManager.Age.DARK:
		return 0
	return 1 if age == GameManager.Age.FEUDAL else 2

func setup(ai) -> void:
	_ai = ai
	_load_building_costs()

func _load_building_costs() -> void:
	for building_id: String in BUILDING_SCENES.keys():
		var res_path: String = "res://resources/buildings/%s.tres" % building_id
		if not ResourceLoader.exists(res_path):
			continue
		var res: BuildingResource = load(res_path) as BuildingResource
		if res == null:
			continue
		_building_costs[building_id] = res.get_cost_dict()

func update_cooldowns(delta: float) -> void:
	for key: String in _build_cooldowns.keys():
		_build_cooldowns[key] = (_build_cooldowns[key] as float) - delta
		if (_build_cooldowns[key] as float) <= 0.0:
			_build_cooldowns.erase(key)
			_build_fail_counts.erase(key)

func sync_built_counts() -> void:
	for key: String in _built.keys():
		_built[key] = 0
	for building: Node in _ai.world.own_buildings(_ai.player_id):
		var bdata: Variant = building.get("building_data")
		if bdata == null:
			continue
		var bid: String = (bdata as Resource).get("id") as String
		if _built.has(bid):
			_built[bid] = (_built[bid] as int) + 1

func manage_population() -> void:
	var pop: int = PopulationManager.get_population(_ai.player_id).get("current", 0) as int
	var cap: int = PopulationManager.get_cap(_ai.player_id)
	if cap - pop <= 3 and ResourceManager.can_afford(_ai.player_id, _building_costs["house"]):
		_build("house")

func manage_economy_buildings() -> void:
	var age: int = AgeManager.get_age(_ai.player_id)
	var res: Dictionary = ResourceManager.get_resources(_ai.player_id)
	var wood: int = res.get("wood", 0) as int

	if _built["lumber_camp"] == 0 and ResourceManager.can_afford(_ai.player_id, _building_costs["lumber_camp"]):
		_build_near_resource("lumber_camp", ResourceNode.ResourceType.WOOD)

	if age >= GameManager.Age.FEUDAL and _built["mining_camp"] == 0 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["mining_camp"]):
		_build_near_resource("mining_camp", ResourceNode.ResourceType.GOLD)

	# One Mill, early: the food drop-off (and the herding-dog kennel) sits by
	# the TC where the flock is brought home.
	if _built["mill"] == 0 and ResourceManager.can_afford(_ai.player_id, _building_costs["mill"]):
		_build("mill")

	if age >= GameManager.Age.FEUDAL:
		var farm_count: int = _built.get("farm", 0) as int
		var _easy_mode: bool = GameSettings.difficulty == GameSettings.Difficulty.EASY or GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL
		var max_farms: int = 2 if _easy_mode else 3
		if farm_count < max_farms and wood > 120 \
				and ResourceManager.can_afford(_ai.player_id, _building_costs["farm"]):
			_build("farm")

func manage_military_buildings() -> void:
	var age: int = AgeManager.get_age(_ai.player_id)
	var barracks_count: int = _built.get("barracks", 0) as int

	if barracks_count == 0 and ResourceManager.can_afford(_ai.player_id, _building_costs["barracks"]):
		_build("barracks")
		return

	if age >= GameManager.Age.FEUDAL and barracks_count < 2 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["barracks"]):
		_build("barracks")
		return

	if age >= GameManager.Age.CASTLE and barracks_count < 3 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["barracks"]):
		_build("barracks")
		return

	manage_defensive_towers(age)

## Watch towers on the base perimeter from the Feudal Age (walls stay a
## player-only tool for now — the AI just anchors its edge with towers).
func manage_defensive_towers(age: int) -> void:
	var target: int = tower_target_for_age(age)
	if (_built.get("watch_tower", 0) as int) >= target:
		return
	if not ResourceManager.can_afford(_ai.player_id, _building_costs["watch_tower"]):
		return
	_build("watch_tower")

func manage_advanced_buildings() -> void:
	var age: int = AgeManager.get_age(_ai.player_id)
	if age < GameManager.Age.FEUDAL:
		return
	var barracks_count: int = _built.get("barracks", 0) as int
	if barracks_count == 0:
		return
	if _built.get("archery_range", 0) as int == 0 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs.get("archery_range", {"wood": 175})):
		_build("archery_range")
		return
	if _built.get("blacksmith", 0) as int == 0 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["blacksmith"]):
		_build("blacksmith")
	if _built.get("stable", 0) as int == 0 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["stable"]):
		_build("stable")
	if age >= GameManager.Age.CASTLE:
		if _built.get("university", 0) as int == 0 \
				and ResourceManager.can_afford(_ai.player_id, _building_costs["university"]):
			_build("university")
		if _built.get("temple", 0) as int == 0 \
				and ResourceManager.can_afford(_ai.player_id, _building_costs["temple"]):
			_build("temple")
		if _built.get("siege_workshop", 0) as int == 0 \
				and ResourceManager.can_afford(_ai.player_id, _building_costs["siege_workshop"]):
			_build("siege_workshop")
	if _built.get("market", 0) as int == 0 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["market"]):
		_build("market")
	if MatchConfig.victory_mode == MatchConfig.VictoryMode.WONDER \
			and age >= GameManager.Age.IMPERIAL \
			and _built.get("wonder", 0) as int == 0 \
			and ResourceManager.can_afford(_ai.player_id, _building_costs["wonder"]):
		_build("wonder")

func is_pos_clear(pos: Vector2) -> bool:
	return _build_pos_clear(pos)

func _build_pos_clear_footprint(pos: Vector2, footprint: float) -> bool:
	if TerrainManager.is_ocean(pos):
		return false
	if not TerrainManager.is_buildable(pos):
		return false
	for node: Node in _ai.get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node):
			continue
		if pos.distance_to((node as Node2D).global_position) < footprint + 32.0:
			return false
	for building: Node in _ai.world.all_buildings():
		var other_id: String = ""
		var bdata: Variant = building.get("building_data")
		if bdata != null:
			other_id = (bdata as Resource).get("id") as String
		var other_fp: float = BUILDING_FOOTPRINT.get(other_id, BUILDING_CLEAR * 0.5) as float
		var needed: float = footprint + other_fp + 8.0
		if pos.distance_to((building as Node2D).global_position) < needed:
			return false
	return true

func _build(building_id: String) -> void:
	if _build_cooldowns.has(building_id):
		return
	if not is_instance_valid(_ai.town_center):
		return
	var zone: Dictionary = _get_build_zone(building_id)
	var min_r: float = zone["min_r"] as float
	var max_r: float = _build_radius_for(building_id, zone["max_r"] as float)
	var bias: Vector2 = Vector2.ZERO
	if zone["toward_enemy"] as bool:
		var etc: Node2D = _ai._military.get_primary_enemy_tc()
		if etc != null:
			bias = _ai.town_center.global_position.direction_to(etc.global_position)
	var pos: Vector2 = _find_build_pos(_ai.town_center.global_position, min_r, max_r, bias, building_id)
	if pos == Vector2.INF:
		_record_build_fail(building_id)
		return
	_build_fail_counts.erase(building_id)
	if _place(building_id, pos) == null:
		return
	_ai.debug_log("BUILD %s at (%.0f,%.0f)" % [building_id, pos.x, pos.y])

func _build_near_resource(building_id: String, rtype: ResourceNode.ResourceType) -> void:
	if _build_cooldowns.has(building_id):
		return
	var origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else Vector2.ZERO
	var nearest: ResourceNode = _ai._economy.find_nearest_resource(rtype, origin)
	if nearest == null:
		_build(building_id)
		return
	var max_r: float = _build_radius_for(building_id, 140.0)
	var pos: Vector2 = _find_build_pos(nearest.global_position, 50.0, max_r, Vector2.ZERO, building_id)
	if pos == Vector2.INF:
		_record_build_fail(building_id)
		return
	_build_fail_counts.erase(building_id)
	var b: Node = _place(building_id, pos)
	if b == null:
		return
	_ai.debug_log("BUILD %s near resource at (%.0f,%.0f)" % [building_id, pos.x, pos.y])
	_ai._economy.redirect_villagers_to_drop_off(b as Node2D, rtype)

## Places one AI building through the CommandBus (instant construction) and
## keeps the local built-count in step. Returns the node, or null.
func _place(building_id: String, pos: Vector2) -> Node:
	var cmd: PlaceBuildingCommand = PlaceBuildingCommand.make(_ai.player_id, building_id,
		[pos] as Array[Vector2], 0.0, [] as Array[int], true)
	CommandBus.submit(cmd)
	if cmd.last_placed.is_empty():
		return null
	_built[building_id] = (_built.get(building_id, 0) as int) + 1
	return cmd.last_placed[0]

## Snaps a world position to the nearest GRID_STEP cell relative to TC origin.
func _snap_to_grid(pos: Vector2, tc_origin: Vector2) -> Vector2:
	var local: Vector2 = pos - tc_origin
	local.x = roundf(local.x / GRID_STEP) * GRID_STEP
	local.y = roundf(local.y / GRID_STEP) * GRID_STEP
	return tc_origin + local

## Grid-aware placement. Iterates candidate grid cells in rings from min_r to
## max_r, sorted by distance, shuffled within each ring to avoid always picking
## the same corner. Falls back to wider rings on repeated failure.
func _find_build_pos(origin: Vector2, min_r: float, max_r: float, bias: Vector2 = Vector2.ZERO, building_id: String = "") -> Vector2:
	var tc_origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else origin
	var fails: int = _build_fail_counts.get(building_id, 0) as int
	var effective_max: float = max_r * (1.0 + 0.4 * float(maxi(fails - BUILD_FAIL_WIDEN_THRESHOLD + 1, 0)))
	var footprint: float = BUILDING_FOOTPRINT.get(building_id, BUILDING_CLEAR * 0.5) as float

	# Collect all grid cells in [min_r, effective_max] ring
	var cells: Array[Vector2] = []
	var grid_min: int = int(ceil(min_r / GRID_STEP))
	var grid_max: int = int(floor(effective_max / GRID_STEP)) + 2
	for gx: int in range(-grid_max, grid_max + 1):
		for gy: int in range(-grid_max, grid_max + 1):
			var cell: Vector2 = tc_origin + Vector2(gx, gy) * GRID_STEP
			var dist: float = tc_origin.distance_to(cell)
			if dist < min_r - GRID_STEP * 0.5 or dist > effective_max + GRID_STEP * 0.5:
				continue
			cells.append(cell)

	# Sort by distance then shuffle within distance bands for variety
	cells.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return tc_origin.distance_squared_to(a) < tc_origin.distance_squared_to(b))

	# Bias: prefer cells in the enemy direction
	if bias != Vector2.ZERO:
		cells.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			var da: float = tc_origin.distance_squared_to(a)
			var db: float = tc_origin.distance_squared_to(b)
			var ba: float = (a - tc_origin).normalized().dot(bias)
			var bb: float = (b - tc_origin).normalized().dot(bias)
			# Primary: bias alignment (higher = better); secondary: closer first
			if absf(ba - bb) > 0.25:
				return ba > bb
			return da < db)

	for cell: Vector2 in cells:
		if _build_pos_clear_footprint(cell, footprint):
			return cell

	return Vector2.INF

func _get_build_zone(building_id: String) -> Dictionary:
	match building_id:
		"house":
			return {"min_r": GRID_STEP * 1.0, "max_r": GRID_STEP * 2.5, "toward_enemy": false}
		"farm":
			return {"min_r": GRID_STEP * 0.5, "max_r": GRID_STEP * 2.0, "toward_enemy": false}
		"barracks", "archery_range", "stable", "siege_workshop":
			return {"min_r": GRID_STEP * 2.0, "max_r": GRID_STEP * 4.0, "toward_enemy": true}
		"blacksmith":
			return {"min_r": GRID_STEP * 1.5, "max_r": GRID_STEP * 3.0, "toward_enemy": true}
		"mill":
			return {"min_r": GRID_STEP * 1.0, "max_r": GRID_STEP * 2.5, "toward_enemy": false}
		"watch_tower":
			return {"min_r": GRID_STEP * 3.0, "max_r": GRID_STEP * 5.0, "toward_enemy": true}
		"university", "temple", "market":
			return {"min_r": GRID_STEP * 1.5, "max_r": GRID_STEP * 3.0, "toward_enemy": false}
		"wonder":
			return {"min_r": GRID_STEP * 1.0, "max_r": GRID_STEP * 2.0, "toward_enemy": false}
		_:
			return {"min_r": GRID_STEP * 1.0, "max_r": GRID_STEP * 3.0, "toward_enemy": false}

func _build_radius_for(building_id: String, base_max: float) -> float:
	var fails: int = _build_fail_counts.get(building_id, 0) as int
	if fails >= BUILD_FAIL_WIDEN_THRESHOLD:
		return base_max * (1.0 + 0.3 * float(maxi(fails - BUILD_FAIL_WIDEN_THRESHOLD + 1, 1)))
	return base_max

func _record_build_fail(building_id: String) -> void:
	var count: int = (_build_fail_counts.get(building_id, 0) as int) + 1
	_build_fail_counts[building_id] = count
	if count >= BUILD_FAIL_SKIP_THRESHOLD:
		_build_cooldowns[building_id] = BUILD_FAIL_COOLDOWN
		_build_fail_counts.erase(building_id)

func _build_pos_clear(pos: Vector2) -> bool:
	return _build_pos_clear_footprint(pos, BUILDING_CLEAR * 0.5)

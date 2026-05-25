class_name AIConstruction extends RefCounted

var _ai  # AIPlayer — untyped Variant so dynamic property access works at runtime

var _built: Dictionary = {
	"barracks": 0, "blacksmith": 0, "stable": 0, "house": 0,
	"lumber_camp": 0, "mining_camp": 0, "farm": 0, "dock": 0,
	"university": 0, "market": 0, "temple": 0, "siege_workshop": 0, "wonder": 0
}
var _building_costs: Dictionary = {}
var _build_fail_counts: Dictionary = {}
var _build_cooldowns: Dictionary = {}

const BUILDING_SCENES: Dictionary = {
	"barracks":       "res://scenes/buildings/barracks.tscn",
	"blacksmith":     "res://scenes/buildings/blacksmith.tscn",
	"stable":         "res://scenes/buildings/stable.tscn",
	"house":          "res://scenes/buildings/house.tscn",
	"lumber_camp":    "res://scenes/buildings/lumber_camp.tscn",
	"mining_camp":    "res://scenes/buildings/mining_camp.tscn",
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
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
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

func manage_advanced_buildings() -> void:
	var age: int = AgeManager.get_age(_ai.player_id)
	if age < GameManager.Age.FEUDAL:
		return
	var barracks_count: int = _built.get("barracks", 0) as int
	if barracks_count == 0:
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

func _build(building_id: String) -> void:
	if _build_cooldowns.has(building_id):
		return
	var scene_path: String = BUILDING_SCENES.get(building_id, "") as String
	if scene_path.is_empty() or not is_instance_valid(_ai.town_center):
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var zone: Dictionary = _get_build_zone(building_id)
	var min_r: float = zone["min_r"] as float
	var max_r: float = _build_radius_for(building_id, zone["max_r"] as float)
	var bias: Vector2 = Vector2.ZERO
	if zone["toward_enemy"] as bool:
		var etc: Node2D = _ai._military.get_primary_enemy_tc()
		if etc != null:
			bias = _ai.town_center.global_position.direction_to(etc.global_position)
	var pos: Vector2 = _find_build_pos(_ai.town_center.global_position, min_r, max_r, bias)
	if pos == Vector2.INF:
		_record_build_fail(building_id)
		return
	_build_fail_counts.erase(building_id)
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = pos
	b.set("player_id", _ai.player_id)
	_ai.buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, _ai.player_id)
	ResourceManager.spend_resource(_ai.player_id, _building_costs[building_id])
	_built[building_id] = (_built.get(building_id, 0) as int) + 1
	_ai.debug_log("BUILD %s at (%.0f,%.0f)" % [building_id, pos.x, pos.y])

func _build_near_resource(building_id: String, rtype: ResourceNode.ResourceType) -> void:
	if _build_cooldowns.has(building_id):
		return
	var origin: Vector2 = _ai.town_center.global_position if is_instance_valid(_ai.town_center) else Vector2.ZERO
	var nearest: ResourceNode = _ai._economy.find_nearest_resource(rtype, origin)
	if nearest == null:
		_build(building_id)
		return
	var scene_path: String = BUILDING_SCENES.get(building_id, "") as String
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var max_r: float = _build_radius_for(building_id, 140.0)
	var pos: Vector2 = _find_build_pos(nearest.global_position, 50.0, max_r)
	if pos == Vector2.INF:
		_record_build_fail(building_id)
		return
	_build_fail_counts.erase(building_id)
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = pos
	b.set("player_id", _ai.player_id)
	_ai.buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, _ai.player_id)
	ResourceManager.spend_resource(_ai.player_id, _building_costs[building_id])
	_built[building_id] = (_built.get(building_id, 0) as int) + 1
	_ai.debug_log("BUILD %s near resource at (%.0f,%.0f)" % [building_id, pos.x, pos.y])
	_ai._economy.redirect_villagers_to_drop_off(b, rtype)

func _find_build_pos(origin: Vector2, min_r: float, max_r: float, bias: Vector2 = Vector2.ZERO) -> Vector2:
	var bias_angle: float = bias.angle() if bias != Vector2.ZERO else 0.0
	var use_bias: bool = bias != Vector2.ZERO
	for _i: int in range(48):
		var angle: float
		if use_bias and randf() < 0.70:
			angle = bias_angle + randf_range(-PI / 3.0, PI / 3.0)
		else:
			angle = randf() * TAU
		var dist: float  = randf_range(min_r, max_r)
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		if _build_pos_clear(pos):
			return pos
	for _i: int in range(20):
		var angle: float = randf() * TAU
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * max_r * 1.5
		if _build_pos_clear(pos):
			return pos
	return Vector2.INF

func _get_build_zone(building_id: String) -> Dictionary:
	match building_id:
		"house":
			return {"min_r": 70.0, "max_r": 160.0, "toward_enemy": false}
		"farm":
			return {"min_r": 55.0, "max_r": 130.0, "toward_enemy": false}
		"barracks", "stable", "siege_workshop":
			return {"min_r": 150.0, "max_r": 300.0, "toward_enemy": true}
		"blacksmith":
			return {"min_r": 120.0, "max_r": 220.0, "toward_enemy": true}
		"university", "temple", "market":
			return {"min_r": 100.0, "max_r": 200.0, "toward_enemy": false}
		"wonder":
			return {"min_r": 80.0, "max_r": 160.0, "toward_enemy": false}
		_:
			return {"min_r": 80.0, "max_r": 220.0, "toward_enemy": false}

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
	if TerrainManager.is_ocean(pos):
		return false
	if not TerrainManager.is_buildable(pos):
		return false
	for node: Node in _ai.get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node):
			continue
		if pos.distance_to((node as Node2D).global_position) < BUILDING_CLEAR:
			return false
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		if pos.distance_to((building as Node2D).global_position) < BUILDING_CLEAR:
			return false
	return true

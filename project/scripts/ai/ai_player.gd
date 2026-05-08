extends Node

## AIPlayer — tick-based AI that manages economy, constructs buildings, trains
## varied military units, and launches coordinated attacks.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const BUILDING_SCENES: Dictionary = {
	"barracks":    "res://scenes/buildings/barracks.tscn",
	"house":       "res://scenes/buildings/house.tscn",
	"lumber_camp": "res://scenes/buildings/lumber_camp.tscn",
	"mining_camp": "res://scenes/buildings/mining_camp.tscn",
	"farm":        "res://scenes/buildings/farm.tscn",
	"dock":        "res://scenes/buildings/dock.tscn",
}
const BUILDING_COSTS: Dictionary = {
	"barracks":    {"wood": 175},
	"house":       {"wood": 25},
	"lumber_camp": {"wood": 100},
	"mining_camp": {"wood": 100},
	"farm":        {"wood": 60},
	"dock":        {"wood": 150},
}

const TICK_INTERVAL: float        = 2.0
const THREAT_CHECK_INTERVAL: float = 3.0
const CONTROL_ZONE_RADIUS: float  = 400.0
const AGGRESSION_DECAY: float     = 20.0

@export var player_id: int = 1

var town_center: Node2D   = null
var units_layer: Node2D   = null
var buildings_layer: Node2D = null
var drop_off: Node2D      = null
var enemy_town_center: Node2D = null

var _timer: float         = 0.0
var _attack_timer: float  = 0.0
var _threat_timer: float  = 0.0

# Track which building types have been built (counts)
var _built: Dictionary = {"barracks": 0, "house": 0, "lumber_camp": 0, "mining_camp": 0, "farm": 0, "dock": 0}

# Naval state
var _naval_transport: Node = null   # active transport ship reference
var _naval_assault_timer: float = 0.0
const NAVAL_ASSAULT_INTERVAL: float = 45.0

enum AggressionLevel { PASSIVE, ALERTED, AGGRESSIVE }
var _aggression: AggressionLevel = AggressionLevel.PASSIVE
var _aggression_timer: float = 0.0

func _ready() -> void:
	EventBus.ai_unit_under_attack.connect(_on_ai_unit_under_attack)

func _on_ai_unit_under_attack(attacked_player_id: int) -> void:
	if attacked_player_id != player_id:
		return
	notify_under_attack()

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	_timer        += delta
	_attack_timer += delta
	_threat_timer += delta

	if _aggression > AggressionLevel.PASSIVE:
		_aggression_timer += delta
		if _aggression_timer >= AGGRESSION_DECAY:
			_aggression = AggressionLevel.PASSIVE
			_aggression_timer = 0.0

	if _timer >= TICK_INTERVAL:
		_timer = 0.0
		_run_tick()

	if _is_naval_map():
		_naval_assault_timer += delta
		if _naval_assault_timer >= NAVAL_ASSAULT_INTERVAL:
			_naval_assault_timer = 0.0
			_launch_naval_assault()

	if _attack_timer >= _effective_attack_interval():
		_attack_timer = 0.0
		_launch_attack()

	if _threat_timer >= THREAT_CHECK_INTERVAL:
		_threat_timer = 0.0
		_check_zone_threat()

func _effective_attack_interval() -> float:
	match _aggression:
		AggressionLevel.AGGRESSIVE: return GameSettings.get_ai_attack_interval() * 0.33
		AggressionLevel.ALERTED:    return GameSettings.get_ai_attack_interval() * 0.60
	return GameSettings.get_ai_attack_interval()

func _run_tick() -> void:
	_sync_built_counts()
	_manage_population()
	_manage_villagers()
	_manage_economy_buildings()
	_manage_military_buildings()
	_manage_military()
	_manage_age_advance()
	if _is_naval_map():
		_manage_naval()

# ── Population ───────────────────────────────────────────────────────────────

func _manage_population() -> void:
	var pop: int    = PopulationManager.get_population(player_id).get("current", 0) as int
	var cap: int    = PopulationManager.get_cap(player_id)
	# Build a house when within 3 of the cap and we can afford it
	if cap - pop <= 3 and ResourceManager.can_afford(player_id, BUILDING_COSTS["house"]):
		_build("house")

# ── Economy ──────────────────────────────────────────────────────────────────

func _manage_villagers() -> void:
	if not is_instance_valid(town_center):
		return
	var vcount: int = _count_of_type("Villager")
	var target: int = GameSettings.get_ai_villager_target()
	if vcount < target and not PopulationManager.at_cap(player_id):
		_spawn_villager()
	# Re-assign idle villagers
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != player_id:
			continue
		if v.current_state == UnitBase.UnitState.IDLE:
			_assign_villager(v)

func _assign_villager(v: Villager) -> void:
	var res: Dictionary = ResourceManager.get_resources(player_id)
	var wood: int  = res.get("wood",  0) as int
	var food: int  = res.get("food",  0) as int
	var gold: int  = res.get("gold",  0) as int

	# Priority: always need food; push wood if low; gold for military
	var priority: Array[ResourceNode.ResourceType]
	if food < 200:
		priority = [ResourceNode.ResourceType.FOOD_HUNT, ResourceNode.ResourceType.WOOD,
					ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE]
	elif wood < 150:
		priority = [ResourceNode.ResourceType.WOOD, ResourceNode.ResourceType.FOOD_HUNT,
					ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE]
	elif gold < 100:
		priority = [ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.WOOD,
					ResourceNode.ResourceType.FOOD_HUNT, ResourceNode.ResourceType.STONE]
	else:
		priority = [ResourceNode.ResourceType.WOOD, ResourceNode.ResourceType.FOOD_HUNT,
					ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE]

	for rtype: ResourceNode.ResourceType in priority:
		var node: ResourceNode = _find_nearest_resource(rtype, v.global_position)
		if node != null:
			var nearest_drop: Node2D = _find_nearest_drop_off(rtype)
			v.order_gather(node, node.get_resource_name(), nearest_drop if nearest_drop != null else drop_off)
			return

# ── Economy buildings ─────────────────────────────────────────────────────────

func _manage_economy_buildings() -> void:
	var age: int = AgeManager.get_age(player_id)
	var res: Dictionary = ResourceManager.get_resources(player_id)
	var wood: int = res.get("wood", 0) as int

	# Lumber camp: build one near the nearest wood cluster if we have no drop-off for wood
	if _built["lumber_camp"] == 0 and ResourceManager.can_afford(player_id, BUILDING_COSTS["lumber_camp"]):
		_build_near_resource("lumber_camp", ResourceNode.ResourceType.WOOD)

	# Mining camp: build one near gold/stone once in Feudal
	if age >= GameManager.Age.FEUDAL and _built["mining_camp"] == 0 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["mining_camp"]):
		_build_near_resource("mining_camp", ResourceNode.ResourceType.GOLD)

	# Farms: build up to 2 farms in Feudal when food is low and we have wood spare
	if age >= GameManager.Age.FEUDAL:
		var farm_count: int = _built.get("farm", 0) as int
		var max_farms: int = 2 if GameSettings.difficulty == GameSettings.Difficulty.EASY else 3
		if farm_count < max_farms and wood > 120 \
				and ResourceManager.can_afford(player_id, BUILDING_COSTS["farm"]):
			_build("farm")

# ── Military buildings ────────────────────────────────────────────────────────

func _manage_military_buildings() -> void:
	var age: int = AgeManager.get_age(player_id)
	var barracks_count: int = _built.get("barracks", 0) as int

	# First barracks as soon as possible
	if barracks_count == 0 and ResourceManager.can_afford(player_id, BUILDING_COSTS["barracks"]):
		_build("barracks")
		return

	# Second barracks in Feudal
	if age >= GameManager.Age.FEUDAL and barracks_count < 2 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["barracks"]):
		_build("barracks")
		return

	# Third barracks in Castle
	if age >= GameManager.Age.CASTLE and barracks_count < 3 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["barracks"]):
		_build("barracks")

# ── Military training ─────────────────────────────────────────────────────────

func _manage_military() -> void:
	if _built.get("barracks", 0) as int == 0:
		return

	var age: int = AgeManager.get_age(player_id)
	var military: int = _count_military()
	var passive_target: int = GameSettings.get_ai_military_target_passive()
	var target: int = passive_target if _aggression == AggressionLevel.PASSIVE else passive_target + 4

	if military >= target:
		return

	# Desired composition by age: [militia_fraction, archer_fraction, pikeman_fraction]
	# Values are relative weights — pick unit type by current ratio deficit
	var desired: Dictionary
	match age:
		GameManager.Age.DARK:
			desired = {"militia": 1.0, "archer": 0.0, "pikeman": 0.0}
		GameManager.Age.FEUDAL:
			desired = {"militia": 0.4, "archer": 0.5, "pikeman": 0.1}
		GameManager.Age.CASTLE:
			desired = {"militia": 0.3, "archer": 0.4, "pikeman": 0.3}
		_: # IMPERIAL
			desired = {"militia": 0.2, "archer": 0.4, "pikeman": 0.4}

	var unit_id: String = _pick_unit_to_train(desired)
	if unit_id.is_empty():
		return

	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is Barracks):
			continue
		var br: Barracks = building as Barracks
		if br.player_id != player_id:
			continue
		if br.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if br.get_queue().size() >= br.get_max_queue():
			continue
		br.order_train(unit_id)
		break

func _pick_unit_to_train(desired: Dictionary) -> String:
	var militia_c: int = _count_of_type("Militia")
	var archer_c: int  = _count_of_type("Archer")
	var pike_c: int    = _count_of_type("Pikeman")
	var total: int     = militia_c + archer_c + pike_c

	if total == 0:
		# Train whatever is available first
		for unit_id: String in ["militia", "archer", "pikeman"]:
			if _can_train(unit_id):
				return unit_id
		return ""

	# Find unit type most below its desired ratio
	var best_id: String = ""
	var best_deficit: float = -1.0
	for unit_id: String in desired.keys():
		var want: float = desired[unit_id] as float
		if want <= 0.0:
			continue
		if not _can_train(unit_id):
			continue
		var current_ratio: float = 0.0
		match unit_id:
			"militia": current_ratio = float(militia_c) / float(total)
			"archer":  current_ratio = float(archer_c)  / float(total)
			"pikeman": current_ratio = float(pike_c)    / float(total)
		var deficit: float = want - current_ratio
		if deficit > best_deficit:
			best_deficit = deficit
			best_id = unit_id
	return best_id

func _can_train(unit_id: String) -> bool:
	var age: int = AgeManager.get_age(player_id)
	match unit_id:
		"militia":  return true  # available from Dark Age
		"archer":   return age >= GameManager.Age.FEUDAL
		"pikeman":  return age >= GameManager.Age.CASTLE
	return false

# ── Age advancement ───────────────────────────────────────────────────────────

func _manage_age_advance() -> void:
	if AgeManager.is_advancing(player_id):
		return
	if AgeManager.get_age(player_id) >= GameManager.Age.IMPERIAL:
		return
	# Only advance when economy is stable and we have a defensive force
	var military: int = _count_military()
	var min_mil: int = 2 if GameSettings.difficulty == GameSettings.Difficulty.EASY else 3
	if military >= min_mil and AgeManager.can_advance(player_id):
		AgeManager.start_advance(player_id)

# ── Attack & Defense ──────────────────────────────────────────────────────────

func _launch_attack() -> void:
	if not is_instance_valid(enemy_town_center):
		return
	var mcount: int = _count_military()
	var min_units: int = GameSettings.get_ai_min_attack_units()
	if _aggression == AggressionLevel.AGGRESSIVE:
		min_units = maxi(min_units - 1, 1)
	if mcount < min_units:
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if unit is Militia or unit is Archer or unit is Pikeman:
			if unit.has_method("order_attack"):
				unit.order_attack(enemy_town_center)

func _check_zone_threat() -> void:
	if not is_instance_valid(town_center):
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if (unit as Node2D).global_position.distance_to(town_center.global_position) <= CONTROL_ZONE_RADIUS:
			_escalate_aggression(AggressionLevel.AGGRESSIVE)
			_defend_base()
			return

func _escalate_aggression(level: AggressionLevel) -> void:
	if level > _aggression:
		_aggression = level
	_aggression_timer = 0.0

func notify_under_attack() -> void:
	_escalate_aggression(AggressionLevel.ALERTED)
	if _count_military() >= 2:
		_attack_timer = _effective_attack_interval()

func _defend_base() -> void:
	if not is_instance_valid(town_center):
		return
	var best_enemy: Node = null
	var best_dist: float = CONTROL_ZONE_RADIUS
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var d: float = (unit as Node2D).global_position.distance_to(town_center.global_position)
		if d < best_dist:
			best_dist = d
			best_enemy = unit
	if best_enemy == null:
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if (unit is Militia or unit is Archer or unit is Pikeman) and unit.has_method("order_attack"):
			unit.order_attack(best_enemy)

# ── Naval AI ─────────────────────────────────────────────────────────────────

func _is_naval_map() -> bool:
	return MatchConfig.map_type == MatchConfig.MapType.ISLANDS

func _manage_naval() -> void:
	# Build a dock near the shore if we don't have one yet
	if _built.get("dock", 0) as int == 0 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["dock"]):
		_build_dock_on_shore()
		return

	if _built.get("dock", 0) as int == 0:
		return

	# Train war galleys for defense, then a transport once we have 3+ military
	var dock: Node = _find_own_dock()
	if dock == null or dock.get("state") as int != BuildingBase.BuildingState.COMPLETE:
		return
	if (dock as Dock).get_queue().size() >= (dock as Dock).get_max_queue():
		return

	var age: int = AgeManager.get_age(player_id)
	if age < GameManager.Age.FEUDAL:
		return

	var galleys: int  = _count_naval("WarGalley")
	var transports: int = _count_naval("TransportShip")

	# Keep 1-2 war galleys before investing in transport
	if galleys < 2 and ResourceManager.can_afford(player_id, {"wood": 75, "gold": 25}):
		(dock as Dock).order_train("war_galley")
		return

	# One transport is enough for the assault
	if transports < 1 and ResourceManager.can_afford(player_id, {"wood": 100, "gold": 50}):
		(dock as Dock).order_train("transport_ship")

func _launch_naval_assault() -> void:
	if not is_instance_valid(enemy_town_center):
		return
	var military: int = _count_military()
	if military < 3:
		return

	# Find or reuse the AI transport ship
	if not is_instance_valid(_naval_transport):
		_naval_transport = _find_own_transport()
	if not is_instance_valid(_naval_transport):
		return
	var ts: TransportShip = _naval_transport as TransportShip
	if ts == null:
		return

	# Board idle military units onto the transport
	var boarded: int = 0
	for unit: Node in units_layer.get_children():
		if ts.is_full():
			break
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if not (unit is Militia or unit is Archer or unit is Pikeman):
			continue
		if unit.has_method("current_state") or unit.get("current_state") as int == UnitBase.UnitState.IDLE:
			ts.board(unit)
			boarded += 1

	if boarded > 0 or ts.get_garrison().size() > 0:
		# Order the ship to move near the enemy town center then unload
		ts.order_move_then_unload(enemy_town_center.global_position)

func _build_dock_on_shore() -> void:
	# Find a shore position: probe outward from TC until we hit an ocean-adjacent land tile
	if not is_instance_valid(town_center):
		return
	var pos: Vector2 = _find_shore_position()
	if pos == Vector2.ZERO:
		return
	var scene_path: String = BUILDING_SCENES.get("dock", "") as String
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = pos
	b.set("player_id", player_id)
	buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, player_id)
	ResourceManager.spend_resource(player_id, BUILDING_COSTS["dock"])
	_built["dock"] = 1

func _find_shore_position() -> Vector2:
	# Spiral outward from TC, looking for a land tile that is adjacent to ocean
	var origin: Vector2 = town_center.global_position
	const PROBE: float = 48.0
	const DIRS: Array = [
		Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1),
		Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1),
	]
	for radius: int in range(2, 14):
		for dir: Variant in DIRS:
			var candidate: Vector2 = origin + (dir as Vector2) * PROBE * float(radius)
			if TerrainManager.is_ocean(candidate):
				continue
			# Check if at least one neighbour is ocean
			for nd: Variant in DIRS:
				if TerrainManager.is_ocean(candidate + (nd as Vector2) * PROBE):
					return candidate
	return Vector2.ZERO

func _find_own_dock() -> Node:
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if building is Dock:
			return building
	return null

func _find_own_transport() -> Node:
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if unit is TransportShip:
			return unit
	return null

func _count_naval(type_name: String) -> int:
	var count: int = 0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		match type_name:
			"WarGalley":      if unit is WarGalley:      count += 1
			"TransportShip":  if unit is TransportShip:  count += 1
	return count

# ── Building placement ────────────────────────────────────────────────────────

func _build(building_id: String) -> void:
	var scene_path: String = BUILDING_SCENES.get(building_id, "") as String
	if scene_path.is_empty() or not is_instance_valid(town_center):
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = _find_build_pos(town_center.global_position, 80.0, 220.0)
	b.set("player_id", player_id)
	buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, player_id)
	ResourceManager.spend_resource(player_id, BUILDING_COSTS[building_id])
	_built[building_id] = (_built.get(building_id, 0) as int) + 1

func _build_near_resource(building_id: String, rtype: ResourceNode.ResourceType) -> void:
	var nearest: ResourceNode = _find_nearest_resource(rtype,
		town_center.global_position if is_instance_valid(town_center) else Vector2.ZERO)
	if nearest == null:
		_build(building_id)
		return
	var scene_path: String = BUILDING_SCENES.get(building_id, "") as String
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = _find_build_pos(nearest.global_position, 50.0, 140.0)
	b.set("player_id", player_id)
	buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, player_id)
	ResourceManager.spend_resource(player_id, BUILDING_COSTS[building_id])
	_built[building_id] = (_built.get(building_id, 0) as int) + 1
	# Re-assign nearby idle villagers to this drop-off
	_redirect_villagers_to_drop_off(b, rtype)

func _find_build_pos(origin: Vector2, min_r: float, max_r: float) -> Vector2:
	for _i: int in range(20):
		var angle: float = randf() * TAU
		var dist: float  = randf_range(min_r, max_r)
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		if not TerrainManager.is_ocean(pos):
			return pos
	return origin + Vector2(randf_range(-max_r, max_r), randf_range(min_r, max_r))

func _redirect_villagers_to_drop_off(new_drop: Node2D, rtype: ResourceNode.ResourceType) -> void:
	var reassigned: int = 0
	for unit: Node in units_layer.get_children():
		if reassigned >= 2:
			break
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != player_id:
			continue
		var carried: Variant = v.get("carried_resource")
		if carried != null and (carried as String) != "" and v.gather_target != null:
			v.drop_off_target = new_drop
			reassigned += 1

# ── Spawn helpers ─────────────────────────────────────────────────────────────

func _spawn_villager() -> void:
	if not ResourceManager.spend_resource(player_id, {"food": 50}):
		return
	var v: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	v.set("player_id", player_id)
	v.set("civ_id", MatchConfig.rival_civ_id)
	units_layer.add_child(v)
	v.global_position = town_center.global_position + Vector2(randf_range(-50.0, 50.0), 60.0)
	PopulationManager.add_unit(player_id)
	EventBus.unit_spawned.emit(v, player_id)

# ── Sync built counts from actual buildings layer ─────────────────────────────

func _sync_built_counts() -> void:
	for key: String in _built.keys():
		_built[key] = 0
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var bdata: Variant = building.get("building_data")
		if bdata == null:
			continue
		var bid: String = (bdata as Resource).get("id") as String
		if _built.has(bid):
			_built[bid] = (_built[bid] as int) + 1

# ── Resource search ───────────────────────────────────────────────────────────

func _find_nearest_resource(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.resource_type != rtype:
			continue
		var d: float = from.distance_to(rn.global_position)
		if d < best_dist:
			best_dist = d
			best = rn
	return best

func _find_nearest_drop_off(rtype: ResourceNode.ResourceType) -> Node2D:
	# Wood → lumber camp; gold/stone → mining camp; food → TC
	var preferred_id: String
	match rtype:
		ResourceNode.ResourceType.WOOD:
			preferred_id = "lumber_camp"
		ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE:
			preferred_id = "mining_camp"
		_:
			return drop_off
	var best: Node2D = null
	var best_dist: float = INF
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var bdata: Variant = building.get("building_data")
		if bdata == null:
			continue
		if (bdata as Resource).get("id") as String != preferred_id:
			continue
		if building.get("state") as int != BuildingBase.BuildingState.COMPLETE:
			continue
		var d: float = (building as Node2D).global_position.distance_to(town_center.global_position)
		if d < best_dist:
			best_dist = d
			best = building as Node2D
	return best if best != null else drop_off

# ── Count helpers ─────────────────────────────────────────────────────────────

func _count_of_type(type_name: String) -> int:
	var count: int = 0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		match type_name:
			"Villager": if unit is Villager:  count += 1
			"Militia":  if unit is Militia:   count += 1
			"Archer":   if unit is Archer:    count += 1
			"Pikeman":  if unit is Pikeman:   count += 1
	return count

func _count_military() -> int:
	return _count_of_type("Militia") + _count_of_type("Archer") + _count_of_type("Pikeman")

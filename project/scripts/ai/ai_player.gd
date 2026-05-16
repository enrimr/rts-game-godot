extends Node

## AIPlayer — tick-based AI that manages economy, constructs buildings, trains
## varied military units, and launches coordinated attacks.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
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
const BUILDING_COSTS: Dictionary = {
	"barracks":       {"wood": 175},
	"blacksmith":     {"wood": 150},
	"stable":         {"wood": 175},
	"house":          {"wood": 25},
	"lumber_camp":    {"wood": 100},
	"mining_camp":    {"wood": 100},
	"farm":           {"wood": 60},
	"dock":           {"wood": 150},
	"fish_trap":      {"wood": 75},
	"university":     {"wood": 200},
	"market":         {"wood": 175},
	"temple":         {"wood": 175},
	"siege_workshop": {"wood": 200},
	"wonder":         {"wood": 2500, "food": 2500, "stone": 2500, "gold": 5000},
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
var _built: Dictionary = {"barracks": 0, "blacksmith": 0, "stable": 0, "house": 0, "lumber_camp": 0, "mining_camp": 0, "farm": 0, "dock": 0, "university": 0, "market": 0, "temple": 0, "siege_workshop": 0, "wonder": 0}
var _build_fail_counts: Dictionary = {}   # building_id -> int fail streak
var _build_cooldowns: Dictionary = {}     # building_id -> float time_remaining

# Naval state
var _naval_transport: Node = null   # active transport ship reference
var _naval_scout_target: Vector2 = Vector2.ZERO  # last scout destination for war galleys

enum AggressionLevel { PASSIVE, ALERTED, AGGRESSIVE }
var _aggression: AggressionLevel = AggressionLevel.PASSIVE
var _aggression_timer: float = 0.0

func _ready() -> void:
	EventBus.ai_unit_under_attack.connect(_on_ai_unit_under_attack)

func _exit_tree() -> void:
	if EventBus.ai_unit_under_attack.is_connected(_on_ai_unit_under_attack):
		EventBus.ai_unit_under_attack.disconnect(_on_ai_unit_under_attack)

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
	for key: String in _build_cooldowns.keys():
		_build_cooldowns[key] = (_build_cooldowns[key] as float) - delta
		if (_build_cooldowns[key] as float) <= 0.0:
			_build_cooldowns.erase(key)
			_build_fail_counts.erase(key)

	if _aggression > AggressionLevel.PASSIVE:
		_aggression_timer += delta
		if _aggression_timer >= AGGRESSION_DECAY:
			_aggression = AggressionLevel.PASSIVE
			_aggression_timer = 0.0

	if _timer >= TICK_INTERVAL:
		_timer = 0.0
		_run_tick()

	if _attack_timer >= _effective_attack_interval():
		_attack_timer = 0.0
		if _is_naval_map():
			_launch_naval_assault()
		else:
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
	_manage_advanced_buildings()
	_manage_military()
	_manage_age_advance()
	if _is_naval_map():
		_manage_naval()
		_manage_naval_patrol()
		_manage_fishing_boats()
		_attack_with_idle_land_units()

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
	# Pre-compute gather counts once so _assign_villager doesn't re-walk children per idle unit
	var counts: Dictionary = {}
	var assigned_total: int = 0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var vil: Villager = unit as Villager
		if vil.player_id != player_id:
			continue
		if not is_instance_valid(vil.gather_target) or not (vil.gather_target is ResourceNode):
			continue
		var rt: ResourceNode.ResourceType = (vil.gather_target as ResourceNode).resource_type
		var n: int = counts.get(rt, 0) as int
		counts[rt] = n + 1
		assigned_total += 1
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != player_id:
			continue
		if v.current_state == UnitBase.UnitState.IDLE:
			_assign_villager(v, counts, assigned_total)

func _assign_villager(v: Villager, counts: Dictionary, assigned_total: int) -> void:
	var age: int = AgeManager.get_age(player_id)

	# Target fraction of villagers on each resource type, by age (IMPERIAL is the default)
	var target_fractions: Dictionary = {
		ResourceNode.ResourceType.FOOD_HUNT: 0.25,
		ResourceNode.ResourceType.WOOD:      0.20,
		ResourceNode.ResourceType.GOLD:      0.45,
		ResourceNode.ResourceType.STONE:     0.10,
	}
	match age:
		GameManager.Age.DARK:
			target_fractions = {
				ResourceNode.ResourceType.FOOD_HUNT: 0.60,
				ResourceNode.ResourceType.WOOD:      0.40,
				ResourceNode.ResourceType.GOLD:      0.00,
				ResourceNode.ResourceType.STONE:     0.00,
			}
		GameManager.Age.FEUDAL:
			target_fractions = {
				ResourceNode.ResourceType.FOOD_HUNT: 0.40,
				ResourceNode.ResourceType.WOOD:      0.30,
				ResourceNode.ResourceType.GOLD:      0.25,
				ResourceNode.ResourceType.STONE:     0.05,
			}
		GameManager.Age.CASTLE:
			target_fractions = {
				ResourceNode.ResourceType.FOOD_HUNT: 0.30,
				ResourceNode.ResourceType.WOOD:      0.25,
				ResourceNode.ResourceType.GOLD:      0.35,
				ResourceNode.ResourceType.STONE:     0.10,
			}

	# Send the villager to whichever resource type is most below its target fraction
	var best_node: ResourceNode = null
	var best_deficit: float = -INF
	# +1 so the unit being assigned is counted in the denominator
	var total: float = float(assigned_total + 1)
	for rtype: ResourceNode.ResourceType in target_fractions.keys():
		var want: float = target_fractions[rtype] as float
		if want <= 0.0:
			continue
		var node: ResourceNode = _find_nearest_resource(rtype, v.global_position)
		if node == null:
			continue
		var current_frac: float = float(counts.get(rtype, 0) as int) / total
		var deficit: float = want - current_frac
		if deficit > best_deficit:
			best_deficit = deficit
			best_node = node

	if best_node == null:
		return
	var nearest_drop: Node2D = _find_nearest_drop_off(best_node.resource_type)
	v.order_gather(best_node, best_node.get_resource_name(), nearest_drop if nearest_drop != null else drop_off)

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
		var _easy_mode: bool = GameSettings.difficulty == GameSettings.Difficulty.EASY or GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL
		var max_farms: int = 2 if _easy_mode else 3
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

# ── Advanced buildings ────────────────────────────────────────────────────────

func _manage_advanced_buildings() -> void:
	var age: int = AgeManager.get_age(player_id)
	if age < GameManager.Age.FEUDAL:
		return
	var barracks_count: int = _built.get("barracks", 0) as int
	if barracks_count == 0:
		return
	if _built.get("blacksmith", 0) as int == 0 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["blacksmith"]):
		_build("blacksmith")
	if _built.get("stable", 0) as int == 0 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["stable"]):
		_build("stable")
	if age >= GameManager.Age.CASTLE:
		if _built.get("university", 0) as int == 0 \
				and ResourceManager.can_afford(player_id, BUILDING_COSTS["university"]):
			_build("university")
		if _built.get("temple", 0) as int == 0 \
				and ResourceManager.can_afford(player_id, BUILDING_COSTS["temple"]):
			_build("temple")
		if _built.get("siege_workshop", 0) as int == 0 \
				and ResourceManager.can_afford(player_id, BUILDING_COSTS["siege_workshop"]):
			_build("siege_workshop")
	if _built.get("market", 0) as int == 0 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["market"]):
		_build("market")
	if MatchConfig.victory_mode == MatchConfig.VictoryMode.WONDER \
			and age >= GameManager.Age.IMPERIAL \
			and _built.get("wonder", 0) as int == 0 \
			and ResourceManager.can_afford(player_id, BUILDING_COSTS["wonder"]):
		_build("wonder")
	_manage_stable_training()
	_manage_siege_training()

func _manage_siege_training() -> void:
	if _built.get("siege_workshop", 0) as int == 0:
		return
	var age: int = AgeManager.get_age(player_id)
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is SiegeWorkshop):
			continue
		var sw: SiegeWorkshop = building as SiegeWorkshop
		if sw.player_id != player_id:
			continue
		if sw.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if sw.get_queue().size() >= sw.get_max_queue():
			continue
		if age >= GameManager.Age.IMPERIAL and ResourceManager.can_afford(player_id, {"wood": 200, "gold": 200}):
			sw.order_train("trebuchet")
		elif ResourceManager.can_afford(player_id, {"wood": 160, "gold": 135}):
			sw.order_train("mangonel")
		elif ResourceManager.can_afford(player_id, {"wood": 160}):
			sw.order_train("battering_ram")
		break

func _manage_stable_training() -> void:
	if _built.get("stable", 0) as int == 0:
		return
	var age: int = AgeManager.get_age(player_id)
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is Stable):
			continue
		var st: Stable = building as Stable
		if st.player_id != player_id:
			continue
		if st.state != BuildingBase.BuildingState.COMPLETE:
			continue
		if st.get_queue().size() >= st.get_max_queue():
			continue
		if age >= GameManager.Age.CASTLE and ResourceManager.can_afford(player_id, {"food": 60, "gold": 75}):
			st.order_train("knight")
		elif age >= GameManager.Age.FEUDAL and ResourceManager.can_afford(player_id, {"food": 80, "gold": 30}):
			st.order_train("heavy_scout")
		break

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
	var _easy_mode: bool = GameSettings.difficulty == GameSettings.Difficulty.EASY or GameSettings.difficulty == GameSettings.Difficulty.TUTORIAL
	var min_mil: int = 2 if _easy_mode else 3
	if military >= min_mil and AgeManager.can_advance(player_id):
		AgeManager.start_advance(player_id)

# ── Attack & Defense ──────────────────────────────────────────────────────────

func _find_enemy_building_targets(max_count: int) -> Array[Node]:
	var origin: Vector2 = town_center.global_position if is_instance_valid(town_center) else Vector2.ZERO
	var candidates: Array[Node] = []
	var etc: Node2D = _get_primary_enemy_tc()
	if etc != null:
		candidates.append(etc)
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var sv: Variant = building.get("state")
		if sv != null and (sv as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			continue
		if not candidates.has(building):
			candidates.append(building)
	candidates.sort_custom(func(a: Node, b: Node) -> bool:
		return origin.distance_to((a as Node2D).global_position) < \
			   origin.distance_to((b as Node2D).global_position)
	)
	return candidates.slice(0, max_count) as Array[Node]

func _launch_attack() -> void:
	var etc: Node2D = _get_primary_enemy_tc()
	if etc == null:
		return
	var mcount: int = _count_military()
	var min_units: int = GameSettings.get_ai_min_attack_units()
	if _aggression == AggressionLevel.AGGRESSIVE:
		min_units = maxi(min_units - 1, 1)
	if mcount < min_units:
		return

	var targets: Array[Node] = _find_enemy_building_targets(3)
	if targets.is_empty():
		targets.append(etc)
	var target_count: int = targets.size()

	# Collect military units that are not already engaged with a valid target
	var idle_attackers: Array[Node] = []
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if not (unit is Militia or unit is Archer or unit is Pikeman or unit is HeavyScout or unit is Knight or unit is BatteringRam or unit is Mangonel or unit is Trebuchet):
			continue
		# Skip units already attacking a valid enemy target
		var existing_target: Variant = unit.get("attack_target")
		if existing_target != null and is_instance_valid(existing_target as Node):
			var tpid: Variant = (existing_target as Node).get("player_id")
			if tpid != null and (tpid as int) != player_id:
				continue
		idle_attackers.append(unit)

	# Distribute idle attackers across targets in round-robin order
	for i: int in range(idle_attackers.size()):
		var target: Node = targets[i % target_count]
		if idle_attackers[i].has_method("order_attack"):
			idle_attackers[i].order_attack(target)

# Returns the nearest valid enemy town center (any player that isn't us).
func _get_primary_enemy_tc() -> Node2D:
	if is_instance_valid(enemy_town_center):
		return enemy_town_center
	# Fallback: scan buildings for any TC not owned by us
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if building.get("is_town_center") == true or \
				building.get_script() != null and (building.get_script() as Script).resource_path.contains("town_center"):
			return building as Node2D
	return null

func _find_nearest_enemy_building() -> Node:
	var origin: Vector2 = town_center.global_position if is_instance_valid(town_center) else Vector2.ZERO
	var best: Node = null
	var best_dist: float = INF
	# Seed with current primary enemy TC if valid
	var etc: Node2D = _get_primary_enemy_tc()
	if etc != null:
		best = etc
		best_dist = origin.distance_to(etc.global_position)
	# Check all enemy buildings in the buildings layer
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var sv: Variant = building.get("state")
		if sv != null and (sv as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
			continue
		var d: float = origin.distance_to((building as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = building
	return best

func _check_zone_threat() -> void:
	if not is_instance_valid(town_center):
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if unit.get("is_cloaked") == true:
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
		if unit.get("is_cloaked") == true:
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
		if (unit is Militia or unit is Archer or unit is Pikeman or unit is HeavyScout or unit is Knight or unit is BatteringRam or unit is Mangonel or unit is Trebuchet) and unit.has_method("order_attack"):
			unit.order_attack(best_enemy)

# ── Naval AI ─────────────────────────────────────────────────────────────────

func _is_naval_map() -> bool:
	return MatchConfig.map_type == MatchConfig.MapType.ISLANDS

func _manage_naval() -> void:
	# Build dock as soon as we can afford it
	if _built.get("dock", 0) as int == 0:
		if ResourceManager.can_afford(player_id, BUILDING_COSTS["dock"]):
			_build_dock_on_shore()
		return

	var dock: Node = _find_own_dock()
	if dock == null:
		return
	var dk: Dock = dock as Dock
	if dk.state != BuildingBase.BuildingState.COMPLETE:
		return
	if dk.get_queue().size() >= dk.get_max_queue():
		return

	var age: int = AgeManager.get_age(player_id)
	var galleys: int    = _count_naval("WarGalley")
	var transports: int = _count_naval("TransportShip")

	# Dark Age: only fishing boats for food income
	if age < GameManager.Age.FEUDAL:
		if _count_naval("FishingBoat") < 2:
			dk.order_train("fishing_boat")
		return

	# Feudal+: build 2 war galleys first, then 1 transport, then more galleys
	var galley_target: int = 2 if age == GameManager.Age.FEUDAL else 3
	if galleys < galley_target and ResourceManager.can_afford(player_id, {"wood": 75, "gold": 35}):
		dk.order_train("war_galley")
		return
	if transports < 1 and ResourceManager.can_afford(player_id, {"wood": 125}):
		dk.order_train("transport_ship")
		return
	# Additional galleys in Castle/Imperial
	if age >= GameManager.Age.CASTLE and galleys < 4 \
			and ResourceManager.can_afford(player_id, {"wood": 75, "gold": 35}):
		dk.order_train("war_galley")

func _manage_fishing_boats() -> void:
	var dock: Node = _find_own_dock()
	if dock == null:
		return
	var dk_pos: Vector2 = (dock as Node2D).global_position

	# Check if any wild fish node exists in the ocean
	var fish_node: Node = _find_nearest_fish_node(dk_pos)

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is FishingBoat):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var fb: FishingBoat = unit as FishingBoat
		if fb.current_state != UnitBase.UnitState.IDLE:
			continue

		if fish_node != null:
			# Send to nearest wild fish bank
			fb.order_fish(fish_node, dock)
		else:
			# No wild fish — look for an existing own fish trap that isn't depleted
			var trap: FishTrap = _find_own_fish_trap()
			if trap != null:
				fb.order_fish(trap, dock)
			else:
				# Build a fish trap if we can afford it
				if ResourceManager.can_afford(player_id, BUILDING_COSTS["fish_trap"]):
					_build_fish_trap(fb, dock)

func _find_nearest_fish_node(from: Vector2) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		var rtype: Variant = node.get("resource_type")
		if rtype == null or (rtype as int) != ResourceNode.ResourceType.FOOD_FISH:
			continue
		var d: float = from.distance_to((node as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

func _find_own_fish_trap() -> FishTrap:
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is FishTrap):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var ft: FishTrap = building as FishTrap
		if ft.state == BuildingBase.BuildingState.COMPLETE and not ft.is_depleted():
			return ft
	return null

func _build_fish_trap(boat: FishingBoat, dock: Node) -> void:
	# Place the fish trap in the ocean near the dock
	var pos: Vector2 = _find_ocean_build_pos((dock as Node2D).global_position, 80.0, 200.0)
	if pos == Vector2.ZERO:
		return
	var scene_path: String = BUILDING_SCENES.get("fish_trap", "") as String
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
	ResourceManager.spend_resource(player_id, BUILDING_COSTS["fish_trap"])
	# Send the boat to build it, then it will auto-fish once construction completes
	boat.order_build(b)

func _find_ocean_build_pos(origin: Vector2, min_r: float, max_r: float) -> Vector2:
	for _i: int in range(24):
		var angle: float = randf() * TAU
		var dist: float = randf_range(min_r, max_r)
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		if TerrainManager.is_ocean(pos):
			return pos
	return Vector2.ZERO

const GALLEY_RETREAT_HP_RATIO: float = 0.30
const GALLEY_REJOIN_HP_RATIO:  float = 0.65

func _galley_needs_retreat(wg: WarGalley) -> bool:
	var max_hp: float = wg.get("max_health") as float
	if max_hp <= 0.0:
		return false
	return (wg.get("current_health") as float) / max_hp < GALLEY_RETREAT_HP_RATIO

func _galley_is_recovering(wg: WarGalley) -> bool:
	var max_hp: float = wg.get("max_health") as float
	if max_hp <= 0.0:
		return false
	return (wg.get("current_health") as float) / max_hp < GALLEY_REJOIN_HP_RATIO

func _retreat_galley(wg: WarGalley) -> void:
	var dock: Node = _find_own_dock()
	if dock == null:
		return
	var dock_pos: Vector2 = (dock as Node2D).global_position
	var jitter: Vector2 = Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
	var dest: Vector2 = dock_pos + jitter
	if TerrainManager.is_ocean(dest):
		wg.order_move(dest)

func _manage_naval_patrol() -> void:
	var etc: Node2D = _get_primary_enemy_tc()
	if etc == null:
		return
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is WarGalley):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var wg: WarGalley = unit as WarGalley
		if _galley_needs_retreat(wg):
			if wg.current_state != UnitBase.UnitState.MOVING:
				_retreat_galley(wg)
			continue
		if _galley_is_recovering(wg):
			continue
		if wg.current_state != UnitBase.UnitState.IDLE:
			continue
		var toward: Vector2 = etc.global_position
		var jitter: Vector2 = Vector2(randf_range(-300.0, 300.0), randf_range(-300.0, 300.0))
		var dest: Vector2 = wg.global_position.lerp(toward + jitter, randf_range(0.3, 0.7))
		if TerrainManager.is_ocean(dest):
			wg.order_move(dest)

func _launch_naval_assault() -> void:
	var etc: Node2D = _get_primary_enemy_tc()
	if etc == null:
		return

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is WarGalley):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		var wg: WarGalley = unit as WarGalley
		if _galley_needs_retreat(wg):
			if wg.current_state != UnitBase.UnitState.MOVING:
				_retreat_galley(wg)
			continue
		if _galley_is_recovering(wg):
			continue
		var enemy_ship: Node = _find_nearest_enemy_ship(wg.global_position)
		if enemy_ship != null:
			wg.order_attack(enemy_ship)
		elif wg.current_state == UnitBase.UnitState.IDLE:
			var toward: Vector2 = etc.global_position
			var jitter: Vector2 = Vector2(randf_range(-200.0, 200.0), randf_range(-200.0, 200.0))
			var dest: Vector2 = wg.global_position.lerp(toward + jitter, randf_range(0.4, 0.8))
			if TerrainManager.is_ocean(dest):
				wg.order_move(dest)

	var military: int = _count_military()
	if military < 3:
		return

	if not is_instance_valid(_naval_transport):
		_naval_transport = _find_own_transport()
	if not is_instance_valid(_naval_transport):
		return
	var ts: TransportShip = _naval_transport as TransportShip

	if ts.get_garrison().size() > 0:
		ts.order_move_then_unload(etc.global_position)
		return

	if ts.current_state != UnitBase.UnitState.IDLE:
		return

	var boarded: int = 0
	for unit: Node in units_layer.get_children():
		if ts.is_full() or boarded >= 4:
			break
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if not (unit is Militia or unit is Archer or unit is Pikeman or unit is HeavyScout or unit is Knight or unit is BatteringRam or unit is Mangonel or unit is Trebuchet):
			continue
		if unit.get("current_state") as int == UnitBase.UnitState.IDLE:
			ts.board(unit)
			boarded += 1

	if boarded > 0:
		ts.order_move_then_unload(etc.global_position)

func _find_nearest_enemy_ship(from: Vector2) -> Node:
	var best: Node = null
	var best_dist: float = 800.0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if not (unit is WarGalley or unit is FishingBoat or unit is TransportShip):
			continue
		var d: float = from.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

func _build_dock_on_shore() -> void:
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
			for nd: Variant in DIRS:
				if TerrainManager.is_ocean(candidate + (nd as Vector2) * PROBE):
					if _build_pos_clear(candidate):
						return candidate
	return Vector2.ZERO

func _attack_with_idle_land_units() -> void:
	var etc: Node2D = _get_primary_enemy_tc()
	if etc == null:
		return
	if not is_instance_valid(town_center):
		return
	var own_origin: Vector2 = town_center.global_position
	var enemy_origin: Vector2 = etc.global_position
	var target: Node = _find_nearest_enemy_building()
	if target == null:
		target = etc
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if not (unit is Militia or unit is Archer or unit is Pikeman or unit is HeavyScout or unit is Knight or unit is BatteringRam or unit is Mangonel or unit is Trebuchet):
			continue
		var ustate: Variant = unit.get("current_state")
		if ustate == null or (ustate as int) != UnitBase.UnitState.IDLE:
			continue
		var upos: Vector2 = (unit as Node2D).global_position
		# Only order attack if the unit is closer to the enemy TC than to our own TC,
		# meaning it has already crossed the water onto the enemy island.
		if upos.distance_to(enemy_origin) < upos.distance_to(own_origin):
			if unit.has_method("order_attack"):
				unit.order_attack(target)

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
			"FishingBoat":    if unit is FishingBoat:    count += 1
	return count

# ── Building placement ────────────────────────────────────────────────────────

const BUILD_FAIL_WIDEN_THRESHOLD: int  = 3   # fails before expanding radius
const BUILD_FAIL_SKIP_THRESHOLD: int   = 6   # fails before cooling down
const BUILD_FAIL_COOLDOWN: float       = 30.0

func _record_build_fail(building_id: String) -> void:
	var count: int = (_build_fail_counts.get(building_id, 0) as int) + 1
	_build_fail_counts[building_id] = count
	if count >= BUILD_FAIL_SKIP_THRESHOLD:
		_build_cooldowns[building_id] = BUILD_FAIL_COOLDOWN
		_build_fail_counts.erase(building_id)

func _build_radius_for(building_id: String, base_max: float) -> float:
	var fails: int = _build_fail_counts.get(building_id, 0) as int
	if fails >= BUILD_FAIL_WIDEN_THRESHOLD:
		return base_max * (1.0 + 0.3 * float(maxi(fails - BUILD_FAIL_WIDEN_THRESHOLD + 1, 1)))
	return base_max

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

func _build(building_id: String) -> void:
	if _build_cooldowns.has(building_id):
		return
	var scene_path: String = BUILDING_SCENES.get(building_id, "") as String
	if scene_path.is_empty() or not is_instance_valid(town_center):
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var zone: Dictionary = _get_build_zone(building_id)
	var min_r: float = zone["min_r"] as float
	var max_r: float = _build_radius_for(building_id, zone["max_r"] as float)
	var bias: Vector2 = Vector2.ZERO
	if zone["toward_enemy"] as bool:
		var etc: Node2D = _get_primary_enemy_tc()
		if etc != null:
			bias = town_center.global_position.direction_to(etc.global_position)
	var pos: Vector2 = _find_build_pos(town_center.global_position, min_r, max_r, bias)
	if pos == Vector2.INF:
		_record_build_fail(building_id)
		return
	_build_fail_counts.erase(building_id)
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = pos
	b.set("player_id", player_id)
	buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, player_id)
	ResourceManager.spend_resource(player_id, BUILDING_COSTS[building_id])
	_built[building_id] = (_built.get(building_id, 0) as int) + 1

func _build_near_resource(building_id: String, rtype: ResourceNode.ResourceType) -> void:
	if _build_cooldowns.has(building_id):
		return
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
	var max_r: float = _build_radius_for(building_id, 140.0)
	var pos: Vector2 = _find_build_pos(nearest.global_position, 50.0, max_r)
	if pos == Vector2.INF:
		_record_build_fail(building_id)
		return
	_build_fail_counts.erase(building_id)
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = pos
	b.set("player_id", player_id)
	buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, player_id)
	ResourceManager.spend_resource(player_id, BUILDING_COSTS[building_id])
	_built[building_id] = (_built.get(building_id, 0) as int) + 1
	# Re-assign nearby idle villagers to this drop-off
	_redirect_villagers_to_drop_off(b, rtype)

# bias: unit vector that pulls candidate positions toward a direction (can be ZERO).
# When bias is non-zero, 70 % of candidates are drawn from a ±60° cone around it.
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
	# Fallback: wider ring, no bias constraint
	for _i: int in range(20):
		var angle: float = randf() * TAU
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * max_r * 1.5
		if _build_pos_clear(pos):
			return pos
	return Vector2.INF

## Returns true when `pos` is safe to build at: not ocean, not impassable
## terrain, no resource nodes within BUILDING_CLEAR px, and no existing
## building footprint overlapping.
const BUILDING_CLEAR: float = 72.0
func _build_pos_clear(pos: Vector2) -> bool:
	if TerrainManager.is_ocean(pos):
		return false
	if not TerrainManager.is_buildable(pos):
		return false
	# Check resource nodes
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node):
			continue
		if pos.distance_to((node as Node2D).global_position) < BUILDING_CLEAR:
			return false
	# Check existing buildings
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		if pos.distance_to((building as Node2D).global_position) < BUILDING_CLEAR:
			return false
	return true

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
	v.set("civ_id", MatchConfig.get_rival_civ_id(player_id))
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
			"Villager":   if unit is Villager:    count += 1
			"Militia":    if unit is Militia:     count += 1
			"Archer":     if unit is Archer:      count += 1
			"Pikeman":    if unit is Pikeman:     count += 1
			"HeavyScout":   if unit is HeavyScout:   count += 1
			"Knight":       if unit is Knight:       count += 1
			"BatteringRam": if unit is BatteringRam: count += 1
			"Mangonel":     if unit is Mangonel:     count += 1
			"Trebuchet":    if unit is Trebuchet:    count += 1
	return count

func _count_military() -> int:
	return _count_of_type("Militia") + _count_of_type("Archer") + _count_of_type("Pikeman") \
		+ _count_of_type("HeavyScout") + _count_of_type("Knight") \
		+ _count_of_type("BatteringRam") + _count_of_type("Mangonel") + _count_of_type("Trebuchet")

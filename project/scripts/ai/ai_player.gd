extends Node

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

const TICK_INTERVAL: float         = 2.0
const THREAT_CHECK_INTERVAL: float = 3.0

@export var player_id: int = 1

var town_center: Node2D     = null
var units_layer: Node2D     = null
var buildings_layer: Node2D = null
var drop_off: Node2D        = null
var enemy_town_center: Node2D = null

var _timer: float        = 0.0
var _attack_timer: float = 0.0
var _threat_timer: float = 0.0

var _tc_rebuild_pending: bool = false

var _construction: AIConstruction
var _economy: AIEconomy
var _military: AIMilitary
var _naval: AINaval

var _building_costs: Dictionary:
	get: return _construction._building_costs

# ── Debug log ─────────────────────────────────────────────────────────────────
const DEBUG_LOG_SIZE: int = 40
var _debug_log: Array[String] = []

func debug_log(msg: String) -> void:
	if not GameSettings.ai_debug:
		return
	var entry: String = "[P%d] %s" % [player_id, msg]
	_debug_log.push_back(entry)
	if _debug_log.size() > DEBUG_LOG_SIZE:
		_debug_log.pop_front()

func get_debug_log() -> Array[String]:
	return _debug_log

func _ready() -> void:
	_construction = AIConstruction.new()
	_construction.setup(self)
	_economy = AIEconomy.new()
	_economy.setup(self)
	_military = AIMilitary.new()
	_military.setup(self)
	_naval = AINaval.new()
	_naval.setup(self)
	EventBus.ai_unit_under_attack.connect(_on_ai_unit_under_attack)
	EventBus.building_destroyed.connect(_on_building_destroyed)

func _exit_tree() -> void:
	if EventBus.ai_unit_under_attack.is_connected(_on_ai_unit_under_attack):
		EventBus.ai_unit_under_attack.disconnect(_on_ai_unit_under_attack)
	if EventBus.building_destroyed.is_connected(_on_building_destroyed):
		EventBus.building_destroyed.disconnect(_on_building_destroyed)

func _on_ai_unit_under_attack(attacked_player_id: int) -> void:
	if attacked_player_id != player_id:
		return
	_military.notify_under_attack()

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	_timer        += delta
	_attack_timer += delta
	_threat_timer += delta
	_construction.update_cooldowns(delta)
	_military.update_aggression(delta)

	if _timer >= TICK_INTERVAL:
		_timer = 0.0
		_run_tick()

	if _attack_timer >= _military.get_effective_attack_interval():
		_attack_timer = 0.0
		if _is_naval_map():
			_naval.launch_naval_assault()
		else:
			_military.launch_attack()

	if _threat_timer >= THREAT_CHECK_INTERVAL:
		_threat_timer = 0.0
		_military.check_zone_threat()

func _run_tick() -> void:
	_construction.sync_built_counts()
	_construction.manage_population()
	_economy.manage_villagers()
	_construction.manage_economy_buildings()
	_construction.manage_military_buildings()
	_construction.manage_advanced_buildings()
	_military.manage_research()
	_military.manage_military()
	_military.manage_unique_barracks_unit()
	_military.manage_stable_training()
	_military.manage_siege_training()
	_economy.manage_age_advance()
	if _is_naval_map():
		_naval.manage_naval()
		_naval.manage_naval_patrol()
		_naval.manage_fishing_boats()
		_naval.attack_with_idle_land_units()

# ── TC loss / elimination ─────────────────────────────────────────────────────

func _on_building_destroyed(building: Node, owner_id: int) -> void:
	if owner_id == player_id:
		if building == town_center or (building is TownCenterBuilding) or (building is TownCenterBuildable):
			town_center = null
			_tc_rebuild_pending = false
			get_tree().create_timer(0.5).timeout.connect(_attempt_tc_rebuild)
		return
	_military.push_units_past_destroyed_building(building as Node2D)

func _attempt_tc_rebuild() -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if is_instance_valid(town_center):
		return

	var villager: Villager = _find_safest_villager()
	if villager == null:
		_check_elimination()
		return

	if not ResourceManager.can_afford(player_id, {"wood": 275}):
		get_tree().create_timer(8.0).timeout.connect(_attempt_tc_rebuild)
		return

	_build_new_tc(villager)

func _find_safest_villager() -> Villager:
	var best: Villager = null
	var best_score: float = -INF
	var enemy_origin: Vector2 = Vector2.ZERO
	var enemy_count: int = 0
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		enemy_origin += (unit as Node2D).global_position
		enemy_count += 1
	for b: Node in buildings_layer.get_children():
		if not is_instance_valid(b):
			continue
		var pid: Variant = b.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		enemy_origin += (b as Node2D).global_position
		enemy_count += 1
	if enemy_count > 0:
		enemy_origin /= float(enemy_count)

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var v: Villager = unit as Villager
		if v.player_id != player_id:
			continue
		var score: float = 0.0
		if enemy_count > 0:
			score = v.global_position.distance_to(enemy_origin)
		if score > best_score:
			best_score = score
			best = v
	return best

func _build_new_tc(builder: Villager) -> void:
	if not ResourceManager.spend_resource(player_id, {"wood": 275}):
		return
	var build_origin: Vector2 = builder.global_position
	var pos: Vector2 = _find_safe_tc_position(build_origin)
	if pos == Vector2.INF:
		ResourceManager.add_resource(player_id, "wood", 275.0)
		get_tree().create_timer(10.0).timeout.connect(_attempt_tc_rebuild)
		return
	var packed: PackedScene = load("res://scenes/buildings/town_center_ai.tscn") as PackedScene
	if packed == null:
		ResourceManager.add_resource(player_id, "wood", 275.0)
		return
	var tc: Node2D = packed.instantiate() as Node2D
	tc.global_position = pos
	tc.set("player_id", player_id)
	buildings_layer.add_child(tc)
	town_center = tc
	var new_drop: Node = tc.get_node_or_null("DropOff")
	if new_drop != null:
		drop_off = new_drop as Node2D
	EventBus.building_placed.emit(tc, player_id)
	_tc_rebuild_pending = true
	builder.order_build(tc)

func _find_safe_tc_position(origin: Vector2) -> Vector2:
	var enemy_center: Vector2 = Vector2.ZERO
	var enemy_count: int = 0
	for b: Node in buildings_layer.get_children():
		if not is_instance_valid(b):
			continue
		var pid: Variant = b.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		enemy_center += (b as Node2D).global_position
		enemy_count += 1
	var bias: Vector2 = Vector2.ZERO
	if enemy_count > 0:
		enemy_center /= float(enemy_count)
		bias = (origin - enemy_center).normalized()
	for _i: int in range(60):
		var angle: float
		if bias != Vector2.ZERO and randf() < 0.75:
			angle = bias.angle() + randf_range(-PI / 3.0, PI / 3.0)
		else:
			angle = randf() * TAU
		var dist: float = randf_range(200.0, 600.0)
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		if _construction.is_pos_clear(pos):
			return pos
	return Vector2.INF

func _check_elimination() -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if is_instance_valid(town_center):
		return
	var has_any: bool = false
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		has_any = true
		break
	if has_any:
		return
	for b: Node in buildings_layer.get_children():
		if not is_instance_valid(b):
			continue
		var pid: Variant = b.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		has_any = true
		break
	if not has_any:
		EventBus.player_eliminated.emit(player_id)

func _is_naval_map() -> bool:
	return MatchConfig.map_type == MatchConfig.MapType.ISLANDS

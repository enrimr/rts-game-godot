extends Node

class_name AIPlayer

const BUILDING_SCENES: Dictionary = {
	"barracks":       "res://scenes/buildings/barracks.tscn",
	"archery_range":  "res://scenes/buildings/archery_range.tscn",
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

const THREAT_CHECK_INTERVAL: float = 3.0

@export var player_id: int = 1

var town_center: Node2D     = null
var units_layer: Node2D     = null
var buildings_layer: Node2D = null
var drop_off: Node2D        = null
var enemy_town_center: Node2D = null

# Read-only query service over the layers. Lazily built because game_world
# assigns units_layer/buildings_layer after add_child() (post-_ready); rebuilt
# if the layer references ever change.
var _world: WorldQuery = null
var world: WorldQuery:
	get:
		if _world == null or _world._units_layer != units_layer or _world._buildings_layer != buildings_layer:
			_world = WorldQuery.new(units_layer, buildings_layer)
		return _world

var _timer: float        = 0.0
var _attack_timer: float = 0.0
var _threat_timer: float = 0.0

## Campaign scripting (MissionDirector): while true this brain never LAUNCHES
## attacks — economy, defense and retaliation keep running; the mission's
## scripted waves provide the pressure at authored moments.
var offense_held: bool = false

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
	EventBus.player_entity_under_attack.connect(_on_human_ally_under_attack)
	EventBus.building_destroyed.connect(_on_building_destroyed)

func _exit_tree() -> void:
	if EventBus.ai_unit_under_attack.is_connected(_on_ai_unit_under_attack):
		EventBus.ai_unit_under_attack.disconnect(_on_ai_unit_under_attack)
	if EventBus.player_entity_under_attack.is_connected(_on_human_ally_under_attack):
		EventBus.player_entity_under_attack.disconnect(_on_human_ally_under_attack)
	if EventBus.building_destroyed.is_connected(_on_building_destroyed):
		EventBus.building_destroyed.disconnect(_on_building_destroyed)

func _on_ai_unit_under_attack(attacked_player_id: int) -> void:
	if attacked_player_id == player_id:
		_military.notify_under_attack()
		return
	# A team-mate (another AI, or a non-host human — their hits emit this
	# signal too) is under fire: rally to their base.
	if GameManager.are_allied(player_id, attacked_player_id):
		var their_buildings: Array = world.own_buildings(attacked_player_id)
		if not their_buildings.is_empty():
			_military.assist_ally((their_buildings[0] as Node2D).global_position)

## The HOST human (player 0) is under attack — the signal carries the spot.
func _on_human_ally_under_attack(pos: Vector2, _attacker: Node) -> void:
	if player_id != 0 and GameManager.are_allied(player_id, 0):
		_military.assist_ally(pos)

# Physics ticks, not render frames: delta is the fixed physics step, so the
# decision cadence is a deterministic tick count — a replay of the same seed
# fires the same ticks regardless of render frame rate.
func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	_timer        += delta
	_attack_timer += delta
	_threat_timer += delta
	_construction.update_cooldowns(delta)
	_military.update_aggression(delta)

	if _timer >= GameSettings.get_ai_tick_interval():
		_timer = 0.0
		_run_tick()

	if _attack_timer >= _military.get_effective_attack_interval():
		_attack_timer = 0.0
		if not offense_held:
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
	# Age-up spends BEFORE training: with the reverse order the tick that
	# finally banked the cost would immediately leak it into a unit queue and
	# the AI livelocked a few food short of the next age forever.
	_economy.manage_age_advance()
	# While banking the age-up cost, training would eat the food faster than
	# villagers deliver it and the AI would stay in the Dark Age forever.
	if not is_saving_for_age_up():
		_military.manage_military()
		_military.manage_unique_barracks_unit()
		_military.manage_stable_training()
		_military.manage_siege_training()
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
			_rebuild_retry(0.5)
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
		_rebuild_retry(8.0)
		return

	_build_new_tc(villager)

## Retry timer counted in physics ticks (process_in_physics), so the rebuild
## fires on a deterministic simulation tick instead of a render-frame boundary.
func _rebuild_retry(seconds: float) -> void:
	get_tree().create_timer(seconds, true, true).timeout.connect(_attempt_tc_rebuild)

func _find_safest_villager() -> Villager:
	var best: Villager = null
	var best_score: float = -INF
	var enemy_origin: Vector2 = Vector2.ZERO
	var enemy_count: int = 0
	for unit: Node in world.enemy_units(player_id):
		enemy_origin += (unit as Node2D).global_position
		enemy_count += 1
	for b: Node in world.enemy_buildings(player_id):
		enemy_origin += (b as Node2D).global_position
		enemy_count += 1
	if enemy_count > 0:
		enemy_origin /= float(enemy_count)

	for v: Villager in WorldQuery.of_type(world.own_units(player_id), Villager):
		var score: float = 0.0
		if enemy_count > 0:
			score = v.global_position.distance_to(enemy_origin)
		if score > best_score:
			best_score = score
			best = v
	return best

func _build_new_tc(builder: Villager) -> void:
	var build_origin: Vector2 = builder.global_position
	var pos: Vector2 = _find_safe_tc_position(build_origin)
	if pos == Vector2.INF:
		_rebuild_retry(10.0)
		return
	# The rebuilt TC goes through the bus like every other placement; it is NOT
	# instant — the surviving villager raises it (the command orders the build).
	var cmd: PlaceBuildingCommand = PlaceBuildingCommand.make(player_id, "town_center_ai",
		[pos] as Array[Vector2], 0.0, [EntityRegistry.id_of(builder)] as Array[int], false)
	CommandBus.submit(cmd)
	if cmd.last_placed.is_empty():
		return
	var tc: Node2D = cmd.last_placed[0] as Node2D
	town_center = tc
	var new_drop: Node = tc.get_node_or_null("DropOff")
	if new_drop != null:
		drop_off = new_drop as Node2D
	_tc_rebuild_pending = true

func _find_safe_tc_position(origin: Vector2) -> Vector2:
	var enemy_center: Vector2 = Vector2.ZERO
	var enemy_count: int = 0
	for b: Node in world.enemy_buildings(player_id):
		enemy_center += (b as Node2D).global_position
		enemy_count += 1
	var bias: Vector2 = Vector2.ZERO
	if enemy_count > 0:
		enemy_center /= float(enemy_count)
		bias = (origin - enemy_center).normalized()
	for _i: int in range(60):
		var angle: float
		if bias != Vector2.ZERO and MatchRng.randf() < 0.75:
			angle = bias.angle() + MatchRng.randf_range(-PI / 3.0, PI / 3.0)
		else:
			angle = MatchRng.randf() * TAU
		var dist: float = MatchRng.randf_range(200.0, 600.0)
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		if _construction.is_pos_clear(pos):
			return pos
	return Vector2.INF

func _check_elimination() -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if is_instance_valid(town_center):
		return
	if not world.own_units(player_id).is_empty():
		return
	if world.own_buildings(player_id).is_empty():
		EventBus.player_eliminated.emit(player_id)

func _is_naval_map() -> bool:
	return MatchConfig.map_type == MatchConfig.MapType.ISLANDS

var _banking_for_age: bool = false

## True while the AI should bank resources for the next age instead of
## spending them on training. Arms once the military minimum that
## manage_age_advance requires is met; sticky (hysteresis) so raid losses
## don't flip it off every time one soldier dies — only an army collapse
## to half the minimum abandons the fund.
func is_saving_for_age_up() -> bool:
	if AgeManager.is_advancing(player_id) \
			or AgeManager.get_age(player_id) >= GameManager.Age.IMPERIAL:
		_banking_for_age = false
		return false
	var military: int = _military.count_military()
	var min_mil: int = GameSettings.get_ai_age_advance_min_military()
	if _banking_for_age:
		if military < maxi(1, int(ceil(min_mil / 2.0))):
			_banking_for_age = false
	elif military >= min_mil:
		_banking_for_age = true
	return _banking_for_age

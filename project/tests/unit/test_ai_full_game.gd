extends GutTest

## Magazine review #09 fixes — the AI and the pastoral economy:
##   1. The Mill and the Watch Tower are in the AI's build plan (scenes, costs,
##      placement zones, per-age tower targets).
##   2. With a complete own Mill and 30F/10G in the bank the AI queues a
##      Presa Canario (through ProductionCommand/CommandBus), capped at
##      MAX_AI_DOGS.
##   3. An IDLE own dog is sent to herd the nearest non-owned animal
##      (UnitTargetCommand "herd" through the bus); busy dogs are left alone,
##      the AI's own flock is never fetched.

const CONSTRUCTION := preload("res://scripts/ai/ai_construction.gd")
const ECON := preload("res://scripts/ai/ai_economy.gd")
const MILL_SCENE := preload("res://scenes/buildings/mill.tscn")
const SHEEP_SCENE := preload("res://scenes/units/sheep.tscn")

const AI_PID: int = 1

# Minimal AIPlayer stand-in: exactly the surface the economy module touches.
class FakeAI:
	extends RefCounted
	var player_id: int = 1
	var town_center: Node2D = null
	var drop_off: Node2D = null
	var world: WorldQuery = null
	var saving: bool = false
	func is_saving_for_age_up() -> bool:
		return saving
	func debug_log(_msg: String) -> void:
		pass

## Idle dog double: the Presa Canario has no class_name — order_herd is the
## capability the AI keys on, so a double with the method is a dog.
class DogDouble:
	extends Node2D
	var player_id: int = 1
	var current_state: int = UnitBase.UnitState.IDLE
	var herd_target: Node = null
	var herd_orders: Array = []
	func order_herd(target: Node) -> void:
		herd_orders.append(target)
		herd_target = target
		current_state = UnitBase.UnitState.ATTACKING

var _world: Node2D = null
var _units: Node2D = null
var _buildings: Node2D = null

func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_units = Node2D.new()
	_units.name = "UnitsLayer"
	_world.add_child(_units)
	_buildings = Node2D.new()
	_buildings.name = "BuildingsLayer"
	_world.add_child(_buildings)
	CommandBus.start_match(_world)
	ResourceManager.init_player(AI_PID, {"food": 0, "wood": 0, "gold": 0, "stone": 0})
	PopulationManager.init_player(AI_PID)

func _econ() -> AIEconomy:
	var e: AIEconomy = ECON.new()
	var ai: FakeAI = FakeAI.new()
	ai.player_id = AI_PID
	ai.world = WorldQuery.new(_units, _buildings)
	e._ai = ai
	return e

func _spawn_mill(complete: bool = true) -> Mill:
	var mill: Mill = MILL_SCENE.instantiate() as Mill
	mill.player_id = AI_PID
	if complete:
		mill.state = BuildingBase.BuildingState.COMPLETE
	_buildings.add_child(mill)
	return mill

func _spawn_dog(state: int = UnitBase.UnitState.IDLE, pos: Vector2 = Vector2.ZERO) -> DogDouble:
	var dog: DogDouble = DogDouble.new()
	dog.player_id = AI_PID
	dog.current_state = state
	_units.add_child(dog)
	dog.global_position = pos
	return dog

func _spawn_sheep(pid: int, pos: Vector2) -> Animal:
	var sheep: Animal = SHEEP_SCENE.instantiate() as Animal
	_units.add_child(sheep)
	sheep.global_position = pos
	if pid >= 0:
		sheep.player_id = pid
		sheep.current_state = Animal.AnimalState.OWNED
	return sheep

# ── 1. Build plan ─────────────────────────────────────────────────────────────

func test_mill_and_watch_tower_in_build_plan() -> void:
	var c: AIConstruction = CONSTRUCTION.new()
	c.setup(FakeAI.new())
	assert_true(AIConstruction.BUILDING_SCENES.has("mill"), "mill is in the AI scene table")
	assert_true(AIConstruction.BUILDING_SCENES.has("watch_tower"), "watch tower is in the AI scene table")
	assert_true(c._built.has("mill"), "mill built-count is tracked")
	assert_true(c._built.has("watch_tower"), "tower built-count is tracked")
	assert_eq(c._building_costs.get("mill", {}).get("wood", 0), 100,
		"mill cost comes from mill.tres")
	assert_eq(c._building_costs.get("watch_tower", {}).get("stone", 0), 125,
		"tower cost comes from watch_tower.tres")

func test_tower_targets_per_age() -> void:
	var c: AIConstruction = CONSTRUCTION.new()
	assert_eq(c.tower_target_for_age(GameManager.Age.DARK), 0, "no towers in the Dark Age")
	assert_eq(c.tower_target_for_age(GameManager.Age.FEUDAL), 1, "one tower from Feudal")
	assert_eq(c.tower_target_for_age(GameManager.Age.CASTLE), 2, "two from Castle")
	assert_eq(c.tower_target_for_age(GameManager.Age.IMPERIAL), 2, "capped at two")

func test_tower_zone_is_base_perimeter() -> void:
	var c: AIConstruction = CONSTRUCTION.new()
	var zone: Dictionary = c._get_build_zone("watch_tower")
	assert_gte(zone["min_r"] as float, AIConstruction.GRID_STEP * 3.0,
		"towers go to the perimeter, not among the houses")
	assert_true(zone["toward_enemy"] as bool, "towers face the threat")

# ── 2. Dog training ───────────────────────────────────────────────────────────

func test_dog_trained_when_mill_complete_and_affordable() -> void:
	var mill: Mill = _spawn_mill()
	ResourceManager.init_player(AI_PID, {"food": 30, "wood": 0, "gold": 10, "stone": 0})
	_econ().manage_dogs()
	assert_eq(mill.get_queue().size(), 1, "one presa_canario queued through the bus")

func test_dog_not_trained_when_unaffordable() -> void:
	var mill: Mill = _spawn_mill()
	ResourceManager.init_player(AI_PID, {"food": 29, "wood": 0, "gold": 10, "stone": 0})
	_econ().manage_dogs()
	assert_eq(mill.get_queue().size(), 0, "29 food is not 30")

func test_dog_not_trained_without_complete_mill() -> void:
	var mill: Mill = _spawn_mill(false)
	ResourceManager.init_player(AI_PID, {"food": 200, "wood": 0, "gold": 100, "stone": 0})
	_econ().manage_dogs()
	assert_eq(mill.get_queue().size(), 0, "a construction site breeds no dogs")

func test_dog_cap_respected() -> void:
	var mill: Mill = _spawn_mill()
	ResourceManager.init_player(AI_PID, {"food": 200, "wood": 0, "gold": 100, "stone": 0})
	_spawn_dog()
	_spawn_dog()
	_econ().manage_dogs()
	assert_eq(mill.get_queue().size(), 0, "MAX_AI_DOGS = 2 already alive")

# ── 3. Herding orders ─────────────────────────────────────────────────────────

func test_idle_dog_receives_herd_order() -> void:
	var dog: DogDouble = _spawn_dog(UnitBase.UnitState.IDLE, Vector2.ZERO)
	var wild: Animal = _spawn_sheep(-1, Vector2(400, 0))
	_econ().manage_dogs()
	assert_eq(dog.herd_orders.size(), 1, "idle dog was sent to work")
	assert_eq(dog.herd_orders[0], wild, "at the wild sheep")

func test_busy_dog_not_reordered() -> void:
	var dog: DogDouble = _spawn_dog(UnitBase.UnitState.ATTACKING, Vector2.ZERO)
	_spawn_sheep(-1, Vector2(400, 0))
	_econ().manage_dogs()
	assert_eq(dog.herd_orders.size(), 0, "a herding (ATTACKING) dog is left alone")

func test_own_flock_never_fetched() -> void:
	var dog: DogDouble = _spawn_dog(UnitBase.UnitState.IDLE, Vector2.ZERO)
	_spawn_sheep(AI_PID, Vector2(300, 0))
	_econ().manage_dogs()
	assert_eq(dog.herd_orders.size(), 0, "the AI's own sheep are already home")

func test_enemy_sheep_is_fair_game() -> void:
	var dog: DogDouble = _spawn_dog(UnitBase.UnitState.IDLE, Vector2.ZERO)
	var stolen: Animal = _spawn_sheep(0, Vector2(500, 0))
	_econ().manage_dogs()
	assert_eq(dog.herd_orders.size(), 1)
	assert_eq(dog.herd_orders[0], stolen, "honest AoE2 sheep-stealing")

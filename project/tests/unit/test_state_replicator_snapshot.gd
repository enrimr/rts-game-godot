extends GutTest

## The host snapshot must only stream SIM ENTITIES. Tower and archer arrows
## fly INSIDE the unit/building layers (get_parent().add_child) — the sampler
## used to crash casting an arrow's null "health" to float on every combat
## snapshot tick, and to REGISTER each arrow in EntityRegistry, shipping a
## junk spawn/remove record per shot.

const ARROW_SCENE: PackedScene = preload("res://scenes/combat/arrow.tscn")
const MILITIA_SCENE: PackedScene = preload("res://scenes/units/militia.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watch_tower.tscn")

var _world: Node2D = null
var _units: Node2D = null
var _buildings: Node2D = null
var _replicator: StateReplicator = null

func before_each() -> void:
	_world = Node2D.new()
	_units = Node2D.new()
	_units.name = "UnitsLayer"
	_buildings = Node2D.new()
	_buildings.name = "BuildingsLayer"
	_world.add_child(_units)
	_world.add_child(_buildings)
	var world_script: GDScript = GDScript.new()
	world_script.source_code = """
extends Node2D
@onready var units_layer: Node2D = $UnitsLayer
@onready var buildings_layer: Node2D = $BuildingsLayer
var drop_off: Node2D = null
"""
	world_script.reload()
	_world.set_script(world_script)
	add_child_autofree(_world)
	_replicator = StateReplicator.new()
	_world.add_child(_replicator)
	_replicator.setup(_world)

func _arrow() -> Node2D:
	var arrow: Node2D = ARROW_SCENE.instantiate() as Node2D
	# A live arrow needs a target to fly at; the snapshot must not care.
	arrow.set_physics_process(false)
	return arrow

func test_snapshot_survives_arrows_in_both_layers() -> void:
	var militia: Node2D = MILITIA_SCENE.instantiate() as Node2D
	militia.set("player_id", 0)
	_units.add_child(militia)
	_units.add_child(_arrow())
	var tower: Node2D = TOWER_SCENE.instantiate() as Node2D
	tower.set("player_id", 0)
	_buildings.add_child(tower)
	_buildings.add_child(_arrow())

	var pre_ids: int = EntityRegistry.id_of(militia)   # registers the real ones
	var tower_id: int = EntityRegistry.id_of(tower)
	assert_gt(pre_ids, 0)
	assert_gt(tower_id, 0)

	_replicator._host_snapshot()   # used to crash: arrow health null -> float

	var announced: Dictionary = _replicator.get("_announced") as Dictionary
	assert_eq(announced.size(), 2,
		"only the militia and the tower ride the stream — never the arrows")
	assert_true(announced.has(pre_ids))
	assert_true(announced.has(tower_id))

func test_arrows_are_never_registered_as_entities() -> void:
	var arrow: Node2D = _arrow()
	_units.add_child(arrow)
	_replicator._host_snapshot()
	# The sampler must not have minted an id for the arrow behind our back.
	var announced: Dictionary = _replicator.get("_announced") as Dictionary
	assert_eq(announced.size(), 0, "an empty world announces nothing")

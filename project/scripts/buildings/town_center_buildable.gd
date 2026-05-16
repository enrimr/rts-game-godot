extends BuildingBase

class_name TownCenterBuildable

## Additional Town Center placed by a villager from Castle Age onwards.
## Behaves identically to TownCenter once construction is complete.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const VILLAGER_DATA: UnitResource = preload("res://resources/units/villager_data.tres")
const VILLAGER_COSTS: Dictionary = {"food": 50}
const HERO_RESPAWN_TIME: float = 120.0
const MAX_QUEUE: int = 5

var _train_queue: Array[Dictionary] = []
var _train_timer: float = 0.0
var _hero_respawn_timer: float = 0.0
var _pending_hero_data: UnitResource = null

@onready var _train_bar: ProgressBar = get_node_or_null("TrainingBar")

func _ready() -> void:
	super._ready()
	EventBus.hero_died.connect(_on_hero_died)
	# Propagate player_id to the drop-off node once the tree is ready.
	call_deferred("_sync_drop_off_player_id")

func _sync_drop_off_player_id() -> void:
	var drop_off: Node = get_node_or_null("DropOff")
	if drop_off != null:
		drop_off.set("player_id", player_id)

func _process(delta: float) -> void:
	super._process(delta)
	if state != BuildingState.COMPLETE:
		return
	_process_hero_respawn(delta)
	_process_training(delta)

func _process_hero_respawn(delta: float) -> void:
	if _pending_hero_data == null:
		return
	_hero_respawn_timer -= delta
	if _hero_respawn_timer <= 0.0:
		_hero_respawn_timer = 0.0
		var data: UnitResource = _pending_hero_data
		_pending_hero_data = null
		_do_respawn_hero(data)

func _process_training(delta: float) -> void:
	if _train_queue.is_empty():
		return
	_train_timer += delta
	var train_time: float = VILLAGER_DATA.train_time
	if is_instance_valid(_train_bar):
		_train_bar.value = (_train_timer / train_time) * 100.0
	if _train_timer >= train_time:
		if PopulationManager.at_cap(player_id):
			return
		_train_timer = 0.0
		_train_queue.pop_front()
		if is_instance_valid(_train_bar) and _train_queue.is_empty():
			_train_bar.value = 0.0
		_spawn_villager()
		EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func order_train() -> bool:
	if state != BuildingState.COMPLETE:
		return false
	if _train_queue.size() >= MAX_QUEUE:
		return false
	if PopulationManager.at_cap(player_id):
		return false
	if not ResourceManager.spend_resource(player_id, VILLAGER_COSTS):
		return false
	_train_queue.append({"unit_id": "villager", "label": "V", "color": Color(0.6, 0.45, 0.2), "costs": VILLAGER_COSTS})
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)
	return true

func order_cancel_train(index: int) -> void:
	if index < 0 or index >= _train_queue.size():
		return
	var entry: Dictionary = _train_queue[index]
	ResourceManager.add_resource(player_id, "food", (entry["costs"] as Dictionary).get("food", 0))
	_train_queue.remove_at(index)
	if index == 0:
		_train_timer = 0.0
		if is_instance_valid(_train_bar):
			_train_bar.value = 0.0
	EventBus.train_queue_changed.emit(self, _train_queue.duplicate(), MAX_QUEUE)

func get_queue() -> Array:
	return _train_queue.duplicate()

func get_max_queue() -> int:
	return MAX_QUEUE

func get_train_progress() -> float:
	if _train_queue.is_empty():
		return 0.0
	var t: float = VILLAGER_DATA.train_time
	return _train_timer / t if t > 0.0 else 0.0

func is_respawning_hero() -> bool:
	return _pending_hero_data != null

func get_hero_respawn_fraction() -> float:
	if _pending_hero_data == null or HERO_RESPAWN_TIME <= 0.0:
		return 0.0
	return clampf(1.0 - _hero_respawn_timer / HERO_RESPAWN_TIME, 0.0, 1.0)

func get_hero_respawn_remaining() -> int:
	return int(ceil(_hero_respawn_timer))

func _on_hero_died(died_player_id: int, hero_data: UnitResource) -> void:
	if died_player_id != player_id:
		return
	# Only take the respawn if the main TC isn't already handling it.
	# The main TC always connects first; this one only picks it up if it fires again.
	_pending_hero_data = hero_data
	_hero_respawn_timer = HERO_RESPAWN_TIME

func _spawn_villager() -> void:
	var unit: Node2D = VILLAGER_SCENE.instantiate() as Node2D
	unit.set("player_id", player_id)
	unit.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	get_parent().add_child(unit)
	unit.global_position = global_position + Vector2(90.0, 0.0)
	PopulationManager.add_unit(player_id)
	if rally_point != Vector2.ZERO and unit.has_method("order_move"):
		unit.order_move(rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

func _do_respawn_hero(hero_data: UnitResource) -> void:
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var hero: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", hero_data)
	hero.set("player_id", player_id)
	hero.set("civ_id", MatchConfig.player_civ_id if player_id == 0 else MatchConfig.get_rival_civ_id(player_id))
	hero.global_position = global_position + Vector2(-80.0, -60.0)
	get_parent().add_child(hero)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(hero, player_id)
	EventBus.hero_respawned.emit(player_id)

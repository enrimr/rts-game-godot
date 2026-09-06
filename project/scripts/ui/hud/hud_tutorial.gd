class_name HudTutorial
extends Node

## Tutorial lesson driver: owns the TutorialOverlay, listens to the gameplay
## signals each step waits for, and gates HUD actions while lessons are
## active. Resource top-ups go through EventBus.tutorial_grant_resources —
## the world applies them, the HUD never mutates a stockpile directly.

var _hud: CanvasLayer = null   # HudManager — panel refresh callbacks

var _overlay: TutorialOverlay = null
var _res_baseline: Dictionary = {}
## Highest step reached; used to gate tutorial-mode actions.
var step: int = 0
## True only in tutorial mode; false after skip.
var gates_active: bool = false

## Build ids unlocked per tutorial step (cumulative).
const BUILD_UNLOCK: Dictionary = {
	3: ["build:lumber_camp", "build:mining_camp"],
	4: ["build:house"],
	6: ["build:barracks"],
	7: [],  # all remaining buildings unlocked after age-advance step
}

## Minimum stockpile each lesson step needs to be completable.
const MINIMUMS: Dictionary = {
	"resource_gathered":   {"wood": 0},
	"camp_complete":        {"wood": 100},
	"house_complete":       {"wood": 25},
	"villager_trained":    {"food": 60},
	# The step asks for a Barracks (175 wood) AND "queue up several" militia
	# (60 food + 20 wood each) — the old 60 wood could not even start it.
	"militia_trained":     {"wood": 260, "food": 240},
	"age_advance_complete": {"food": 500},
	"unit_attacked":       {"food": 60, "wood": 20},
}

func init(hud: CanvasLayer) -> void:
	_hud = hud

func overlay_active() -> bool:
	return _overlay != null and is_instance_valid(_overlay)

## Build ids unlocked so far (only meaningful while gates_active).
func unlocked_build_ids() -> Array[String]:
	var unlocked: Array[String] = []
	for step_key: Variant in BUILD_UNLOCK:
		if step >= (step_key as int):
			for bid: Variant in (BUILD_UNLOCK[step_key] as Array):
				unlocked.append(bid as String)
	return unlocked

func start() -> void:
	gates_active = true
	_overlay = TutorialOverlay.new()
	_hud.get_node("HUDRoot").add_child(_overlay)
	_overlay.finished.connect(_on_finished)
	_overlay.completed.connect(func() -> void: GameManager.declare_winner(0))
	_overlay.step_changed.connect(_on_step_changed)
	_overlay.start()
	_wire_signals()

func _wire_signals() -> void:
	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.unit_command_issued.connect(_on_unit_command)
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_construction_complete.connect(_on_building_complete)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.age_advance_complete.connect(_on_age_complete)
	EventBus.hero_ability_used.connect(_on_hero_ability)
	EventBus.enemy_unit_spotted.connect(_on_enemy_spotted)
	EventBus.map_explored.connect(_on_map_explored)
	EventBus.unit_attacked.connect(_on_unit_attacked)

func _on_finished() -> void:
	_overlay = null
	gates_active = false
	_hud.call("refresh_after_tutorial_change")

func _notify(condition: String) -> void:
	if not overlay_active():
		return
	if _overlay.current_condition() == condition:
		_overlay.unlock_current()

func _on_camera_moved() -> void:
	_notify("camera_moved")

func _on_unit_selected(_units: Array) -> void:
	_notify("unit_selected")

func _on_unit_command(_units: Array, _cmd: Dictionary) -> void:
	_notify("unit_moved")

func _on_step_changed(new_step: int, condition: String) -> void:
	step = maxi(step, new_step)
	# Refresh open panels so newly unlocked actions appear.
	_hud.call("refresh_after_tutorial_change")
	if condition == "camera_moved":
		EventBus.tutorial_reset_camera_flag.emit()
	if condition == "resource_gathered":
		_res_baseline = ResourceManager.get_resources(_pid()).duplicate()
	if condition == "map_explored":
		var fog: FogOfWar = null
		for child: Node in _world().get_children():
			if child is FogOfWar:
				fog = child as FogOfWar
				break
		if fog != null:
			fog.start_explore_tracking()
	var minimums: Dictionary = MINIMUMS.get(condition, {}) as Dictionary
	for res: String in minimums:
		var needed: int = minimums[res] as int
		var have: int = ResourceManager.get_resources(_pid()).get(res, 0) as int
		if have < needed:
			EventBus.tutorial_grant_resources.emit(_pid(), res, needed - have)
	if condition == "unit_attacked":
		var tc_node: Node2D = _world().get_node_or_null("DropOffNode") as Node2D
		var tc_pos: Vector2 = tc_node.global_position if tc_node != null else Vector2.ZERO
		EventBus.tutorial_spawn_enemy_scout.emit(tc_pos)
	if condition == "hero_ability_used":
		EventBus.tutorial_highlight_unit.emit("hero")
	if condition == "map_explored":
		EventBus.tutorial_highlight_unit.emit("scout")

func _pid() -> int:
	return _hud.get("local_player_id") as int

func _world() -> Node:
	var world: Node = get_tree().get_first_node_in_group("world")
	return world if world != null else get_tree().current_scene

func _on_resource_changed(player_id: int, res: String, amt: int) -> void:
	if player_id != _pid():
		return
	var baseline: float = _res_baseline.get(res, -1.0) as float
	if baseline >= 0.0 and (amt as float) > baseline:
		_notify("resource_gathered")

func _building_id_of(building: Node) -> String:
	var bid: String = building.get_meta("building_id", "") as String
	if bid.is_empty():
		# Fallback: derive type from script path.
		var script: Script = building.get_script() as Script
		if script != null:
			bid = script.resource_path.to_lower()
	return bid.to_lower()

func _on_building_placed(building: Node, player_id: int) -> void:
	if player_id != _pid():
		return
	_notify("building_placed")
	var bid: String = _building_id_of(building)
	if "lumber_camp" in bid or "mining_camp" in bid:
		_notify("camp_built")
	if "house" in bid:
		_notify("house_built")
	if "barracks" in bid:
		_notify("barracks_built")

func _on_unit_spawned(unit: Node, player_id: int) -> void:
	if player_id != _pid():
		return
	var script: Script = unit.get_script() as Script
	if script == null:
		return
	var path: String = script.resource_path.to_lower()
	if "militia" in path:
		_notify("militia_trained")
	elif unit.has_method("order_gather"):
		_notify("villager_trained")

func _on_building_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid == null or (pid as int) != _pid():
		return
	var bid: String = _building_id_of(building)
	if "lumber_camp" in bid or "mining_camp" in bid:
		_notify("camp_complete")
	if "house" in bid:
		_notify("house_complete")

func _on_age_complete(player_id: int, _new_age: int) -> void:
	if player_id == _pid():
		_notify("age_advance_complete")

func _on_hero_ability(player_id: int) -> void:
	if player_id == _pid():
		_notify("hero_ability_used")

func _on_enemy_spotted(_unit: Node) -> void:
	_notify("enemy_spotted")

func _on_map_explored(_cells: int) -> void:
	_notify("map_explored")

func _on_unit_attacked(attacker: Node, _target: Node) -> void:
	var pid: Variant = attacker.get("player_id")
	if pid == null or (pid as int) != _pid():
		return
	# Auto-retaliation used to complete the step while the player just
	# watched — only an attack THEY ordered counts as learning it.
	if attacker.get("_auto_engaged") == true:
		return
	_notify("unit_attacked")

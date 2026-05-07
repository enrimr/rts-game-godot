extends Node2D

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const SCOUT_SCENE: PackedScene = preload("res://scenes/units/scout.tscn")
const AI_TOWN_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/town_center_ai.tscn")

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const BUILDING_SCENES: Dictionary = {
	"house":         "res://scenes/buildings/house.tscn",
	"barracks":      "res://scenes/buildings/barracks.tscn",
	"lumber_camp":   "res://scenes/buildings/lumber_camp.tscn",
	"mining_camp":   "res://scenes/buildings/mining_camp.tscn",
	"farm":          "res://scenes/buildings/farm.tscn",
	"wall_segment":  "res://scenes/buildings/wall_segment.tscn",
	"gate":          "res://scenes/buildings/gate.tscn",
}

const BUILDING_COSTS: Dictionary = {
	"house":         {"wood": 25},
	"barracks":      {"wood": 175},
	"lumber_camp":   {"wood": 100},
	"mining_camp":   {"wood": 100},
	"farm":          {"wood": 60},
	"wall_segment":  {"stone": 5},
	"gate":          {"wood": 30},
}

const CAMERA_SPEED: float = 400.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
const CAMERA_ZOOM_STEP: float = 0.1
const UNIT_CLICK_RADIUS: float = 32.0

@onready var units_layer: Node2D = $UnitsLayer
@onready var buildings_layer: Node2D = $BuildingsLayer
@onready var camera: Camera2D = $Camera2D
@onready var drop_off: Node2D = $DropOffNode
@onready var hud: CanvasLayer = $HUD

var _ai_town_center: Node2D = null
var _fog: FogOfWar = null

var _selected_units: Array[Node] = []
var _selected_building: Node = null
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false

var _panning: bool = false
var _pan_last_pos: Vector2 = Vector2.ZERO

var _following: bool = false

# Build placement state
var _placing_building: bool = false
var _placing_id: String = ""
var _ghost: Node2D = null
var _ghost_rotation: float = 0.0

# Drag-select rectangle overlay
var _drag_overlay: Node2D = null

func _ready() -> void:
	ResourceManager.init_player(0)
	PopulationManager.init_player(0)
	AgeManager.init_player(0, MatchConfig.starting_age)
	ResourceManager.init_player(1)
	PopulationManager.init_player(1)
	AgeManager.init_player(1)

	_apply_civilization()

	_rng.randomize()
	var map_data: Dictionary = MapGenerator.generate(self, units_layer, _rng)

	# Place player TC at generated position
	drop_off.global_position = map_data["tc0"] as Vector2
	camera.position = drop_off.global_position

	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		units_layer.add_child(v)
		v.global_position = drop_off.global_position + Vector2(i * 40 - 40, 60.0)
		v.set("player_id", 0)
		PopulationManager.add_unit(0)
		EventBus.unit_spawned.emit(v, 0)

	var scout0: CharacterBody2D = SCOUT_SCENE.instantiate()
	units_layer.add_child(scout0)
	scout0.global_position = drop_off.global_position + Vector2(80.0, -60.0)
	scout0.set("player_id", 0)
	PopulationManager.add_unit(0)
	EventBus.unit_spawned.emit(scout0, 0)

	_setup_ai(map_data["tc1"] as Vector2)

	hud.action_requested.connect(_on_action_requested)
	hud.follow_requested.connect(toggle_follow)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.building_destroyed.connect(_on_building_destroyed_check_victory)
	EventBus.minimap_move_order.connect(func(p: Vector2) -> void:
		_following = false
		_order_move_all(p)
	)
	EventBus.unit_selected.connect(_on_unit_selected_follow)

	_fog = FogOfWar.new()
	add_child(_fog)
	_fog.setup(units_layer, buildings_layer, drop_off, self)

	var minimap: MinimapRenderer = hud.get_node_or_null("%Minimap") as MinimapRenderer
	if minimap != null:
		minimap.world_node = self
		minimap.camera_node = camera
		minimap.fog = _fog

	_drag_overlay = _DragOverlay.new()
	_drag_overlay.z_index = 20
	add_child(_drag_overlay)

	GameManager.start_game([{"id": 0}, {"id": 1}])
	AudioManager.play_music()
	GameManager.game_over.connect(_on_game_over)

func _apply_civilization() -> void:
	var civ_path: String = "res://resources/civilizations/%s.tres" % MatchConfig.player_civ_id
	var civ: CivilizationResource = load(civ_path) as CivilizationResource
	if civ == null:
		return
	# Apply starting resource bonuses
	for key: String in (civ.starting_bonuses as Dictionary):
		ResourceManager.add_resource(0, key, (civ.starting_bonuses as Dictionary)[key] as float)
	# Apply villager stat multipliers at spawn time via unit_data overrides stored in MatchConfig
	MatchConfig.set_meta("civ", civ)

func _setup_ai(tc_pos: Vector2) -> void:
	_ai_town_center = AI_TOWN_CENTER_SCENE.instantiate() as Node2D
	_ai_town_center.global_position = tc_pos
	_ai_town_center.set("player_id", 1)
	buildings_layer.add_child(_ai_town_center)

	# AI drop-off is the DropOff child of the town center
	var ai_drop_off: Node = _ai_town_center.get_node_or_null("DropOff")

	# Spawn 3 AI villagers
	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		units_layer.add_child(v)
		v.global_position = _ai_town_center.global_position + Vector2(i * 40 - 40, 60.0)
		v.set("player_id", 1)
		PopulationManager.add_unit(1)
		EventBus.unit_spawned.emit(v, 1)

	var scout1: CharacterBody2D = SCOUT_SCENE.instantiate()
	units_layer.add_child(scout1)
	scout1.global_position = _ai_town_center.global_position + Vector2(80.0, -60.0)
	scout1.set("player_id", 1)
	PopulationManager.add_unit(1)
	EventBus.unit_spawned.emit(scout1, 1)

	# Wire up AI controller
	var ai: Node = Node.new()
	ai.set_script(load("res://scripts/ai/ai_player.gd"))
	ai.set("player_id", 1)
	add_child(ai)
	ai.set("town_center", _ai_town_center)
	ai.set("units_layer", units_layer)
	ai.set("buildings_layer", buildings_layer)
	ai.set("drop_off", ai_drop_off if ai_drop_off != null else _ai_town_center)
	ai.set("enemy_town_center", drop_off)

func _on_building_destroyed_check_victory(building: Node, owner_id: int) -> void:
	# Player's town center destroyed → AI wins
	if building == drop_off:
		GameManager.declare_winner(1)
		return
	# AI's town center destroyed → Player wins
	if building == _ai_town_center:
		GameManager.declare_winner(0)
		return

func _process(delta: float) -> void:
	_handle_camera(delta)
	_handle_follow()
	if _placing_building and is_instance_valid(_ghost):
		_ghost.global_position = get_global_mouse_position()
		_ghost.rotation = _ghost_rotation
		var valid: bool = not _placement_overlaps(get_global_mouse_position())
		_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5) if valid else Color(1.0, 0.2, 0.2, 0.5)
	if is_instance_valid(_drag_overlay):
		var overlay: _DragOverlay = _drag_overlay as _DragOverlay
		overlay.active = _dragging
		if _dragging:
			overlay.drag_rect = Rect2(_drag_start, Vector2.ZERO).expand(get_global_mouse_position())
		overlay.queue_redraw()

class _DragOverlay extends Node2D:
	var drag_rect: Rect2 = Rect2()
	var active: bool = false
	func _draw() -> void:
		if not active:
			return
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.18), true)
		draw_rect(drag_rect, Color(0.3, 0.85, 0.3, 0.75), false, 1.5)

func _handle_follow() -> void:
	if not _following or _selected_units.is_empty():
		return
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit: Node in _selected_units:
		if is_instance_valid(unit):
			centroid += (unit as Node2D).global_position
			count += 1
	if count == 0:
		_following = false
		return
	camera.position = centroid / float(count)

func toggle_follow() -> void:
	_following = not _following

func _on_unit_selected_follow(_units: Array) -> void:
	_following = false

const EDGE_SCROLL_MARGIN: float = 24.0

func _handle_camera(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("camera_pan_left"):  dir.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"): dir.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):    dir.y -= 1.0
	if Input.is_action_pressed("camera_pan_down"):  dir.y += 1.0

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var mp: Vector2 = get_viewport().get_mouse_position()
	if mp.x < EDGE_SCROLL_MARGIN:               dir.x -= 1.0
	elif mp.x > vp.x - EDGE_SCROLL_MARGIN:      dir.x += 1.0
	if mp.y < EDGE_SCROLL_MARGIN:               dir.y -= 1.0
	elif mp.y > vp.y - EDGE_SCROLL_MARGIN:      dir.y += 1.0

	if dir != Vector2.ZERO:
		if _following:
			_following = false
			EventBus.camera_follow_cancelled.emit()
		camera.position += dir.normalized() * CAMERA_SPEED * delta

func _is_mouse_over_hud() -> bool:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for control: Node in _get_hud_blocking_rects():
		if not is_instance_valid(control):
			continue
		var c: Control = control as Control
		if c.get_global_rect().has_point(mouse_pos):
			return true
	return false

func _get_hud_blocking_rects() -> Array[Control]:
	var result: Array[Control] = []
	var top_bar: Control = hud.get_node_or_null("HUDRoot/TopBar") as Control
	var bottom_bar: Control = hud.get_node_or_null("HUDRoot/BottomBar") as Control
	if top_bar != null: result.append(top_bar)
	if bottom_bar != null: result.append(bottom_bar)
	return result

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if _placing_building and ke.pressed and not ke.echo and ke.physical_keycode == KEY_R:
			_ghost_rotation += PI / 2.0
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _panning:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		camera.position -= motion.relative / camera.zoom.x
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			if _panning and _following:
				_following = false
				EventBus.camera_follow_cancelled.emit()
			get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(-CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return

		if _is_mouse_over_hud():
			return

		if _placing_building:
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_confirm_placement(get_global_mouse_position())
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_placement()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = get_global_mouse_position()
				_dragging = true
			else:
				if _dragging:
					_dragging = false
					_finish_selection(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(get_global_mouse_position())

func _zoom(step: float) -> void:
	camera.zoom = (camera.zoom + Vector2(step, step)).clamp(
		Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
		Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX))

# --- Selection ---

const BUILDING_CLICK_RADIUS: float = 40.0

func _finish_selection(release_pos: Vector2) -> void:
	var rect: Rect2 = Rect2(_drag_start, Vector2.ZERO).expand(release_pos)
	var is_click: bool = rect.get_area() < 10.0

	for sel: Node in _selected_units:
		if is_instance_valid(sel):
			sel.set_selected(false)
	_selected_units.clear()
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null

	if is_click:
		# Click: select only the single nearest friendly unit within radius
		var best_unit: Node = null
		var best_dist: float = UNIT_CLICK_RADIUS
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			var unit2d: Node2D = unit as Node2D
			var d: float = _drag_start.distance_to(unit2d.global_position)
			if d >= best_dist:
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
					best_dist = d
					best_unit = unit
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			best_dist = d
			best_unit = unit
		if best_unit != null:
			best_unit.set_selected(true)
			_selected_units.append(best_unit)
			AudioManager.play("ui_select")
			SelectionManager.select(_selected_units)
			return
		# Check Town Center first
		if _drag_start.distance_to(drop_off.global_position) < BUILDING_CLICK_RADIUS:
			_selected_building = drop_off
			EventBus.building_selected.emit(drop_off)
			return
		for building: Node in buildings_layer.get_children():
			if not is_instance_valid(building):
				continue
			var b2d: Node2D = building as Node2D
			if _drag_start.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
				var bpid: Variant = building.get("player_id")
				if bpid != null and (bpid as int) != 0:
					continue
				_selected_building = building
				EventBus.building_selected.emit(building)
				return
		for child: Node in get_children():
			if not (child is ResourceNode):
				continue
			var rn: ResourceNode = child as ResourceNode
			if _drag_start.distance_to(rn.global_position) < UNIT_CLICK_RADIUS:
				EventBus.resource_node_selected.emit(rn)
				return
	else:
		# Drag: select all friendly units and owned animals inside the rectangle
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			if unit is Animal:
				var animal: Animal = unit as Animal
				if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
					if rect.has_point((unit as Node2D).global_position):
						animal.set_selected(true)
						_selected_units.append(animal)
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			if rect.has_point((unit as Node2D).global_position):
				unit.set_selected(true)
				_selected_units.append(unit)

	if not _selected_units.is_empty():
		AudioManager.play("ui_select")
	SelectionManager.select(_selected_units)

# --- Right-click: gather or move ---

func _handle_right_click(world_pos: Vector2) -> void:
	if _selected_units.is_empty():
		if is_instance_valid(_selected_building) and _selected_building.has_method("set_rally_point"):
			_selected_building.set_rally_point(world_pos)
			_flash_target(_selected_building, Color(1.0, 0.92, 0.2, 1.0))
		return

	# 1. Enemy unit clicked → attack
	var enemy_unit: Node = _find_enemy_unit_at(world_pos)
	if enemy_unit != null:
		_order_attack_all(enemy_unit)
		return

	# 2. Animal clicked
	var animal: Animal = _find_animal_at(world_pos)
	if animal != null:
		_order_interact_animal(animal)
		return

	# 3. Enemy building clicked → attack
	var enemy_building: Node = _find_enemy_building_at(world_pos)
	if enemy_building != null:
		_order_attack_all(enemy_building)
		return

	# 4. Own resource drop-off → drop off carried resources, or repair if damaged and no one carries
	var drop_off_node: Node = _find_drop_off_at(world_pos)
	if drop_off_node != null:
		var hp: Variant = drop_off_node.get("health")
		var mhp: Variant = drop_off_node.get("max_health")
		var is_damaged: bool = hp != null and mhp != null and (hp as float) < (mhp as float)
		var any_carrying: bool = false
		for u: Node in _selected_units:
			if is_instance_valid(u) and (u.get("carried_amount") as float) > 0.0:
				any_carrying = true
				break
		if is_damaged and not any_carrying:
			_order_build_all(drop_off_node)
		else:
			_order_drop_off_all(drop_off_node)
		return

	# 5. Resource node → gather
	var resource_node: ResourceNode = _find_resource_at(world_pos)
	if resource_node != null:
		_order_gather_all(resource_node)
		return

	# 6. Farm → gather/restore
	var farm: Farm = _find_farm_at(world_pos)
	if farm != null:
		_order_gather_farm(farm)
		return

	# 7. Own gate → just move through it
	var gate: Gate = _find_gate_at(world_pos)
	if gate != null and gate.state == BuildingBase.BuildingState.COMPLETE:
		_order_move_all(world_pos)
		return

	# 8. Own building under construction → build
	var own_construction: Node = _find_own_construction_at(world_pos)
	if own_construction != null:
		_order_build_all(own_construction)
		return

	# 9. Own complete but damaged building → repair
	var damaged_building: Node = _find_own_damaged_building_at(world_pos)
	if damaged_building != null:
		_order_build_all(damaged_building)
		return

	_order_move_all(world_pos)

func _find_animal_at(world_pos: Vector2) -> Animal:
	for unit: Node in units_layer.get_children():
		if not (unit is Animal):
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit as Animal
	return null

func _order_interact_animal(animal: Animal) -> void:
	# Own sheep: move selected units toward it (to escort / bring closer)
	# Enemy or wild animals: attack
	if animal.current_state == Animal.AnimalState.OWNED and animal.player_id == 0:
		_order_move_all((animal as Node2D).global_position)
		return
	for unit: Node in _selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("order_attack"):
			unit.order_attack(animal)

func _find_gate_at(world_pos: Vector2) -> Gate:
	for building: Node in buildings_layer.get_children():
		if not (building is Gate):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			return building as Gate
	return null

func _find_drop_off_at(world_pos: Vector2) -> Node:
	# Town Center
	if world_pos.distance_to(drop_off.global_position) < BUILDING_CLICK_RADIUS:
		return drop_off
	# Lumber/Mining camps (any complete building that has a DropOffBuilding child)
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) >= BUILDING_CLICK_RADIUS:
			continue
		for child: Node in building.get_children():
			if child is DropOffBuilding:
				return building
	return null

func _order_drop_off_all(target: Node) -> void:
	_flash_target(target, Color(1.8, 1.8, 0.4, 1.0))
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_drop_off"):
			unit.order_drop_off(target)

func _find_farm_at(world_pos: Vector2) -> Farm:
	for building: Node in buildings_layer.get_children():
		if not (building is Farm):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			var farm: Farm = building as Farm
			if farm.state == BuildingBase.BuildingState.COMPLETE:
				return farm
	return null

func _order_gather_farm(farm: Farm) -> void:
	_flash_target(farm, Color(1.8, 1.8, 0.4, 1.0))
	if farm.is_depleted():
		_order_restore_farm(farm)
		return
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(farm, "food", null)

func _order_restore_farm(farm: Farm) -> void:
	if not ResourceManager.spend_resource(0, farm.get_restore_cost()):
		return
	farm.restore()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(farm, "food", null)

func _find_enemy_unit_at(world_pos: Vector2) -> Node:
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or unit is Animal:
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit
	return null

func _find_enemy_building_at(world_pos: Vector2) -> Node:
	# Check enemy Town Center
	if is_instance_valid(_ai_town_center):
		if world_pos.distance_to((_ai_town_center as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			return _ai_town_center
	# Check buildings layer
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			return building
	return null

func _find_own_construction_at(world_pos: Vector2) -> Node:
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			var state_val: Variant = building.get("state")
			if state_val != null and (state_val as int) == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
				return building
	return null

func _find_own_damaged_building_at(world_pos: Vector2) -> Node:
	# Helper: returns true if a node is a complete (or TC-style) building with less than full HP
	var check: Callable = func(node: Node) -> bool:
		var hp: Variant = node.get("health")
		var mhp: Variant = node.get("max_health")
		if hp == null or mhp == null or (mhp as float) <= 0.0:
			return false
		if (hp as float) >= (mhp as float):
			return false
		# Must be complete (BuildingBase) or have no state field (TownCenterBuilding)
		var sv: Variant = node.get("state")
		if sv != null and (sv as int) != BuildingBase.BuildingState.COMPLETE:
			return false
		return true

	if world_pos.distance_to(drop_off.global_position) < BUILDING_CLICK_RADIUS and check.call(drop_off):
		return drop_off
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS and check.call(building):
			return building
	return null

func _flash_target(node: Node, flash_color: Color = Color(2.0, 2.0, 2.0, 1.0)) -> void:
	if not is_instance_valid(node):
		return
	var n2d: Node2D = node as Node2D
	var original: Color = n2d.modulate
	var tw: Tween = create_tween()
	tw.tween_property(n2d, "modulate", flash_color, 0.07)
	tw.tween_property(n2d, "modulate", original,    0.28)

func _order_attack_all(target: Node) -> void:
	AudioManager.play("cmd_attack")
	_flash_target(target, Color(2.2, 0.4, 0.4, 1.0))
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_attack"):
			unit.order_attack(target)

func _order_build_all(building: Node) -> void:
	_flash_target(building, Color(0.6, 1.8, 0.6, 1.0))
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_build"):
			unit.order_build(building)

func _find_resource_at(world_pos: Vector2) -> ResourceNode:
	for child: Node in get_children():
		if child is ResourceNode:
			var rn: ResourceNode = child as ResourceNode
			if world_pos.distance_to(rn.global_position) < 32.0:
				return rn
	return null

func _order_gather_all(resource_node: ResourceNode) -> void:
	_flash_target(resource_node, Color(1.8, 1.8, 0.4, 1.0))
	var resource_name: String = resource_node.get_resource_name()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(resource_node, resource_name, drop_off)

func _order_move_all(world_pos: Vector2) -> void:
	AudioManager.play("cmd_move")
	var valid_units: Array[Node] = []
	for u: Node in _selected_units:
		if is_instance_valid(u) and u.has_method("order_move"):
			valid_units.append(u)
	var count: int = valid_units.size()
	if count == 0:
		return
	var slots: Array[Vector2] = _formation_slots(world_pos, count)
	for i: int in range(count):
		valid_units[i].order_move(slots[i])

## Returns world-space positions for `count` units in concentric rings around `center`.
## The formation faces away from the average origin of the selected units (nearest ring
## is placed on the side closest to where units are coming from).
func _formation_slots(center: Vector2, count: int) -> Array[Vector2]:
	const SPACING: float = 34.0  # px between slots

	# Average position of selected units → direction they approach from
	var avg_origin: Vector2 = Vector2.ZERO
	for u: Node in _selected_units:
		if is_instance_valid(u):
			avg_origin += (u as Node2D).global_position
	avg_origin /= float(_selected_units.size())
	# "back" direction: from center toward average origin (units arrive from that side)
	var back_dir: Vector2 = (avg_origin - center).normalized()
	if back_dir == Vector2.ZERO:
		back_dir = Vector2.DOWN

	var slots: Array[Vector2] = []
	slots.append(center)  # slot 0: the exact target point
	if count == 1:
		return slots

	# Fill concentric rings: ring r has 6*r slots, radius r*SPACING
	var ring: int = 1
	while slots.size() < count:
		var slots_in_ring: int = 6 * ring
		var radius: float = ring * SPACING
		# Start angle: point the first slot toward the back (approaching side)
		var start_angle: float = back_dir.angle()
		for s: int in range(slots_in_ring):
			if slots.size() >= count:
				break
			var angle: float = start_angle + s * TAU / float(slots_in_ring)
			slots.append(center + Vector2(cos(angle), sin(angle)) * radius)
		ring += 1

	return slots

# --- Building placement ---

func _start_placement(building_id: String) -> void:
	if not BUILDING_SCENES.has(building_id):
		return
	if not ResourceManager.can_afford(0, BUILDING_COSTS.get(building_id, {})):
		return

	_cancel_placement()
	_placing_building = true
	_placing_id = building_id
	_ghost_rotation = 0.0

	var scene: PackedScene = load(BUILDING_SCENES[building_id]) as PackedScene
	_ghost = scene.instantiate() as Node2D
	_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5)
	for child: Node in _ghost.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			(child as CollisionShape2D).disabled = true
	buildings_layer.add_child(_ghost)

func _placement_overlaps(world_pos: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape: RectangleShape2D = _get_ghost_shape()
	if shape == null:
		return false
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, world_pos)
	params.collision_mask = 1
	params.exclude = []
	var results: Array[Dictionary] = space.intersect_shape(params, 1)
	return results.size() > 0

func _get_ghost_shape() -> RectangleShape2D:
	for child: Node in _ghost.get_children():
		if child is CollisionShape2D:
			var cs: CollisionShape2D = child as CollisionShape2D
			if cs.shape is RectangleShape2D:
				return cs.shape as RectangleShape2D
	return null

func _confirm_placement(world_pos: Vector2) -> void:
	if _placement_overlaps(world_pos):
		return
	var costs: Dictionary = BUILDING_COSTS.get(_placing_id, {})
	if not ResourceManager.spend_resource(0, costs):
		_cancel_placement()
		return

	var scene: PackedScene = load(BUILDING_SCENES[_placing_id]) as PackedScene
	var building: Node2D = scene.instantiate() as Node2D
	building.global_position = world_pos
	building.rotation = _ghost_rotation
	building.set("player_id", 0)
	building.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	buildings_layer.add_child(building)
	AudioManager.play("build_place")
	EventBus.building_placed.emit(building, 0)

	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_build"):
			unit.order_build(building)

	if Input.is_key_pressed(KEY_SHIFT):
		# Keep placement mode active for the same building type.
		var keep_id: String = _placing_id
		_cancel_placement()
		_start_placement(keep_id)
	else:
		_cancel_placement()

func _cancel_placement() -> void:
	_placing_building = false
	_placing_id = ""
	_ghost_rotation = 0.0
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null

# --- HUD action buttons ---

func _on_action_requested(action_id: String) -> void:
	if action_id.begins_with("build:"):
		_start_placement(action_id.trim_prefix("build:"))
		return
	match action_id:
		"gather_wood":
			_order_gather_nearest_resource(ResourceNode.ResourceType.WOOD)
		"gather_gold":
			_order_gather_nearest_resource(ResourceNode.ResourceType.GOLD)
		"gather_stone":
			_order_gather_nearest_resource(ResourceNode.ResourceType.STONE)
		"gather_food":
			_order_gather_nearest_resource(ResourceNode.ResourceType.FOOD_HUNT)
		"train:villager":
			if is_instance_valid(_selected_building) and _selected_building.has_method("order_train"):
				if _selected_building is TownCenter or _selected_building is TownCenterBuilding:
					_selected_building.order_train()
		"train:militia":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train("militia")
		"train:archer":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train("archer")
		"train:pikeman":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train("pikeman")
		"advance_age":
			AgeManager.start_advance(0)
		"gate_lock":
			if is_instance_valid(_selected_building) and _selected_building is Gate:
				(_selected_building as Gate).toggle_lock()
		"stop":
			for unit: Node in _selected_units:
				if is_instance_valid(unit) and unit.has_method("order_move"):
					unit.order_move((unit as Node2D).global_position)
		"destroy":
			if not _selected_units.is_empty():
				for unit: Node in _selected_units:
					if is_instance_valid(unit) and unit.has_method("die"):
						unit.die()
				_selected_units.clear()
				SelectionManager.select([])
			elif is_instance_valid(_selected_building):
				var target: Node = _selected_building
				if target.has_method("set_selected"):
					target.set_selected(false)
				_selected_building = null
				if target.has_method("take_damage"):
					var hp: Variant = target.get("health")
					var dmg: float = (hp as float + 1.0) if hp != null else 9999.0
					target.take_damage(dmg)
				elif target.has_method("queue_free"):
					target.queue_free()

func _order_gather_nearest_resource(rtype: ResourceNode.ResourceType) -> void:
	if _selected_units.is_empty():
		return
	var pivot: Vector2 = (_selected_units[0] as Node2D).global_position
	var nearest: ResourceNode = _find_nearest_resource_of_type(rtype, pivot)
	if nearest == null:
		return
	var resource_name: String = nearest.get_resource_name()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(nearest, resource_name, drop_off)

func _find_nearest_resource_of_type(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for child: Node in get_children():
		if not (child is ResourceNode):
			continue
		var rn: ResourceNode = child as ResourceNode
		if rn.resource_type != rtype:
			continue
		var d: float = from.distance_to(rn.global_position)
		if d < best_dist:
			best_dist = d
			best = rn
	return best

func _on_unit_spawned(unit: Node, _player: int) -> void:
	if unit.get_parent() != units_layer:
		unit.reparent(units_layer)

func _on_game_over(_winner: int) -> void:
	AudioManager.stop_music()
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	# Freeze units and buildings without pausing the whole tree
	# (pausing the tree stops building production queues too)
	for unit: Node in units_layer.get_children():
		if is_instance_valid(unit):
			(unit as Node).set_process(false)
			(unit as Node).set_physics_process(false)
	for building: Node in buildings_layer.get_children():
		if is_instance_valid(building):
			(building as Node).set_process(false)
	if is_instance_valid(drop_off):
		drop_off.set_process(false)
	if is_instance_valid(_ai_town_center):
		_ai_town_center.set_process(false)

extends Node2D

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
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

var _selected_units: Array[Node] = []
var _selected_building: Node = null
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false

var _panning: bool = false
var _pan_last_pos: Vector2 = Vector2.ZERO

# Build placement state
var _placing_building: bool = false
var _placing_id: String = ""
var _ghost: Node2D = null
var _ghost_rotation: float = 0.0

func _ready() -> void:
	ResourceManager.init_player(0)
	PopulationManager.init_player(0)
	ResourceManager.init_player(1)
	PopulationManager.init_player(1)

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

	_setup_ai(map_data["tc1"] as Vector2)

	hud.action_requested.connect(_on_action_requested)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.building_destroyed.connect(_on_building_destroyed_check_victory)

	var minimap: MinimapRenderer = hud.get_node_or_null("%Minimap") as MinimapRenderer
	if minimap != null:
		minimap.world_node = self
		minimap.camera_node = camera

	GameManager.start_game([{"id": 0}, {"id": 1}])

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
	if _placing_building and is_instance_valid(_ghost):
		_ghost.global_position = get_global_mouse_position()
		_ghost.rotation = _ghost_rotation
		var valid: bool = not _placement_overlaps(get_global_mouse_position())
		_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5) if valid else Color(1.0, 0.2, 0.2, 0.5)

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
	_selected_building = null

	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit is Animal:
			continue  # animals are selected separately below
		var unit2d: Node2D = unit as Node2D
		var in_rect: bool = not is_click and rect.has_point(unit2d.global_position)
		var clicked: bool = is_click and _drag_start.distance_to(unit2d.global_position) < UNIT_CLICK_RADIUS
		if in_rect or clicked:
			unit.set_selected(true)
			_selected_units.append(unit)

	if is_click and _selected_units.is_empty():
		# Check animals
		var animal: Animal = _find_animal_at(_drag_start)
		if animal != null:
			animal.set_selected(true)
			_selected_units.append(animal)
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

	SelectionManager.select(_selected_units)

# --- Right-click: gather or move ---

func _handle_right_click(world_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return
	var animal: Animal = _find_animal_at(world_pos)
	if animal != null:
		_order_interact_animal(animal)
		return
	var resource_node: ResourceNode = _find_resource_at(world_pos)
	if resource_node != null:
		_order_gather_all(resource_node)
		return
	var farm: Farm = _find_farm_at(world_pos)
	if farm != null:
		_order_gather_farm(farm)
		return
	var drop_off_node: Node = _find_drop_off_at(world_pos)
	if drop_off_node != null:
		_order_drop_off_all(drop_off_node)
		return
	var gate: Gate = _find_gate_at(world_pos)
	if gate != null and gate.state == BuildingBase.BuildingState.COMPLETE:
		_order_move_all(world_pos)
		return
	var building: Node = _find_building_at(world_pos)
	if building != null:
		_order_build_all(building)
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
	# Villagers lure the animal; military units attack it
	for unit: Node in _selected_units:
		if not is_instance_valid(unit):
			continue
		if unit is Villager:
			animal.lure(unit)
			(unit as Villager).order_move((animal as Node2D).global_position)
		elif unit.has_method("order_attack"):
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

func _find_building_at(world_pos: Vector2) -> Node:
	for building: Node in buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			var state_val: Variant = building.get("state")
			if state_val != null and state_val as int == BuildingBase.BuildingState.UNDER_CONSTRUCTION:
				return building
	return null

func _order_build_all(building: Node) -> void:
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
	var resource_name: String = resource_node.get_resource_name()
	for unit: Node in _selected_units:
		if is_instance_valid(unit) and unit.has_method("order_gather"):
			unit.order_gather(resource_node, resource_name, drop_off)

func _order_move_all(world_pos: Vector2) -> void:
	var count: int = _selected_units.size()
	for i: int in range(count):
		var unit: Node = _selected_units[i]
		if not is_instance_valid(unit) or not unit.has_method("order_move"):
			continue
		var offset: Vector2 = Vector2(float(i % 4) * 30.0 - 45.0, float(i / 4) * 30.0)
		unit.order_move(world_pos + offset)

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
			if is_instance_valid(_selected_building) and _selected_building is TownCenter:
				(_selected_building as TownCenter).order_train()
		"train:militia":
			if is_instance_valid(_selected_building) and _selected_building is Barracks:
				(_selected_building as Barracks).order_train()
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

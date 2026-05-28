class_name AINaval extends RefCounted

var _ai  # AIPlayer — untyped Variant so dynamic property access works at runtime

var _naval_transport: Node = null
var _naval_scout_target: Vector2 = Vector2.ZERO

const BUILDING_SCENES: Dictionary = {
	"dock":      "res://scenes/buildings/dock.tscn",
	"fish_trap": "res://scenes/buildings/fish_trap.tscn",
}

const GALLEY_RETREAT_HP_RATIO: float = 0.30
const GALLEY_REJOIN_HP_RATIO: float  = 0.65

func setup(ai) -> void:
	_ai = ai

func manage_naval() -> void:
	if _ai._construction._built.get("dock", 0) as int == 0:
		if ResourceManager.can_afford(_ai.player_id, _ai._construction._building_costs["dock"]):
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

	var age: int = AgeManager.get_age(_ai.player_id)
	var galleys: int    = _count_naval("WarGalley")
	var transports: int = _count_naval("TransportShip")

	if age < GameManager.Age.FEUDAL:
		if _count_naval("FishingBoat") < 2:
			dk.order_train("fishing_boat")
		return

	var ai_civ: String = MatchConfig.get_rival_civ_id(_ai.player_id)
	var galley_target: int = 2 if age == GameManager.Age.FEUDAL else 3
	if galleys < galley_target:
		if ai_civ == "fenicios" and ResourceManager.can_afford(_ai.player_id, {"wood": 100, "gold": 50}):
			dk.order_train("trireme")
			return
		if ResourceManager.can_afford(_ai.player_id, {"wood": 75, "gold": 35}):
			dk.order_train("war_galley")
			return
	if transports < 1 and ResourceManager.can_afford(_ai.player_id, {"wood": 125}):
		dk.order_train("transport_ship")
		return
	if age >= GameManager.Age.CASTLE and galleys < 4:
		if ai_civ == "fenicios" and ResourceManager.can_afford(_ai.player_id, {"wood": 100, "gold": 50}):
			dk.order_train("trireme")
		elif ResourceManager.can_afford(_ai.player_id, {"wood": 75, "gold": 35}):
			dk.order_train("war_galley")

func manage_naval_patrol() -> void:
	var etc: Node2D = _ai._military.get_primary_enemy_tc()
	if etc == null:
		return
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is WarGalley):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
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

func manage_fishing_boats() -> void:
	var dock: Node = _find_own_dock()
	if dock == null:
		return
	var dk_pos: Vector2 = (dock as Node2D).global_position

	var fish_node: Node = _find_nearest_fish_node(dk_pos)

	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is FishingBoat):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		var fb: FishingBoat = unit as FishingBoat
		if fb.current_state != UnitBase.UnitState.IDLE:
			continue

		if fish_node != null:
			fb.order_fish(fish_node, dock)
		else:
			var trap: FishTrap = _find_own_fish_trap()
			if trap != null:
				fb.order_fish(trap, dock)
			else:
				if ResourceManager.can_afford(_ai.player_id, _ai._construction._building_costs["fish_trap"]):
					_build_fish_trap(fb, dock)

func launch_naval_assault() -> void:
	var etc: Node2D = _ai._military.get_primary_enemy_tc()
	if etc == null:
		return

	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is WarGalley):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
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

	var military: int = _ai._military.count_military()
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
	for unit: Node in _ai.units_layer.get_children():
		if ts.is_full() or boarded >= 4:
			break
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if not _ai._military.is_military_unit(unit):
			continue
		if unit.get("current_state") as int == UnitBase.UnitState.IDLE:
			ts.board(unit)
			boarded += 1

	if boarded > 0:
		ts.order_move_then_unload(etc.global_position)

func attack_with_idle_land_units() -> void:
	if not is_instance_valid(_ai.town_center):
		return
	var own_origin: Vector2 = _ai.town_center.global_position
	var etc: Node2D = _ai._military.get_primary_enemy_tc()
	var target: Node = _ai._military.find_nearest_enemy_building()
	if target == null:
		target = etc
	if target == null:
		target = _ai._military.find_nearest_enemy_unit()
	if target == null:
		return
	var enemy_origin: Vector2 = (target as Node2D).global_position
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if not _ai._military.is_military_unit(unit):
			continue
		var ustate: Variant = unit.get("current_state")
		if ustate == null or (ustate as int) != UnitBase.UnitState.IDLE:
			continue
		var upos: Vector2 = (unit as Node2D).global_position
		# Only attack if the unit has already crossed the water onto the enemy island
		if upos.distance_to(enemy_origin) < upos.distance_to(own_origin):
			if unit.has_method("order_attack"):
				unit.order_attack(target)

func _find_own_dock() -> Node:
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if building is Dock:
			return building
	return null

func _find_own_transport() -> Node:
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		if unit is TransportShip:
			return unit
	return null

func _find_own_fish_trap() -> FishTrap:
	for building: Node in _ai.buildings_layer.get_children():
		if not is_instance_valid(building) or not (building is FishTrap):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		var ft: FishTrap = building as FishTrap
		if ft.state == BuildingBase.BuildingState.COMPLETE and not ft.is_depleted():
			return ft
	return null

func _find_nearest_fish_node(from: Vector2) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for node: Node in _ai.get_tree().get_nodes_in_group("resource_nodes"):
		var rtype: Variant = node.get("resource_type")
		if rtype == null or (rtype as int) != ResourceNode.ResourceType.FOOD_FISH:
			continue
		var d: float = from.distance_to((node as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

func _find_shore_position() -> Vector2:
	var origin: Vector2 = _ai.town_center.global_position
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
					if _ai._construction.is_pos_clear(candidate):
						return candidate
	return Vector2.ZERO

func _find_ocean_build_pos(origin: Vector2, min_r: float, max_r: float) -> Vector2:
	for _i: int in range(24):
		var angle: float = randf() * TAU
		var dist: float = randf_range(min_r, max_r)
		var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		if TerrainManager.is_ocean(pos):
			return pos
	return Vector2.ZERO

func _build_dock_on_shore() -> void:
	if not is_instance_valid(_ai.town_center):
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
	b.set("player_id", _ai.player_id)
	_ai.buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, _ai.player_id)
	ResourceManager.spend_resource(_ai.player_id, _ai._construction._building_costs["dock"])
	_ai._construction._built["dock"] = 1

func _build_fish_trap(boat: FishingBoat, dock: Node) -> void:
	var pos: Vector2 = _find_ocean_build_pos((dock as Node2D).global_position, 80.0, 200.0)
	if pos == Vector2.ZERO:
		return
	var scene_path: String = BUILDING_SCENES.get("fish_trap", "") as String
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return
	var b: Node2D = packed.instantiate() as Node2D
	b.global_position = pos
	b.set("player_id", _ai.player_id)
	_ai.buildings_layer.add_child(b)
	b.set("state", BuildingBase.BuildingState.UNDER_CONSTRUCTION)
	b.add_construction(100.0)
	EventBus.building_placed.emit(b, _ai.player_id)
	ResourceManager.spend_resource(_ai.player_id, _ai._construction._building_costs["fish_trap"])
	boat.order_build(b)

func _count_naval(type_name: String) -> int:
	var count: int = 0
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != _ai.player_id:
			continue
		match type_name:
			"WarGalley":     if unit is WarGalley:     count += 1
			"TransportShip": if unit is TransportShip: count += 1
			"FishingBoat":   if unit is FishingBoat:   count += 1
	return count

func _galley_needs_retreat(wg: WarGalley) -> bool:
	var udata: Variant = wg.get("unit_data")
	if udata == null:
		return false
	var max_hp: float = (udata as UnitResource).max_health
	if max_hp <= 0.0:
		return false
	var hp: float = wg.get("health") as float
	return hp / max_hp < GALLEY_RETREAT_HP_RATIO

func _galley_is_recovering(wg: WarGalley) -> bool:
	var udata: Variant = wg.get("unit_data")
	if udata == null:
		return false
	var max_hp: float = (udata as UnitResource).max_health
	if max_hp <= 0.0:
		return false
	var hp: float = wg.get("health") as float
	return hp / max_hp < GALLEY_REJOIN_HP_RATIO

func _retreat_galley(wg: WarGalley) -> void:
	var dock: Node = _find_own_dock()
	if dock == null:
		return
	var dock_pos: Vector2 = (dock as Node2D).global_position
	var jitter: Vector2 = Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
	var dest: Vector2 = dock_pos + jitter
	if TerrainManager.is_ocean(dest):
		wg.order_move(dest)

func _find_nearest_enemy_ship(from: Vector2) -> Node:
	var best: Node = null
	var best_dist: float = 800.0
	for unit: Node in _ai.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == _ai.player_id:
			continue
		if not (unit is WarGalley or unit is FishingBoat or unit is TransportShip):
			continue
		var d: float = from.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

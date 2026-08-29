class_name WorldCommands extends RefCounted

## The player's intent layer: right-click resolution, the click-target pickers
## (_find_*_at), the HUD action router, pending map-click actions and the
## click-feedback flashes. Every simulation mutation is packaged as a
## GameCommand and submitted through the CommandBus autoload — this class
## decides WHAT the player meant, the commands do it. UI feedback (audio,
## flashes, selection changes, HUD refreshes) stays here: it is local-only and
## must not replay or cross the network.

const UNIT_CLICK_RADIUS: float = 32.0
const BUILDING_CLICK_RADIUS: float = 40.0

var _world  # GameWorld — untyped so dynamic access works

# Pending action waiting for a map click ("move_to" or "attack_move")
var _pending_action: String = ""

# Formation the next group move fans out into (local UI state: the CHOICE is
# not a command, every move command carries the formation it was issued with).
var _formation: String = "line"

func setup(world) -> void:
	_world = world

## Registry IDs of the current live selection — the unit set every command
## carries. Ownership is re-checked at execute time by the command itself.
func _selection_ids() -> Array[int]:
	return EntityRegistry.ids_of(_world.live_selection())

## Feeds CursorManager.resolve_context (the pure, tested mapping) with the
## current selection and whatever right-click target sits under the mouse,
## reusing the same _find_*_at helpers _handle_right_click uses — in the same
## priority order, so cursor and click never disagree.
func _resolve_cursor_context() -> String:
	if _world._selected_units.is_empty() or _world._placement._placing_building \
			or _world._placement._wall_drag_active or not _pending_action.is_empty():
		return "default"
	if _world._is_mouse_over_hud() or _world.get_viewport().gui_get_hovered_control() != null:
		return "default"
	var has_villagers: bool = false
	var has_military: bool = false
	var has_land_units: bool = false
	for unit: Node in _world.live_selection():
		if not is_instance_valid(unit) or unit is Animal:
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if unit is Villager:
			has_villagers = true
		elif unit.has_method("is_combat_unit") and unit.is_combat_unit():
			has_military = true
		if not (unit is ShipBase):
			has_land_units = true
	var world_pos: Vector2 = _world.get_global_mouse_position()
	var target_kind: String = "none"
	var target_resource: String = ""
	var transport: TransportShip = _find_own_transport_at(world_pos)
	if transport != null and not transport.is_full():
		target_kind = "transport"
	elif _find_enemy_unit_at(world_pos) != null:
		target_kind = "enemy"
	elif _find_animal_at(world_pos) != null:
		target_kind = "animal"
	elif _find_enemy_building_at(world_pos) != null:
		target_kind = "enemy"
	else:
		var resource_node: ResourceNode = _find_resource_at(world_pos)
		if resource_node != null:
			target_kind = "resource"
			target_resource = resource_node.get_resource_name()
		elif _find_farm_at(world_pos) != null:
			target_kind = "resource"
			target_resource = "food"
		elif _find_own_construction_at(world_pos) != null:
			target_kind = "construction"
		elif _find_own_damaged_building_at(world_pos) != null:
			target_kind = "damaged"
	return CursorManager.resolve_context(has_villagers, has_military,
		has_land_units, target_kind, target_resource)

class _FlashMarker extends Node2D:
	var flash_color: Color = Color.WHITE
	var flash_t: float = 0.0:
		set(v):
			flash_t = v
			queue_redraw()
	# Drawn in world space on purpose: the iso camera turns the circle into a
	# 2:1 ground ellipse and the world-axis square into the classic ground
	# diamond, so the order marker reads as lying flat on the terrain.
	func _draw() -> void:
		var radius: float = 10.0 + flash_t * 10.0
		var alpha: float = (1.0 - flash_t) * 0.85
		var col: Color = Color(flash_color.r, flash_color.g, flash_color.b, alpha)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col, 2.0)
		var d: float = maxf(2.0, radius * (1.0 - flash_t) * 0.7)
		var diamond: PackedVector2Array = PackedVector2Array([
			Vector2(-d, -d), Vector2(d, -d), Vector2(d, d), Vector2(-d, d), Vector2(-d, -d),
		])
		draw_polyline(diamond, col, 1.5)

# --- Right-click: gather or move ---

func _handle_right_click(world_pos: Vector2) -> void:
	if _world._selected_units.is_empty():
		if is_instance_valid(_world._selected_building) and _world._selected_building.has_method("set_rally_point"):
			CommandBus.submit(BuildingActionCommand.make(0, "set_rally",
				EntityRegistry.id_of(_world._selected_building), world_pos))
			_flash_target(_world._selected_building, Color(1.0, 0.92, 0.2, 1.0))
		return

	# 0a. Own transport ship clicked with boardable land units → board
	var transport: TransportShip = _find_own_transport_at(world_pos)
	if transport != null and not transport.is_full():
		var boardable: Array[int] = []
		for unit: Node in _world.live_selection():
			if not is_instance_valid(unit) or unit is ShipBase:
				continue
			var pid: Variant = unit.get("player_id")
			if pid == null or (pid as int) != 0:
				continue
			boardable.append(EntityRegistry.id_of(unit))
		if not boardable.is_empty():
			CommandBus.submit(UnitTargetCommand.make(0, "board", boardable,
				EntityRegistry.id_of(transport)))
			_flash_target(transport, Color(0.4, 1.0, 0.4, 1.0))
			return

	# 0b. Transport ship selected → right-click on land = move then unload
	if _world._selected_units.size() == 1 and is_instance_valid(_world._selected_units[0]) \
			and _world._selected_units[0] is TransportShip:
		var ts: TransportShip = _world._selected_units[0] as TransportShip
		if not ts._garrison.is_empty() and not TerrainManager.is_ocean(world_pos):
			CommandBus.submit(TransportCommand.make(0, "move_unload",
				EntityRegistry.id_of(ts), -1, world_pos))
			return

	# 0c. Own garrisonable building (TC/tower) clicked with military selected →
	# garrison them. Villagers keep the drop-off/repair gestures below.
	var fort: Node = _find_garrisonable_at(world_pos)
	if fort != null and (fort.get_garrison() as Array).size() < (fort.garrison_capacity() as int):
		var troops: Array[int] = []
		for unit: Node in _world.live_selection():
			if not is_instance_valid(unit) or unit is ShipBase:
				continue
			var upid: Variant = unit.get("player_id")
			if upid == null or (upid as int) != 0:
				continue
			if unit.has_method("is_combat_unit") and unit.call("is_combat_unit") \
					and not (unit is BatteringRam or unit is Mangonel or unit is Trebuchet):
				troops.append(EntityRegistry.id_of(unit))
		if not troops.is_empty():
			CommandBus.submit(UnitTargetCommand.make(0, "garrison", troops,
				EntityRegistry.id_of(fort)))
			_flash_target(fort, Color(0.4, 1.0, 0.4, 1.0))
			return

	# 1. Enemy unit clicked → attack
	var enemy_unit: Node = _find_enemy_unit_at(world_pos)
	if enemy_unit != null:
		_order_attack_all(enemy_unit)
		return

	# 2. Animal clicked → send the selection to slaughter it for food (own
	# herded sheep included — that's how a sheep yields meat); soldiers attack it.
	var animal: Animal = _find_animal_at(world_pos)
	if animal != null:
		CommandBus.submit(UnitTargetCommand.make(0, "attack", _selection_ids(),
			EntityRegistry.id_of(animal)))
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
		for u: Node in _world.live_selection():
			var ca: Variant = u.get("carried_amount")
			if is_instance_valid(u) and ca != null and (ca as float) > 0.0:
				any_carrying = true
				break
		if is_damaged and not any_carrying:
			_order_build_all(drop_off_node)
		else:
			_flash_target(drop_off_node, Color(1.8, 1.8, 0.4, 1.0))
			CommandBus.submit(UnitTargetCommand.make(0, "drop_off", _selection_ids(),
				EntityRegistry.id_of(drop_off_node)))
		return

	# 5. Resource node → gather
	var resource_node: ResourceNode = _find_resource_at(world_pos)
	if resource_node != null:
		_order_gather_all(resource_node)
		return

	# 6. Farm → gather (the command restores a depleted farm first)
	var farm: Farm = _find_farm_at(world_pos)
	if farm != null:
		_order_gather_all(farm)
		return

	# 6b. Fish Trap clicked by fishing boat → gather (idem restore)
	var fish_trap: FishTrap = _find_fish_trap_at(world_pos)
	if fish_trap != null:
		_order_gather_all(fish_trap)
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

func _order_attack_ground_all(world_pos: Vector2) -> void:
	# Deliberately does NOT emit minimap_move_order: that signal is wired to
	# _order_move_all, so emitting it here synchronously overrode the freshly
	# issued attack-ground with a plain move (cover fire cancelled itself).
	CommandBus.submit(UnitPointCommand.make(0, "attack_ground", _selection_ids(), world_pos))
	_flash_point(world_pos, Color(1.0, 0.6, 0.1, 1.0))

func _find_own_transport_at(world_pos: Vector2) -> TransportShip:
	for unit: Node in _world.units_layer.get_children():
		if not (unit is TransportShip):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit as TransportShip
	return null

func _find_animal_at(world_pos: Vector2) -> Animal:
	for unit: Node in _world.units_layer.get_children():
		if not (unit is Animal):
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit as Animal
	return null

## Own COMPLETE building with garrison room under the click (the player's TC
## included — it lives outside the buildings layer).
func _find_garrisonable_at(world_pos: Vector2) -> Node:
	var candidates: Array[Node] = []
	if is_instance_valid(_world.drop_off):
		candidates.append(_world.drop_off)
	for building: Node in _world.buildings_layer.get_children():
		if is_instance_valid(building):
			candidates.append(building)
	for building: Node in candidates:
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if not building.has_method("garrison_capacity") \
				or (building.garrison_capacity() as int) <= 0:
			continue
		var state_val: Variant = building.get("state")
		if state_val != null and (state_val as int) != BuildingBase.BuildingState.COMPLETE:
			continue
		if _building_click_hit(building as Node2D, world_pos):
			return building
	return null

func _find_gate_at(world_pos: Vector2) -> Gate:
	for building: Node in _world.buildings_layer.get_children():
		if not (building is Gate):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			return building as Gate
	return null

func _find_drop_off_at(world_pos: Vector2) -> Node:
	# Town Center
	if is_instance_valid(_world.drop_off) and _building_click_hit(_world.drop_off as Node2D, world_pos):
		return _world.drop_off
	for building: Node in _world.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var b2d: Node2D = building as Node2D
		if not _building_click_hit(b2d, world_pos):
			continue
		# Dock — drop-off for fishing boats
		if building is Dock:
			return building
		# Lumber/Mining camps (any complete building that has a DropOffBuilding child)
		for child: Node in building.get_children():
			if child is DropOffBuilding:
				return building
	return null

func _find_farm_at(world_pos: Vector2) -> Farm:
	for building: Node in _world.buildings_layer.get_children():
		if not (building is Farm):
			continue
		var b2d: Node2D = building as Node2D
		if world_pos.distance_to(b2d.global_position) < BUILDING_CLICK_RADIUS:
			var farm: Farm = building as Farm
			if farm.state == BuildingBase.BuildingState.COMPLETE:
				return farm
	return null

func _find_fish_trap_at(world_pos: Vector2) -> FishTrap:
	for building: Node in _world.buildings_layer.get_children():
		if not (building is FishTrap):
			continue
		if world_pos.distance_to((building as Node2D).global_position) < BUILDING_CLICK_RADIUS:
			var ft: FishTrap = building as FishTrap
			if ft.state == BuildingBase.BuildingState.COMPLETE:
				return ft
	return null

func _find_enemy_unit_at(world_pos: Vector2) -> Node:
	for unit: Node in _world.units_layer.get_children():
		if not is_instance_valid(unit) or unit is Animal:
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if world_pos.distance_to((unit as Node2D).global_position) < UNIT_CLICK_RADIUS:
			return unit
	return null

## True when a click at `world_pos` lands on `building` as the player SEES it:
## the world-space footprint, or the upright massing volume the iso projection
## draws up-screen from the origin. A distance-to-origin test misses most of a
## large building's base and all of its elevation (the whole visible facade of
## a Town Center resolved to "nothing", silently degrading attack clicks).
func _building_click_hit(building: Node2D, world_pos: Vector2) -> bool:
	var local: Vector2 = world_pos - building.global_position
	var half: Vector2 = Vector2(BUILDING_CLICK_RADIUS, BUILDING_CLICK_RADIUS)
	var cs: CollisionShape2D = building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		half = (cs.shape as RectangleShape2D).size * 0.5 + Vector2(6.0, 6.0)
	if absf(local.x) <= half.x and absf(local.y) <= half.y:
		return true
	# Massing test in screen space; ground-plane buildings (farms) have no
	# massing metadata and fall back to a shallow band over the footprint.
	var s: Vector2 = IsoProjection.world_to_screen(local)
	var half_w: float = (half.x + half.y) * 0.7071
	var top_y: float = (building.get_meta("massing_top_y") as float) \
		if building.has_meta("massing_top_y") else -half_w * 0.5
	var bot_y: float = (building.get_meta("massing_bot_y") as float) \
		if building.has_meta("massing_bot_y") else half_w * 0.5
	return absf(s.x) <= half_w and s.y >= top_y - 4.0 and s.y <= bot_y + 4.0

func _find_enemy_building_at(world_pos: Vector2) -> Node:
	# Front-most (greatest projected origin y) wins when facades overlap.
	var best: Node = null
	var best_depth: float = -INF
	if is_instance_valid(_world._ai_town_center) and _building_click_hit(_world._ai_town_center, world_pos):
		best = _world._ai_town_center
		best_depth = IsoProjection.world_to_screen((_world._ai_town_center as Node2D).global_position).y
	for building: Node in _world.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		if not _building_click_hit(building as Node2D, world_pos):
			continue
		var depth: float = IsoProjection.world_to_screen((building as Node2D).global_position).y
		if depth > best_depth:
			best_depth = depth
			best = building
	return best

func _find_own_construction_at(world_pos: Vector2) -> Node:
	for building: Node in _world.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if _building_click_hit(building as Node2D, world_pos):
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

	if is_instance_valid(_world.drop_off) and _building_click_hit(_world.drop_off as Node2D, world_pos) \
			and check.call(_world.drop_off):
		return _world.drop_off
	for building: Node in _world.buildings_layer.get_children():
		if not is_instance_valid(building):
			continue
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		if _building_click_hit(building as Node2D, world_pos) and check.call(building):
			return building
	return null

func _flash_target(node: Node, flash_color: Color = Color(2.0, 2.0, 2.0, 1.0)) -> void:
	if not is_instance_valid(node):
		return
	var n2d: Node2D = node as Node2D
	var original: Color = n2d.modulate
	var tw: Tween = _world.create_tween()
	tw.tween_property(n2d, "modulate", flash_color, 0.07)
	tw.tween_property(n2d, "modulate", original,    0.28)

func _order_attack_all(target: Node) -> void:
	AudioManager.play("cmd_attack")
	_flash_target(target, Color(2.2, 0.4, 0.4, 1.0))
	CommandBus.submit(UnitTargetCommand.make(0, "attack", _selection_ids(),
		EntityRegistry.id_of(target)))

func _order_build_all(building: Node) -> void:
	_flash_target(building, Color(0.6, 1.8, 0.6, 1.0))
	CommandBus.submit(UnitTargetCommand.make(0, "build", _selection_ids(),
		EntityRegistry.id_of(building)))

func _find_resource_at(world_pos: Vector2) -> ResourceNode:
	for child: Node in _world.get_children():
		if child is ResourceNode:
			var rn: ResourceNode = child as ResourceNode
			if world_pos.distance_to(rn.global_position) < UNIT_CLICK_RADIUS:
				return rn
	return null

## One gather entry point for resource nodes, farms and fish traps — the
## GatherCommand sorts out fishing boats, drop-offs and depleted restores.
func _order_gather_all(target: Node) -> void:
	_flash_target(target, Color(1.8, 1.8, 0.4, 1.0))
	CommandBus.submit(UnitTargetCommand.make(0, "gather", _selection_ids(),
		EntityRegistry.id_of(target)))

func _execute_pending_action(world_pos: Vector2) -> void:
	var action: String = _pending_action
	_world.hud.cancel_pending()   # clears _pending_action via signal
	match action:
		"move_to":
			_order_move_all(world_pos)
			_flash_point(world_pos, Color(0.4, 0.8, 1.0, 1.0))
		"attack_move":
			# If an enemy is directly at the click position, attack it
			var enemy_unit: Node = _find_enemy_unit_at(world_pos)
			var enemy_building: Node = _find_enemy_building_at(world_pos)
			var target: Node = enemy_unit if enemy_unit != null else enemy_building
			if target != null:
				_order_attack_all(target)
			else:
				# Move to position; units will auto-attack any enemy they spot en route
				_order_attack_move_all(world_pos)
			_flash_point(world_pos, Color(1.0, 0.35, 0.15, 1.0))
		"cover_fire":
			_order_attack_ground_all(world_pos)

func _order_attack_move_all(world_pos: Vector2) -> void:
	AudioManager.play("cmd_move")
	CommandBus.submit(UnitPointCommand.make(0, "attack_move", _selection_ids(), world_pos,
		_formation))

## Briefly shows a coloured expanding ring at `world_pos` to confirm a click order.
func _flash_point(world_pos: Vector2, color: Color) -> void:
	var marker: _FlashMarker = _FlashMarker.new()
	marker.flash_color = color
	marker.z_index = 10
	_world.add_child(marker)
	marker.global_position = world_pos
	var tween: Tween = _world.create_tween()
	tween.tween_property(marker, "flash_t", 1.0, 0.45).from(0.0)
	tween.tween_callback(func() -> void:
		if is_instance_valid(marker):
			marker.queue_free()
	)

func _order_move_all(world_pos: Vector2) -> void:
	AudioManager.play("cmd_move")
	var valid_units: Array[Node] = []
	for u: Node in _world.live_selection():
		if is_instance_valid(u) and u.has_method("order_move"):
			valid_units.append(u)
	if valid_units.is_empty():
		return
	CommandBus.submit(UnitPointCommand.make(0, "move",
		EntityRegistry.ids_of(valid_units), world_pos, _formation))
	# Ground flash where the player clicked — move was the only order
	# without click feedback (gather/attack flash their target already).
	_flash_point(world_pos, Color(0.35, 1.0, 0.45, 1.0))
	EventBus.unit_command_issued.emit(valid_units, {"type": "move", "pos": world_pos})

# --- HUD action buttons ---

func _selected_building_id() -> int:
	if not is_instance_valid(_world._selected_building):
		return 0
	return EntityRegistry.id_of(_world._selected_building)

func _on_action_requested(action_id: String) -> void:
	if action_id.begins_with("build:"):
		_world._placement._start_placement(action_id.trim_prefix("build:"))
		return
	if action_id.begins_with("formation:"):
		var form: String = action_id.trim_prefix("formation:")
		if form in UnitPointCommand.FORMATIONS:
			_formation = form
		return
	if action_id.begins_with("stance:"):
		CommandBus.submit(UnitActionCommand.make(0,
			"stance_" + action_id.trim_prefix("stance:"), _selection_ids()))
		return
	if action_id == "ungarrison":
		if is_instance_valid(_world._selected_building):
			CommandBus.submit(BuildingActionCommand.make(0, "ungarrison",
				_selected_building_id()))
		return
	if action_id.begins_with("research:"):
		if is_instance_valid(_world._selected_building):
			CommandBus.submit(ProductionCommand.make(0, "research",
				_selected_building_id(), action_id.substr("research:".length())))
		return
	if action_id.begins_with("market:"):
		if is_instance_valid(_world._selected_building) and _world._selected_building is Market:
			var parts: PackedStringArray = action_id.split(":")
			if parts.size() == 3:
				CommandBus.submit(MarketCommand.make(0, parts[1],
					_selected_building_id(), parts[2]))
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
			if is_instance_valid(_world._selected_building) and _world._selected_building.has_method("order_train"):
				# TownCenterBuildable is now also the player's STARTING TC, so it
				# must be accepted here too or the villager button does nothing.
				if _world._selected_building is TownCenter or _world._selected_building is TownCenterBuilding \
						or _world._selected_building is TownCenterBuildable:
					CommandBus.submit(ProductionCommand.make(0, "train", _selected_building_id()))
		"train:militia", "train:pikeman", \
		"train:menceyes_guard", \
		"train:conquistador", "train:tidecaller", "train:sand_raider":
			if is_instance_valid(_world._selected_building) and _world._selected_building is Barracks:
				CommandBus.submit(ProductionCommand.make(0, "train",
					_selected_building_id(), action_id.trim_prefix("train:")))
		"train:archer", "train:ravine_archer", "train:longbowman":
			if is_instance_valid(_world._selected_building) and _world._selected_building is ArcheryRange:
				CommandBus.submit(ProductionCommand.make(0, "train",
					_selected_building_id(), action_id.trim_prefix("train:")))
		"train:scout", "train:heavy_scout", "train:knight":
			if is_instance_valid(_world._selected_building) and _world._selected_building is Stable:
				CommandBus.submit(ProductionCommand.make(0, "train",
					_selected_building_id(), action_id.trim_prefix("train:")))
		"train:battering_ram", "train:mangonel", "train:trebuchet":
			if is_instance_valid(_world._selected_building) and _world._selected_building is SiegeWorkshop:
				CommandBus.submit(ProductionCommand.make(0, "train",
					_selected_building_id(), action_id.trim_prefix("train:")))
		"trebuchet_deploy":
			CommandBus.submit(UnitActionCommand.make(0, "trebuchet_toggle", _selection_ids()))
			for unit: Node in _world.live_selection():
				if unit is Trebuchet:
					_world.hud.call_deferred("_populate_trebuchet_buttons", unit)
					break
		"train:fishing_boat", "train:transport_ship", "train:war_galley":
			if is_instance_valid(_world._selected_building) and _world._selected_building is Dock:
				CommandBus.submit(ProductionCommand.make(0, "train",
					_selected_building_id(), action_id.trim_prefix("train:")))
		"advance_age":
			CommandBus.submit(AdvanceAgeCommand.make(0))
		"gate_lock":
			if is_instance_valid(_world._selected_building) and _world._selected_building is Gate:
				CommandBus.submit(BuildingActionCommand.make(0, "gate_lock", _selected_building_id()))
		"unload":
			for unit: Node in _world.live_selection():
				if unit is TransportShip:
					CommandBus.submit(TransportCommand.make(0, "unload_all",
						EntityRegistry.id_of(unit)))
					break
		"scout_explore":
			CommandBus.submit(UnitActionCommand.make(0, "scout_explore", _selection_ids()))
		"scout_explore_stop":
			CommandBus.submit(UnitActionCommand.make(0, "scout_explore_stop", _selection_ids()))
		"show_path":
			# Debug visual, local-only: not a simulation mutation.
			for unit: Node in _world.live_selection():
				if is_instance_valid(unit) and unit.has_method("toggle_path_display"):
					unit.toggle_path_display()
		"stop":
			CommandBus.submit(UnitActionCommand.make(0, "stop", _selection_ids()))
		"hero_ability":
			CommandBus.submit(UnitActionCommand.make(0, "hero_ability", _selection_ids()))
		"destroy":
			if is_instance_valid(_world._selected_building):
				var target: Node = _world._selected_building
				if target.has_method("set_selected"):
					target.set_selected(false)
				_world._selected_building = null
				CommandBus.submit(BuildingActionCommand.make(0, "delete",
					EntityRegistry.id_of(target)))
			elif not _world._selected_units.is_empty():
				CommandBus.submit(UnitActionCommand.make(0, "delete", _selection_ids()))
				_world._selected_units.clear()
				SelectionManager.select([])
		_:
			if action_id.begins_with("unload_unit:"):
				var idx: int = int(action_id.substr(12))
				for unit: Node in _world.live_selection():
					if unit is TransportShip:
						CommandBus.submit(TransportCommand.make(0, "unload_one",
							EntityRegistry.id_of(unit), idx))
						break

func _order_gather_nearest_resource(rtype: ResourceNode.ResourceType) -> void:
	if _world._selected_units.is_empty():
		return
	var live: Array[Node] = _world.live_selection()
	if live.is_empty():
		return
	var pivot: Vector2 = (live[0] as Node2D).global_position
	var nearest: ResourceNode = _find_nearest_resource_of_type(rtype, pivot)
	if nearest == null:
		return
	_order_gather_all(nearest)

func _find_nearest_resource_of_type(rtype: ResourceNode.ResourceType, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for child: Node in _world.get_children():
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

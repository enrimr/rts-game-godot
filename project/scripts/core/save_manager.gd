extends Node

## SaveManager — serialises and restores a complete game snapshot.
## Save format is JSON stored in user://saves/autosave.json.
## Restoration happens in two phases:
##   1. game_world._ready() regenerates the same map (same RNG seed) but
##      skips fresh spawning, then calls SaveManager.restore_world().
##   2. All autoloads (resources, ages, techs, pop) are restored here, then
##      all units, buildings and resource nodes are re-created from save data.

const SAVE_PATH: String = "user://saves/autosave.json"
const SCHEMA_VERSION: int = 1

# When true, game_world skips fresh spawning and calls restore_world() instead.
var pending_load: bool = false
var _save_data: Dictionary = {}

const UNIT_SCENES: Dictionary = {
	"Villager":      "res://scenes/units/villager.tscn",
	"Militia":       "res://scenes/units/militia.tscn",
	"HeroUnit":      "res://scenes/units/militia.tscn",
	"Scout":         "res://scenes/units/scout.tscn",
	"Archer":        "res://scenes/units/archer.tscn",
	"Pikeman":       "res://scenes/units/pikeman.tscn",
	"WarGalley":     "res://scenes/units/war_galley.tscn",
	"FishingBoat":   "res://scenes/units/fishing_boat.tscn",
	"TransportShip": "res://scenes/units/transport_ship.tscn",
	"Animal":        "res://scenes/units/animal.tscn",
	"Sheep":         "res://scenes/units/sheep.tscn",
}

const BUILDING_SCENES: Dictionary = {
	"TownCenterBuilding": "res://scenes/buildings/town_center_ai.tscn",
	"House":         "res://scenes/buildings/house.tscn",
	"Barracks":      "res://scenes/buildings/barracks.tscn",
	"LumberCamp":    "res://scenes/buildings/lumber_camp.tscn",
	"MiningCamp":    "res://scenes/buildings/mining_camp.tscn",
	"Farm":          "res://scenes/buildings/farm.tscn",
	"WallSegment":   "res://scenes/buildings/wall_segment.tscn",
	"Gate":          "res://scenes/buildings/gate.tscn",
	"Dock":          "res://scenes/buildings/dock.tscn",
	"FishTrap":      "res://scenes/buildings/fish_trap.tscn",
}

# ── Public API ──────────────────────────────────────────────────────────────

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(world: Node) -> bool:
	var data: Dictionary = _collect(world)
	var json: String = JSON.stringify(data, "\t")
	DirAccess.make_dir_recursive_absolute("user://saves")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open %s for writing" % SAVE_PATH)
		return false
	file.store_string(json)
	file.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_error("SaveManager: corrupt save file")
		return false
	_save_data = parsed as Dictionary
	pending_load = true
	_restore_match_config(_save_data)
	return true

func get_saved_rng_seed() -> int:
	return _save_data.get("rng_seed", 0) as int

## Called by game_world after regenerating the map and the AI node structure.
func restore_world(world: Node) -> void:
	if not pending_load or _save_data.is_empty():
		return
	_restore_autoloads(_save_data)
	_restore_units(world, _save_data)
	_restore_buildings(world, _save_data)
	_rewire_ai_town_centers(world)
	_restore_resource_nodes(world, _save_data)
	_restore_fog(world, _save_data)
	pending_load = false
	_save_data = {}

func _rewire_ai_town_centers(world: Node) -> void:
	var buildings_layer: Node = world.get_node_or_null("BuildingsLayer")
	if buildings_layer == null:
		return
	var tc_by_player: Dictionary = {}
	for bld: Node in buildings_layer.get_children():
		if bld is TownCenterBuilding:
			var pid: Variant = bld.get("player_id")
			if pid != null:
				tc_by_player[pid as int] = bld

	# Update world's _ai_town_centers dict and each AI controller's references
	var ai_tcs: Variant = world.get("_ai_town_centers")
	if ai_tcs != null:
		(ai_tcs as Dictionary).clear()
	for rival_id: int in MatchConfig.get_rival_player_ids():
		var tc_node: Variant = tc_by_player.get(rival_id)
		if tc_node == null:
			continue
		if ai_tcs != null:
			(ai_tcs as Dictionary)[rival_id] = tc_node as Node2D
	# Legacy alias
	if ai_tcs != null and (ai_tcs as Dictionary).has(1):
		world.set("_ai_town_center", (ai_tcs as Dictionary)[1])

	for child: Node in world.get_children():
		var pid: Variant = child.get("player_id")
		if pid == null or (pid as int) == 0:
			continue
		var tc_node: Variant = tc_by_player.get(pid as int)
		if tc_node != null:
			child.set("town_center", tc_node as Node2D)
			var dop: Node = (tc_node as Node).get_node_or_null("DropOff")
			if dop != null:
				child.set("drop_off", dop)

# ── Serialisation ───────────────────────────────────────────────────────────

func _collect(world: Node) -> Dictionary:
	var data: Dictionary = {}
	data["schema_version"] = SCHEMA_VERSION
	# The seed stored on the world node (set after randomize() on a fresh game)
	var seed_var: Variant = world.get("_saved_rng_seed")
	data["rng_seed"] = (seed_var as int) if seed_var != null else 0

	data["match_config"] = {
		"map_size":      MatchConfig.map_size,
		"resources":     MatchConfig.resources,
		"map_type":      MatchConfig.map_type,
		"player_civ_id": MatchConfig.player_civ_id,
		"starting_age":  MatchConfig.starting_age,
		"rival_count":   MatchConfig.rival_count,
		"rival_civ_ids": Array(MatchConfig.rival_civ_ids),
	}

	var player_ids: Array[int] = [0]
	for rid: int in MatchConfig.get_rival_player_ids():
		player_ids.append(rid)

	var resources_map: Dictionary = {}
	var ages_map: Dictionary = {}
	var pop_map: Dictionary = {}
	var techs_map: Dictionary = {}

	for pid: int in player_ids:
		resources_map[str(pid)] = ResourceManager.get_resources(pid).duplicate()
		ages_map[str(pid)] = {
			"age":            AgeManager.get_age(pid),
			"advancing":      AgeManager.is_advancing(pid),
			"advance_timer":  AgeManager._advance_timer.get(pid, 0.0),
			"advance_target": AgeManager._advance_target.get(pid, 0),
		}
		var pop: Dictionary = PopulationManager.get_population(pid)
		pop_map[str(pid)] = {"cap": pop["cap"] as int}
		var tlist: Variant = TechManager._researched.get(pid)
		techs_map[str(pid)] = Array(tlist) if tlist != null else []

	data["resources"]        = resources_map
	data["ages"]             = ages_map
	data["population_caps"]  = pop_map
	data["technologies"]     = techs_map

	var units_layer: Node = world.get_node_or_null("UnitsLayer")
	var units_arr: Array = []
	if units_layer != null:
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			var u: Dictionary = _collect_unit(unit)
			if not u.is_empty():
				units_arr.append(u)
	data["units"] = units_arr

	# Player TC is saved separately — it always exists as DropOffNode in the scene
	# and doesn't need a class check.
	var drop_off: Node = world.get_node_or_null("DropOffNode")
	if is_instance_valid(drop_off):
		data["player_tc"] = _collect_tc_state(drop_off)

	var buildings_arr: Array = []
	var buildings_layer: Node = world.get_node_or_null("BuildingsLayer")
	if buildings_layer != null:
		for bld: Node in buildings_layer.get_children():
			if not is_instance_valid(bld):
				continue
			var b: Dictionary = _collect_building(bld, "")
			if not b.is_empty():
				buildings_arr.append(b)
	data["buildings"] = buildings_arr

	var res_nodes_arr: Array = []
	for child: Node in world.get_children():
		if not (child is ResourceNode):
			continue
		var rn: ResourceNode = child as ResourceNode
		res_nodes_arr.append({
			"resource_type":    rn.resource_type as int,
			"initial_amount":   rn.initial_amount,
			"remaining_amount": rn.remaining_amount,
			"position":         _v2(rn.global_position),
		})
	data["resource_nodes"] = res_nodes_arr

	var fog: FogOfWar = _find_fog(world)
	if fog != null:
		data["fog_cells"] = Marshalls.raw_to_base64(fog._cells)

	return data

func _collect_tc_state(tc: Node) -> Dictionary:
	var d: Dictionary = {
		"health":      _float_or(tc.get("health"), 2000.0),
		"max_health":  _float_or(tc.get("max_health"), 2000.0),
		"rally_point": _v2(_vec_or(tc.get("rally_point"), Vector2.ZERO)),
	}
	if tc.has_method("get_queue"):
		var q: Array = tc.call("get_queue") as Array
		var queue_arr: Array = []
		for entry: Variant in q:
			var qe: Dictionary = entry as Dictionary
			queue_arr.append({
				"unit_id":    str(qe.get("unit_id", "")),
				"train_time": qe.get("train_time", 0.0) as float,
				"label":      str(qe.get("label", "")),
				"costs":      (qe.get("costs", {}) as Dictionary).duplicate(),
				"scene":      str(qe.get("scene", "")),
			})
		d["train_queue"] = queue_arr
		d["train_timer"] = _float_or(tc.get("_train_timer"), 0.0)
	return d

func _collect_unit(unit: Node) -> Dictionary:
	var cn: String = _class_name_of(unit)
	if cn.is_empty():
		return {}
	var u: Dictionary = {
		"class":     cn,
		"position":  _v2((unit as Node2D).global_position),
		"player_id": unit.get("player_id") as int,
		"civ_id":    str(unit.get("civ_id")),
		"health":    unit.get("health") as float,
	}
	if unit is HeroUnit:
		var ud: Variant = unit.get("unit_data")
		if ud != null:
			u["unit_data_path"] = (ud as Resource).resource_path
		u["cooldown_remaining"] = unit.get("_cooldown_remaining") as float
	if unit is Villager:
		u["carried_resource"] = str(unit.get("carried_resource"))
		u["carried_amount"]   = unit.get("carried_amount") as float
	return u

func _collect_building(bld: Node, role: String) -> Dictionary:
	var cn: String = _class_name_of(bld)
	if cn.is_empty():
		return {}
	var b: Dictionary = {
		"class":                 cn,
		"role":                  role,
		"position":              _v2((bld as Node2D).global_position),
		"rotation":              (bld as Node2D).rotation,
		"player_id":             bld.get("player_id") as int,
		"health":                _float_or(bld.get("health"), -1.0),
		"max_health":            _float_or(bld.get("max_health"), -1.0),
		"state":                 _int_or(bld.get("state"), -1),
		"construction_progress": _float_or(bld.get("construction_progress"), 0.0),
		"rally_point":           _v2(_vec_or(bld.get("rally_point"), Vector2.ZERO)),
	}
	if bld.has_method("get_queue"):
		var q: Array = bld.call("get_queue") as Array
		var queue_arr: Array = []
		for entry: Variant in q:
			var qe: Dictionary = entry as Dictionary
			queue_arr.append({
				"unit_id":    str(qe.get("unit_id", "")),
				"train_time": qe.get("train_time", 0.0) as float,
				"label":      str(qe.get("label", "")),
				"costs":      (qe.get("costs", {}) as Dictionary).duplicate(),
				"scene":      str(qe.get("scene", "")),
			})
		b["train_queue"] = queue_arr
		b["train_timer"] = _float_or(bld.get("_train_timer"), 0.0)
	if bld is Farm:
		var farm: Farm = bld as Farm
		b["remaining"]   = farm._remaining
		b["is_depleted"] = farm._is_depleted
	elif bld is FishTrap:
		b["remaining"] = _float_or(bld.get("_remaining"), 0.0)
	return b

# ── Restoration ──────────────────────────────────────────────────────────────

func _restore_match_config(data: Dictionary) -> void:
	var mc: Dictionary = data.get("match_config", {}) as Dictionary
	if mc.is_empty():
		return
	MatchConfig.map_size      = mc.get("map_size",      MatchConfig.map_size)      as int
	MatchConfig.resources     = mc.get("resources",     MatchConfig.resources)     as int
	MatchConfig.map_type      = mc.get("map_type",      MatchConfig.map_type)      as int
	MatchConfig.player_civ_id = str(mc.get("player_civ_id", MatchConfig.player_civ_id))
	MatchConfig.starting_age  = mc.get("starting_age",  MatchConfig.starting_age)  as int
	MatchConfig.rival_count   = mc.get("rival_count",   MatchConfig.rival_count)   as int
	var rcids: Variant = mc.get("rival_civ_ids")
	if rcids != null:
		MatchConfig.rival_civ_ids.clear()
		for cid: Variant in (rcids as Array):
			MatchConfig.rival_civ_ids.append(str(cid))

func _restore_autoloads(data: Dictionary) -> void:
	var res_map: Dictionary = data.get("resources", {}) as Dictionary
	for pid_str: Variant in res_map.keys():
		var pid: int = int(str(pid_str))
		var res_dict: Dictionary = res_map[pid_str] as Dictionary
		var existing: Dictionary = ResourceManager.get_resources(pid)
		for key: Variant in existing.keys():
			var target: float = res_dict.get(str(key), 0.0) as float
			var current: float = existing[key] as float
			var diff: float = target - current
			if diff != 0.0:
				ResourceManager.add_resource(pid, str(key), diff)

	var ages_map: Dictionary = data.get("ages", {}) as Dictionary
	for pid_str: Variant in ages_map.keys():
		var pid: int = int(str(pid_str))
		var ag: Dictionary = ages_map[pid_str] as Dictionary
		AgeManager._player_age[pid]     = ag.get("age", 0)            as int
		AgeManager._advancing[pid]      = ag.get("advancing", false)  as bool
		AgeManager._advance_timer[pid]  = ag.get("advance_timer", 0.0) as float
		AgeManager._advance_target[pid] = ag.get("advance_target", 0) as int

	var pop_map: Dictionary = data.get("population_caps", {}) as Dictionary
	for pid_str: Variant in pop_map.keys():
		var pid: int = int(str(pid_str))
		var pop: Dictionary = pop_map[pid_str] as Dictionary
		var saved_cap: int  = pop.get("cap", 15) as int
		var delta_cap: int  = saved_cap - PopulationManager.get_cap(pid)
		if delta_cap != 0:
			PopulationManager.add_cap(pid, delta_cap)

	var techs_map: Dictionary = data.get("technologies", {}) as Dictionary
	for pid_str: Variant in techs_map.keys():
		var pid: int = int(str(pid_str))
		var tlist: Array = techs_map[pid_str] as Array
		TechManager._researched[pid] = []
		for tech_id: Variant in tlist:
			TechManager._apply_tech(pid, str(tech_id))

func _restore_units(world: Node, data: Dictionary) -> void:
	var units_layer: Node = world.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return
	# Remove default units spawned during _ready() (none when loading, but be safe)
	for child: Node in units_layer.get_children().duplicate():
		child.queue_free()

	for entry: Variant in (data.get("units", []) as Array):
		var u: Dictionary = entry as Dictionary
		var cn: String = str(u.get("class", ""))
		var scene_path: String = UNIT_SCENES.get(cn, "") as String
		if scene_path.is_empty():
			continue
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			continue
		var unit: Node2D = packed.instantiate() as Node2D
		if cn == "HeroUnit":
			unit.set_script(load("res://scripts/units/hero_unit.gd"))
			var udp: String = str(u.get("unit_data_path", ""))
			if not udp.is_empty():
				var ud: UnitResource = load(udp) as UnitResource
				if ud != null:
					unit.set("unit_data", ud)
		var pid: int = u.get("player_id", 0) as int
		unit.set("player_id", pid)
		unit.set("civ_id", str(u.get("civ_id", "")))
		var pos: Array = u.get("position", [0.0, 0.0]) as Array
		unit.global_position = Vector2(pos[0] as float, pos[1] as float)
		units_layer.add_child(unit)
		# _ready() has run synchronously; now override health
		var hp: float = u.get("health", -1.0) as float
		if hp >= 0.0:
			unit.set("health", hp)
			var hbar: Variant = unit.get("health_bar")
			if hbar != null:
				(hbar as ProgressBar).value = hp
		if cn == "HeroUnit":
			unit.set("_cooldown_remaining", u.get("cooldown_remaining", 0.0) as float)
		if cn == "Villager":
			unit.set("carried_resource", str(u.get("carried_resource", "")))
			unit.set("carried_amount",   u.get("carried_amount", 0.0) as float)
		PopulationManager.add_unit(pid)
		EventBus.unit_spawned.emit(unit, pid)

func _restore_buildings(world: Node, data: Dictionary) -> void:
	var buildings_layer: Node = world.get_node_or_null("BuildingsLayer")
	var drop_off: Node        = world.get_node_or_null("DropOffNode")

	# Restore player TC from its dedicated key
	var tc_data: Variant = data.get("player_tc")
	if tc_data != null and is_instance_valid(drop_off):
		_apply_building_state(drop_off, tc_data as Dictionary)

	# Remove buildings spawned by _setup_ai_node_only (the AI TCs)
	if buildings_layer != null:
		for child: Node in buildings_layer.get_children().duplicate():
			child.queue_free()

	for entry: Variant in (data.get("buildings", []) as Array):
		var b: Dictionary = entry as Dictionary
		var cn: String   = str(b.get("class", ""))

		var scene_path: String = BUILDING_SCENES.get(cn, "") as String
		if scene_path.is_empty() or buildings_layer == null:
			continue
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			continue
		var bld: Node2D = packed.instantiate() as Node2D
		var pos_arr: Array = b.get("position", [0.0, 0.0]) as Array
		bld.global_position = Vector2(pos_arr[0] as float, pos_arr[1] as float)
		bld.rotation = b.get("rotation", 0.0) as float
		bld.set("player_id", b.get("player_id", 0) as int)
		buildings_layer.add_child(bld)
		_apply_building_state(bld, b)

func _apply_building_state(bld: Node, b: Dictionary) -> void:
	var hp: float = b.get("health", -1.0) as float
	if hp >= 0.0:
		bld.set("health", hp)
		var hbar: Variant = bld.get("_health_bar")
		if hbar != null:
			(hbar as ProgressBar).value = hp

	var mhp: float = b.get("max_health", -1.0) as float
	if mhp >= 0.0:
		bld.set("max_health", mhp)
		var hbar: Variant = bld.get("_health_bar")
		if hbar != null:
			(hbar as ProgressBar).max_value = mhp

	var st: int = b.get("state", -1) as int
	if st >= 0:
		bld.set("state", st)

	bld.set("construction_progress", b.get("construction_progress", 0.0) as float)

	var rp_arr: Array = b.get("rally_point", [0.0, 0.0]) as Array
	var rp: Vector2 = Vector2(rp_arr[0] as float, rp_arr[1] as float)
	if rp != Vector2.ZERO and bld.has_method("set_rally_point"):
		bld.call("set_rally_point", rp)

	var queue_arr: Variant = b.get("train_queue")
	if queue_arr != null and bld.has_method("get_queue"):
		var train_q: Array = []
		for qentry: Variant in (queue_arr as Array):
			var qe: Dictionary = qentry as Dictionary
			train_q.append({
				"unit_id":    str(qe.get("unit_id", "")),
				"train_time": qe.get("train_time", 30.0) as float,
				"label":      str(qe.get("label", "")),
				"color":      Color.WHITE,
				"costs":      (qe.get("costs", {}) as Dictionary).duplicate(),
				"scene":      str(qe.get("scene", "")),
			})
		bld.set("_train_queue", train_q)
		bld.set("_train_timer", b.get("train_timer", 0.0) as float)

	if bld is Farm:
		var farm: Farm = bld as Farm
		farm._remaining   = b.get("remaining", 0.0) as float
		farm._is_depleted = b.get("is_depleted", false) as bool
	elif bld is FishTrap:
		bld.set("_remaining", b.get("remaining", 0.0) as float)

func _restore_resource_nodes(world: Node, data: Dictionary) -> void:
	for child: Node in world.get_children().duplicate():
		if child is ResourceNode:
			child.queue_free()
	ResourceManager.reset_resource_cache()

	# Use a deterministic RNG seeded from the world's saved seed so visuals
	# are consistent across save/load cycles.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_var: Variant = world.get("_saved_rng_seed")
	rng.seed = (seed_var as int) if seed_var != null else 0

	var res_script: Script = load("res://scripts/economy/resource_node.gd") as Script
	for entry: Variant in (data.get("resource_nodes", []) as Array):
		var rnd: Dictionary = entry as Dictionary
		var rtype: ResourceNode.ResourceType = rnd.get("resource_type", 0) as ResourceNode.ResourceType
		var initial: float = rnd.get("initial_amount", 100.0) as float
		var pos_arr: Array = rnd.get("position", [0.0, 0.0]) as Array
		var pos: Vector2 = Vector2(pos_arr[0] as float, pos_arr[1] as float)
		MapGenerator.create_resource_node(world as Node2D, pos, rtype, initial, rng, res_script)
		# _ready() ran synchronously; override remaining amount on the just-added node
		var rn: Node = world.get_children().back()
		if rn is ResourceNode:
			rn.set("remaining_amount", rnd.get("remaining_amount", initial) as float)

func _restore_fog(world: Node, data: Dictionary) -> void:
	var hex: Variant = data.get("fog_cells")
	if hex == null:
		return
	var fog: FogOfWar = _find_fog(world)
	if fog == null:
		return
	var decoded: PackedByteArray = Marshalls.base64_to_raw(str(hex))
	if decoded.size() == fog._cells.size():
		fog._cells = decoded
		fog._dirty_cells.fill(1)

# ── Helpers ──────────────────────────────────────────────────────────────────

func _class_name_of(node: Node) -> String:
	if node is HeroUnit:          return "HeroUnit"
	if node is Villager:          return "Villager"
	if node is Militia:           return "Militia"
	if node is Archer:            return "Archer"
	if node is Pikeman:           return "Pikeman"
	if node is Scout:             return "Scout"
	if node is WarGalley:         return "WarGalley"
	if node is FishingBoat:       return "FishingBoat"
	if node is TransportShip:     return "TransportShip"
	if node is Sheep:             return "Sheep"
	if node is Animal:            return "Animal"
	if node is TownCenter:        return "TownCenter"
	if node is TownCenterBuilding:return "TownCenterBuilding"
	if node is Barracks:          return "Barracks"
	if node is Dock:              return "Dock"
	if node is Farm:              return "Farm"
	if node is FishTrap:          return "FishTrap"
	if node is House:             return "House"
	if node is LumberCamp:        return "LumberCamp"
	if node is MiningCamp:        return "MiningCamp"
	if node is WallSegment:       return "WallSegment"
	if node is Gate:              return "Gate"
	return ""

func _v2(v: Vector2) -> Array:
	return [v.x, v.y]

func _float_or(val: Variant, default_val: float) -> float:
	return (val as float) if val != null else default_val

func _int_or(val: Variant, default_val: int) -> int:
	return (val as int) if val != null else default_val

func _vec_or(val: Variant, default_val: Vector2) -> Vector2:
	return (val as Vector2) if val != null else default_val

func _find_fog(world: Node) -> FogOfWar:
	for child: Node in world.get_children():
		if child is FogOfWar:
			return child as FogOfWar
	return null

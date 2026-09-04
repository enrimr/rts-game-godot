extends Node

## SaveManager — serialises and restores a complete game snapshot.
## Saves are stored in user://saves/save_NN.json (NN = 01..99).
## Restoration happens in two phases:
##   1. game_world._ready() regenerates the same map (same RNG seed) but
##      skips fresh spawning, then calls SaveManager.restore_world().
##   2. All autoloads (resources, ages, techs, pop) are restored here, then
##      all units, buildings and resource nodes are re-created from save data.

const SAVE_DIR: String  = "user://saves/"
const MAX_SLOTS: int    = 99
## v2: research queues, garrisons (buildings + transports), stances, weather.
## Older saves load with defaults for the new keys; NEWER schemas are refused.
const SCHEMA_VERSION: int = 2

# When true, game_world skips fresh spawning and calls restore_world() instead.
var pending_load: bool = false
var _save_data: Dictionary = {}

## Campaign state of the loaded save (mission index + director runtime).
## Kept out of _save_data so it survives restore_world; the MissionDirector
## consumes it when it mounts (it mounts after restore_world).
var _restored_campaign: Dictionary = {}

## Multiplayer sheet of the loaded save ({"humans": [...], "roster": {...}}),
## empty for single-player saves. Kept out of _save_data so it survives
## restore_world — the resume lobby and later rejoins read it all match long.
var _resume_sheet: Dictionary = {}
## Per-player explored fog of the loaded save: pid (String) -> raw base64.
var _resume_fog: Dictionary = {}

## One entry per existing save, sorted newest-first.
## Each dict: { slot, display_name, timestamp, civ, map_type, play_time_sec }
func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if fname.begins_with("save_") and fname.ends_with(".json"):
			var slot_str: String = fname.trim_prefix("save_").trim_suffix(".json")
			if slot_str.is_valid_int():
				var meta: Dictionary = _read_meta(SAVE_DIR + fname)
				if not meta.is_empty():
					meta["slot"] = slot_str.to_int()
					result.append(meta)
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("timestamp", 0) as int) > (b.get("timestamp", 0) as int))
	return result

func has_any_save() -> bool:
	return not list_saves().is_empty()

## Kept for backwards compatibility — returns true if any slot exists.
func has_save() -> bool:
	return has_any_save()

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "save_%02d.json" % slot

func _next_free_slot() -> int:
	for i: int in range(1, MAX_SLOTS + 1):
		if not FileAccess.file_exists(_slot_path(i)):
			return i
	return 1   # overwrite slot 1 if all full

func _read_meta(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var txt: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed as Dictionary
	var mc: Dictionary = d.get("match_config", {}) as Dictionary
	var mp: Dictionary = d.get("multiplayer", {}) as Dictionary
	var names: Array = []
	for entry: Variant in (mp.get("roster", {}) as Dictionary).values():
		names.append(str((entry as Dictionary).get("name", "?")))
	return {
		"display_name": str(d.get("display_name", "")),
		"timestamp":    d.get("timestamp", 0) as int,
		"civ":          str(mc.get("player_civ_id", "?")),
		"map_type":     mc.get("map_type", 0) as int,
		"play_time_sec":d.get("play_time_sec", 0) as int,
		"multiplayer":  not mp.is_empty(),
		"player_names": names,
	}

func save_game(world: Node, slot: int = -1) -> bool:
	if slot < 1:
		slot = _next_free_slot()
	# Each client's explored fog lives on its machine only — gather it first
	# so a multiplayer save can restore every player's map, not just the host's.
	if NetworkSession.is_host() and NetworkSession.is_online():
		await NetworkSession.collect_client_fogs()
	var data: Dictionary = _collect(world)
	data["timestamp"]    = int(Time.get_unix_time_from_system())
	data["display_name"] = _make_display_name(data)
	var json: String = JSON.stringify(data, "\t")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open slot %d for writing" % slot)
		return false
	file.store_string(json)
	file.close()
	return true

func _make_display_name(data: Dictionary) -> String:
	var mc: Dictionary = data.get("match_config", {}) as Dictionary
	var civ: String = str(mc.get("player_civ_id", "?")).capitalize()
	var ts: int = data.get("timestamp", 0) as int
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%s — %02d/%02d %02d:%02d" % [
		civ, dt.get("day", 0), dt.get("month", 0),
		dt.get("hour", 0), dt.get("minute", 0)]

func load_game(slot: int) -> bool:
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_error("SaveManager: corrupt save in slot %d" % slot)
		return false
	var schema: int = int((parsed as Dictionary).get("schema_version", 1) as float)
	if schema > SCHEMA_VERSION:
		push_error("SaveManager: slot %d uses save schema %d but this build only supports up to %d — update the game to load it" % [slot, schema, SCHEMA_VERSION])
		return false
	_save_data = parsed as Dictionary
	_resume_sheet = (_save_data.get("multiplayer", {}) as Dictionary).duplicate(true)
	_resume_fog = (_save_data.get("fog_by_player", {}) as Dictionary).duplicate()
	_restored_campaign = (_save_data.get("campaign", {}) as Dictionary).duplicate(true)
	pending_load = true
	_restore_match_config(_save_data)
	return true

## One-shot: the MissionDirector takes the restored campaign runtime when it
## mounts (after restore_world), empty for non-campaign saves.
func consume_campaign_state() -> Dictionary:
	var out: Dictionary = _restored_campaign
	_restored_campaign = {}
	return out

## Backs out of a load that will not happen (e.g. a cancelled resume lobby).
func cancel_pending() -> void:
	pending_load = false
	_save_data = {}
	_resume_sheet = {}
	_resume_fog = {}
	_restored_campaign = {}

func resume_sheet() -> Dictionary:
	return _resume_sheet

## One player's saved exploration, zstd+base64 for the resync wire ("" when
## the save carries none for that seat).
func resume_fog_b64(pid: int) -> String:
	var raw_b64: Variant = _resume_fog.get(str(pid))
	if raw_b64 == null:
		return ""
	var raw: PackedByteArray = Marshalls.base64_to_raw(str(raw_b64))
	if raw.is_empty():
		return ""
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))

func delete_save(slot: int) -> void:
	var path: String = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

const UNIT_SCENES: Dictionary = {
	"Villager":      "res://scenes/units/villager.tscn",
	"Militia":       "res://scenes/units/militia.tscn",
	"HeroUnit":      "res://scenes/units/militia.tscn",
	"Scout":         "res://scenes/units/scout.tscn",
	"Archer":        "res://scenes/units/archer.tscn",
	"Pikeman":       "res://scenes/units/pikeman.tscn",
	"HeavyScout":    "res://scenes/units/heavy_scout.tscn",
	"Knight":        "res://scenes/units/knight.tscn",
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
	"Blacksmith":    "res://scenes/buildings/blacksmith.tscn",
	"Stable":        "res://scenes/buildings/stable.tscn",
	"LumberCamp":    "res://scenes/buildings/lumber_camp.tscn",
	"MiningCamp":    "res://scenes/buildings/mining_camp.tscn",
	"Farm":          "res://scenes/buildings/farm.tscn",
	"WallSegment":   "res://scenes/buildings/wall_segment.tscn",
	"Gate":          "res://scenes/buildings/gate.tscn",
	"Dock":          "res://scenes/buildings/dock.tscn",
	"FishTrap":      "res://scenes/buildings/fish_trap.tscn",
	"University":    "res://scenes/buildings/university.tscn",
	"Market":        "res://scenes/buildings/market.tscn",
	"Temple":        "res://scenes/buildings/temple.tscn",
	"Wonder":        "res://scenes/buildings/wonder.tscn",
}

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
	_restore_match_rng(_save_data)
	WeatherManager.apply_saved_state(_save_data.get("weather", {}) as Dictionary)
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
		"victory_mode":  MatchConfig.victory_mode,
		"player_teams":  MatchConfig.player_teams.duplicate(),
		"weather_enabled":   MatchConfig.weather_enabled,
		"weather_frequency": MatchConfig.weather_frequency,
		"hero_gender":       MatchConfig.hero_gender,
	}

	# Campaign missions: without this a reloaded mission silently became a
	# plain skirmish — no objectives, no waves, no survive timer, no progress.
	if MatchConfig.campaign_mission >= 0:
		var camp: Dictionary = {"mission": MatchConfig.campaign_mission}
		var director: Node = world.get_node_or_null("MissionDirector")
		if director != null:
			camp["elapsed"] = director.get("_elapsed") as float
			camp["survive_left"] = director.get("_survive_left") as float
			camp["objectives"] = (director.call("objectives") as Array).duplicate(true)
		data["campaign"] = camp

	# Multiplayer sheet: who sat where, so the match can be resumed with the
	# SAME players (seats matched by Steam ID or name in the resume lobby).
	if NetworkSession.is_host() and NetworkSession.is_online():
		var seats: Dictionary = NetworkSession.seat_snapshot()
		var roster_out: Dictionary = {}
		for spid: Variant in seats:
			var entry: Dictionary = (seats[spid] as Dictionary).duplicate()
			entry.erase("peer")
			roster_out[str(spid)] = entry
		data["multiplayer"] = {
			"humans": NetworkSession.match_human_ids.duplicate(),
			"roster": roster_out,
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
	# Garrisoned units stay in the tree (hidden, processing off): the sweep must
	# skip them or they duplicate as free-standing units at their pre-boarding
	# spot — they are saved NESTED under their holder instead.
	var garrisoned: Dictionary = _garrisoned_unit_ids(world)
	if units_layer != null:
		for unit: Node in units_layer.get_children():
			if not is_instance_valid(unit):
				continue
			if garrisoned.has(unit.get_instance_id()):
				continue
			var u: Dictionary = _collect_unit(unit)
			if not u.is_empty():
				units_arr.append(u)
	data["units"] = units_arr

	# Player TC is saved separately — it always exists as DropOffNode in the scene
	# and doesn't need a class check.
	var drop_off: Node = world.get_node_or_null("DropOffNode")
	if is_instance_valid(drop_off):
		var tc_state: Dictionary = _collect_tc_state(drop_off)
		# Use the authoritatively stored TC position (set from map_data at spawn time)
		# to avoid capturing a stale or camera-influenced position.
		var stored_pos: Variant = world.get("_saved_tc_position")
		if stored_pos != null and (stored_pos as Vector2) != Vector2.ZERO:
			tc_state["position"] = _v2(stored_pos as Vector2)
		data["player_tc"] = tc_state

	var buildings_arr: Array = []
	# Research is keyed by instance id in TechManager, which does not survive a
	# load: map each researching building to its INDEX in the saved array (the
	# restore rebuilds the same array in the same order), "tc" for the scene TC.
	var research_keys: Dictionary = {}
	if is_instance_valid(drop_off):
		research_keys[drop_off.get_instance_id()] = "tc"
	var buildings_layer: Node = world.get_node_or_null("BuildingsLayer")
	if buildings_layer != null:
		for bld: Node in buildings_layer.get_children():
			if not is_instance_valid(bld):
				continue
			var b: Dictionary = _collect_building(bld, "")
			if not b.is_empty():
				research_keys[bld.get_instance_id()] = str(buildings_arr.size())
				buildings_arr.append(b)
	data["buildings"] = buildings_arr
	data["research"] = TechManager.collect_state(research_keys)
	data["weather"] = WeatherManager.collect_state()

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
		# Client fogs were collected (compressed) just before _collect ran;
		# store them raw-base64, same encoding as the host's fog_cells.
		if NetworkSession.is_host() and NetworkSession.is_online():
			var by_player: Dictionary = {}
			for fpid: Variant in NetworkSession.client_fogs:
				var cells: PackedByteArray = NetworkSession.fog_cells_from_b64(
					NetworkSession.client_fogs[fpid] as String, fog._cells.size())
				if not cells.is_empty():
					by_player[str(fpid)] = Marshalls.raw_to_base64(cells)
			data["fog_by_player"] = by_player

	# As a String: the RNG state is a full 64-bit value and JSON numbers are
	# doubles, so a raw int would silently lose the low bits.
	data["match_rng_state"] = str(MatchRng.get_state())

	return data

func _collect_tc_state(tc: Node) -> Dictionary:
	var d: Dictionary = {
		"health":      _float_or(tc.get("health"), 2000.0),
		"max_health":  _float_or(tc.get("max_health"), 2000.0),
		"rally_point": _v2(_vec_or(tc.get("rally_point"), Vector2.ZERO)),
		"position":    _v2((tc as Node2D).global_position),
	}
	if tc.has_method("get_garrison"):
		var g: Array = []
		for occupant: Variant in tc.call("get_garrison") as Array:
			if occupant is Node and is_instance_valid(occupant as Node):
				var rec: Dictionary = _collect_unit(occupant as Node)
				if not rec.is_empty():
					g.append(rec)
		if not g.is_empty():
			d["garrison"] = g
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
	# The true scene beats the class table: `is`-checks degraded every unique
	# unit to its base class on load (a Menceyes Guard came back a Militia),
	# and anything OUTSIDE the table — all siege, the Harimaguada, the Presa
	# Canario — was silently DROPPED from the save.
	var scene: String = unit.scene_file_path
	if cn.is_empty() and scene.is_empty():
		return {}
	var u: Dictionary = {
		"class":     cn,
		"scene":     scene,
		"position":  _v2((unit as Node2D).global_position),
		"player_id": unit.get("player_id") as int,
		"civ_id":    str(unit.get("civ_id")) if unit.get("civ_id") != null else "",
		"health":    unit.get("health") as float,
		# Animals don't extend UnitBase and carry no gender — `null as bool`
		# aborts the whole collect and silently DROPS the animal from the save.
		"is_female": unit.get("is_female") == true,
	}
	if unit is HeroUnit:
		# Through the source-path accessor: stat-mutating duplicates (Quijote's
		# Rocinante) wipe unit_data.resource_path and would break the restore.
		u["unit_data_path"] = str(unit.call("data_source_path"))
		u["cooldown_remaining"] = unit.get("_cooldown_remaining") as float
	if unit is Villager:
		u["carried_resource"] = str(unit.get("carried_resource"))
		u["carried_amount"]   = unit.get("carried_amount") as float
	var stance_v: Variant = unit.get("stance")
	if stance_v != null:
		u["stance"] = stance_v as int
	if unit.has_method("get_garrison"):
		var passengers: Array = _collect_garrison(unit)
		if not passengers.is_empty():
			u["garrison"] = passengers
	return u

## Nested unit records for a holder's occupants (transport ship or building):
## excluded from the free-unit sweep, restored back INSIDE the holder.
func _collect_garrison(holder: Node) -> Array:
	var out: Array = []
	for occupant: Variant in holder.call("get_garrison") as Array:
		if occupant is Node and is_instance_valid(occupant as Node):
			var rec: Dictionary = _collect_unit(occupant as Node)
			if not rec.is_empty():
				out.append(rec)
	return out

## Instance ids of every unit currently sheltered in a building or transport.
func _garrisoned_unit_ids(world: Node) -> Dictionary:
	var ids: Dictionary = {}
	# The scene TC lives outside both layers — without this, its occupants
	# duplicated as free units AND its garrison was never saved.
	var tc: Variant = world.get("drop_off")
	if tc is Node and is_instance_valid(tc as Node) and (tc as Node).has_method("get_garrison"):
		for occupant: Variant in (tc as Node).call("get_garrison") as Array:
			if occupant is Node and is_instance_valid(occupant as Node):
				ids[(occupant as Node).get_instance_id()] = true
	for layer_name: String in ["BuildingsLayer", "UnitsLayer"]:
		var layer: Node = world.get_node_or_null(layer_name)
		if layer == null:
			continue
		for holder: Node in layer.get_children():
			if not is_instance_valid(holder) or not holder.has_method("get_garrison"):
				continue
			for occupant: Variant in holder.call("get_garrison") as Array:
				if occupant is Node and is_instance_valid(occupant as Node):
					ids[(occupant as Node).get_instance_id()] = true
	return ids

func _collect_building(bld: Node, role: String) -> Dictionary:
	var cn: String = _class_name_of(bld)
	# Same scene-beats-table rule as units: the Mill (and any future
	# building) must survive a save without a table entry.
	var scene: String = bld.scene_file_path
	if cn.is_empty() and scene.is_empty():
		return {}
	var b: Dictionary = {
		"class":                 cn,
		"scene":                 scene,
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
	if bld.has_method("get_garrison"):
		var occupants: Array = _collect_garrison(bld)
		if not occupants.is_empty():
			b["garrison"] = occupants
	return b

# ── Restoration ──────────────────────────────────────────────────────────────

func _restore_match_config(data: Dictionary) -> void:
	# Campaign flag first — BEFORE the empty-config early return: any loaded
	# save without campaign data must clear a stale index from a previous
	# session, or a skirmish would mount a MissionDirector. Tutorial-prologue
	# saves also load as plain matches (overlay mid-state is not persisted).
	var camp: Dictionary = data.get("campaign", {}) as Dictionary
	var mission_index: int = camp.get("mission", -1) as int
	if mission_index >= 0 and (CampaignData.mission(mission_index).get("tutorial", false) as bool):
		mission_index = -1
	MatchConfig.campaign_mission = mission_index
	MatchConfig.launch_tutorial = false
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
	MatchConfig.victory_mode = mc.get("victory_mode", MatchConfig.victory_mode) as int
	MatchConfig.weather_enabled   = mc.get("weather_enabled", MatchConfig.weather_enabled) as bool
	MatchConfig.weather_frequency = mc.get("weather_frequency", MatchConfig.weather_frequency) as int
	MatchConfig.hero_gender       = mc.get("hero_gender", MatchConfig.hero_gender) as int
	MatchConfig.player_teams.clear()
	var teams: Variant = mc.get("player_teams")
	if teams is Dictionary:
		for key: Variant in teams as Dictionary:
			MatchConfig.player_teams[int(str(key))] = int((teams as Dictionary)[key] as float)

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
		_restore_unit_record(units_layer, entry as Dictionary)

## One saved unit record → a live unit, including a transport's nested
## passengers (boarded back in, never spilled as free units at sea).
func _restore_unit_record(units_layer: Node, u: Dictionary) -> Node2D:
	var unit: Node2D = _spawn_saved_unit(units_layer, u)
	if unit == null:
		return null
	for grec: Variant in (u.get("garrison", []) as Array):
		var passenger: Node2D = _spawn_saved_unit(units_layer, grec as Dictionary)
		if passenger != null and unit.has_method("board"):
			unit.call("board", passenger)
	return unit

func _spawn_saved_unit(units_layer: Node, u: Dictionary) -> Node2D:
	var cn: String = str(u.get("class", ""))
	var scene_path: String = str(u.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		scene_path = UNIT_SCENES.get(cn, "") as String
	if cn == "HeroUnit":
		# Mounted heroes (Quijote on Rocinante) restore onto their mount rig.
		scene_path = HeroDress.scene_path_for(str(u.get("unit_data_path", "")))
	if scene_path.is_empty():
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
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
	# Set before add_child so _ready (which runs on enter) doesn't re-roll it.
	unit.set("is_female", u.get("is_female", false) as bool)
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
	var stance_v: Variant = u.get("stance")
	if stance_v != null and unit.has_method("set_stance"):
		unit.call("set_stance", int(stance_v as float))
	PopulationManager.add_unit(pid)
	EventBus.unit_spawned.emit(unit, pid)
	return unit

func _restore_buildings(world: Node, data: Dictionary) -> void:
	var buildings_layer: Node = world.get_node_or_null("BuildingsLayer")
	var drop_off: Node        = world.get_node_or_null("DropOffNode")
	var units_layer: Node     = world.get_node_or_null("UnitsLayer")
	# Save-side research keys → restored nodes (same array, same order).
	var research_buildings: Dictionary = {}
	if is_instance_valid(drop_off):
		research_buildings["tc"] = drop_off

	# Restore player TC from its dedicated key
	var tc_data: Variant = data.get("player_tc")
	if tc_data != null and is_instance_valid(drop_off):
		var tcd: Dictionary = tc_data as Dictionary
		if tcd.has("position"):
			var pos_arr: Array = tcd.get("position") as Array
			(drop_off as Node2D).global_position = Vector2(pos_arr[0] as float, pos_arr[1] as float)
		_apply_tc_state(drop_off, tcd)

	# Remove buildings spawned by _setup_ai_node_only (the AI TCs)
	if buildings_layer != null:
		for child: Node in buildings_layer.get_children().duplicate():
			child.queue_free()

	var saved_buildings: Array = data.get("buildings", []) as Array
	for index: int in range(saved_buildings.size()):
		var b: Dictionary = saved_buildings[index] as Dictionary
		var cn: String   = str(b.get("class", ""))

		var scene_path: String = str(b.get("scene", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			scene_path = BUILDING_SCENES.get(cn, "") as String
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
		research_buildings[str(index)] = bld
		_apply_building_state(bld, b, units_layer)
	# Re-arm active research and queues — paid at enqueue, never charged again.
	TechManager.restore_state(data.get("research", {}) as Dictionary, research_buildings)

func _apply_building_state(bld: Node, b: Dictionary, units_layer: Node = null) -> void:
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
	# State lands AFTER _ready and construction_complete never fires on a
	# restore, so a loaded camp/dock/mill missed its drop-off registration —
	# villagers in loaded games hauled everything back to the TC.
	if st == BuildingBase.BuildingState.COMPLETE and bld.has_method("_register_drop_off"):
		var has_drop: bool = false
		for c: Node in bld.get_children():
			if c is DropOffBuilding:
				has_drop = true
				break
		if not has_drop:
			bld.call("_register_drop_off")

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

	# Garrison LAST: state is already COMPLETE (can_garrison_unit's gate). On a
	# failed re-entry the occupant simply stands free at its saved position.
	if units_layer != null and bld.has_method("garrison_unit"):
		for grec: Variant in (b.get("garrison", []) as Array):
			var occupant: Node2D = _spawn_saved_unit(units_layer, grec as Dictionary)
			if occupant != null:
				bld.call("garrison_unit", occupant)

func _apply_tc_state(tc: Node, d: Dictionary) -> void:
	var hp: float = d.get("health", -1.0) as float
	if hp >= 0.0:
		tc.set("health", hp)
	var mhp: float = d.get("max_health", -1.0) as float
	if mhp >= 0.0:
		tc.set("max_health", mhp)
	var rp_arr: Array = d.get("rally_point", [0.0, 0.0]) as Array
	var rp: Vector2 = Vector2(rp_arr[0] as float, rp_arr[1] as float)
	if rp != Vector2.ZERO and tc.has_method("set_rally_point"):
		tc.call("set_rally_point", rp)
	if tc.has_method("garrison_unit"):
		var units_layer: Node = (tc.get_parent() as Node).get_node_or_null("UnitsLayer") \
			if tc.get_parent() != null else null
		if units_layer != null:
			for grec: Variant in (d.get("garrison", []) as Array):
				var occupant: Node2D = _spawn_saved_unit(units_layer, grec as Dictionary)
				if occupant != null:
					tc.call("garrison_unit", occupant)
	var queue_arr: Variant = d.get("train_queue")
	if queue_arr != null and tc.has_method("get_queue"):
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
		tc.set("_train_queue", train_q)
		tc.set("_train_timer", d.get("train_timer", 0.0) as float)

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
		ResourceVisuals.create_resource_node(world as Node2D, pos, rtype, initial, rng, res_script)
		# _ready() ran synchronously; override remaining amount on the just-added node
		var rn: Node = world.get_children().back()
		if rn is ResourceNode:
			rn.set("remaining_amount", rnd.get("remaining_amount", initial) as float)

## Restores the simulation RNG mid-match state (game_world already re-seeded
## MatchRng from the stored seed; this fast-forwards it to where the save left
## off). Old saves without the key keep the fresh seed — same as before.
func _restore_match_rng(data: Dictionary) -> void:
	var state: Variant = data.get("match_rng_state")
	if state is String and (state as String).is_valid_int():
		MatchRng.set_state((state as String).to_int())

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
		fog.mark_all_dirty()

# ── Helpers ──────────────────────────────────────────────────────────────────

func _class_name_of(node: Node) -> String:
	if node is HeroUnit:          return "HeroUnit"
	if node is Villager:          return "Villager"
	if node is Militia:           return "Militia"
	if node is Archer:            return "Archer"
	if node is Pikeman:           return "Pikeman"
	if node is Scout:             return "Scout"
	if node is HeavyScout:        return "HeavyScout"
	if node is Knight:            return "Knight"
	if node is WarGalley:         return "WarGalley"
	if node is FishingBoat:       return "FishingBoat"
	if node is TransportShip:     return "TransportShip"
	if node is Sheep:             return "Sheep"
	if node is Animal:            return "Animal"
	if node is TownCenter:        return "TownCenter"
	if node is TownCenterBuilding:return "TownCenterBuilding"
	if node is Barracks:          return "Barracks"
	if node is Blacksmith:        return "Blacksmith"
	if node is Stable:            return "Stable"
	if node is University:        return "University"
	if node is Market:            return "Market"
	if node is Temple:            return "Temple"
	if node is Wonder:            return "Wonder"
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

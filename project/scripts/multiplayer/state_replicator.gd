class_name StateReplicator extends Node

## Multiplayer phase 2 — host→client state replication. The HOST samples the
## authoritative simulation every SNAPSHOT_TICKS physics ticks and ships it by
## EntityRegistry ID; a CLIENT turns its mirror world into puppets (physics
## processing off — no local simulation, no local damage) and interpolates
## them between snapshots. Spawns/removals and the match outcome travel on the
## reliable channel; the dense position/HP stream is unreliable-ordered.
##
## GameWorld adds this node only when NetworkSession.is_online().

const SNAPSHOT_TICKS: int = 4   # 60 Hz physics → 15 snapshots/s
const PUPPET_META: StringName = &"rep_puppet"

var _world = null   # GameWorld — untyped so dynamic access works
var _units_layer: Node = null
var _buildings_layer: Node = null
var _tick: int = 0
var _interval: float = float(SNAPSHOT_TICKS) / float(Engine.physics_ticks_per_second)

# Host: ids already introduced to the clients (removal detection).
var _announced: Dictionary = {}
# Host: the ids alive at match start — a rejoiner boots exactly this world,
# so its resync is removals(initial−alive) + spawns(alive−initial) + keyframe.
var _initial_ids: Dictionary = {}
# Host: arrows fired since the last snapshot (visual echo for clients).
var _fx_buffer: Array = []
# Host: last row sent per entity id — deltas skip unchanged entities.
var _last_sent: Dictionary = {}
# Host: last per-player meta (stockpiles/pop/ages/weather) sent.
var _last_meta: Dictionary = {}
# Every SLOW_EVERY-th snapshot carries the slow extras (resources left,
# researched techs) — they change on the seconds scale, not at 15 Hz.
const SLOW_EVERY: int = 15
# Deltas encoding beyond this ride the reliable channel (ENet MTU is 1392).
const MTU_SAFE_BYTES: int = 1300
var _snapshot_count: int = 0
# Client: id -> {"a": Vector2, "b": Vector2, "t": float} interpolation spans.
var _spans: Dictionary = {}

const ARROW_SCENE: PackedScene = preload("res://scenes/combat/arrow.tscn")

func setup(world) -> void:
	_world = world
	_units_layer = world.units_layer
	_buildings_layer = world.buildings_layer
	if NetworkSession.is_client():
		NetworkSession.state_received.connect(_on_state)
		NetworkSession.events_received.connect(_on_events)
		_puppet_existing_world()
		if NetworkSession.rejoin_pending:
			# We joined a match already in progress: the freshly generated
			# start-of-match world must be fast-forwarded by the host.
			NetworkSession.rejoin_pending = false
			NetworkSession.notify_resync_ready()
	else:
		GameManager.game_over.connect(func(winner_id: int) -> void:
			NetworkSession.send_events({"over": winner_id}))
		GameManager.game_paused.connect(func(paused: bool) -> void:
			NetworkSession.notify_pause(paused))
		EventBus.ally_message.connect(func(pid: int, msg_kind: String) -> void:
			NetworkSession.send_events({"amsg": [pid, msg_kind]}))
		EventBus.projectile_spawned.connect(func(start: Vector2, target_pos: Vector2, kind: int) -> void:
			_fx_buffer.append([start.x, start.y, target_pos.x, target_pos.y, kind]))
		_seed_announced()
		_initial_ids = _announced.duplicate()
		if NetworkSession.resumed_match:
			# A restored world shares NO deterministic baseline with the fresh
			# world a client boots: the resync must ship EVERYTHING. The shared
			# scene TC is the sole survivor — the registry rescan hands it the
			# same id on both ends (it is registered first).
			_initial_ids = {}
			var tc: Variant = _world.get("drop_off")
			if tc is Node and is_instance_valid(tc as Node):
				_initial_ids[EntityRegistry.id_of(tc as Node)] = true
		NetworkSession.peer_resync_requested.connect(full_resync_to)

## Both machines boot the identical initial world (same seed → same ids), so
## everything alive at match start needs no spawn record — only removals.
func _seed_announced() -> void:
	for node: Node in _units_layer.get_children():
		if is_instance_valid(node):
			_announced[EntityRegistry.id_of(node)] = true
	for node: Node in _buildings_layer.get_children():
		if is_instance_valid(node):
			_announced[EntityRegistry.id_of(node)] = true
	var drop_off: Variant = _world.get("drop_off")
	if drop_off is Node and is_instance_valid(drop_off as Node):
		_announced[EntityRegistry.id_of(drop_off as Node)] = true
	for node: Node in (_world as Node).get_children():
		if node is ResourceNode:
			_announced[EntityRegistry.id_of(node)] = true

func _exit_tree() -> void:
	if NetworkSession.is_client():
		if NetworkSession.state_received.is_connected(_on_state):
			NetworkSession.state_received.disconnect(_on_state)
		if NetworkSession.events_received.is_connected(_on_events):
			NetworkSession.events_received.disconnect(_on_events)
	elif NetworkSession.peer_resync_requested.is_connected(full_resync_to):
		NetworkSession.peer_resync_requested.disconnect(full_resync_to)

## HOST → one rejoined player: fast-forward its start-of-match mirror world
## to the present, all on the reliable channel (order matters: removals of
## dead initial entities, spawn records for everything born since, then a
## full keyframe with positions/HP/queues/meta).
func full_resync_to(player_id: int) -> void:
	var removes: Array = []
	for id: Variant in _initial_ids:
		if not _announced.has(id):
			removes.append(id)
	var spawns: Array = []
	for id: Variant in _announced:
		if _initial_ids.has(id):
			continue
		var node: Node = EntityRegistry.resolve(id as int)
		if node == null:
			continue
		var kind: String = "u"
		if node is ResourceNode:
			kind = "r"
		elif node.get_parent() == _buildings_layer:
			kind = "b"
		spawns.append(_spawn_record(node, id as int, kind))
	var units: Array = []
	for node: Node in _units_layer.get_children():
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var st: int = node.get("current_state") as int if node.get("current_state") != null else 0
		units.append([EntityRegistry.id_of(node),
			(node as Node2D).global_position.x, (node as Node2D).global_position.y,
			st, node.get("health") as float if node.get("health") != null else 0.0])
	var buildings: Array = []
	var bld_nodes: Array = _buildings_layer.get_children()
	var drop_off: Variant = _world.get("drop_off")
	if drop_off is Node and is_instance_valid(drop_off as Node):
		bld_nodes.append(drop_off)
	for node: Variant in bld_nodes:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var row: Array = [EntityRegistry.id_of(node as Node), (node as Node).get("health") as float,
			(node as Node).get("state") as int if (node as Node).get("state") != null else 0]
		var extras: Dictionary = _building_extras(node as Node)
		if not extras.is_empty():
			row.append(extras)
		buildings.append(row)
	var payload: Dictionary = {
		"spawn": spawns,
		"remove": removes,
		"u": units,
		"b": buildings,
		"res": _stockpiles(),
		"pop": _populations(),
		"age": _ages(),
		"w": [WeatherManager.current_weather as int, WeatherManager.intensity,
			WeatherManager._phase, WeatherManager._pending_weather as int,
			WeatherManager._wind_dir],
		"rn": _resource_nodes(),
		"tech": _researched_lists(),
	}
	# Resumed match: the save carries this seat's explored map — restore it so
	# the player comes back to what they had scouted, AoE2 style.
	if NetworkSession.resumed_match:
		var fog_b64: String = SaveManager.resume_fog_b64(player_id)
		if not fog_b64.is_empty():
			payload["fog"] = fog_b64
	NetworkSession.send_events_to(player_id, payload)

# ── Host side ────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if not NetworkSession.is_host():
		return
	_tick += 1
	if _tick % SNAPSHOT_TICKS != 0:
		return
	_host_snapshot()

func _host_snapshot() -> void:
	var units: Array = []
	var buildings: Array = []
	var spawns: Array = []
	for node: Node in _units_layer.get_children():
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var id: int = EntityRegistry.id_of(node)
		if not _announced.has(id):
			_announced[id] = true
			spawns.append(_spawn_record(node, id, "u"))
		var st: int = node.get("current_state") as int if node.get("current_state") != null else 0
		units.append([id, (node as Node2D).global_position.x, (node as Node2D).global_position.y,
			st, node.get("health") as float if node.get("health") != null else 0.0])
	var bld_nodes: Array = _buildings_layer.get_children()
	var drop_off: Variant = _world.get("drop_off")
	if drop_off is Node and is_instance_valid(drop_off as Node):
		bld_nodes.append(drop_off)
	for node: Variant in bld_nodes:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var id: int = EntityRegistry.id_of(node as Node)
		if not _announced.has(id):
			_announced[id] = true
			spawns.append(_spawn_record(node as Node, id, "b"))
		var row: Array = [id, (node as Node).get("health") as float,
			(node as Node).get("state") as int if (node as Node).get("state") != null else 0]
		var extras: Dictionary = _building_extras(node as Node)
		if not extras.is_empty():
			row.append(extras)
		buildings.append(row)
	var removes: Array = []
	for id: Variant in _announced.keys():
		if EntityRegistry.resolve(id as int) == null:
			removes.append(id)
			_last_sent.erase(id)
			_announced.erase(id)
	if not spawns.is_empty() or not removes.is_empty():
		NetworkSession.send_events({"spawn": spawns, "remove": removes})
	_snapshot_count += 1
	var keyframe: bool = _snapshot_count % SLOW_EVERY == 1
	var snapshot: Dictionary = {}
	# Per-player meta and weather only travel when they changed (or in a
	# keyframe) — they were half of every delta packet.
	var meta: Dictionary = {
		"res": _stockpiles(),
		"pop": _populations(),
		"age": _ages(),
		"w": [WeatherManager.current_weather as int, WeatherManager.intensity,
			WeatherManager._phase, WeatherManager._pending_weather as int,
			WeatherManager._wind_dir],
	}
	for key: String in meta:
		if keyframe or _last_meta.get(key) != meta[key]:
			snapshot[key] = meta[key]
			_last_meta[key] = meta[key]
	if keyframe:
		snapshot["u"] = units
		snapshot["b"] = buildings
		for row: Variant in units + buildings:
			_last_sent[(row as Array)[0] as int] = row
	else:
		# Delta: only rows that changed since the last send. Idle armies cost
		# nothing and the packet stays under the ENet MTU; a keyframe on the
		# reliable channel heals whatever unreliable deltas lost.
		snapshot["u"] = _changed_rows(units)
		snapshot["b"] = _changed_rows(buildings)
	if not _fx_buffer.is_empty():
		snapshot["fx"] = _fx_buffer
		_fx_buffer = []
	if keyframe:
		snapshot["rn"] = _resource_nodes()
		snapshot["tech"] = _researched_lists()
		NetworkSession.send_events(snapshot)
	elif var_to_bytes(snapshot).size() > MTU_SAFE_BYTES:
		# A big battle moves everything at once: route the oversized delta
		# through the reliable channel, which fragments safely (an unreliable
		# packet above the ENet MTU is mostly packet loss).
		NetworkSession.send_events(snapshot)
	else:
		NetworkSession.send_state(snapshot)

func _changed_rows(rows: Array) -> Array:
	var out: Array = []
	for row: Variant in rows:
		var id: int = (row as Array)[0] as int
		if _last_sent.get(id) != row:
			_last_sent[id] = row
			out.append(row)
	return out

## Production queue + active research + market rates ride the building row so
## the client HUD shows the truth when this building is selected.
func _building_extras(node: Node) -> Dictionary:
	var extras: Dictionary = {}
	if node.has_method("get_queue"):
		var q: Array = node.call("get_queue") as Array
		if not q.is_empty() or node.get("_train_timer") != null:
			extras["q"] = q
			extras["t"] = node.get("_train_timer") as float
	var research: Variant = TechManager._active_research.get(node.get_instance_id())
	if research is Dictionary:
		extras["r"] = [(research as Dictionary)["tech_id"],
			(research as Dictionary)["timer"], (research as Dictionary)["total_time"]]
	if node.get("_sell_offsets") != null:
		extras["so"] = node.get("_sell_offsets")
		extras["bo"] = node.get("_buy_offsets")
	return extras

func _resource_nodes() -> Array:
	var out: Array = []
	for node: Node in (_world as Node).get_children():
		if node is ResourceNode and is_instance_valid(node):
			out.append([EntityRegistry.id_of(node), node.get("remaining_amount") as float])
	return out

func _researched_lists() -> Dictionary:
	var out: Dictionary = {}
	out[0] = TechManager.get_researched(0)
	for pid: int in MatchConfig.get_rival_player_ids():
		out[pid] = TechManager.get_researched(pid)
	return out

func _spawn_record(node: Node, id: int, kind: String) -> Dictionary:
	var rec: Dictionary = {
		"i": id,
		"k": kind,
		"s": node.scene_file_path,
		"p": node.get("player_id") as int if node.get("player_id") != null else -1,
		"x": (node as Node2D).global_position.x,
		"y": (node as Node2D).global_position.y,
	}
	if kind == "r":
		rec["rt"] = node.get("resource_type") as int
		rec["a"] = node.get("initial_amount") as float
		return rec
	var script: Script = node.get_script() as Script
	if script != null:
		rec["c"] = script.resource_path
	var civ: Variant = node.get("civ_id")
	if civ is String and not (civ as String).is_empty():
		rec["v"] = civ
	if node.has_method("data_source_path"):
		# Heroes: survives Rocinante's stat-mutating duplicate (empty path).
		var dsp: String = str(node.call("data_source_path"))
		if not dsp.is_empty():
			rec["d"] = dsp
	else:
		var udata: Variant = node.get("unit_data")
		if udata is Resource and not (udata as Resource).resource_path.is_empty():
			rec["d"] = (udata as Resource).resource_path
	var female: Variant = node.get("is_female")
	if female is bool:
		rec["f"] = female
	return rec

func _stockpiles() -> Dictionary:
	var out: Dictionary = {}
	out[0] = ResourceManager.get_resources(0).duplicate()
	for pid: int in MatchConfig.get_rival_player_ids():
		out[pid] = ResourceManager.get_resources(pid).duplicate()
	return out

func _populations() -> Dictionary:
	var out: Dictionary = {}
	out[0] = PopulationManager.get_population(0).duplicate()
	for pid: int in MatchConfig.get_rival_player_ids():
		out[pid] = PopulationManager.get_population(pid).duplicate()
	return out

func _ages() -> Dictionary:
	var out: Dictionary = {}
	out[0] = AgeManager.get_age(0)
	for pid: int in MatchConfig.get_rival_player_ids():
		out[pid] = AgeManager.get_age(pid)
	return out

# ── Client side ──────────────────────────────────────────────────────────────

## The mirror world must not simulate: the wire is the only truth. Physics
## processing carries every gameplay decision (state machines, navigation,
## building volleys — and with it local damage); _process stays ON so body
## animation, depth sort and health bars keep working from replicated fields.
func _puppet_existing_world() -> void:
	for node: Node in _units_layer.get_children():
		_make_puppet(node)
	for node: Node in _buildings_layer.get_children():
		_make_puppet(node)
	var drop_off: Variant = _world.get("drop_off")
	if drop_off is Node and is_instance_valid(drop_off as Node):
		_make_puppet(drop_off as Node)

func _make_puppet(node: Node) -> void:
	if not is_instance_valid(node) or node.get_meta(PUPPET_META, false):
		return
	node.set_meta(PUPPET_META, true)
	node.set_physics_process(false)

func _on_events(d: Dictionary) -> void:
	for rec: Variant in d.get("spawn", []) as Array:
		_apply_spawn(rec as Dictionary)
	for id: Variant in d.get("remove", []) as Array:
		var node: Node = EntityRegistry.resolve(id as int)
		_spans.erase(id as int)
		if node != null:
			node.queue_free()
	if d.has("u") or d.has("b"):
		# Reliable keyframe: same shape as the dense stream.
		_on_state(d)
	for e: Variant in d.get("rn", []) as Array:
		var rn: Array = e as Array
		var node: Node = EntityRegistry.resolve(rn[0] as int)
		if node != null and node.get("remaining_amount") != null:
			node.set("remaining_amount", rn[1] as float)
	var techs: Variant = d.get("tech")
	if techs is Dictionary:
		for pid: Variant in techs as Dictionary:
			TechManager.apply_remote_researched(pid as int, (techs as Dictionary)[pid] as Array)
	if d.has("fog"):
		_apply_fog(d["fog"] as String)
	if NetworkSession.resumed_match and not _resume_centered \
			and not (d.get("spawn", []) as Array).is_empty():
		_resume_centered = true
		_center_on_own_base()
	if d.has("amsg"):
		EventBus.ally_message.emit((d["amsg"] as Array)[0] as int, (d["amsg"] as Array)[1] as String)
	if d.has("pause"):
		_set_remote_pause(d["pause"] as bool)
	if d.has("over"):
		_set_remote_pause(false)
		GameManager.declare_winner(d["over"] as int)

## Resumed-match client: jump to our own base once, the moment the resync
## repopulates the mirror world (the fresh-boot camera looked at map center).
var _resume_centered: bool = false

func _center_on_own_base() -> void:
	var pid: int = NetworkSession.local_player_id
	for node: Node in _buildings_layer.get_children():
		if is_instance_valid(node) and node is TownCenterBuilding \
				and node.get("player_id") != null and (node.get("player_id") as int) == pid:
			_world.call("jump_camera_to", (node as Node2D).global_position)
			return
	for node: Node in _units_layer.get_children():
		if is_instance_valid(node) and node is Node2D \
				and node.get("player_id") != null and (node.get("player_id") as int) == pid:
			_world.call("jump_camera_to", (node as Node2D).global_position)
			return

## The saved exploration of THIS seat, shipped once in the resumed resync.
func _apply_fog(b64: String) -> void:
	var fog: Variant = _world.get("_fog")
	if not (fog is FogOfWar):
		return
	var cells: PackedByteArray = NetworkSession.fog_cells_from_b64(
		b64, (fog as FogOfWar)._cells.size())
	if cells.is_empty():
		return
	(fog as FogOfWar)._cells = cells
	(fog as FogOfWar).mark_all_dirty()

func _apply_spawn(rec: Dictionary) -> void:
	var id: int = rec.get("i", 0) as int
	if EntityRegistry.resolve(id) != null:
		return
	if (rec.get("k", "u") as String) == "r":
		# Resource nodes are built programmatically (no scene to instance).
		ResourceVisuals.create_resource_node(_world as Node2D,
			Vector2(rec.get("x", 0.0) as float, rec.get("y", 0.0) as float),
			rec.get("rt", 0) as ResourceNode.ResourceType,
			rec.get("a", 100.0) as float)
		var rn: Node = (_world as Node).get_children().back()
		if rn is ResourceNode:
			EntityRegistry.register_as(rn, id)
			_make_puppet(rn)
		return
	var scene_path: String = rec.get("s", "") as String
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var node: Node = (load(scene_path) as PackedScene).instantiate()
	var script_path: String = rec.get("c", "") as String
	var current: Script = node.get_script() as Script
	if not script_path.is_empty() \
			and (current == null or current.resource_path != script_path):
		node.set_script(load(script_path))
	node.set("player_id", rec.get("p", 0) as int)
	if rec.has("v"):
		node.set("civ_id", rec["v"] as String)
	if rec.has("d") and ResourceLoader.exists(rec["d"] as String):
		node.set("unit_data", load(rec["d"] as String))
	if rec.has("f"):
		node.set("is_female", rec["f"] as bool)
	var layer: Node = _units_layer if (rec.get("k", "u") as String) == "u" else _buildings_layer
	layer.add_child(node)
	(node as Node2D).global_position = Vector2(rec.get("x", 0.0) as float, rec.get("y", 0.0) as float)
	if node is Node2D:
		(node as Node2D).reset_physics_interpolation()
	EntityRegistry.register_as(node, id)
	_make_puppet(node)

func _on_state(d: Dictionary) -> void:
	for e: Variant in d.get("u", []) as Array:
		var row: Array = e as Array
		var node: Node = EntityRegistry.resolve(row[0] as int)
		if node == null or not (node is Node2D):
			continue
		_make_puppet(node)
		var target: Vector2 = Vector2(row[1] as float, row[2] as float)
		_spans[row[0] as int] = {"a": (node as Node2D).global_position, "b": target, "t": 0.0}
		if node.get("current_state") != null:
			node.set("current_state", row[3] as int)
		if node.get("velocity") != null:
			node.set("velocity", (target - (node as Node2D).global_position) / _interval)
		_apply_unit_health(node, row[4] as float)
	for e: Variant in d.get("b", []) as Array:
		var row: Array = e as Array
		var node: Node = EntityRegistry.resolve(row[0] as int)
		if node == null:
			continue
		_make_puppet(node)
		node.set("health", row[1] as float)
		var st: int = row[2] as int
		if node.get("state") != null and (node.get("state") as int) != st:
			if st == BuildingBase.BuildingState.COMPLETE and node.has_method("force_complete"):
				node.call("force_complete")
			else:
				node.set("state", st)
		if row.size() > 3:
			_apply_building_extras(node, row[3] as Dictionary)
		else:
			# No extras any more: whatever research this mirror still shows ended.
			TechManager.clear_remote_research(node)
	for e: Variant in d.get("fx", []) as Array:
		var fx: Array = e as Array
		var kind: int = fx[4] as int if fx.size() > 4 else SiegeFx.KIND_ARROW
		if kind == SiegeFx.KIND_BOULDER:
			SiegeFx.launch_boulder(_units_layer,
				Vector2(fx[0] as float, fx[1] as float),
				Vector2(fx[2] as float, fx[3] as float))
		else:
			_spawn_echo_arrow(Vector2(fx[0] as float, fx[1] as float),
				Vector2(fx[2] as float, fx[3] as float))
	var weather: Variant = d.get("w")
	if weather is Array and (weather as Array).size() >= 5:
		var w: Array = weather as Array
		WeatherManager.apply_remote(w[0] as int, w[1] as float, w[2] as String,
			w[3] as int, w[4] as Vector2)
	var res: Variant = d.get("res")
	if res is Dictionary:
		for pid: Variant in res as Dictionary:
			ResourceManager.apply_remote(pid as int, (res as Dictionary)[pid] as Dictionary)
	var pop: Variant = d.get("pop")
	if pop is Dictionary:
		for pid: Variant in pop as Dictionary:
			var p: Dictionary = (pop as Dictionary)[pid] as Dictionary
			PopulationManager.apply_remote(pid as int, p.get("current", 0) as int, p.get("cap", 0) as int)
	var ages: Variant = d.get("age")
	if ages is Dictionary:
		for pid: Variant in ages as Dictionary:
			AgeManager.apply_remote(pid as int, (ages as Dictionary)[pid] as int)

var _pause_banner: CanvasLayer = null

## The host paused/resumed the simulation: freeze the mirror and say so.
func _set_remote_pause(paused: bool) -> void:
	get_tree().paused = paused
	if paused and _pause_banner == null:
		_pause_banner = CanvasLayer.new()
		_pause_banner.layer = 20
		var label: Label = Label.new()
		label.text = tr("LAN_HOST_PAUSED")
		label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		label.position = Vector2(0.0, 120.0)
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		_pause_banner.add_child(label)
		add_child(_pause_banner)
	elif not paused and _pause_banner != null:
		_pause_banner.queue_free()
		_pause_banner = null

## Mirror the production queue, active research and market rates into the
## puppet building so the HUD answers truthfully when it is selected.
func _apply_building_extras(node: Node, extras: Dictionary) -> void:
	if extras.has("q"):
		var q: Array[Dictionary] = []
		for entry: Variant in extras["q"] as Array:
			q.append(entry as Dictionary)
		var changed: bool = _queue_signature(node.get("_train_queue") as Array) \
			!= _queue_signature(q)
		node.set("_train_queue", q)
		node.set("_train_timer", extras.get("t", 0.0) as float)
		if changed:
			var max_q: int = node.call("get_max_queue") as int \
				if node.has_method("get_max_queue") else q.size()
			EventBus.train_queue_changed.emit(node, q.duplicate(), max_q)
	if extras.has("r"):
		var r: Array = extras["r"] as Array
		TechManager.apply_remote_research(node, r[0] as String, r[1] as float, r[2] as float)
	else:
		TechManager.clear_remote_research(node)
	if extras.has("so"):
		node.set("_sell_offsets", extras["so"])
		node.set("_buy_offsets", extras["bo"])

func _queue_signature(q: Variant) -> String:
	if not (q is Array):
		return ""
	var ids: Array = []
	for entry: Variant in q as Array:
		ids.append((entry as Dictionary).get("unit_id", "?"))
	return ",".join(PackedStringArray(ids))

## Visual-only copy of a host-side arrow: no damage, no target, no report.
func _spawn_echo_arrow(start: Vector2, target_pos: Vector2) -> void:
	var arrow: Node2D = ARROW_SCENE.instantiate() as Node2D
	arrow.set("echo", true)
	arrow.set("target_pos", target_pos)
	_units_layer.add_child(arrow)
	arrow.global_position = start
	arrow.reset_physics_interpolation()

## Units keep a plain `health` var (the bar refresh lives in take_damage), so
## the puppet pokes the bar helper after writing the field.
func _apply_unit_health(node: Node, hp: float) -> void:
	if node.get("health") == null:
		return
	node.set("health", hp)
	if node.has_method("_refresh_health_bar"):
		node.call("_refresh_health_bar")

func _process(delta: float) -> void:
	if not NetworkSession.is_client():
		return
	for id: int in _spans:
		var span: Dictionary = _spans[id]
		var node: Node = EntityRegistry.resolve(id)
		if node == null or not (node is Node2D):
			continue
		span["t"] = (span["t"] as float) + delta / _interval
		var t: float = minf(span["t"] as float, 1.0)
		(node as Node2D).global_position = (span["a"] as Vector2).lerp(span["b"] as Vector2, t)

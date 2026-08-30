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
# Client: id -> {"a": Vector2, "b": Vector2, "t": float} interpolation spans.
var _spans: Dictionary = {}

func setup(world) -> void:
	_world = world
	_units_layer = world.units_layer
	_buildings_layer = world.buildings_layer
	if NetworkSession.is_client():
		NetworkSession.state_received.connect(_on_state)
		NetworkSession.events_received.connect(_on_events)
		_puppet_existing_world()
	else:
		GameManager.game_over.connect(func(winner_id: int) -> void:
			NetworkSession.send_events({"over": winner_id}))

func _exit_tree() -> void:
	if NetworkSession.is_client():
		if NetworkSession.state_received.is_connected(_on_state):
			NetworkSession.state_received.disconnect(_on_state)
		if NetworkSession.events_received.is_connected(_on_events):
			NetworkSession.events_received.disconnect(_on_events)

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
		buildings.append([id, (node as Node).get("health") as float,
			(node as Node).get("state") as int if (node as Node).get("state") != null else 0])
	var removes: Array = []
	for id: Variant in _announced.keys():
		if EntityRegistry.resolve(id as int) == null:
			removes.append(id)
			_announced.erase(id)
	if not spawns.is_empty() or not removes.is_empty():
		NetworkSession.send_events({"spawn": spawns, "remove": removes})
	NetworkSession.send_state({
		"u": units,
		"b": buildings,
		"res": _stockpiles(),
		"pop": _populations(),
		"age": _ages(),
	})

func _spawn_record(node: Node, id: int, kind: String) -> Dictionary:
	var rec: Dictionary = {
		"i": id,
		"k": kind,
		"s": node.scene_file_path,
		"p": node.get("player_id") as int if node.get("player_id") != null else -1,
		"x": (node as Node2D).global_position.x,
		"y": (node as Node2D).global_position.y,
	}
	var script: Script = node.get_script() as Script
	if script != null:
		rec["c"] = script.resource_path
	var civ: Variant = node.get("civ_id")
	if civ is String and not (civ as String).is_empty():
		rec["v"] = civ
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
	if d.has("over"):
		GameManager.declare_winner(d["over"] as int)

func _apply_spawn(rec: Dictionary) -> void:
	var id: int = rec.get("i", 0) as int
	if EntityRegistry.resolve(id) != null:
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

class_name WorldQuery
extends RefCounted

## Read-only query service over the units/buildings scene layers.
##
## Centralises the "walk the layer + filter" boilerplate the AI modules
## currently repeat ~43 times, and isolates the dependency on the scene-tree
## structure (units_layer / buildings_layer) to a single place. Pure with
## respect to autoloads — it only reads node properties (player_id, is_cloaked,
## current_state) and types — so it is exercisable against a synthetic tree.
##
## Behaviour contract (matches the pre-refactor inline loops exactly):
##   • Nodes failing is_instance_valid() are always skipped.
##   • A node whose player_id is null is always skipped.
##   • "own"   = player_id == owner_id ; "enemy" = player_id != owner_id.
##   • Enemy-UNIT queries additionally drop cloaked units (is_cloaked == true);
##     own units, and all building queries, do NOT apply the cloak filter.

var _units_layer: Node = null
var _buildings_layer: Node = null

func _init(units_layer: Node, buildings_layer: Node) -> void:
	_units_layer = units_layer
	_buildings_layer = buildings_layer

# ── All entities (no player filter) ───────────────────────────────────────────

## Every valid building, regardless of owner (e.g. footprint/placement checks).
func all_buildings() -> Array:
	return _all(_buildings_layer)

## Every valid unit, regardless of owner.
func all_units() -> Array:
	return _all(_units_layer)

func _all(layer: Node) -> Array:
	var result: Array = []
	if not is_instance_valid(layer):
		return result
	for node: Node in layer.get_children():
		if is_instance_valid(node):
			result.append(node)
	return result

# ── Internal core ─────────────────────────────────────────────────────────────

# own == true  -> keep player_id == owner_id
# own == false -> keep player_id != owner_id (enemy)
func _collect(layer: Node, owner_id: int, own: bool, drop_cloaked: bool) -> Array:
	var result: Array = []
	if not is_instance_valid(layer):
		return result
	for node: Node in layer.get_children():
		if not is_instance_valid(node):
			continue
		var pid: Variant = node.get("player_id")
		if pid == null:
			continue
		# "own" keeps only the owner's entities; "enemy" keeps only HOSTILE
		# ones — allied players are neither, so team-mates never get farmed
		# as targets by the AI.
		if own:
			if (pid as int) != owner_id:
				continue
		elif GameManager.are_allied(pid as int, owner_id):
			continue
		if drop_cloaked and node.get("is_cloaked") == true:
			continue
		result.append(node)
	return result

# ── Units ─────────────────────────────────────────────────────────────────────

func own_units(owner_id: int) -> Array:
	return _collect(_units_layer, owner_id, true, false)

## Enemy units the AI may act on — cloaked units are excluded, matching the
## combat-scan loops in ai_military / ai_naval.
func enemy_units_visible(owner_id: int) -> Array:
	return _collect(_units_layer, owner_id, false, true)

## Enemy units including cloaked ones (for queries that never filtered cloak).
func enemy_units(owner_id: int) -> Array:
	return _collect(_units_layer, owner_id, false, false)

# ── Buildings ─────────────────────────────────────────────────────────────────

func own_buildings(owner_id: int) -> Array:
	return _collect(_buildings_layer, owner_id, true, false)

func enemy_buildings(owner_id: int) -> Array:
	return _collect(_buildings_layer, owner_id, false, false)

# ── Sighting layer (fog-honest combat targeting) ──────────────────────────────
#
# An enemy entity is *sighted* while inside the line-of-sight radius of any own
# unit or building (LOS read from the entity's .tres, converted at FogOfWar's
# 64 px per LOS unit), and once sighted it is *remembered* at its last seen
# position after leaving sight — AoE2 semantics: buildings stay honest targets
# where they were last scouted, units are only targetable while actually seen.
# The refresh is throttled per owner (SIGHT_REFRESH_TICKS of physics frames),
# so the O(own × enemy) sweep runs at most ~1.7×/s regardless of query volume.

const SIGHT_REFRESH_TICKS: int = 36        # ~0.6 s at 60 Hz physics
const LOS_TO_PX: float = 64.0              # FogOfWar._vision_radius_cells scale
const DEFAULT_UNIT_LOS: float = 5.0        # FogOfWar defaults when no .tres data
const DEFAULT_BUILDING_LOS: float = 8.0

var _sight_stamp: Dictionary = {}   # owner_id -> physics frame of last refresh
var _sighted: Dictionary = {}       # owner_id -> { instance_id -> Node }
var _memory: Dictionary = {}        # owner_id -> { instance_id -> [Node, last_pos] }

func refresh_sightings(owner_id: int, force: bool = false) -> void:
	var now: int = Engine.get_physics_frames()
	if not force and _sight_stamp.has(owner_id) \
			and now - (_sight_stamp[owner_id] as int) < SIGHT_REFRESH_TICKS:
		return
	_sight_stamp[owner_id] = now

	# Flat (x, y, los²) triplets: the enemy sweep below is the hot loop.
	var obs: PackedFloat32Array = PackedFloat32Array()
	for u: Node in own_units(owner_id):
		_append_observer(obs, u, false)
	for b: Node in own_buildings(owner_id):
		_append_observer(obs, b, true)

	var mem: Dictionary = _memory.get(owner_id, {}) as Dictionary
	for iid: Variant in mem.keys():
		# No `as Object` cast here: casting a freed instance raises an engine
		# error — is_instance_valid takes the raw Variant safely.
		if not is_instance_valid((mem[iid] as Array)[0]):
			mem.erase(iid)

	var sighted: Dictionary = {}
	var obs_count: int = obs.size() / 3
	var candidates: Array = enemy_units_visible(owner_id) + enemy_buildings(owner_id)
	for e: Node in candidates:
		if not (e is Node2D):
			continue
		var epos: Vector2 = (e as Node2D).global_position
		for i: int in range(obs_count):
			var dx: float = epos.x - obs[i * 3]
			var dy: float = epos.y - obs[i * 3 + 1]
			if dx * dx + dy * dy <= obs[i * 3 + 2]:
				var iid: int = e.get_instance_id()
				sighted[iid] = e
				mem[iid] = [e, epos]
				break
	_sighted[owner_id] = sighted
	_memory[owner_id] = mem

func _append_observer(obs: PackedFloat32Array, entity: Node, is_building: bool) -> void:
	if not (entity is Node2D):
		return
	var los: float = DEFAULT_BUILDING_LOS if is_building else DEFAULT_UNIT_LOS
	if entity is Animal:
		los = (entity as Animal).line_of_sight
	else:
		var data: Variant = entity.get("building_data" if is_building else "unit_data")
		if data != null:
			var v: Variant = (data as Object).get("line_of_sight")
			if v != null:
				los = v as float
	var pos: Vector2 = (entity as Node2D).global_position
	var r: float = los * LOS_TO_PX
	obs.append(pos.x)
	obs.append(pos.y)
	obs.append(r * r)

## Enemy units and buildings currently inside own line of sight.
func enemies_sighted(owner_id: int) -> Array:
	refresh_sightings(owner_id)
	var out: Array = []
	for n: Node in (_sighted.get(owner_id, {}) as Dictionary).values():
		if is_instance_valid(n):
			out.append(n)
	return out

## Enemy UNITS currently in sight (cloak-honest, like enemy_units_visible).
func sighted_enemy_units(owner_id: int) -> Array:
	refresh_sightings(owner_id)
	var s: Dictionary = _sighted.get(owner_id, {}) as Dictionary
	var out: Array = []
	for u: Node in enemy_units_visible(owner_id):
		if s.has(u.get_instance_id()):
			out.append(u)
	return out

## Enemy BUILDINGS sighted now OR remembered from an earlier sighting —
## buildings do not move, so a remembered one is still an honest target.
func known_enemy_buildings(owner_id: int) -> Array:
	refresh_sightings(owner_id)
	var s: Dictionary = _sighted.get(owner_id, {}) as Dictionary
	var m: Dictionary = _memory.get(owner_id, {}) as Dictionary
	var out: Array = []
	for b: Node in enemy_buildings(owner_id):
		var iid: int = b.get_instance_id()
		if s.has(iid) or m.has(iid):
			out.append(b)
	return out

func is_sighted(owner_id: int, entity: Node) -> bool:
	refresh_sightings(owner_id)
	return (_sighted.get(owner_id, {}) as Dictionary).has(entity.get_instance_id())

## instance_id -> last known position for every still-existing enemy ever seen.
func remembered_enemy_positions(owner_id: int) -> Dictionary:
	refresh_sightings(owner_id)
	var out: Dictionary = {}
	var mem: Dictionary = _memory.get(owner_id, {}) as Dictionary
	for iid: Variant in mem:
		var entry: Array = mem[iid] as Array
		if is_instance_valid(entry[0]):
			out[iid] = entry[1]
	return out

## Nearest currently-sighted enemy (unit or building), or null.
func nearest_sighted_enemy(owner_id: int, from_pos: Vector2) -> Node:
	return nearest_to(enemies_sighted(owner_id), from_pos)

# ── Composable refinements ────────────────────────────────────────────────────

## Subset of `nodes` that are instances of `type` (e.g. Villager, Barracks).
static func of_type(nodes: Array, type: Variant) -> Array:
	var result: Array = []
	for n: Node in nodes:
		if is_instance_of(n, type):
			result.append(n)
	return result

## Subset of `nodes` whose current_state equals `state` (UnitBase.UnitState).
static func in_state(nodes: Array, state: int) -> Array:
	var result: Array = []
	for n: Node in nodes:
		var s: Variant = n.get("current_state")
		if s != null and (s as int) == state:
			result.append(n)
	return result

## Nearest node in `nodes` to `from_pos`, or null if empty.
static func nearest_to(nodes: Array, from_pos: Vector2) -> Node:
	var best: Node = null
	var best_d: float = INF
	for n: Node in nodes:
		if not (n is Node2D):
			continue
		var d: float = (n as Node2D).global_position.distance_squared_to(from_pos)
		if d < best_d:
			best_d = d
			best = n
	return best

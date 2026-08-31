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

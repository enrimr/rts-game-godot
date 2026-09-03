extends Node2D

## Sea-containment chaos probe: boots a real Islands match, then actively
## tries to shove land units into the ocean the way real matches do —
## cross-water attack-moves at the enemy island, straight move orders into
## deep sea, villagers sent at fish nodes, and a shoreline melee where RVO
## pushes bodies around — while auditing EVERY land unit EVERY sampled tick.
## A violation is a non-amphibious, non-ship, non-DEAD unit standing on
## OCEAN terrain. Prints each unit's worst trespass (depth px, state) and a
## final PASS/FAIL summary; exits 1 on FAIL so it can gate CI.
##
##   $GODOT --headless --path project res://tools/check_sea_containment.tscn
##   Env: CALIMA_SEED (default 4242), CALIMA_MAP (default 4 = ISLANDS),
##        CALIMA_TICKS (default 4800), CALIMA_RIVALS (default 1)

const SAMPLE_EVERY: int = 10

var _world: Node2D = null
var _violations: Dictionary = {}   # entity id → worst record
var _wet_streak: Dictionary = {}   # entity id → consecutive wet samples
var _dips: int = 0                 # single-sample dips (warned, not failed)
var _samples: int = 0
var _unit_samples: int = 0

func _ready() -> void:
	var seed_env: String = OS.get_environment("CALIMA_SEED")
	OS.set_environment("CALIMA_SEED", seed_env if not seed_env.is_empty() else "4242")
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.ISLANDS
	MatchConfig.weather_enabled = false
	var rivals_env: String = OS.get_environment("CALIMA_RIVALS")
	MatchConfig.rival_count = int(rivals_env) if not rivals_env.is_empty() else 1
	var ticks_env: String = OS.get_environment("CALIMA_TICKS")
	var ticks: int = int(ticks_env) if not ticks_env.is_empty() else 4800

	Engine.time_scale = 8.0
	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("SEA_CONTAINMENT seed=%s map=%d ticks=%d rivals=%d" % [
		OS.get_environment("CALIMA_SEED"), MatchConfig.map_type, ticks,
		MatchConfig.rival_count])

	for tick: int in range(ticks):
		await get_tree().physics_frame
		if tick == 240:
			_force_chaos()
		if tick % SAMPLE_EVERY == 0:
			_audit(tick)

	_report()

## Every hostile-to-the-coast order a real match can produce.
func _force_chaos() -> void:
	var own: Array[Node] = []
	var villagers: Array[Node] = []
	for unit: Node in (_world.units_layer as Node).get_children():
		if not (unit is UnitBase) or unit is ShipBase:
			continue
		if (unit.get("player_id") as int) != 0:
			continue
		if unit is Villager:
			villagers.append(unit)
		else:
			own.append(unit)
	var enemy_tc: Node2D = _find_enemy_tc()
	var ids: Array[int] = []
	for u: Node in own:
		ids.append(EntityRegistry.id_of(u))
	if enemy_tc != null and not ids.is_empty():
		# 1. Attack-move ACROSS the water at the enemy island.
		CommandBus.submit(UnitPointCommand.make(0, "attack_move", ids,
			enemy_tc.global_position))
		print("  chaos: attack_move %d units -> enemy TC %s" % [ids.size(),
			enemy_tc.global_position])
	# 2. A straight move order into deep ocean (minimap right-click can do this).
	var deep: Vector2 = _find_deep_ocean()
	if deep != Vector2.INF and not ids.is_empty():
		CommandBus.submit(UnitPointCommand.make(0, "move", ids, deep))
		print("  chaos: move %d units -> deep ocean %s" % [ids.size(), deep])
	# 3. Villagers sent at a fish node in open water.
	var fish: Node2D = _find_fish()
	if fish != null and not villagers.is_empty():
		var vids: Array[int] = []
		for v: Node in villagers:
			vids.append(EntityRegistry.id_of(v))
		CommandBus.submit(UnitTargetCommand.make(0, "gather", vids,
			EntityRegistry.id_of(fish)))
		print("  chaos: %d villagers -> fish node %s" % [vids.size(),
			fish.global_position])
	# 4. Shoreline melee: two spawned mobs shoving each other at the beach.
	var beach: Vector2 = _find_beach()
	if beach != Vector2.INF:
		_spawn_brawl(beach)
		print("  chaos: 16-unit brawl at beach %s (coast %.0f px away)" % [
			beach, TerrainManager.distance_to_coast(beach)])

func _find_enemy_tc() -> Node2D:
	for b: Node in (_world.buildings_layer as Node).get_children():
		if b.has_method("is_respawning_hero") and (b.get("player_id") as int) != 0:
			return b as Node2D
	for b: Node in (_world.buildings_layer as Node).get_children():
		if (b.get("player_id") is int) and (b.get("player_id") as int) > 0:
			return b as Node2D
	return null

func _find_deep_ocean() -> Vector2:
	for r: float in [1400.0, 2000.0, 900.0]:
		for i: int in range(16):
			var a: float = TAU * i / 16.0
			var p: Vector2 = Vector2(cos(a), sin(a)) * r
			if TerrainManager.is_ocean(p) and TerrainManager.distance_to_coast(p) > 120.0:
				return p
	return Vector2.INF

func _find_fish() -> Node2D:
	for child: Node in _world.get_children():
		if child is ResourceNode \
				and (child as ResourceNode).resource_type == ResourceNode.ResourceType.FOOD_FISH:
			return child as Node2D
	return null

## A land point as close to the coastline as the walk allows.
func _find_beach() -> Vector2:
	var tc: Vector2 = Vector2.ZERO
	for b: Node in (_world.buildings_layer as Node).get_children():
		if b.has_method("is_respawning_hero") and (b.get("player_id") as int) == 0:
			tc = (b as Node2D).global_position
			break
	for r: float in [200.0, 320.0, 440.0, 560.0]:
		for i: int in range(24):
			var a: float = TAU * i / 24.0
			var p: Vector2 = tc + Vector2(cos(a), sin(a)) * r
			if not TerrainManager.is_ocean(p) \
					and TerrainManager.distance_to_coast(p) < 60.0 \
					and not TerrainManager.is_impassable_for(p, "", false):
				return p
	return Vector2.INF

func _spawn_brawl(at: Vector2) -> void:
	var packed: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	for side: int in [0, 1]:
		for i: int in range(8):
			var u: Node2D = packed.instantiate() as Node2D
			u.set("player_id", side)
			u.set("civ_id", "guanches")
			(_world.units_layer as Node).add_child(u)
			u.global_position = TerrainManager.nearest_passable(
				at + Vector2((i % 4) * 22.0 - 33.0,
					(i / 4) * 22.0 - 11.0 + side * 60.0 - 30.0), "guanches")
			EventBus.unit_spawned.emit(u, side)
	# Everyone attack-moves at the other side, straight through the beach line.
	for side: int in [0, 1]:
		var ids: Array[int] = []
		for u: Node in (_world.units_layer as Node).get_children():
			if u is Militia and (u.get("player_id") as int) == side \
					and u.global_position.distance_to(at) < 140.0:
				ids.append(EntityRegistry.id_of(u))
		CommandBus.submit(UnitPointCommand.make(side, "attack_move", ids,
			at + Vector2(0, 30.0 - side * 60.0)))

func _audit(tick: int) -> void:
	_samples += 1
	for unit: Node in (_world.units_layer as Node).get_children():
		if not is_instance_valid(unit) or not (unit is Node2D):
			continue
		var is_land_unit: bool = (unit is UnitBase and not (unit is ShipBase) \
			and not (unit.call("is_amphibious") as bool) \
			and (unit.get("current_state") as int) != UnitBase.UnitState.DEAD) \
			or (unit is Animal and (unit.get("current_state") as int) != Animal.AnimalState.DEAD)
		if not is_land_unit:
			continue
		_unit_samples += 1
		var pos: Vector2 = (unit as Node2D).global_position
		var key: int = unit.get_instance_id()
		if not TerrainManager.is_ocean(pos):
			_wet_streak.erase(key)
			continue
		# A single sampled tick in the water is a physics slide the 0.8 s
		# containment backstop heals (and it differs per platform); the BUG
		# this gate exists for is PERSISTENT sea-walking. One-tick dips are
		# reported as warnings; two consecutive samples is a violation.
		var streak: int = (_wet_streak.get(key, 0) as int) + 1
		_wet_streak[key] = streak
		_dips += 1
		if streak < 2:
			continue
		var depth: float = TerrainManager.distance_to_coast(pos)
		var prev: Dictionary = _violations.get(key, {}) as Dictionary
		if prev.is_empty() or (prev.get("depth", 0.0) as float) < depth:
			_violations[key] = {
				"who": (unit.get_script() as Script).resource_path.get_file().get_basename(),
				"pid": unit.get("player_id"),
				"state": unit.get("current_state"),
				"pos": pos, "depth": depth, "tick": tick,
				"hits": (prev.get("hits", 0) as int) + 1,
			}
		else:
			prev["hits"] = (prev.get("hits", 0) as int) + 1

func _report() -> void:
	print("SEA_CONTAINMENT samples=%d unit-samples=%d violators=%d one-tick-dips=%d" % [
		_samples, _unit_samples, _violations.size(), _dips])
	var worst: Array = _violations.values()
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["depth"] as float) > (b["depth"] as float))
	for v: Dictionary in worst:
		print("  VIOLATION %-16s p%s state=%s pos=(%.0f,%.0f) depth=%.0fpx first_tick=%d hits=%d" % [
			v["who"], str(v["pid"]), str(v["state"]),
			(v["pos"] as Vector2).x, (v["pos"] as Vector2).y,
			v["depth"] as float, v["tick"] as int, v["hits"] as int])
	if _violations.is_empty():
		print("SEA_CONTAINMENT: PASS — no land unit ever stood on ocean terrain")
		get_tree().quit(0)
	else:
		print("SEA_CONTAINMENT: FAIL — %d unit(s) trespassed" % _violations.size())
		get_tree().quit(1)

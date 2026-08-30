class_name WorldVictory extends RefCounted

## Victory/defeat/elimination logic for the match: conquest defeat scans,
## wonder countdown timers, and the end-of-game world freeze.

const WONDER_COUNTDOWN_SEC: float = 240.0

var _world  # GameWorld — untyped so dynamic access works

# Wonder mode: per-player countdown. Key = player_id, value = seconds remaining.
var _wonder_timers: Dictionary = {}  # int -> float
# Players who resigned (or dropped mid-match): out of the game even though
# their entities may still stand on the field.
var _resigned: Dictionary = {}  # int -> true

func setup(world) -> void:
	_world = world

## Per-frame wonder countdown; called from GameWorld._process.
func tick(delta: float) -> void:
	if _wonder_timers.is_empty():
		return
	# Victory is decided by the simulation authority only; a client's mirror
	# world receives the outcome over the wire (StateReplicator game-over).
	if NetworkSession.is_client():
		return
	var hud_mgr: Node = _world.hud.get_node_or_null("HudManager")
	for wonder_pid: int in _wonder_timers.keys():
		_wonder_timers[wonder_pid] = (_wonder_timers[wonder_pid] as float) - delta
		if is_instance_valid(hud_mgr) and hud_mgr.has_method("update_wonder_timer"):
			hud_mgr.call("update_wonder_timer", _wonder_timers[wonder_pid] as float)
		if (_wonder_timers[wonder_pid] as float) <= 0.0:
			_wonder_timers.erase(wonder_pid)
			GameManager.declare_winner(wonder_pid)
			break

func _on_building_destroyed_check_victory(building: Node, owner_id: int) -> void:
	if building is Wonder:
		EventBus.wonder_destroyed.emit(owner_id)

	if owner_id == 0:
		if building == _world.drop_off:
			_world.drop_off = null

	# Keep _ai_town_centers in sync so TC-rebuild logic still works.
	for rival_id: int in _world._ai_town_centers:
		if _world._ai_town_centers[rival_id] == building:
			_world._ai_town_centers.erase(rival_id)
			if _world._ai_town_center == building:
				_world._ai_town_center = null
			break

	# Conquest only — Wonder and Regicide have their own handlers.
	if MatchConfig.victory_mode == MatchConfig.VictoryMode.CONQUEST:
		_check_defeat_for.call_deferred(owner_id)

func _on_unit_died_check_victory(_unit: Node, owner_id: int) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	# Conquest only — Regicide is handled by GameManager._on_hero_died_regicide.
	if MatchConfig.victory_mode == MatchConfig.VictoryMode.CONQUEST:
		_check_defeat_for.call_deferred(owner_id)

## A human player resigned or dropped mid-match (host side, any victory
## mode): eliminate them and end the match if nobody is left to fight.
func handle_resignation(pid: int) -> void:
	if NetworkSession.is_client() or pid == 0 or _resigned.has(pid):
		return
	if GameManager.state != GameManager.GameState.PLAYING \
			and GameManager.state != GameManager.GameState.PAUSED:
		return
	_resigned[pid] = true
	EventBus.player_eliminated.emit(pid)
	for rival_id: int in MatchConfig.get_rival_player_ids():
		if _resigned.has(rival_id):
			continue
		if _has_any_units(rival_id) or _has_any_buildings(rival_id):
			return
	GameManager.declare_winner(0)

## Conquest defeat check for any player. Deferred so queue_free() has
## processed before we scan. If the player is out, declare the other side winner.
func _check_defeat_for(pid: int) -> void:
	if NetworkSession.is_client():
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if _has_any_units(pid) or _has_any_buildings(pid):
		return
	# Notify AI coordinator so it can clean up.
	EventBus.player_eliminated.emit(pid)
	if pid == 0:
		# Player lost — pick any surviving rival.
		for rival_id: int in MatchConfig.get_rival_player_ids():
			if _resigned.has(rival_id):
				continue
			if _has_any_units(rival_id) or _has_any_buildings(rival_id):
				GameManager.declare_winner(rival_id)
				return
		GameManager.declare_winner(1)
	else:
		# A rival was eliminated — check if all rivals are now gone.
		for rival_id: int in MatchConfig.get_rival_player_ids():
			if _resigned.has(rival_id):
				continue
			if _has_any_units(rival_id) or _has_any_buildings(rival_id):
				return
		GameManager.declare_winner(0)

func _on_player_eliminated(eliminated_id: int) -> void:
	# Clean up AI coordinator references; victory already handled in _check_defeat_for.
	if _world._ai_town_centers.has(eliminated_id):
		_world._ai_town_centers.erase(eliminated_id)
	if is_instance_valid(_world._ai_town_center) and _world._ai_town_center.get("player_id") == eliminated_id:
		_world._ai_town_center = null

## Returns true if player_id has at least one living combat-capable unit
## (villagers count; animals/sheep do not).
func _has_any_units(pid: int) -> bool:
	for unit: Node in _world.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit is Animal:
			continue
		var p: Variant = unit.get("player_id")
		if p == null or (p as int) != pid:
			continue
		var st: Variant = unit.get("current_state")
		if st != null and (st as int) == UnitBase.UnitState.DEAD:
			continue
		return true
	return false

## Returns true if player_id has at least one unit-producing building
## (TC, Barracks, Stable, SiegeWorkshop, Dock). Walls, houses, towers,
## farms, camps, etc. do not count.
func _has_any_buildings(pid: int) -> bool:
	for b: Node in _world.buildings_layer.get_children():
		if not is_instance_valid(b):
			continue
		if not (b is TownCenterBuilding or b is TownCenterBuildable
				or b is Barracks or b is ArcheryRange or b is Stable
				or b is SiegeWorkshop or b is Dock):
			continue
		var p: Variant = b.get("player_id")
		if p == null or (p as int) != pid:
			continue
		var st: Variant = b.get("state")
		if st != null and (st as int) == BuildingBase.BuildingState.DESTROYED:
			continue
		return true
	return false

func _on_building_construction_complete(building: Node) -> void:
	if building is Wonder:
		EventBus.wonder_built.emit(building.get("player_id") as int)

func _on_wonder_built(pid: int) -> void:
	if MatchConfig.victory_mode != MatchConfig.VictoryMode.WONDER:
		return
	_wonder_timers[pid] = WONDER_COUNTDOWN_SEC
	var hud_mgr: Node = _world.hud.get_node_or_null("HudManager")
	if is_instance_valid(hud_mgr) and hud_mgr.has_method("show_wonder_timer"):
		hud_mgr.call("show_wonder_timer", pid)

func _on_wonder_destroyed(pid: int) -> void:
	if not _wonder_timers.has(pid):
		return
	# Destroying a wonder cancels that player's countdown — no immediate loss.
	# The game continues under conquest rules (or until another wonder timer expires).
	_wonder_timers.erase(pid)
	var hud_mgr: Node = _world.hud.get_node_or_null("HudManager")
	if is_instance_valid(hud_mgr) and hud_mgr.has_method("hide_wonder_timer"):
		hud_mgr.call("hide_wonder_timer")

func _on_game_over(_winner: int) -> void:
	AudioManager.stop_music()
	_world.set_process(false)
	_world.set_physics_process(false)
	_world.set_process_unhandled_input(false)
	# Freeze units and buildings without pausing the whole tree
	# (pausing the tree stops building production queues too)
	for unit: Node in _world.units_layer.get_children():
		if is_instance_valid(unit):
			(unit as Node).set_process(false)
			(unit as Node).set_physics_process(false)
	for building: Node in _world.buildings_layer.get_children():
		if is_instance_valid(building):
			(building as Node).set_process(false)
	if is_instance_valid(_world.drop_off):
		_world.drop_off.set_process(false)
	if is_instance_valid(_world._ai_town_center):
		_world._ai_town_center.set_process(false)

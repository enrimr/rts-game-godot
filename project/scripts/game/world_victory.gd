class_name WorldVictory extends RefCounted

## Victory/defeat/elimination logic for the match: conquest defeat scans,
## wonder countdown timers, and the end-of-game world freeze.

const WONDER_COUNTDOWN_SEC: float = 240.0
## Breathing room between a resignation and the game-over overlay, so the
## "X resigned / X left" chat line can actually be read.
const RESIGN_END_DELAY: float = 2.5

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

## A human player resigned or dropped mid-match (authority side, any victory
## mode): eliminate them and end the match if nobody is left to fight. When
## hostile sides remain the match plays on — the resigned local player stays
## as a spectator (HudMatchStats shows their defeat, GameWorld locks orders).
func handle_resignation(pid: int) -> void:
	if NetworkSession.is_client() or _resigned.has(pid):
		return
	if GameManager.state != GameManager.GameState.PLAYING \
			and GameManager.state != GameManager.GameState.PAUSED:
		return
	_resigned[pid] = true
	EventBus.player_eliminated.emit(pid)
	var active: Array[int] = []
	var all_ids: Array[int] = [0]
	all_ids.append_array(MatchConfig.get_rival_player_ids())
	for other: int in all_ids:
		if _resigned.has(other):
			continue
		if other == 0 or _has_any_units(other) or _has_any_buildings(other):
			active.append(other)
	for other: int in active:
		if not GameManager.are_allied(active[0], other):
			return   # hostile sides remain — the match continues
	# Let everyone read the system chat line before the overlay drops.
	await _world.get_tree().create_timer(RESIGN_END_DELAY).timeout
	GameManager.declare_winner(active[0] if not active.is_empty() else 0)

## Conquest defeat check for any player. Deferred so queue_free() has
## processed before we scan. If the player is out, declare the other side winner.
func _check_defeat_for(pid: int) -> void:
	if NetworkSession.is_client():
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if _resigned.has(pid):
		return   # already out — don't re-announce the elimination
	if _has_any_units(pid) or _has_any_buildings(pid):
		return
	# Out for good — stray building kills must not re-emit the elimination.
	_resigned[pid] = true
	# Notify AI coordinator so it can clean up.
	EventBus.player_eliminated.emit(pid)
	_declare_if_one_side_left(pid)

## Conquest/team end condition: collect every player still standing (not
## resigned, still owning something); when they are all mutually allied,
## that side has won. `just_out` is excluded even if its corpse cleanup is
## still mid-frame.
func _declare_if_one_side_left(just_out: int) -> void:
	var active: Array[int] = []
	var all_ids: Array[int] = [0]
	all_ids.append_array(MatchConfig.get_rival_player_ids())
	for pid: int in all_ids:
		if pid == just_out or _resigned.has(pid):
			continue
		if _has_any_units(pid) or _has_any_buildings(pid):
			active.append(pid)
	if active.is_empty():
		GameManager.declare_winner(just_out if just_out != 0 else 1)
		return
	for pid: int in active:
		if not GameManager.are_allied(active[0], pid):
			return   # at least two hostile sides remain — play on
	GameManager.declare_winner(active[0])

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
	# Freeze units and buildings without pausing the whole tree. Buildings
	# tick in _physics_process too (production, tower volleys) and the AI
	# brains are direct world children — leaving any of them running kept
	# spawning live units into a "frozen" battlefield.
	for unit: Node in _world.units_layer.get_children():
		if is_instance_valid(unit):
			(unit as Node).set_process(false)
			(unit as Node).set_physics_process(false)
	for building: Node in _world.buildings_layer.get_children():
		if is_instance_valid(building):
			(building as Node).set_process(false)
			(building as Node).set_physics_process(false)
	for child: Node in _world.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path.contains("ai_player"):
			child.set_process(false)
			child.set_physics_process(false)
	if is_instance_valid(_world.drop_off):
		_world.drop_off.set_process(false)
		_world.drop_off.set_physics_process(false)
	if is_instance_valid(_world._ai_town_center):
		_world._ai_town_center.set_process(false)
		_world._ai_town_center.set_physics_process(false)

extends Node

## CommandBus (autoload) — the single entry point every simulation-mutating
## player intent goes through. Input/UI code builds a GameCommand and calls
## submit(); the bus tick-stamps it into the match log and executes it against
## the current world. The log is a serializable record of the whole match's
## intents — the foundation replays build on, and the exact payload a LAN
## lockstep session will exchange instead of executing locally right away.
##
## The AI modules submit through the bus too, with their own player_id — the
## whole simulation is driven by logged commands. What does NOT go through the
## bus: selection, control groups, camera, HUD state and other local-only UI
## concerns, plus AI-internal bookkeeping that mutates no game state.

signal command_executed(command: GameCommand)

## kind() tag → command script, for rebuilding a command from its dictionary.
const KINDS: Dictionary = {
	"unit_point":      preload("res://scripts/game/commands/unit_point_command.gd"),
	"unit_target":     preload("res://scripts/game/commands/unit_target_command.gd"),
	"unit_action":     preload("res://scripts/game/commands/unit_action_command.gd"),
	"transport":       preload("res://scripts/game/commands/transport_command.gd"),
	"production":      preload("res://scripts/game/commands/production_command.gd"),
	"building_action": preload("res://scripts/game/commands/building_action_command.gd"),
	"market":          preload("res://scripts/game/commands/market_command.gd"),
	"place_building":  preload("res://scripts/game/commands/place_building_command.gd"),
	"advance_age":     preload("res://scripts/game/commands/advance_age_command.gd"),
	"spawn_unit":      preload("res://scripts/game/commands/spawn_unit_command.gd"),
}

var _world: Node2D = null
var _log: Array[Dictionary] = []
var _tick0: int = 0

## Binds the bus to the match world, resets the tick clock and the command log,
## and gives every already-spawned entity its deterministic ID. Called once at
## the end of GameWorld._ready (after a save restore, so loaded entities are in).
func start_match(world: Node2D) -> void:
	_world = world
	_log.clear()
	_tick0 = Engine.get_physics_frames()
	EntityRegistry.rescan(world)

func current_tick() -> int:
	return Engine.get_physics_frames() - _tick0

func submit(command: GameCommand) -> void:
	if command == null or not is_instance_valid(_world):
		return
	var entry: Dictionary = command.to_dict()
	entry["t"] = current_tick()
	_log.append(entry)
	command.execute(_world)
	command_executed.emit(command)

## Rebuilds a command from a to_dict()/log dictionary. Returns null for an
## unknown kind (a malformed or hostile payload must not crash the bus).
func command_from_dict(d: Dictionary) -> GameCommand:
	var script: Variant = KINDS.get(d.get("kind", "") as String)
	if script == null:
		return null
	return ((script as GDScript).new() as GameCommand).read(d)

func log_entries() -> Array[Dictionary]:
	return _log

## Writes the match's command log as JSON lines. The replay foundation:
## same seed + same log = the same match, once the simulation is deterministic.
func save_log(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	for entry: Dictionary in _log:
		f.store_line(JSON.stringify(entry))
	f.close()
	return true

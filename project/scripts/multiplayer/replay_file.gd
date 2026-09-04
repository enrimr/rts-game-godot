class_name ReplayFile
extends RefCounted

## Replay container: the authoritative snapshot stream StateReplicator already
## produces for multiplayer clients, written to disk instead of (or besides)
## the wire. A replay is a zstd-compressed sequence of store_var records:
## first the header (match config with the RESOLVED seed, so playback reboots
## the identical world), then {t, k, d} packets — t seconds of match clock,
## k "e" (reliable events: spawns/removals/keyframes/game-over) or "s" (dense
## state deltas), d the very dict the client path already knows how to apply.
## Faithful by construction: no re-simulation, so the engine's physics
## nondeterminism cannot rewrite history.

const DIR: String = "user://replays/"
const EXT: String = ".calrep"
const FORMAT_VERSION: int = 1

var _file: FileAccess = null
var _path: String = ""

## ── Recording ────────────────────────────────────────────────────────────────

func open_for_write(header: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	_path = DIR + "replay_%04d%02d%02d_%02d%02d%02d%s" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, EXT]
	_file = FileAccess.open_compressed(_path, FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD)
	if _file == null:
		return false
	header["format"] = FORMAT_VERSION
	header["timestamp"] = int(Time.get_unix_time_from_system())
	_file.store_var(header)
	return true

## t = SIMULATED seconds since match start (physics clock), never wall time:
## playback advances the same clock, so the speed buttons scale both alike.
func append(kind: String, d: Dictionary, t: float) -> void:
	if _file == null:
		return
	_file.store_var({"t": t, "k": kind, "d": d})

func finalize() -> void:
	if _file != null:
		_file.close()
		_file = null

func path() -> String:
	return _path

## ── Reading ──────────────────────────────────────────────────────────────────

static func read_header(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open_compressed(path, FileAccess.READ,
		FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var header: Variant = f.get_var()
	f.close()
	if not (header is Dictionary) \
			or ((header as Dictionary).get("format", 0) as int) > FORMAT_VERSION:
		return {}
	return header as Dictionary

## Opens positioned AFTER the header, ready to stream packets with get_var().
static func open_packets(path: String) -> FileAccess:
	var f: FileAccess = FileAccess.open_compressed(path, FileAccess.READ,
		FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var header: Variant = f.get_var()
	if not (header is Dictionary):
		f.close()
		return null
	return f

static func list_replays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	DirAccess.make_dir_recursive_absolute(DIR)
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(EXT):
			var header: Dictionary = read_header(DIR + fname)
			if not header.is_empty():
				header["path"] = DIR + fname
				out.append(header)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("timestamp", 0) as int) > (b.get("timestamp", 0) as int))
	return out

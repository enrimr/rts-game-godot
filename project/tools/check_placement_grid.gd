extends SceneTree

# Locally-runnable validation of PlacementGrid (GUT isn't vendored locally).
# Also re-derives the CURRENT game_world wall formula inline and asserts
# PlacementGrid.segment_positions matches it exactly, so the grid helper is a
# faithful stand-in for the wall behaviour before Option B wires it in.
# Run: godot --headless -s tools/check_placement_grid.gd

const PG := preload("res://scripts/map/placement_grid.gd")

var _fails: int = 0

func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("PASS " if ok else "FAIL ") + label + "  got=%s want=%s" % [got, want])
	if not ok: _fails += 1

# Verbatim copy of game_world._wall_segment_positions (the source of truth today).
func _wall_formula(start: Vector2, end: Vector2, step: float) -> Array:
	var delta: Vector2 = end - start
	var dist: float = delta.length()
	if dist < step * 0.5:
		return []
	var dir: Vector2 = delta.normalized()
	var count: int = maxi(1, int(dist / step))
	var result: Array = []
	for i: int in range(count):
		result.append(start + dir * (step * 0.5 + i * step))
	return result

func _initialize() -> void:
	_check("snap centre", PG.snap(Vector2(1, 1)), Vector2(8, 8))
	_check("snap idempotent", PG.snap(PG.snap(Vector2(123.4, 77.9))), PG.snap(Vector2(123.4, 77.9)))
	_check("snap negative", PG.snap(Vector2(-17, -9)), Vector2(-24, -8))
	_check("footprint even→corner", fmod(PG.snap_footprint(Vector2(20, 20), Vector2(32, 32)).x, 16.0), 0.0)
	_check("footprint cells barracks", PG.footprint_cells(Vector2(72, 72)), Vector2i(5, 5))
	_check("overlap touching=false", PG.footprints_overlap(Vector2(0,0), Vector2(48,48), Vector2(48,0), Vector2(48,48)), false)
	_check("overlap close=true", PG.footprints_overlap(Vector2(0,0), Vector2(48,48), Vector2(40,0), Vector2(48,48)), true)

	# Fidelity: PlacementGrid.segment_positions == current game_world formula
	# across a spread of drags.
	var cases: Array = [
		[Vector2(0,0), Vector2(64,0), 16.0],
		[Vector2(0,0), Vector2(64,64), 16.0],
		[Vector2(10,5), Vector2(200,40), 16.0],
		[Vector2(0,0), Vector2(4,0), 16.0],   # too short → []
		[Vector2(-50,-50), Vector2(50,50), 16.0],
	]
	for c: Array in cases:
		var a: Array = PG.segment_positions(c[0], c[1], c[2])
		var b: Array = _wall_formula(c[0], c[1], c[2])
		var same: bool = a.size() == b.size()
		if same:
			for i: int in range(a.size()):
				if (a[i] as Vector2).distance_to(b[i] as Vector2) > 0.001:
					same = false
					break
		_check("wall formula fidelity %s→%s" % [c[0], c[1]], same, true)

	print("CHECK_PLACEMENT_GRID: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)

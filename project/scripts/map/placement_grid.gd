class_name PlacementGrid
extends RefCounted

## Pure placement-grid helpers for the (future) snap-to-grid building system.
##
## This module holds ONLY pure functions (no scene tree, no autoloads, no
## physics) so the snap/alignment maths can be unit-tested in isolation before
## game_world.gd is wired to use it. Wiring it in is the actual "Option B" step;
## these helpers + their tests are the safety net created first.
##
## CELL_SIZE matches the existing wall segment step (16 px), so walls, gates and
## buildings all share one grid. A unit is a 12 px-radius capsule (24 px wide),
## so a single empty cell is wide enough for a unit to pass.

const CELL_SIZE: float = 16.0

## Snap a world position to the centre of its grid cell. With a default
## CELL_SIZE the returned point is always on a (n+0.5)*CELL_SIZE lattice, so
## equal-size buildings placed on adjacent cells tile without sub-pixel drift.
static func snap(pos: Vector2, cell: float = CELL_SIZE) -> Vector2:
	return Vector2(_snap_axis(pos.x, cell), _snap_axis(pos.y, cell))

static func _snap_axis(v: float, cell: float) -> float:
	return (floorf(v / cell) + 0.5) * cell

## Snap so that a footprint of the given size stays grid-aligned. Even-cell
## footprints (e.g. 2x2 cells) snap to a cell CORNER; odd-cell footprints snap
## to a cell CENTRE. This keeps a building's edges flush with the lattice
## regardless of its size, which is what lets the nav-bake margin grow without
## leaving sub-cell slivers between neighbours.
static func snap_footprint(pos: Vector2, size: Vector2, cell: float = CELL_SIZE) -> Vector2:
	return Vector2(
		_snap_axis_for_extent(pos.x, size.x, cell),
		_snap_axis_for_extent(pos.y, size.y, cell))

static func _snap_axis_for_extent(v: float, extent: float, cell: float) -> float:
	var cells: int = int(round(extent / cell))
	if cells % 2 == 0:
		# even number of cells → align centre to a lattice line (corner)
		return roundf(v / cell) * cell
	# odd → align centre to a cell centre
	return (floorf(v / cell) + 0.5) * cell

## Whole grid cells a footprint of `size` occupies on each axis (min 1).
static func footprint_cells(size: Vector2, cell: float = CELL_SIZE) -> Vector2i:
	return Vector2i(maxi(1, int(ceilf(size.x / cell))), maxi(1, int(ceilf(size.y / cell))))

## Evenly spaced segment centres from `start` to `end`, `step` apart. Mirrors
## the wall-drag distribution currently in game_world._wall_segment_positions
## (first segment at half a step in, one per whole step covered). Returns [] for
## a drag shorter than half a step.
static func segment_positions(start: Vector2, end: Vector2, step: float) -> Array[Vector2]:
	var delta: Vector2 = end - start
	var dist: float = delta.length()
	if dist < step * 0.5:
		return []
	var dir: Vector2 = delta.normalized()
	var count: int = maxi(1, int(dist / step))
	var result: Array[Vector2] = []
	for i: int in range(count):
		result.append(start + dir * (step * 0.5 + i * step))
	return result

## Whether two axis-aligned footprints (centre + size) overlap. Used to validate
## grid placement without a physics query. Touching edges do NOT count as overlap.
static func footprints_overlap(a_pos: Vector2, a_size: Vector2, b_pos: Vector2, b_size: Vector2) -> bool:
	var dx: float = absf(a_pos.x - b_pos.x)
	var dy: float = absf(a_pos.y - b_pos.y)
	return dx < (a_size.x + b_size.x) * 0.5 and dy < (a_size.y + b_size.y) * 0.5

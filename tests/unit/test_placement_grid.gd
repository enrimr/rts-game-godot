extends GutTest

## Safety net for the snap-to-grid placement work (Option B).
##
## PlacementGrid is the pure maths layer the future grid placement will use.
## These tests pin its behaviour BEFORE game_world.gd is wired to it, and they
## also characterize the current wall-drag distribution (segment_positions
## mirrors game_world._wall_segment_positions exactly) so the wall behaviour
## cannot silently change when the grid is introduced.

const PG := preload("res://scripts/map/placement_grid.gd")

# --- snap ---------------------------------------------------------------------

func test_snap_lands_on_cell_centre() -> void:
	# Any point inside cell [0,16) snaps to its centre (8,8).
	assert_eq(PG.snap(Vector2(1, 1)),   Vector2(8, 8))
	assert_eq(PG.snap(Vector2(15, 9)),  Vector2(8, 8))
	assert_eq(PG.snap(Vector2(17, 0)),  Vector2(24, 8), "next cell over → 24")

func test_snap_is_idempotent() -> void:
	# Snapping an already-snapped point must not move it (no drift).
	var p: Vector2 = PG.snap(Vector2(123.4, 77.9))
	assert_eq(PG.snap(p), p, "snap(snap(x)) == snap(x)")

func test_snap_negative_coords() -> void:
	# floor-based snap is consistent across the origin (no rounding-toward-zero gap).
	assert_eq(PG.snap(Vector2(-1, -1)),  Vector2(-8, -8))
	assert_eq(PG.snap(Vector2(-17, -9)), Vector2(-24, -8))

func test_adjacent_cells_tile_without_gap() -> void:
	# Two 16x16 footprints on neighbouring snapped centres are exactly one cell
	# apart and their edges meet — no sub-pixel sliver (the tiny-gap root cause).
	var a: Vector2 = PG.snap(Vector2(3, 3))
	var b: Vector2 = PG.snap(Vector2(19, 3))
	assert_eq(b.x - a.x, 16.0, "neighbours are exactly one cell apart")

# --- snap_footprint (size-aware alignment) ------------------------------------

func test_footprint_even_cells_snaps_to_corner() -> void:
	# A 32x32 building = 2x2 cells → centre lands on a lattice line (multiple of 16).
	var p: Vector2 = PG.snap_footprint(Vector2(20, 20), Vector2(32, 32))
	assert_eq(fmod(p.x, 16.0), 0.0, "even-cell footprint centre on a grid line")
	assert_eq(fmod(p.y, 16.0), 0.0)

func test_footprint_odd_cells_snaps_to_centre() -> void:
	# A 48x48 building = 3x3 cells → centre lands on a cell centre (8 + n*16).
	var p: Vector2 = PG.snap_footprint(Vector2(20, 20), Vector2(48, 48))
	assert_eq(fmod(p.x - 8.0, 16.0), 0.0, "odd-cell footprint centre on a cell centre")

func test_footprint_cells_count() -> void:
	assert_eq(PG.footprint_cells(Vector2(48, 48)), Vector2i(3, 3), "house = 3x3 cells")
	assert_eq(PG.footprint_cells(Vector2(72, 72)), Vector2i(5, 5), "barracks = 5x5 cells")
	assert_eq(PG.footprint_cells(Vector2(16, 16)), Vector2i(1, 1), "wall = 1 cell")

# --- segment_positions (characterizes current wall drag) ----------------------

func test_segment_positions_matches_current_wall_formula() -> void:
	# Horizontal drag of 64 px at step 16 → 4 segments at 8,24,40,56.
	var segs: Array = PG.segment_positions(Vector2(0, 0), Vector2(64, 0), 16.0)
	assert_eq(segs.size(), 4, "64/16 = 4 segments")
	assert_eq(segs[0], Vector2(8, 0),  "first segment half a step in")
	assert_eq(segs[3], Vector2(56, 0), "last segment")

func test_segment_positions_too_short_returns_empty() -> void:
	assert_eq(PG.segment_positions(Vector2(0, 0), Vector2(4, 0), 16.0).size(), 0,
		"drag shorter than half a step places nothing")

func test_segment_positions_diagonal_spacing() -> void:
	var segs: Array = PG.segment_positions(Vector2(0, 0), Vector2(64, 64), 16.0)
	assert_gt(segs.size(), 0, "diagonal drag still produces segments")
	# consecutive segments are `step` apart along the line
	if segs.size() >= 2:
		assert_almost_eq((segs[1] - segs[0]).length(), 16.0, 0.01)

# --- footprints_overlap -------------------------------------------------------

func test_overlap_detection() -> void:
	# Two 48x48 buildings 48 px apart: edges exactly touch → NOT overlapping.
	assert_false(PG.footprints_overlap(Vector2(0, 0), Vector2(48, 48), Vector2(48, 0), Vector2(48, 48)),
		"touching edges do not count as overlap")
	# 40 px apart → overlapping.
	assert_true(PG.footprints_overlap(Vector2(0, 0), Vector2(48, 48), Vector2(40, 0), Vector2(48, 48)))

func test_overlap_is_symmetric() -> void:
	var a_pos: Vector2 = Vector2(10, 10)
	var b_pos: Vector2 = Vector2(30, 12)
	var s: Vector2 = Vector2(48, 48)
	assert_eq(PG.footprints_overlap(a_pos, s, b_pos, s), PG.footprints_overlap(b_pos, s, a_pos, s))

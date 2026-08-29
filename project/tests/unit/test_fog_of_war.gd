extends GutTest

## Tests for FogOfWar (project/scripts/map/fog_of_war.gd).
##
## What is covered:
##   - Initial cell state after _ready()
##   - get_cell_state() bounds checking
##   - reveal_all() sets every cell to STATE_VISIBLE
##   - _mark_circle() (tested via the public get_cell_state API) marks cells
##     inside a radius as STATE_VISIBLE and leaves cells outside unchanged
##   - _tick() decays STATE_VISIBLE → STATE_EXPLORED when no units supply LOS
##   - Explored persistence: a cell that was VISIBLE never regresses to
##     STATE_UNEXPLORED after a tick removes LOS
##   - World-to-cell mapping at known coordinates
##
## What is NOT covered:
##   - Rendering (Image / ImageTexture pixel colours) — engine internals
##   - apply_visibility node visibility — requires live scene tree with real
##     unit/building nodes; covered by integration tests instead
##
## Setup note:
##   setup() is intentionally skipped in most tests because it connects to the
##   GameManager.game_over signal.  All state-machine logic that matters for the
##   public API works correctly without calling setup(), because _ready() (fired
##   by add_child_autofree) initialises _cells, _image, _texture, and _sprite.
##   Tests that exercise _tick() pass null nodes; the guarded iteration in
##   _reveal_from_units / _reveal_from_buildings / _apply_visibility safely
##   skips null references.

var _fow: FogOfWar
var _saved_map_size: int = MatchConfig.MapSize.MEDIUM

## MEDIUM-map geometry mirrored here so test assertions are self-documenting.
## The grid is sized from MatchConfig.get_map_half() + FogOfWar.GRID_MARGIN in
## _ready(), so before_each pins the map size the numbers below assume.
const CELL_SIZE: float = 50.0
const MAP_ORIGIN: Vector2 = Vector2(-2000.0, -2000.0)
const GRID_W: int = 80
const GRID_H: int = 80

func before_each() -> void:
	_saved_map_size = MatchConfig.map_size
	MatchConfig.map_size = MatchConfig.MapSize.MEDIUM
	_fow = FogOfWar.new()
	add_child_autofree(_fow)

func after_each() -> void:
	MatchConfig.map_size = _saved_map_size


# ---------------------------------------------------------------------------
# 1. Initial state
# ---------------------------------------------------------------------------

func test_all_cells_start_unexplored() -> void:
	## Every cell must be STATE_UNEXPLORED immediately after _ready().
	## Sample the four corners and the centre — if the array was not filled
	## correctly any of these would deviate.
	var corners: Array[Vector2] = [
		Vector2(-2000.0, -2000.0),   # top-left  → cell (0,0)
		Vector2(1975.0, -2000.0),    # top-right  → cell (79,0)
		Vector2(-2000.0,  1975.0),   # bot-left   → cell (0,79)
		Vector2(1975.0,  1975.0),    # bot-right  → cell (79,79)
		Vector2(0.0,     0.0),       # centre     → cell (40,40)
	]
	for pos: Vector2 in corners:
		assert_eq(
			_fow.get_cell_state(pos),
			FogOfWar.STATE_UNEXPLORED,
			"Expected STATE_UNEXPLORED at %s on fresh FogOfWar" % pos
		)


# ---------------------------------------------------------------------------
# 2. get_cell_state — out-of-bounds handling
# ---------------------------------------------------------------------------

func test_get_cell_state_returns_unexplored_for_position_north_of_map() -> void:
	## y < MAP_ORIGIN.y is out of bounds; the function must return
	## STATE_UNEXPLORED (same as the default "black" state) rather than
	## crash or read garbage memory.
	var pos: Vector2 = Vector2(0.0, -3000.0)
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_UNEXPLORED)

func test_get_cell_state_returns_unexplored_for_position_south_of_map() -> void:
	var pos: Vector2 = Vector2(0.0, 3000.0)
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_UNEXPLORED)

func test_get_cell_state_returns_unexplored_for_position_west_of_map() -> void:
	var pos: Vector2 = Vector2(-3000.0, 0.0)
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_UNEXPLORED)

func test_get_cell_state_returns_unexplored_for_position_east_of_map() -> void:
	## Vector2(2000,0) maps to cell x=80, which is >= GRID_W → out of bounds.
	var pos: Vector2 = Vector2(2000.0, 0.0)
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_UNEXPLORED)


# ---------------------------------------------------------------------------
# 3. get_cell_state — in-bounds reads
# ---------------------------------------------------------------------------

func test_get_cell_state_reads_correct_value_for_centre_cell() -> void:
	## Vector2(0,0) maps to cell (40,40) exactly.
	## After _ready() the state is UNEXPLORED; this test confirms the read
	## path reaches the right array index.
	assert_eq(_fow.get_cell_state(Vector2(0.0, 0.0)), FogOfWar.STATE_UNEXPLORED)

func test_get_cell_state_reads_top_left_corner_cell() -> void:
	## (-2000,-2000) → rel=(0,0) → cell (0,0).
	assert_eq(_fow.get_cell_state(Vector2(-2000.0, -2000.0)), FogOfWar.STATE_UNEXPLORED)

func test_get_cell_state_reads_last_valid_cell() -> void:
	## (1975,1975) → rel=(79.5,79.5) → int truncation → cell (79,79).
	assert_eq(_fow.get_cell_state(Vector2(1975.0, 1975.0)), FogOfWar.STATE_UNEXPLORED)


# ---------------------------------------------------------------------------
# 4. reveal_all
# ---------------------------------------------------------------------------

func test_reveal_all_sets_every_sampled_cell_to_visible() -> void:
	_fow.reveal_all()
	var sample_positions: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(-1990.0, -1990.0),
		Vector2(1975.0, 1975.0),
		Vector2(-500.0, 750.0),
		Vector2(300.0, -800.0),
	]
	for pos: Vector2 in sample_positions:
		assert_eq(
			_fow.get_cell_state(pos),
			FogOfWar.STATE_VISIBLE,
			"Expected STATE_VISIBLE at %s after reveal_all()" % pos
		)

func test_reveal_all_does_not_affect_out_of_bounds_queries() -> void:
	## Out-of-bounds positions must still return STATE_UNEXPLORED even after
	## reveal_all(), because get_cell_state() guards the array access.
	_fow.reveal_all()
	assert_eq(_fow.get_cell_state(Vector2(5000.0, 5000.0)), FogOfWar.STATE_UNEXPLORED)


# ---------------------------------------------------------------------------
# 5. World-to-cell mapping (via public get_cell_state)
# ---------------------------------------------------------------------------

func test_world_to_cell_centre_of_map() -> void:
	## Vector2(0,0) must land exactly on cell (40,40).
	## We prove this by marking only cell (40,40) and checking its neighbours.
	## _mark_circle with a sub-cell radius 10px → r=ceil(10/50)+1=1, r²=1.
	## Only (dx,dy) pairs where dx²+dy² <= 1 are marked: (0,0), (±1,0), (0,±1).
	## So cells two steps away must still be UNEXPLORED.
	_fow._mark_circle(Vector2(0.0, 0.0), 10.0)
	assert_eq(
		_fow.get_cell_state(Vector2(0.0, 0.0)),
		FogOfWar.STATE_VISIBLE,
		"Centre cell (40,40) must be VISIBLE after _mark_circle at origin"
	)
	## Cell (40+3, 40) corresponds to world x = -2000 + (40+3)*50 = -2000+2150 = 150.
	assert_eq(
		_fow.get_cell_state(Vector2(150.0, 0.0)),
		FogOfWar.STATE_UNEXPLORED,
		"Cell three steps east must remain UNEXPLORED with tiny radius"
	)

func test_top_left_cell_is_accessible_via_map_origin() -> void:
	## Marking MAP_ORIGIN should change the cell at (0,0) — not wrap or panic.
	_fow._mark_circle(Vector2(-2000.0, -2000.0), 10.0)
	assert_eq(
		_fow.get_cell_state(Vector2(-2000.0, -2000.0)),
		FogOfWar.STATE_VISIBLE
	)


# ---------------------------------------------------------------------------
# 6. _mark_circle — cells within radius become VISIBLE, outside remain unchanged
# ---------------------------------------------------------------------------

func test_mark_circle_centre_cell_becomes_visible() -> void:
	var origin: Vector2 = Vector2(500.0, 500.0)
	_fow._mark_circle(origin, 50.0)
	assert_eq(_fow.get_cell_state(origin), FogOfWar.STATE_VISIBLE)

func test_mark_circle_does_not_mark_distant_cell() -> void:
	## Mark a circle of radius 50px (one-cell radius) around (500,500).
	## A position 300px away is well outside that radius and must be UNEXPLORED.
	_fow._mark_circle(Vector2(500.0, 500.0), 50.0)
	var far_pos: Vector2 = Vector2(800.0, 500.0)
	assert_eq(_fow.get_cell_state(far_pos), FogOfWar.STATE_UNEXPLORED)

func test_mark_circle_large_radius_marks_cells_at_boundary() -> void:
	## Radius 250px = 5 cells from origin.
	## r = ceil(250/50)+1 = 6, r² = 36.
	## A cell 4 cells (200px) away from origin: dx=4,dy=0 → dist²=16 ≤ 36 → VISIBLE.
	var origin: Vector2 = Vector2(0.0, 0.0)
	_fow._mark_circle(origin, 250.0)
	## 4 cells east of origin: world x = -2000 + (40+4)*50 = -2000+2200 = 200.
	assert_eq(
		_fow.get_cell_state(Vector2(200.0, 0.0)),
		FogOfWar.STATE_VISIBLE,
		"Cell 4 steps east should be VISIBLE inside 250px radius"
	)

func test_mark_circle_does_not_mark_cells_just_outside_large_radius() -> void:
	## Radius 250px: r=6, r²=36.
	## dx=7,dy=0 → dist²=49 > 36 → must be UNEXPLORED.
	## World x = -2000 + (40+7)*50 = -2000+2350 = 350.
	var origin: Vector2 = Vector2(0.0, 0.0)
	_fow._mark_circle(origin, 250.0)
	assert_eq(
		_fow.get_cell_state(Vector2(350.0, 0.0)),
		FogOfWar.STATE_UNEXPLORED,
		"Cell 7 steps east should remain UNEXPLORED outside 250px radius"
	)

func test_mark_circle_near_grid_boundary_does_not_crash() -> void:
	## Marking a circle that partially extends past the grid edge must not
	## panic — _mark_circle bounds-clamps each cell with nx/ny range checks.
	_fow._mark_circle(Vector2(-1990.0, -1990.0), 200.0)
	## The origin cell itself must be VISIBLE.
	assert_eq(
		_fow.get_cell_state(Vector2(-1990.0, -1990.0)),
		FogOfWar.STATE_VISIBLE
	)


# ---------------------------------------------------------------------------
# 7. _tick — VISIBLE → EXPLORED decay with no units providing LOS
# ---------------------------------------------------------------------------

func test_tick_decays_visible_cells_to_explored() -> void:
	## Put a known cell into STATE_VISIBLE, then call _tick() with no unit
	## nodes (null).  The tick must decay it to STATE_EXPLORED.
	_fow._mark_circle(Vector2(0.0, 0.0), 50.0)
	assert_eq(_fow.get_cell_state(Vector2(0.0, 0.0)), FogOfWar.STATE_VISIBLE)

	_fow._tick()

	assert_eq(
		_fow.get_cell_state(Vector2(0.0, 0.0)),
		FogOfWar.STATE_EXPLORED,
		"STATE_VISIBLE must decay to STATE_EXPLORED after a tick with no LOS sources"
	)

func test_tick_does_not_change_unexplored_cells() -> void:
	## Cells that are still UNEXPLORED must stay UNEXPLORED after a tick.
	var pos: Vector2 = Vector2(700.0, 700.0)
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_UNEXPLORED)
	_fow._tick()
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_UNEXPLORED)

func test_tick_does_not_change_explored_cells() -> void:
	## An already EXPLORED cell (went VISIBLE once, then was ticked) must stay
	## EXPLORED — not regress further — on a second tick.
	_fow._mark_circle(Vector2(0.0, 0.0), 50.0)
	_fow._tick()   # VISIBLE → EXPLORED
	_fow._tick()   # EXPLORED must stay EXPLORED
	assert_eq(
		_fow.get_cell_state(Vector2(0.0, 0.0)),
		FogOfWar.STATE_EXPLORED,
		"STATE_EXPLORED must not regress to UNEXPLORED on subsequent ticks"
	)


# ---------------------------------------------------------------------------
# 8. Explored persistence — cells never regress to UNEXPLORED
# ---------------------------------------------------------------------------

func test_explored_cell_never_reverts_to_unexplored_after_multiple_ticks() -> void:
	## Simulate a unit passing through: mark visible, tick away, tick again,
	## tick again.  The cell must remain EXPLORED indefinitely.
	var pos: Vector2 = Vector2(200.0, -300.0)
	_fow._mark_circle(pos, 50.0)
	assert_eq(_fow.get_cell_state(pos), FogOfWar.STATE_VISIBLE)

	for _i: int in range(5):
		_fow._tick()

	var final_state: int = _fow.get_cell_state(pos)
	assert_true(
		final_state == FogOfWar.STATE_EXPLORED or final_state == FogOfWar.STATE_VISIBLE,
		"Cell must stay EXPLORED (or VISIBLE) — never revert to UNEXPLORED"
	)
	assert_true(
		final_state != FogOfWar.STATE_UNEXPLORED,
		"Cell must not regress to STATE_UNEXPLORED after being explored"
	)

func test_multiple_mark_circle_calls_accumulate_without_resetting_explored() -> void:
	## Marking a different circle must not reset cells that were already
	## explored outside the new circle.
	var pos_a: Vector2 = Vector2(0.0, 0.0)
	var pos_b: Vector2 = Vector2(600.0, 600.0)

	_fow._mark_circle(pos_a, 50.0)
	_fow._tick()  # pos_a neighbourhood → EXPLORED

	_fow._mark_circle(pos_b, 50.0)
	# pos_a neighbourhood should still be EXPLORED, not UNEXPLORED
	assert_eq(
		_fow.get_cell_state(pos_a),
		FogOfWar.STATE_EXPLORED,
		"Previously explored cell must remain EXPLORED after marking a different circle"
	)


# ---------------------------------------------------------------------------
# 9. Grid sizing — the grid must cover the actual playable map
# ---------------------------------------------------------------------------

func test_medium_map_keeps_the_historical_grid() -> void:
	## MEDIUM (±1800) + the 200 px margin is exactly the old fixed 80×80 rect.
	assert_eq(_fow.grid_w, GRID_W)
	assert_eq(_fow.grid_h, GRID_H)
	assert_eq(_fow.map_origin, MAP_ORIGIN)

func test_large_map_grid_covers_the_margins() -> void:
	## The regression: on a LARGE map (±2600) the old fixed ±2000 grid left a
	## 600 px ring permanently unfogged — the minimap showed islands at the
	## margins without ever scouting them. A position out there must now be a
	## real (unexplored, markable) cell instead of falling off the grid.
	MatchConfig.map_size = MatchConfig.MapSize.LARGE
	var fow: FogOfWar = FogOfWar.new()
	add_child_autofree(fow)
	var margin_pos: Vector2 = Vector2(2500.0, 2500.0)
	assert_eq(fow.get_cell_state(margin_pos), FogOfWar.STATE_UNEXPLORED)
	fow._mark_circle(margin_pos, 50.0)
	assert_eq(fow.get_cell_state(margin_pos), FogOfWar.STATE_VISIBLE,
		"the fog grid must reach the margins of a LARGE map")

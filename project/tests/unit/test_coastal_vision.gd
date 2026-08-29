extends GutTest

## Atlantes coastal vision: the "coastal_vision" civ multiplier (1.50) widens
## line of sight while the unit or building stands inside the coastal band
## (WeatherManager.COASTAL_ZONE_DEPTH — the same band sea fog works in). The
## multiplier existed in atlantes.tres from the start but nothing read it, so the
## bonus its description promises was not in the game at all.

const LAND_HALF: float = 1000.0
# 100 px inland from the shore, so the coastal bonus applies.
const COASTAL_POS: Vector2 = Vector2(900.0, 0.0)
# Dead centre of the island, 1000 px from any shore — outside the band.
const INLAND_POS: Vector2 = Vector2.ZERO

# A watcher with no unit_data gets the 5.0 LOS default → 320 px, which _mark_circle
# rounds up to 8 grid cells; the Atlantes 480 px reaches 11. A probe 10 cells away
# therefore separates the two, and one 6 cells away is inside both.
const NEAR_PROBE_STEPS: int = 6
const FAR_PROBE_STEPS: int = 10

class Watcher extends Node2D:
	var player_id: int = 0

func before_each() -> void:
	TerrainManager.reset()
	TerrainManager.set_land_polys([PackedVector2Array([
		Vector2(-LAND_HALF, -LAND_HALF), Vector2(LAND_HALF, -LAND_HALF),
		Vector2(LAND_HALF, LAND_HALF), Vector2(-LAND_HALF, LAND_HALF),
	])], true)

func after_each() -> void:
	TerrainManager.reset()
	CivBonusManager.init_player(0, "franks")

## World position `steps` grid cells east of `origin`, inside that cell. The
## fog grid origin is always a multiple of CELL_SIZE, so cell boundaries fall
## on multiples of CELL_SIZE regardless of the map size.
func _probe(origin: Vector2, steps: int) -> Vector2:
	var cell_x: int = int(floor(origin.x / FogOfWar.CELL_SIZE)) + steps
	return Vector2((float(cell_x) + 0.5) * FogOfWar.CELL_SIZE, origin.y)

## One independent fog instance per measurement: revealed cells never decay back
## to unexplored, so two civs cannot share a grid.
func _state_seen_by(civ: String, watcher_pos: Vector2, probe: Vector2) -> int:
	CivBonusManager.init_player(0, civ)
	var units: Node2D = Node2D.new()
	add_child_autofree(units)
	var fow: FogOfWar = FogOfWar.new()
	add_child_autofree(fow)
	fow._units_node = units
	var w: Watcher = Watcher.new()
	units.add_child(w)
	w.global_position = watcher_pos
	fow._tick()
	return fow.get_cell_state(probe)

# 1 — the bonus is real: Atlantes see further along the shore than another civ
func test_atlantes_see_further_on_the_coast() -> void:
	var probe: Vector2 = _probe(COASTAL_POS, FAR_PROBE_STEPS)
	assert_eq(_state_seen_by("franks", COASTAL_POS, probe), FogOfWar.STATE_UNEXPLORED,
		"a continental civ does not reach that far")
	assert_eq(_state_seen_by("atlantes", COASTAL_POS, probe), FogOfWar.STATE_VISIBLE,
		"the Atlantes coastal_vision bonus stretches line of sight to it")

# 2 — the base sight radius is untouched, so the only difference is the bonus
func test_base_line_of_sight_is_unchanged() -> void:
	var probe: Vector2 = _probe(COASTAL_POS, NEAR_PROBE_STEPS)
	assert_eq(_state_seen_by("franks", COASTAL_POS, probe), FogOfWar.STATE_VISIBLE,
		"inside the normal 320 px radius every civ sees the same")

# 3 — it is a *coastal* bonus: inland the Atlantes see like anybody else
func test_bonus_does_not_apply_inland() -> void:
	var probe: Vector2 = _probe(INLAND_POS, FAR_PROBE_STEPS)
	assert_eq(_state_seen_by("atlantes", INLAND_POS, probe), FogOfWar.STATE_UNEXPLORED,
		"1000 px from the shore the bonus is off")

# 4 — the multiplier comes from the civ resource, not from code
func test_multiplier_is_data_driven() -> void:
	CivBonusManager.init_player(0, "atlantes")
	assert_eq(CivBonusManager.get_multiplier(0, "coastal_vision"), 1.50,
		"atlantes.tres declares the 1.50 coastal vision multiplier")
	CivBonusManager.init_player(0, "franks")
	assert_eq(CivBonusManager.get_multiplier(0, "coastal_vision"), 1.0,
		"civs without the key fall back to no bonus")

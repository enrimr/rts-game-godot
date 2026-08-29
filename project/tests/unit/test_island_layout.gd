extends GutTest

## MapGenerator._island_layout — the Islands map ring solver.
##
## Islands used to be sized as a fixed share of the map (0.30 * map_half for 3+
## players), which on a small 4-player map put neighbouring islands on top of
## each other: they merged into one land mass and, worse, their overlapping hole
## outlines made the ocean navigation mesh come out empty, freezing every ship.
## The solver now derives the radius from the ring geometry, so these tests check
## the invariant it exists for: at the bumpiest the island outline can get, and
## with both centers jittered towards each other, adjacent islands still keep a
## channel of open water and no island crosses the map boundary.

const MIN_PLAYERS: int = 2
## Lobby cap: 3 rivals + the human player.
const MAX_PLAYERS: int = 4
## Headroom the solver must survive without merging islands if the lobby ever
## offers more rivals (the radius floor takes over from the channel there).
const OVER_CAPACITY: int = 8

const MAP_SIZES: Array[int] = [
	MatchConfig.MapSize.SMALL, MatchConfig.MapSize.MEDIUM, MatchConfig.MapSize.LARGE]

func _layout(map_half: float, players: int) -> Dictionary:
	var gen: MapGenerator = MapGenerator.new()
	gen._map_half = map_half
	return gen._island_layout(players)

## Closest approach between two adjacent islands, worst case: both blobs at
## maximum bulge, both centers jittered straight at each other.
func _worst_channel(layout: Dictionary, players: int) -> float:
	var ring: float = layout["ring"] as float
	var extent: float = (layout["radius"] as float) * MapGenerator.ISLAND_BLOB_MAX
	var n: int = maxi(players, 2)
	var center_gap: float = 2.0 * ring * sin(PI / float(n))
	return center_gap - 2.0 * extent - 2.0 * MapGenerator.ISLAND_CENTER_JITTER

## Furthest an island reaches from the map center, same worst case.
func _worst_reach(layout: Dictionary) -> float:
	return (layout["ring"] as float) \
		+ (layout["radius"] as float) * MapGenerator.ISLAND_BLOB_MAX \
		+ MapGenerator.ISLAND_CENTER_JITTER

func test_adjacent_islands_keep_a_channel_on_every_configuration() -> void:
	for size: int in MAP_SIZES:
		var map_half: float = MatchConfig.MAP_HALF_BY_SIZE[size]
		for players: int in range(MIN_PLAYERS, MAX_PLAYERS + 1):
			var layout: Dictionary = _layout(map_half, players)
			assert_gt(_worst_channel(layout, players), MapGenerator.ISLAND_CHANNEL - 1.0,
				"map_half=%d players=%d: channel narrower than the transport lane" % [
					roundi(map_half), players])

func test_over_capacity_player_counts_still_do_not_merge_islands() -> void:
	for size: int in MAP_SIZES:
		var map_half: float = MatchConfig.MAP_HALF_BY_SIZE[size]
		for players: int in range(MAX_PLAYERS + 1, OVER_CAPACITY + 1):
			var layout: Dictionary = _layout(map_half, players)
			assert_gt(_worst_channel(layout, players), 0.0,
				"map_half=%d players=%d: islands touch and the ocean mesh breaks" % [
					roundi(map_half), players])

func test_islands_stay_inside_the_map_boundary() -> void:
	for size: int in MAP_SIZES:
		var map_half: float = MatchConfig.MAP_HALF_BY_SIZE[size]
		for players: int in range(MIN_PLAYERS, OVER_CAPACITY + 1):
			var layout: Dictionary = _layout(map_half, players)
			# The ocean mesh is cut to ±map_half; land past it is unreachable.
			assert_lt(_worst_reach(layout), map_half - MapGenerator.ISLAND_SHORE_MARGIN + 1.0,
				"map_half=%d players=%d: island spills past the shore margin" % [
					roundi(map_half), players])

func test_a_single_player_map_is_treated_as_two_islands() -> void:
	var one: Dictionary = _layout(1800.0, 1)
	var two: Dictionary = _layout(1800.0, 2)
	assert_eq(one["radius"], two["radius"], "no divide-by-sin(PI) blow-up for one player")

func test_islands_shrink_as_players_are_added() -> void:
	var previous: float = INF
	for players: int in range(MIN_PLAYERS, OVER_CAPACITY + 1):
		var radius: float = _layout(1800.0, players)["radius"] as float
		assert_lt(radius, previous + 0.001,
			"%d players must not get a bigger island than %d" % [players, players - 1])
		assert_gt(radius, 0.0, "%d players: island degenerated" % players)
		previous = radius

func test_two_players_still_get_a_generous_island() -> void:
	var layout: Dictionary = _layout(1800.0, 2)
	assert_between(layout["radius"] as float, 500.0, 1800.0 * 0.38,
		"a duel map should not shrink below the old hand-tuned radius")

extends GutTest

## MatchRng — the single seeded stream for all simulation randomness. The
## property everything rests on: same seed + same draw order = same values,
## for the whole set of draw methods.

func test_same_seed_reproduces_the_sequence() -> void:
	MatchRng.reset(1234)
	var first: Array = [MatchRng.randf(), MatchRng.randi(),
		MatchRng.randf_range(-50.0, 50.0), MatchRng.randi_range(3, 8)]
	MatchRng.reset(1234)
	var second: Array = [MatchRng.randf(), MatchRng.randi(),
		MatchRng.randf_range(-50.0, 50.0), MatchRng.randi_range(3, 8)]
	assert_eq(second, first, "resetting to the same seed replays the exact draws")

func test_different_seed_diverges() -> void:
	MatchRng.reset(1234)
	var a: float = MatchRng.randf()
	MatchRng.reset(9999)
	var b: float = MatchRng.randf()
	assert_ne(a, b, "a different match seed draws a different stream")

func test_ranges_are_respected() -> void:
	MatchRng.reset(42)
	for _i: int in range(50):
		var f: float = MatchRng.randf_range(-10.0, 10.0)
		assert_between(f, -10.0, 10.0)
		var n: int = MatchRng.randi_range(3, 8)
		assert_between(n, 3, 8)

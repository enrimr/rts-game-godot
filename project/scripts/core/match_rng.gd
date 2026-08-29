extends Node

## MatchRng (autoload) — the single seeded RNG stream for everything random in
## the SIMULATION: unit spawn jitter, animal wander, scout waypoints, weather
## rolls, projectile drift, AI position searches. GameWorld seeds it with the
## match seed right after deciding it, so a replay of the same seed draws the
## same sequence — provided the draw ORDER is identical, which is why nothing
## simulation-facing may call the global randf()/randi() (those are fine for
## local-only audio/visual noise that never feeds back into game state).

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func reset(match_seed: int) -> void:
	_rng.seed = match_seed

## Mid-match generator state, for SaveManager: a loaded game continues the
## exact draw sequence it left off instead of replaying the seed from scratch.
## Serialized as a String — the state is a full 64-bit value and JSON numbers
## are doubles (53-bit mantissa), so a raw int would silently lose bits.
func get_state() -> int:
	return _rng.state

func set_state(state: int) -> void:
	_rng.state = state

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func randi() -> int:
	return _rng.randi()

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

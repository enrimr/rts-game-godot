class_name SiegeFx extends RefCounted

## Shared siege-boulder visual: an arcing stone from `from` to `to`, freed on
## impact. Purely cosmetic — damage stays with the caller (`on_impact`), so
## the client-side replication echo can reuse it with no callback at all.
## On the multiplayer host every launch is reported for the echo stream.

const KIND_ARROW: int = 0
const KIND_BOULDER: int = 1

static func launch_boulder(parent: Node, from: Vector2, to: Vector2,
		on_impact: Callable = Callable()) -> void:
	if not is_instance_valid(parent):
		if on_impact.is_valid():
			on_impact.call()
		return
	var boulder: Polygon2D = Polygon2D.new()
	boulder.color = Color(0.45, 0.35, 0.20, 1.0)
	boulder.polygon = PackedVector2Array([
		Vector2(5, 0), Vector2(3.5, 3.5), Vector2(0, 5),
		Vector2(-3.5, 3.5), Vector2(-5, 0), Vector2(-3.5, -3.5),
		Vector2(0, -5), Vector2(3.5, -3.5),
	])
	boulder.z_index = IsoBillboard.Z_AIRBORNE
	parent.add_child(boulder)
	boulder.global_position = from

	if NetworkSession.is_host():
		EventBus.projectile_spawned.emit(from, to, KIND_BOULDER)

	var flight_time: float = clampf(from.distance_to(to) / 600.0, 0.4, 0.9)
	var peak: Vector2 = (from + to) * 0.5 + Vector2(0.0, -80.0)
	var traj: Tween = boulder.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	traj.tween_property(boulder, "global_position", peak, flight_time * 0.5)
	traj.set_ease(Tween.EASE_IN)
	traj.tween_property(boulder, "global_position", to, flight_time * 0.5)
	traj.tween_callback(boulder.queue_free)
	if on_impact.is_valid():
		traj.tween_callback(on_impact)

extends UnitBase

class_name Mangonel

const SPLASH_RADIUS: float = 72.0
const MIN_RANGE_RATIO: float = 0.35

func get_selection_sound() -> String:
	return "select_siege"

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 15.4, 5.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func order_attack_ground(world_pos: Vector2) -> void:
	attack_target = null
	_destination_state = UnitState.IDLE
	current_state = UnitState.IDLE
	nav_agent.set_velocity(Vector2.ZERO)
	_fire_at(world_pos)

# ── Combat machine hooks ──

# The approach only stops inside the firing band: past minimum range but
# within reach, so the mangonel never parks on top of its target.
func _in_attack_position(dist: float, reach: float) -> bool:
	return dist <= reach and dist >= reach * MIN_RANGE_RATIO

# Move away if target is too close (minimum range)
func _combat_reposition(dist: float, reach: float) -> bool:
	if dist >= reach * MIN_RANGE_RATIO:
		return false
	var away: Vector2 = global_position \
		+ (global_position - (attack_target as Node2D).global_position).normalized() * 120.0
	nav_agent.target_position = _safe_destination(away)
	nav_agent.set_velocity(_nav_velocity())
	return true

# _fire_at deals the splash damage, emits unit_attacked and plays the impact
# sound itself — no extra strike sound here.
func _execute_strike(target: Node) -> void:
	_fire_at((target as Node2D).global_position)

func _fire_at(target_pos: Vector2) -> void:
	# Drift impact point with wind/storm conditions
	var dist: float = global_position.distance_to(target_pos)
	var flight_time: float = clampf(dist / 500.0, 0.3, 0.8)
	var drifted_target: Vector2 = target_pos + WeatherManager.get_projectile_drift() * flight_time

	var dmg: float = _get_effective_attack() * CivBonusManager.get_siege_attack_bonus(player_id)
	# Splash: hit all units and buildings in radius around impact
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = SPLASH_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, drifted_target)
	query.collision_mask = 3
	var results: Array[Dictionary] = space.intersect_shape(query, 32)
	for result: Dictionary in results:
		var body: Node = result["collider"] as Node
		if not is_instance_valid(body):
			continue
		var body_pid: Variant = body.get("player_id")
		if body_pid == null or (body_pid as int) == player_id:
			continue
		var armor: float = _get_target_armor(body)
		var actual_dmg: float = maxf(dmg - armor, 1.0)
		if body.has_method("take_damage"):
			body.take_damage(actual_dmg, self)
			EventBus.unit_attacked.emit(self, body)
	AudioManager.play_if_visible("hit_ranged", global_position, -2.0)

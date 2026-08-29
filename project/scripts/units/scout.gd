extends UnitBase

class_name Scout

const EXPLORE_DURATION: float = 60.0
const EXPLORE_WAYPOINT_RADIUS: float = 400.0

var _exploring: bool = false
var _explore_timer: float = 0.0
var _explore_waypoint_cooldown: float = 0.0

func get_selection_sound() -> String:
	return "select_cavalry"

func _ready() -> void:
	super._ready()
	UnitDress.apply.call_deferred(self, player_id)

# Wider stripe under the horse's hooves so it reads as a mounted unit's banner
# without covering the horse/rider.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 9.9, 12.0)

# Wider, lower shadow to match the horse's longer footprint.
func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 15.0, 4.5, 11.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func start_auto_explore() -> void:
	_exploring = true
	_explore_timer = EXPLORE_DURATION
	_pick_explore_waypoint()

func stop_auto_explore() -> void:
	_exploring = false
	_explore_timer = 0.0

func is_exploring() -> bool:
	return _exploring

func get_explore_fraction() -> float:
	return clampf(_explore_timer / EXPLORE_DURATION, 0.0, 1.0)

func _combat_side_tick(delta: float) -> void:
	if not _exploring:
		return
	_explore_timer -= delta
	if _explore_timer <= 0.0:
		stop_auto_explore()
		return
	_explore_waypoint_cooldown -= delta
	if _explore_waypoint_cooldown <= 0.0 or current_state == UnitState.IDLE:
		_pick_explore_waypoint()

func _pick_explore_waypoint() -> void:
	_explore_waypoint_cooldown = MatchRng.randf_range(3.0, 7.0)
	var mh: float = TerrainManager.minimap_map_half * 0.92   # slight inset from edge
	for _i: int in range(12):
		var candidate: Vector2 = Vector2(
			MatchRng.randf_range(-mh, mh),
			MatchRng.randf_range(-mh, mh)
		)
		if not TerrainManager.is_impassable_for(candidate, civ_id):
			order_move(candidate)
			return
	# Fallback: random direction from current position, clamped to map bounds.
	var angle: float = MatchRng.randf_range(0.0, TAU)
	var far: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * MatchRng.randf_range(400.0, 1200.0)
	far = far.clamp(Vector2(-mh, -mh), Vector2(mh, mh))
	order_move(TerrainManager.nearest_passable(far, civ_id))

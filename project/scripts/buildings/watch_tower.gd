extends BuildingBase

class_name WatchTower

const ARROW_SCENE: PackedScene = preload("res://scenes/combat/arrow.tscn")

const ATTACK_RANGE: float = 220.0
const ATTACK_DAMAGE: float = 5.0
const ATTACK_INTERVAL: float = 1.0 / 1.2
## Arrows leave from the tower top: 60 px up-SCREEN, converted to the world
## offset that projects there (a raw world -Y would read as up-left).
const ARROW_LAUNCH_SCREEN_OFFSET: Vector2 = Vector2(0.0, -60.0)

var _attack_timer: float = 0.0
var _attack_target: Node = null

func _physics_process(delta: float) -> void:
	if state != BuildingState.COMPLETE:
		return
	if not is_instance_valid(_attack_target) or \
			global_position.distance_to((_attack_target as Node2D).global_position) > ATTACK_RANGE:
		_attack_target = _find_nearest_enemy()
	if not is_instance_valid(_attack_target):
		return
	_attack_timer += delta
	if _attack_timer >= ATTACK_INTERVAL:
		_attack_timer = 0.0
		_launch_arrow(_attack_target)

## The arrow carries the damage and emits unit_attacked on impact (same flow
## as the Archer), so the shot is visible instead of instant invisible damage.
func _launch_arrow(target: Node) -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	arrow.damage = ATTACK_DAMAGE * CivBonusManager.get_unit_attack_multiplier(player_id, "watch_tower")
	arrow.shooter = self
	arrow.target_pos = (target as Node2D).global_position
	arrow._original_target = target
	get_parent().add_child(arrow)
	arrow.global_position = global_position \
		+ IsoProjection.screen_to_world(ARROW_LAUNCH_SCREEN_OFFSET)
	# Without this the spawn teleport is interpolated from the parent origin
	# and the arrow ghosts across the screen for a frame.
	arrow.reset_physics_interpolation()

func _find_nearest_enemy() -> Node:
	var best: Node = null
	var best_dist: float = ATTACK_RANGE
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		var pid: Variant = unit.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var d: float = global_position.distance_to((unit as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best

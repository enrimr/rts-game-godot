extends BuildingBase

class_name WatchTower

const ATTACK_RANGE: float = 220.0
const ATTACK_DAMAGE: float = 5.0
const ATTACK_INTERVAL: float = 1.0 / 1.2

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
		var dmg: float = ATTACK_DAMAGE * CivBonusManager.get_unit_attack_multiplier(player_id, "watch_tower")
		_attack_target.take_damage(dmg, self)
		EventBus.unit_attacked.emit(self, _attack_target)

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

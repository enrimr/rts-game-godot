extends UnitBase

class_name BatteringRam

func get_selection_sound() -> String:
	return "select_siege"

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 19.8, 5.0)

func _on_auto_attack_target(target: Node) -> void:
	# Only auto-attacks buildings — does not chase units
	if target is BuildingBase or target is StaticBody2D:
		order_attack(target)

func _on_enemy_entered_range(body: Node) -> void:
	if current_state != UnitState.IDLE and not (current_state == UnitState.MOVING and _attack_move_active):
		return
	var body_pid: Variant = body.get("player_id")
	if body_pid == null or (body_pid as int) == player_id:
		return
	# Rams only auto-attack buildings
	if body.get("building_data") == null:
		return
	# Through the stance funnel like every acquisition, or passive/leash
	# rules would not apply to rams.
	_auto_engage(body)

func _strike_sound_db() -> float:
	return -6.0

func _get_effective_attack_vs(target: Node) -> float:
	var base: float = _get_effective_attack()
	# Triple damage vs buildings, minimal vs units
	if target is BuildingBase or target is StaticBody2D:
		base *= 3.0 * CivBonusManager.get_siege_attack_bonus(player_id)
	else:
		base *= 0.2
	return base

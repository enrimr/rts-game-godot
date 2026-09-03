extends UnitBase

## Harimaguada — the Canarii priestess-healer, trained at the Temple. She
## never fights: attack is 0, her stance is locked PASSIVE and she is not a
## combat unit. Her machine is follow-and-mend: an explicit heal order (or an
## idle auto-scan for wounded allies nearby) walks her into touch range with
## the chase repath, then channels HEAL_RATE hp/s through UnitBase.heal()
## until the patient is whole — and looks for the next one.

const HEAL_RATE: float = 5.0
const HEAL_RANGE: float = 42.0
const AUTO_SCAN_RADIUS: float = 260.0
const AUTO_SCAN_INTERVAL: float = 0.6

var heal_target: Node = null
var _scan_timer: float = 0.0

func _ready() -> void:
	# The harimaguadas were consecrated WOMEN — never a gender roll here
	# (set before super so UnitBase._ready sees it as already decided).
	is_female = true
	super._ready()
	stance = Stance.PASSIVE

func is_combat_unit() -> bool:
	return false

func get_selection_sound() -> String:
	return "select_healer"

## The command layer's entry point (UnitTargetCommand "heal" verb).
func order_heal(target: Node) -> void:
	if not _can_heal(target):
		return
	clear_waypoints()
	attack_target = null
	heal_target = target
	current_state = UnitState.ATTACKING   # reused as the "tending" state
	_navigate_to((target as Node2D).global_position)

func _can_heal(target: Node) -> bool:
	if not is_instance_valid(target) or target == self or not (target is UnitBase):
		return false
	var pid: Variant = target.get("player_id")
	if pid == null or not GameManager.are_allied(pid as int, player_id):
		return false
	if (target as UnitBase).current_state == UnitState.DEAD:
		return false
	return not (target as UnitBase).is_fully_healed()

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement(delta)
		UnitState.ATTACKING:
			_handle_healing(delta)
		UnitState.IDLE:
			_auto_scan(delta)

func _handle_healing(delta: float) -> void:
	if not _can_heal(heal_target):
		heal_target = null
		current_state = UnitState.IDLE
		_drive_agent(Vector2.ZERO)
		return
	var patient: Node2D = heal_target as Node2D
	if global_position.distance_to(patient.global_position) > HEAL_RANGE:
		_repath_to(patient.global_position)
		_drive_agent(_nav_velocity())
		return
	_drive_agent(Vector2.ZERO)
	(heal_target as UnitBase).heal(HEAL_RATE * delta)

## Idle triage: tend the most wounded ally in reach, all by herself.
func _auto_scan(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer < AUTO_SCAN_INTERVAL:
		return
	_scan_timer = 0.0
	var best: Node = null
	var best_ratio: float = 1.0
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if not _can_heal(unit):
			continue
		var pos: Vector2 = (unit as Node2D).global_position
		if global_position.distance_to(pos) > AUTO_SCAN_RADIUS:
			continue
		var bar: Variant = unit.get("health_bar")
		if not (bar is ProgressBar):
			continue
		var ratio: float = (unit.get("health") as float) / maxf(float((bar as ProgressBar).max_value), 1.0)
		if ratio < best_ratio:
			best_ratio = ratio
			best = unit
	if best != null:
		order_heal(best)

## She never fights back — a threatened healer's answer is her legs.
func _auto_engage(_target: Node) -> void:
	pass

## Her rig carries no weapon, so the base ATTACKING swing would read as a
## strike: instead walking is a soft sway and tending is a slow nursing lean
## toward the patient, while the ritual motes over her bowl breathe. Rotations
## compose on the upright billboard base, as in UnitBase._animate_body.
func _animate_body(delta: float) -> void:
	var body: Node2D = get_node_or_null("Body") as Node2D
	if body == null:
		return
	_update_body_orientation(body)
	var t: float = _anim_time
	match current_state:
		UnitState.MOVING:
			body.rotation = IsoBillboard.UPRIGHT_ROTATION + sin(t * TAU * 1.9) * 0.05
		UnitState.ATTACKING:
			body.rotation = IsoBillboard.UPRIGHT_ROTATION + 0.09 + sin(t * TAU * 0.8) * 0.05
		_:
			body.rotation = move_toward(body.rotation,
				IsoBillboard.UPRIGHT_ROTATION, delta * 4.0)
	var motes: Node2D = body.get_node_or_null("Motes") as Node2D
	if motes != null:
		var tending: bool = current_state == UnitState.ATTACKING
		motes.position.y = sin(t * TAU * 0.7) * (1.6 if tending else 0.8)
		motes.modulate.a = 0.85 + sin(t * TAU * 1.1) * 0.15

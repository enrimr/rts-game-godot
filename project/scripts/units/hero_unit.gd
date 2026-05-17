extends Militia

class_name HeroUnit

## Generic hero unit. Behaviour is identical to Militia (move + attack)
## plus one special ability driven by unit_data.hero_ability_id.
## Heroes are spawned once at game start; if killed they are gone permanently.

signal ability_used(hero: HeroUnit)
signal ability_ready(hero: HeroUnit)

enum Ability {
	NONE,
	# Guanches — Bencomo
	MENCEYES_CHARGE,      # nearby allies +30% attack speed for 10s
	# Canarii — Doramas
	CHALLENGE,            # force one enemy to target only this hero for 8s
	# Mahos — Guadarfía
	AMBUSH,               # become invisible until attacking or hit
	# Francos — Jean de Béthencourt
	FORCED_DIPLOMACY,     # temporarily convert a nearby native unit for 12s
	# Britanos — Francis Drake
	PLUNDER,              # kills near hero yield bonus gold for 20s
	# Castellanos — Don Quijote
	KNIGHT_ERRANT_CHARGE, # charge in a straight line damaging everything in the path
	# Atlantes — Artaxerax
	CALIMA,               # create artificial fog patch hiding own units for 12s
	# Fenicios — Hannón
	TRADE_ROUTE,          # passive gold corridor between two points for 30s
}

const ABILITY_MAP: Dictionary = {
	"menceyes_charge":      Ability.MENCEYES_CHARGE,
	"challenge":            Ability.CHALLENGE,
	"ambush":               Ability.AMBUSH,
	"forced_diplomacy":     Ability.FORCED_DIPLOMACY,
	"plunder":              Ability.PLUNDER,
	"knight_errant_charge": Ability.KNIGHT_ERRANT_CHARGE,
	"calima":               Ability.CALIMA,
	"trade_route":          Ability.TRADE_ROUTE,
}

var _ability: Ability = Ability.NONE
var _cooldown_remaining: float = 0.0
var _ability_active: bool = false
var _ability_timer: float = 0.0
var _trade_route_timer: Timer = null
var _taunt_target: Node = null

# Visual ring showing the hero is a hero (gold circle)
var _hero_ring: Node2D = null

# Rocinante passive (Don Quijote): base speed stored to apply delay on attack
var _quijote_attack_delay: float = 0.0
var _quijote_post_attack_penalty: float = 0.0

func _ready() -> void:
	super._ready()
	if unit_data and not unit_data.hero_ability_id.is_empty():
		_ability = ABILITY_MAP.get(unit_data.hero_ability_id, Ability.NONE) as Ability
	# Rocinante passive: faster movement but a post-attack stumble delay
	if _ability == Ability.KNIGHT_ERRANT_CHARGE and unit_data:
		unit_data = unit_data.duplicate() as UnitResource
		unit_data.move_speed *= 1.15
		_quijote_attack_delay = 1.2
	_build_hero_ring()
	# Update portrait label to hero initials instead of the militia default "M"
	if unit_data:
		var label_node: Node = get_node_or_null("UnitLabel")
		if label_node != null:
			var parts: PackedStringArray = unit_data.display_name.split(" ")
			var initials: String = ""
			for p: String in parts:
				if not p.is_empty():
					initials += p[0]
			label_node.set("text", initials.left(2))

func die() -> void:
	_end_ability()
	if unit_data:
		EventBus.hero_died.emit(player_id, unit_data)
	super.die()

func _build_hero_ring() -> void:
	_hero_ring = Node2D.new()
	_hero_ring.z_index = -1
	add_child(_hero_ring)

func _draw_hero_ring() -> void:
	if not is_instance_valid(_hero_ring):
		return
	# Drawn via a child Node2D that overrides _draw
	pass

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
		if _cooldown_remaining <= 0.0:
			_cooldown_remaining = 0.0
			ability_ready.emit(self)
	if _ability_active:
		_ability_timer -= delta
		if _ability_timer <= 0.0:
			_end_ability()

# Called by game_world when player right-clicks the hero or presses the ability key
func use_ability() -> bool:
	if _cooldown_remaining > 0.0 or _ability == Ability.NONE:
		return false
	_trigger_ability()
	return true

func get_cooldown_fraction() -> float:
	if unit_data == null:
		return 0.0
	return clampf(_cooldown_remaining / unit_data.hero_ability_cooldown, 0.0, 1.0)

func _trigger_ability() -> void:
	var duration: float = 0.0
	match _ability:
		Ability.MENCEYES_CHARGE:
			duration = 10.0
			_buff_nearby_attack_speed(1.30, duration)
		Ability.CHALLENGE:
			duration = 8.0
			_taunt_nearest_enemy(duration)
		Ability.AMBUSH:
			duration = 15.0
			modulate.a = 0.15
		Ability.FORCED_DIPLOMACY:
			duration = 12.0
			_convert_nearest_native(duration)
		Ability.PLUNDER:
			duration = 20.0
			if not EventBus.unit_died.is_connected(_on_plunder_kill):
				EventBus.unit_died.connect(_on_plunder_kill)
		Ability.KNIGHT_ERRANT_CHARGE:
			duration = 0.0   # instant — runs the charge, no lingering state
			_do_charge()
			return
		Ability.CALIMA:
			duration = 12.0
			_spawn_calima_cloud(duration)
		Ability.TRADE_ROUTE:
			duration = 30.0
			_activate_trade_route(duration)

	_ability_active = duration > 0.0
	_ability_timer = duration
	_cooldown_remaining = unit_data.hero_ability_cooldown if unit_data else 50.0
	ability_used.emit(self)
	EventBus.hero_ability_used.emit(player_id)

func _end_ability() -> void:
	_ability_active = false
	match _ability:
		Ability.AMBUSH:
			modulate.a = 1.0
		Ability.PLUNDER:
			if EventBus.unit_died.is_connected(_on_plunder_kill):
				EventBus.unit_died.disconnect(_on_plunder_kill)
		Ability.CHALLENGE:
			if is_instance_valid(_taunt_target):
				_taunt_target.set("is_taunted", false)
				_taunt_target.set("taunt_source", null)
				_taunt_target.set("attack_target", null)
				_taunt_target.set("current_state", UnitBase.UnitState.IDLE)
			_taunt_target = null
		Ability.TRADE_ROUTE:
			if is_instance_valid(_trade_route_timer):
				_trade_route_timer.stop()
				_trade_route_timer.queue_free()
			_trade_route_timer = null

func _handle_attacking(delta: float) -> void:
	if _quijote_attack_delay <= 0.0:
		super._handle_attacking(delta)
		return
	# Rocinante passive: after each hit, _quijote_post_attack_penalty counts down
	# before the attack timer resumes, making consecutive swings slower.
	if _quijote_post_attack_penalty > 0.0:
		_quijote_post_attack_penalty -= delta
		return
	if not is_instance_valid(attack_target):
		attack_target = null
		current_state = UnitState.IDLE
		_scan_area_for_target()
		return
	var dist: float = global_position.distance_to((attack_target as Node2D).global_position)
	var attack_reach: float = _attack_reach_to(attack_target)
	if dist > attack_reach:
		nav_agent.target_position = _nav_target_for(attack_target)
		if _advance_stuck(delta):
			_unstick()
			return
		nav_agent.set_velocity(_nav_velocity())
		return
	nav_agent.set_velocity(Vector2.ZERO)
	_attack_timer += delta
	if _attack_timer >= 1.0 / unit_data.attack_speed:
		_attack_timer = 0.0
		_quijote_post_attack_penalty = _quijote_attack_delay
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(_get_effective_attack_vs(attack_target) - _get_target_armor(attack_target), self)
			AudioManager.play_if_visible("hit_melee", global_position, -4.0)
			EventBus.unit_attacked.emit(self, attack_target)

# --- Ability implementations ---

func _buff_nearby_attack_speed(multiplier: float, duration: float) -> void:
	var radius: float = 180.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for u: Node in units:
		var pid: Variant = u.get("player_id")
		if pid == null or (pid as int) != player_id:
			continue
		if not is_instance_valid(u) or u == self:
			continue
		if (u as Node2D).global_position.distance_to(global_position) > radius:
			continue
		var udata: Variant = u.get("unit_data")
		if udata == null:
			continue
		var data: UnitResource = (udata as UnitResource).duplicate() as UnitResource
		var original_speed: float = data.attack_speed
		data.attack_speed *= multiplier
		u.set("unit_data", data)
		# Restore after duration
		var tw: SceneTreeTimer = get_tree().create_timer(duration)
		tw.timeout.connect(func() -> void:
			if is_instance_valid(u):
				var d2: UnitResource = (u.get("unit_data") as UnitResource).duplicate() as UnitResource
				d2.attack_speed = original_speed
				u.set("unit_data", d2)
		)

func _taunt_nearest_enemy(duration: float) -> void:
	var best: Node = null
	var best_dist: float = 300.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for u: Node in units:
		var pid: Variant = u.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var d: float = (u as Node2D).global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = u
	if best == null:
		return
	_taunt_target = best
	best.set("is_taunted", true)
	best.set("taunt_source", self)
	if best.has_method("order_attack"):
		best.call("order_attack", self)
	var tw: SceneTreeTimer = get_tree().create_timer(duration)
	tw.timeout.connect(func() -> void:
		if is_instance_valid(best):
			best.set("is_taunted", false)
			best.set("taunt_source", null)
			best.set("attack_target", null)
			best.set("current_state", UnitBase.UnitState.IDLE)
		_taunt_target = null
	)

func _convert_nearest_native(_duration: float) -> void:
	# Finds the nearest enemy unit and temporarily sets its player_id to ours.
	# The unit reverts after duration via a timer.
	var best: Node = null
	var best_dist: float = 200.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for u: Node in units:
		var pid: Variant = u.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		var d: float = (u as Node2D).global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = u
	if best == null:
		return
	var original_pid: int = best.get("player_id") as int
	best.set("player_id", player_id)
	var tw: SceneTreeTimer = get_tree().create_timer(_duration)
	tw.timeout.connect(func() -> void:
		if is_instance_valid(best):
			best.set("player_id", original_pid)
	)

func _on_plunder_kill(unit: Node, killed_player_id: int) -> void:
	if killed_player_id == player_id:
		return
	var dist: float = (unit as Node2D).global_position.distance_to(global_position)
	if dist <= 220.0:
		ResourceManager.add_resource(player_id, "gold", 15.0)

func _do_charge() -> void:
	# Straight-line charge: moves rapidly in facing direction, damages all in path.
	# Direction = toward current nav target, or forward if idle.
	var dir: Vector2 = Vector2.RIGHT
	if not nav_agent.is_navigation_finished():
		dir = (nav_agent.target_position - global_position).normalized()
	elif velocity.length() > 1.0:
		dir = velocity.normalized()

	var charge_dist: float = 400.0
	var charge_speed: float = unit_data.move_speed * 3.0
	var elapsed: float = 0.0
	var total_time: float = charge_dist / charge_speed
	var hit_nodes: Array = []

	# Disable nav during charge
	var saved_state: UnitBase.UnitState = current_state
	current_state = UnitState.MOVING

	var tw: Tween = create_tween()
	tw.tween_method(func(t: float) -> void:
		var step: float = charge_speed * (t - elapsed) * total_time
		elapsed = t
		global_position += dir * charge_dist * get_process_delta_time() * (charge_speed / charge_dist)
		# Damage nearby nodes that haven't been hit yet
		for u: Node in get_tree().get_nodes_in_group("units"):
			if u == self or hit_nodes.has(u):
				continue
			if (u as Node2D).global_position.distance_to(global_position) < 28.0:
				hit_nodes.append(u)
				if u.has_method("take_damage"):
					u.call("take_damage", unit_data.attack * 2.0, self)
	, 0.0, 1.0, total_time)
	tw.tween_callback(func() -> void:
		current_state = saved_state
		_cooldown_remaining = unit_data.hero_ability_cooldown if unit_data else 50.0
		ability_used.emit(self)
	)

const CALIMA_RADIUS: float = 180.0

func _spawn_calima_cloud(duration: float) -> void:
	var cloud: Node2D = Node2D.new()
	cloud.z_index = 50
	cloud.global_position = global_position
	var cloud_color: Color = Color(0.85, 0.78, 0.60, 0.45)
	cloud.draw.connect(func() -> void:
		cloud.draw_circle(Vector2.ZERO, CALIMA_RADIUS, cloud_color)
	)
	get_tree().current_scene.add_child(cloud)
	cloud.queue_redraw()

	# Apply cloak to all allied units inside the radius
	var cloaked_units: Array[Node] = []
	var units_layer: Node = get_parent()
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is UnitBase):
			continue
		var uid: Variant = unit.get("player_id")
		if uid == null or (uid as int) != player_id:
			continue
		if (unit as Node2D).global_position.distance_to(global_position) > CALIMA_RADIUS:
			continue
		unit.set("is_cloaked", true)
		# Dim AI units so the player can barely see them; keep player units at full opacity
		if player_id != 0:
			(unit as Node2D).modulate.a = 0.25
		cloaked_units.append(unit)

	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(cloud):
			cloud.queue_free()
		for unit: Node in cloaked_units:
			if is_instance_valid(unit):
				unit.set("is_cloaked", false)
				(unit as Node2D).modulate.a = 1.0
	)

func _activate_trade_route(duration: float) -> void:
	var ticks: int = int(duration)
	var tick_count: int = 0
	_trade_route_timer = Timer.new()
	_trade_route_timer.wait_time = 1.0
	_trade_route_timer.autostart = true
	add_child(_trade_route_timer)
	_trade_route_timer.timeout.connect(func() -> void:
		if not is_instance_valid(_trade_route_timer):
			return
		ResourceManager.add_resource(player_id, "gold", 8.0)
		tick_count += 1
		if tick_count >= ticks:
			_end_ability()
	)

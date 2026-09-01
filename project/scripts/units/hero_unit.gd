extends Militia

class_name HeroUnit

## Generic hero unit. Behaviour is identical to Militia (move + attack)
## plus one special ability driven by unit_data.hero_ability_id.
## Heroes are spawned once at game start; if killed they are gone permanently.

signal ability_used(hero: HeroUnit)
signal ability_ready(hero: HeroUnit)

## is_female is inherited from UnitBase. The spawner sets it before _ready() to
## pick the lobby-chosen gender; _apply_female_appearance gives the queen look.

func get_selection_sound() -> String:
	return "select_hero"

enum Ability {
	NONE,
	# Male Heroes
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
	# Female Heroes
	# Guanches — Dácil
	MOUNTAIN_VOICE,       # nearby allies +2 armor and +50% heal rate for 12s
	# Canarii — Guayarmina
	FATES_ARROW,          # 80 damage ignore-armor snipe, half cooldown if kill
	# Mahos — Tibiabin
	SANDSTORM,            # AoE 200px: 3dmg/s, -40% speed, -50% projectile accuracy for 10s
	# Franks — Catalina
	HONOR_DUEL,           # challenge enemy hero: both +100% dmg to each other, -50% to others, 15s
	# Britons — Grace O'Malley
	BOARDING_ACTION,      # dash 200px, damage + stun enemies in path for 2s
	# Castellanos — Dulcinea
	CALL_TO_ARMS,         # summon 3 temporary Militia for 40s
	# Atlantes — Cleito
	RISING_TIDE,          # AoE 250px: allies heal 60HP + 30% speed, enemies 20dmg + -20% speed
	# Fenicios — Elissa
	MERCENARY_PACT,       # spend 400g to permanently convert one enemy unit
}

const ABILITY_MAP: Dictionary = {
	# Male heroes
	"menceyes_charge":      Ability.MENCEYES_CHARGE,
	"challenge":            Ability.CHALLENGE,
	"ambush":               Ability.AMBUSH,
	"forced_diplomacy":     Ability.FORCED_DIPLOMACY,
	"plunder":              Ability.PLUNDER,
	"knight_errant_charge": Ability.KNIGHT_ERRANT_CHARGE,
	"calima":               Ability.CALIMA,
	"trade_route":          Ability.TRADE_ROUTE,
	# Female heroes
	"mountain_voice":       Ability.MOUNTAIN_VOICE,
	"fates_arrow":          Ability.FATES_ARROW,
	"sandstorm":            Ability.SANDSTORM,
	"honor_duel":           Ability.HONOR_DUEL,
	"boarding_action":      Ability.BOARDING_ACTION,
	"call_to_arms":         Ability.CALL_TO_ARMS,
	"rising_tide":          Ability.RISING_TIDE,
	"mercenary_pact":       Ability.MERCENARY_PACT,
}

var _ability: Ability = Ability.NONE
var _cooldown_remaining: float = 0.0
var _ability_active: bool = false
var _ability_timer: float = 0.0
# Instant-ability bookkeeping: a fizzled cast charges no cooldown; a Fate's
# Arrow kill refunds half of it. Both consumed by _trigger_ability.
var _ability_fizzled: bool = false
var _fates_kill_refund: bool = false
var _trade_route_timer: Timer = null
var _taunt_target: Node = null

# Reversible state stored so _end_ability() can always clean up, whether the
# ability expires naturally or the hero dies mid-cast.
var _buffed_units: Array[Dictionary] = []   # MENCEYES_CHARGE: [{unit, original_speed}]
var _fd_target: Node = null                  # FORCED_DIPLOMACY converted unit
var _fd_original_pid: int = -1               # FORCED_DIPLOMACY original player_id
var _calima_cloud: Node2D = null             # CALIMA cloud node in the scene
var _cloaked_units: Array[Node] = []         # CALIMA units that were cloaked

# Visual marking the hero as a hero: the animated golden energy aura behind
# the figure (see HeroAura), always visible.
var _hero_aura: HeroAura = null

# Rocinante passive (Don Quijote): base speed stored to apply delay on attack
var _quijote_attack_delay: float = 0.0
var _quijote_post_attack_penalty: float = 0.0

# Female heroes state
var _sandstorm_area: Area2D = null
var _duel_target: Node = null
var _duel_original_dmg_mult: float = 1.0
var _summoned_militia: Array[Node] = []

func _ready() -> void:
	super._ready()
	if unit_data and not unit_data.hero_ability_id.is_empty():
		_ability = ABILITY_MAP.get(unit_data.hero_ability_id, Ability.NONE) as Ability
	# Rocinante passive: faster movement but a post-attack stumble delay
	if _ability == Ability.KNIGHT_ERRANT_CHARGE and unit_data:
		unit_data = unit_data.duplicate() as UnitResource
		unit_data.move_speed *= 1.15
		_quijote_attack_delay = 1.2
	_build_hero_aura()
	if is_female:
		_apply_female_appearance()
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

# Heroes style their own gender (the queen look in _apply_female_appearance), so
# opt out of the generic hair the base class would otherwise add.
func _apply_gender_appearance() -> void:
	pass

func die() -> void:
	_end_ability()
	if unit_data:
		EventBus.hero_died.emit(player_id, unit_data)
	super.die()

# Restyles the inherited militia body so a heroine reads as female: swaps the
# helmet for long hair + a circlet, slims the torso into a flared gown, and
# softens the limb colours. Keeps the weapon/shield — she's still a warrior.
func _apply_female_appearance() -> void:
	var body: Node2D = get_node_or_null("Body") as Node2D
	if body == null:
		return

	# Gown: narrow shoulders flaring out to a wide skirt hem at the feet.
	var gown_col: Color = Color(0.60, 0.16, 0.30, 1.0)
	var torso: Polygon2D = body.get_node_or_null("Torso") as Polygon2D
	if torso != null:
		torso.color = gown_col
		torso.polygon = PackedVector2Array([
			Vector2(-6, 9), Vector2(-3, -6), Vector2(-2, -8),
			Vector2(2, -8), Vector2(3, -6), Vector2(6, 9)])
	# Hide the legs under the skirt.
	for leg_name: String in ["LegLeft", "LegRight"]:
		var leg: Polygon2D = body.get_node_or_null(leg_name) as Polygon2D
		if leg != null:
			leg.visible = false
	# Skirt hem trim.
	var hem: Polygon2D = Polygon2D.new()
	hem.name = "GownHem"
	hem.color = Color(0.78, 0.62, 0.32, 1.0)
	hem.polygon = PackedVector2Array([Vector2(-6, 9), Vector2(6, 9), Vector2(6, 7), Vector2(-6, 7)])
	body.add_child(hem)
	# Waist sash over the belt.
	var belt: Polygon2D = body.get_node_or_null("Belt") as Polygon2D
	if belt != null:
		belt.color = Color(0.82, 0.66, 0.34, 1.0)

	# Replace the helmet with long hair framing the face and falling to the back.
	var helmet: Polygon2D = body.get_node_or_null("Helmet") as Polygon2D
	if helmet != null:
		helmet.queue_free()
	var hair_back: Polygon2D = Polygon2D.new()
	hair_back.name = "HairBack"
	hair_back.color = Color(0.30, 0.18, 0.08, 1.0)
	hair_back.polygon = PackedVector2Array([
		Vector2(-4, -12), Vector2(-4, -2), Vector2(-2, -2),
		Vector2(-2, -11), Vector2(2, -11), Vector2(2, -2),
		Vector2(4, -2), Vector2(4, -12), Vector2(2, -15),
		Vector2(-2, -15)])
	body.add_child(hair_back)
	body.move_child(hair_back, 0)   # behind head/torso
	# Crown/circlet marking her as a leader.
	var circlet: Polygon2D = Polygon2D.new()
	circlet.name = "Circlet"
	circlet.color = Color(0.90, 0.78, 0.30, 1.0)
	circlet.polygon = PackedVector2Array([
		Vector2(-3, -13), Vector2(-3, -15), Vector2(0, -17),
		Vector2(3, -15), Vector2(3, -13)])
	body.add_child(circlet)

func _build_hero_aura() -> void:
	_hero_aura = HeroAura.new()
	_hero_aura.name = "HeroAura"
	add_child(_hero_aura)
	# Before Body in tree order: the figure draws on top of the flames, the
	# ground shadow (z -1) stays under both.
	var body: Node = get_node_or_null("Body")
	if body != null:
		move_child(_hero_aura, body.get_index())
	IsoBillboard.make_upright(_hero_aura)

const MOUNTAIN_VOICE_HEAL_PER_SEC: float = 4.0
var _heal_accum: float = 0.0

func _tick_mountain_voice_healing(delta: float) -> void:
	if _ability != Ability.MOUNTAIN_VOICE or not _ability_active:
		return
	_heal_accum += delta
	if _heal_accum < 1.0:
		return
	_heal_accum -= 1.0
	for entry: Dictionary in _buffed_units:
		var unit: Node = entry.get("unit") as Node
		if not is_instance_valid(unit):
			continue
		var bar: Variant = unit.get("health_bar")
		var max_hp: float = (bar as ProgressBar).max_value if bar is ProgressBar \
			else (unit.get("health") as float)
		unit.set("health", minf((unit.get("health") as float) + MOUNTAIN_VOICE_HEAL_PER_SEC, max_hp))
		if unit.has_method("_refresh_health_bar"):
			unit.call("_refresh_health_bar")

func _combat_side_tick(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
		if _cooldown_remaining <= 0.0:
			_cooldown_remaining = 0.0
			ability_ready.emit(self)
	_tick_mountain_voice_healing(delta)
	if _ability_active:
		_ability_timer -= delta
		if _ability_timer <= 0.0:
			_end_ability()
	# The Rocinante stumble only counts down mid-combat, matching the original
	# machine which decremented it inside _handle_attacking.
	if current_state == UnitState.ATTACKING and _quijote_post_attack_penalty > 0.0:
		_quijote_post_attack_penalty -= delta

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
			_buff_nearby_attack_speed(1.30)
		Ability.CHALLENGE:
			duration = 8.0
			_taunt_nearest_enemy()
		Ability.AMBUSH:
			duration = 15.0
			modulate.a = 0.15
			is_cloaked = true   # the flag targeting actually consults
		Ability.FORCED_DIPLOMACY:
			duration = 12.0
			_convert_nearest_native()
		Ability.PLUNDER:
			duration = 20.0
			if not EventBus.unit_died.is_connected(_on_plunder_kill):
				EventBus.unit_died.connect(_on_plunder_kill)
		Ability.KNIGHT_ERRANT_CHARGE:
			duration = 0.0   # instant — runs the charge, no lingering state
			_do_charge()
		Ability.CALIMA:
			duration = 12.0
			_spawn_calima_cloud()
		Ability.TRADE_ROUTE:
			duration = 30.0
			_activate_trade_route(duration)
		# Female Heroes
		Ability.MOUNTAIN_VOICE:
			duration = 12.0
			_buff_nearby_armor_and_healing()
		Ability.FATES_ARROW:
			duration = 0.0  # instant
			_fire_fates_arrow()
		Ability.SANDSTORM:
			duration = 10.0
			_create_sandstorm()
		Ability.HONOR_DUEL:
			duration = 15.0
			_challenge_to_duel()
		Ability.BOARDING_ACTION:
			duration = 0.0  # instant dash
			_boarding_dash()
		Ability.CALL_TO_ARMS:
			duration = 40.0
			_summon_militia()
		Ability.RISING_TIDE:
			duration = 0.0  # instant wave
			_create_tidal_wave()
		Ability.MERCENARY_PACT:
			duration = 0.0  # instant conversion
			_convert_enemy_for_gold()

	_ability_active = duration > 0.0
	_ability_timer = duration
	if _ability_fizzled:
		# Nothing happened (no target / not enough gold): no cooldown charged.
		_ability_fizzled = false
		_ability_active = false
		return
	_cooldown_remaining = unit_data.hero_ability_cooldown if unit_data else 50.0
	if _fates_kill_refund:
		_fates_kill_refund = false
		_cooldown_remaining *= 0.5
	ability_used.emit(self)
	EventBus.hero_ability_used.emit(player_id)

func _end_ability() -> void:
	_ability_active = false
	match _ability:
		Ability.MENCEYES_CHARGE:
			for entry: Dictionary in _buffed_units:
				if is_instance_valid(entry.unit):
					var d: UnitResource = (entry.unit.get("unit_data") as UnitResource).duplicate() as UnitResource
					d.attack_speed = entry.original_speed
					entry.unit.set("unit_data", d)
			_buffed_units.clear()
		Ability.AMBUSH:
			modulate.a = 1.0
			is_cloaked = false
		Ability.PLUNDER:
			if EventBus.unit_died.is_connected(_on_plunder_kill):
				EventBus.unit_died.disconnect(_on_plunder_kill)
		Ability.HONOR_DUEL:
			_end_duel()
		Ability.CHALLENGE:
			if is_instance_valid(_taunt_target):
				_taunt_target.set("is_taunted", false)
				_taunt_target.set("taunt_source", null)
				_taunt_target.set("attack_target", null)
				_taunt_target.set("current_state", UnitBase.UnitState.IDLE)
			_taunt_target = null
		Ability.FORCED_DIPLOMACY:
			if is_instance_valid(_fd_target):
				_fd_target.set("player_id", _fd_original_pid)
			_fd_target = null
			_fd_original_pid = -1
		Ability.CALIMA:
			if is_instance_valid(_calima_cloud):
				_calima_cloud.queue_free()
			for unit: Node in _cloaked_units:
				if is_instance_valid(unit):
					unit.set("is_cloaked", false)
					(unit as Node2D).modulate.a = 1.0
			_cloaked_units.clear()
			_calima_cloud = null
		Ability.TRADE_ROUTE:
			if is_instance_valid(_trade_route_timer):
				_trade_route_timer.stop()
				_trade_route_timer.queue_free()
			_trade_route_timer = null
		# Female heroes cleanup
		Ability.MOUNTAIN_VOICE:
			_restore_armor_buffs()
		Ability.SANDSTORM:
			_cleanup_sandstorm()
		Ability.HONOR_DUEL:
			_end_duel()
		Ability.CALL_TO_ARMS:
			_cleanup_summoned_militia()

# ── Combat machine hooks ──

## Rocinante passive: after each hit the hero holds position while
## _quijote_post_attack_penalty counts down, making consecutive swings slower.
func _attack_paused() -> bool:
	return _quijote_post_attack_penalty > 0.0

func _after_strike(_target: Node) -> void:
	if _quijote_attack_delay > 0.0:
		_quijote_post_attack_penalty = _quijote_attack_delay
	# Striking breaks the ambush — you cannot stab from the shadows twice.
	if _ability == Ability.AMBUSH and _ability_active:
		_end_ability()

# --- Ability implementations ---

# Buffs nearby allied units' attack speed. State stored in _buffed_units so
# _end_ability() can revert it whether the hero dies or the ability expires.
func _buff_nearby_attack_speed(multiplier: float) -> void:
	var radius: float = 180.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for u: Node in units:
		var pid: Variant = u.get("player_id")
		if pid == null or not GameManager.are_allied(pid as int, player_id):
			continue
		if not is_instance_valid(u) or u == self:
			continue
		if (u as Node2D).global_position.distance_to(global_position) > radius:
			continue
		var udata: Variant = u.get("unit_data")
		if udata == null:
			continue
		var original_speed: float = (udata as UnitResource).attack_speed
		var data: UnitResource = (udata as UnitResource).duplicate() as UnitResource
		data.attack_speed *= multiplier
		u.set("unit_data", data)
		_buffed_units.append({"unit": u, "original_speed": original_speed})

func _taunt_nearest_enemy() -> void:
	var best: Node = null
	var best_dist: float = 300.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for u: Node in units:
		var pid: Variant = u.get("player_id")
		if pid == null or GameManager.are_allied(pid as int, player_id):
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

func _convert_nearest_native() -> void:
	var best: Node = null
	var best_dist: float = 200.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for u: Node in units:
		var pid: Variant = u.get("player_id")
		if pid == null or GameManager.are_allied(pid as int, player_id):
			continue
		var d: float = (u as Node2D).global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = u
	if best == null:
		return
	_fd_target = best
	_fd_original_pid = best.get("player_id") as int
	best.set("player_id", player_id)

func _on_plunder_kill(unit: Node, killed_player_id: int) -> void:
	if GameManager.are_allied(killed_player_id, player_id):
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
	# One snapshot of hostile candidates: the old per-tween-tick group scan
	# was O(units) every tick AND hit allies (no team filter).
	var candidates: Array = []
	for u: Node in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		var upid: Variant = u.get("player_id")
		if upid == null or GameManager.are_allied(upid as int, player_id):
			continue
		if (u as Node2D).global_position.distance_to(global_position) < charge_dist + 120.0:
			candidates.append(u)

	# Disable nav during charge
	var saved_state: UnitBase.UnitState = current_state
	current_state = UnitState.MOVING

	# create_tween() binds the tween to this node; it auto-kills on queue_free().
	var tw: Tween = create_tween()
	tw.tween_method(func(t: float) -> void:
		var step: float = charge_speed * (t - elapsed) * total_time
		elapsed = t
		global_position += dir * charge_dist * get_process_delta_time() * (charge_speed / charge_dist)
		# Damage nearby hostiles that haven't been hit yet
		for u: Node in candidates:
			if hit_nodes.has(u) or not is_instance_valid(u):
				continue
			if (u as Node2D).global_position.distance_to(global_position) < 28.0:
				hit_nodes.append(u)
				if u.has_method("take_damage"):
					u.call("take_damage", unit_data.attack * 2.0, self)
	, 0.0, 1.0, total_time)
	tw.tween_callback(func() -> void:
		current_state = saved_state
	)

const CALIMA_RADIUS: float = 180.0

# Creates the visual cloud and cloaks allied units. State stored in _calima_cloud
# and _cloaked_units so _end_ability() can clean up on hero death or expiry.
func _spawn_calima_cloud() -> void:
	var cloud: Node2D = Node2D.new()
	cloud.z_index = IsoBillboard.Z_AIRBORNE + 2
	cloud.global_position = global_position
	var cloud_color: Color = Color(0.85, 0.78, 0.60, 0.45)
	cloud.draw.connect(func() -> void:
		cloud.draw_circle(Vector2.ZERO, CALIMA_RADIUS, cloud_color)
	)
	# Parented to the units layer, not current_scene: harnesses (and any
	# instanced world) have no current_scene to speak of.
	get_parent().add_child(cloud)
	cloud.global_position = global_position
	cloud.queue_redraw()
	_calima_cloud = cloud

	var units_layer: Node = get_parent()
	for unit: Node in units_layer.get_children():
		if not is_instance_valid(unit) or not (unit is UnitBase):
			continue
		var uid: Variant = unit.get("player_id")
		if uid == null or not GameManager.are_allied(uid as int, player_id):
			continue
		if (unit as Node2D).global_position.distance_to(global_position) > CALIMA_RADIUS:
			continue
		unit.set("is_cloaked", true)
		# Dim AI units so the player can barely see them; keep player units at full opacity
		if player_id != 0:
			(unit as Node2D).modulate.a = 0.25
		_cloaked_units.append(unit)

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
# Heroine abilities implementation - to be appended to hero_unit.gd

## DÁCIL - MOUNTAIN VOICE
func _buff_nearby_armor_and_healing() -> void:
	var units: Array = get_tree().get_nodes_in_group("units")
	_buffed_units.clear()
	for unit: Node in units:
		if not is_instance_valid(unit):
			continue
		var unit_pid: Variant = unit.get("player_id")
		if unit_pid == null or not GameManager.are_allied(unit_pid as int, player_id):
			continue
		var dist: float = global_position.distance_to((unit as Node2D).global_position)
		if dist <= 300.0:
			var data: UnitResource = unit.get("unit_data") as UnitResource
			if data != null:
				var dup: UnitResource = data.duplicate() as UnitResource
				_buffed_units.append({
					"unit": unit,
					"original_armor_m": dup.armor_melee,
					"original_armor_p": dup.armor_pierce
				})
				dup.armor_melee += 2.0
				dup.armor_pierce += 2.0
				unit.set("unit_data", dup)

func _restore_armor_buffs() -> void:
	for entry: Dictionary in _buffed_units:
		if is_instance_valid(entry.unit):
			var data: UnitResource = (entry.unit.get("unit_data") as UnitResource).duplicate() as UnitResource
			data.armor_melee = entry.original_armor_m
			data.armor_pierce = entry.original_armor_p
			entry.unit.set("unit_data", data)
	_buffed_units.clear()

## GUAYARMINA - FATE'S ARROW
func _fire_fates_arrow() -> void:
	# Find target: nearest enemy within 600px
	var nearest: Node = null
	var nearest_dist: float = 600.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for unit: Node in units:
		if not is_instance_valid(unit):
			continue
		var unit_pid: Variant = unit.get("player_id")
		if unit_pid == null or GameManager.are_allied(unit_pid as int, player_id):
			continue
		var dist: float = global_position.distance_to((unit as Node2D).global_position)
		if dist < nearest_dist:
			nearest = unit
			nearest_dist = dist

	if nearest != null and nearest.has_method("take_damage"):
		var target_hp: float = nearest.get("health") as float
		nearest.take_damage(80.0, self)
		AudioManager.play_if_visible("hit_ranged", (nearest as Node2D).global_position, 0.0)
		# Halve cooldown if kill
		if target_hp <= 80.0:
			_fates_kill_refund = true
	else:
		_ability_fizzled = true

## TIBIABIN - SANDSTORM
func _create_sandstorm() -> void:
	_sandstorm_area = Area2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 200.0
	shape.shape = circle
	_sandstorm_area.add_child(shape)
	_sandstorm_area.collision_layer = 0
	_sandstorm_area.collision_mask = 3
	_sandstorm_area.global_position = global_position
	get_parent().add_child(_sandstorm_area)

	# Visual: ColorRect with semi-transparent brown
	var visual: ColorRect = ColorRect.new()
	visual.color = Color(0.6, 0.4, 0.2, 0.3)
	visual.size = Vector2(400, 400)
	visual.position = Vector2(-200, -200)
	_sandstorm_area.add_child(visual)

	# DoT timer
	var timer: Timer = Timer.new()
	timer.wait_time = 1.0
	timer.one_shot = false
	_sandstorm_area.add_child(timer)
	timer.timeout.connect(_sandstorm_tick)
	timer.start()

func _sandstorm_tick() -> void:
	if not is_instance_valid(_sandstorm_area):
		return
	var bodies: Array[Node2D] = _sandstorm_area.get_overlapping_bodies()
	for body: Node in bodies:
		if not is_instance_valid(body):
			continue
		var body_pid: Variant = body.get("player_id")
		if body_pid == null or GameManager.are_allied(body_pid as int, player_id):
			continue
		if body.has_method("take_damage"):
			body.take_damage(3.0, self)
		if body.has_method("apply_slow"):
			# Re-applied every 1 s tick with a 1.3 s window: leaving the
			# storm lets the slow lapse on its own.
			body.call("apply_slow", 0.60, 1300)

func _cleanup_sandstorm() -> void:
	if is_instance_valid(_sandstorm_area):
		_sandstorm_area.queue_free()
	_sandstorm_area = null

## CATALINA - HONOR DUEL
func _challenge_to_duel() -> void:
	# Find nearest enemy hero or unique unit within 250px
	var nearest: Node = null
	var nearest_dist: float = 250.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for unit: Node in units:
		if not is_instance_valid(unit):
			continue
		var unit_pid: Variant = unit.get("player_id")
		if unit_pid == null or GameManager.are_allied(unit_pid as int, player_id):
			continue
		var data: UnitResource = unit.get("unit_data") as UnitResource
		if data == null:
			continue
		# Must be hero or unique unit
		if not (data.is_hero or unit is MenceyesGuard or unit is RavineArcher or unit is SandRaider
			or unit is ChevalierNormand or unit is Longbowman or unit is Conquistador
			or unit is Tidecaller or unit is Trireme):
			continue
		var dist: float = global_position.distance_to((unit as Node2D).global_position)
		if dist < nearest_dist:
			nearest = unit
			nearest_dist = dist

	if nearest != null:
		_duel_target = nearest
		# The challenged champion is compelled to fight the duelist.
		nearest.set("is_taunted", true)
		nearest.set("taunt_source", self)
		if nearest.has_method("order_attack"):
			nearest.call("order_attack", self)
		order_attack(nearest)
	else:
		_ability_fizzled = true

func _end_duel() -> void:
	if is_instance_valid(_duel_target):
		_duel_target.set("is_taunted", false)
		_duel_target.set("taunt_source", null)
	_duel_target = null

func _duel_active() -> bool:
	return _ability == Ability.HONOR_DUEL and _ability_active \
		and is_instance_valid(_duel_target)

## Duel bubble: the duelist hits her rival twice as hard and everyone else
## half as hard; damage FROM the rival doubles, from outsiders halves.
func _strike_damage(target: Node) -> float:
	var dmg: float = super._strike_damage(target)
	if _duel_active():
		dmg *= 2.0 if target == _duel_target else 0.5
	return dmg

func take_damage(amount: float, source: Node = null) -> void:
	if _duel_active() and source != null:
		amount *= 2.0 if source == _duel_target else 0.5
	super.take_damage(amount, source)

## GRACE O'MALLEY - BOARDING ACTION
func _boarding_dash() -> void:
	# Dash 200px toward the nearest hostile (mouse position would desync
	# replays and the networked command execution), else along our facing.
	var direction: Vector2 = Vector2.ZERO
	var nearest_d: float = 400.0
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		var upid: Variant = unit.get("player_id")
		if upid == null or GameManager.are_allied(upid as int, player_id):
			continue
		var d: float = global_position.distance_to((unit as Node2D).global_position)
		if d < nearest_d:
			nearest_d = d
			direction = (unit as Node2D).global_position - global_position
	if direction == Vector2.ZERO:
		direction = velocity if velocity != Vector2.ZERO else Vector2.RIGHT
	direction = direction.normalized()
	var start_pos: Vector2 = global_position
	var end_pos: Vector2 = start_pos + direction * 200.0

	# Query all bodies along the path
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start_pos, end_pos)
	query.collision_mask = 3
	query.hit_from_inside = true

	# Instant teleport (simplified - full implementation would lerp)
	global_position = end_pos

	# Damage + stun everything in 200px line
	var units: Array = get_tree().get_nodes_in_group("units")
	for unit: Node in units:
		if not is_instance_valid(unit):
			continue
		var unit_pid: Variant = unit.get("player_id")
		if unit_pid == null or GameManager.are_allied(unit_pid as int, player_id):
			continue
		# Check if unit was in the dash path (simplified: just check distance to line)
		var unit_pos: Vector2 = (unit as Node2D).global_position
		var dist_to_line: float = _point_to_line_distance(unit_pos, start_pos, end_pos)
		if dist_to_line <= 40.0:  # 40px width of dash
			if unit.has_method("take_damage"):
				unit.take_damage(30.0, self)
			if unit.has_method("apply_stun"):
				unit.call("apply_stun", 2000)

	# Damage buildings
	var buildings: Array = get_tree().get_nodes_in_group("buildings")
	for building: Node in buildings:
		if not is_instance_valid(building):
			continue
		var b_pid: Variant = building.get("player_id")
		if b_pid == null or GameManager.are_allied(b_pid as int, player_id):
			continue
		var b_pos: Vector2 = (building as Node2D).global_position
		var dist_to_line: float = _point_to_line_distance(b_pos, start_pos, end_pos)
		if dist_to_line <= 40.0:
			if building.has_method("take_damage"):
				building.take_damage(100.0, self)

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec: Vector2 = line_end - line_start
	var point_vec: Vector2 = point - line_start
	var line_len_sq: float = line_vec.length_squared()
	if line_len_sq == 0.0:
		return point_vec.length()
	var t: float = clampf(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection: Vector2 = line_start + t * line_vec
	return point.distance_to(projection)

## DULCINEA - CALL TO ARMS
func _summon_militia() -> void:
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return

	_summoned_militia.clear()
	for i: int in range(3):
		var militia: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
		var offset: Vector2 = Vector2(40.0 * (i - 1), 0.0).rotated(MatchRng.randf() * TAU)
		militia.global_position = global_position + offset
		militia.set("player_id", player_id)

		# Buff HP and attack by 20%
		var data: UnitResource = militia.get("unit_data") as UnitResource
		if data != null:
			var buffed: UnitResource = data.duplicate() as UnitResource
			buffed.max_health *= 1.2
			buffed.attack *= 1.2
			militia.set("unit_data", buffed)
			militia.set("health", buffed.max_health)

		get_parent().add_child(militia)
		_summoned_militia.append(militia)

func _cleanup_summoned_militia() -> void:
	for militia: Node in _summoned_militia:
		if is_instance_valid(militia):
			militia.queue_free()
	_summoned_militia.clear()

## CLEITO - RISING TIDE
func _create_tidal_wave() -> void:
	# Query all units/buildings in 250px
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 250.0
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 3
	var results: Array[Dictionary] = space.intersect_shape(query, 64)

	for result: Dictionary in results:
		var body: Node = result["collider"] as Node
		if not is_instance_valid(body):
			continue
		var body_pid: Variant = body.get("player_id")
		if body_pid == null:
			continue

		if GameManager.are_allied(body_pid as int, player_id):
			# Ally: heal 60 HP
			var health: Variant = body.get("health")
			if health != null:
				var data: UnitResource = body.get("unit_data") as UnitResource
				if data != null:
					var new_hp: float = minf((health as float) + 60.0, data.max_health)
					body.set("health", new_hp)
					if body.has_method("_update_health_bar"):
						body.call("_update_health_bar")
		else:
			# Enemy: damage 20
			if body.has_method("take_damage"):
				body.take_damage(20.0, self)

## ELISSA - MERCENARY PACT
func _convert_enemy_for_gold() -> void:
	# Check if player has 400 gold
	if (ResourceManager.get_resources(player_id).get("gold", 0.0) as float) < 400.0:
		_ability_fizzled = true
		return

	# Find nearest enemy unit (non-hero) within 200px
	var nearest: Node = null
	var nearest_dist: float = 200.0
	var units: Array = get_tree().get_nodes_in_group("units")
	for unit: Node in units:
		if not is_instance_valid(unit):
			continue
		var unit_pid: Variant = unit.get("player_id")
		if unit_pid == null or GameManager.are_allied(unit_pid as int, player_id):
			continue
		var data: UnitResource = unit.get("unit_data") as UnitResource
		if data == null or data.is_hero:
			continue
		var dist: float = global_position.distance_to((unit as Node2D).global_position)
		if dist < nearest_dist:
			nearest = unit
			nearest_dist = dist

	if nearest == null:
		_ability_fizzled = true
	if nearest != null:
		ResourceManager.add_resource(player_id, "gold", -400.0)
		nearest.set("player_id", player_id)
		# Re-apply player color stripe
		if nearest.has_method("_add_player_color_stripe"):
			nearest.call("_add_player_color_stripe")

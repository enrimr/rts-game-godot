class_name BuildingDamageFx extends Node2D

## Progressive fire & smoke on a damaged building: light smoke from the FIRST
## point of damage (so an attack is visible immediately), flames join under
## 50 % HP, heavy fire and dark smoke under 25 %. Repairing walks the stages
## back down; construction sites and rubble never burn. Attach() parents it to
## the building root and uprights it, so the plumes rise up-screen under the
## iso camera. Purely visual — particles draw their randomness from the
## render-side RNG, never from MatchRng.

const CHECK_INTERVAL: float = 0.3
## HP ratios BELOW which each stage starts (stage 1, 2, 3). The first sits a
## hair under 1.0: any damage at all starts the smoke.
const STAGE_RATIOS: Array[float] = [0.9999, 0.5, 0.25]

const SMOKE_LIGHT: Color = Color(0.55, 0.55, 0.58, 0.55)
const SMOKE_DARK: Color = Color(0.16, 0.15, 0.16, 0.7)
const FIRE_BRIGHT: Color = Color(1.0, 0.82, 0.25, 0.9)
const FIRE_DEEP: Color = Color(0.95, 0.35, 0.08, 0.85)

static var _puff_texture: Texture2D = null

var _building: Node = null
var _half_width: float = 40.0
var _stage: int = -1
var _timer: float = CHECK_INTERVAL
var _smoke: CPUParticles2D = null
var _fires: Array[CPUParticles2D] = []

static func attach(building: Node2D) -> void:
	if building.get_node_or_null("DamageFx") != null:
		return
	var fx: BuildingDamageFx = BuildingDamageFx.new()
	fx.name = "DamageFx"
	fx._building = building
	var cs: CollisionShape2D = building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		fx._half_width = maxf((cs.shape as RectangleShape2D).size.x * 0.5, 24.0)
	building.add_child(fx)
	IsoBillboard.make_upright(fx)

## HP ratio → damage stage 0..3. Pure, tested.
static func stage_for(ratio: float) -> int:
	var stage: int = 0
	for threshold: float in STAGE_RATIOS:
		if ratio < threshold:
			stage += 1
	return stage

func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_apply_stage(_current_stage())

func _current_stage() -> int:
	if not is_instance_valid(_building):
		return 0
	# Construction sites climb through low HP by design, and rubble must not
	# smoulder forever — only a COMPLETE building burns. TC scripts without a
	# `state` property are always complete.
	var state: Variant = _building.get("state")
	if state != null and (state as int) != BuildingBase.BuildingState.COMPLETE:
		return 0
	var hp: Variant = _building.get("health")
	var max_hp: Variant = _building.get("max_health")
	if hp == null or max_hp == null or (max_hp as float) <= 0.0:
		return 0
	return stage_for(clampf((hp as float) / (max_hp as float), 0.0, 1.0))

func _apply_stage(stage: int) -> void:
	if stage == _stage:
		return
	_stage = stage
	if stage > 0 and _smoke == null:
		_build_emitters()
	if _smoke == null:
		return
	_smoke.emitting = stage > 0
	_smoke.amount = 6 + stage * 3
	_smoke.color = SMOKE_LIGHT.lerp(SMOKE_DARK, (stage - 1) / 2.0) if stage > 0 else SMOKE_LIGHT
	_smoke.scale_amount_min = 0.35 + stage * 0.1
	_smoke.scale_amount_max = 0.8 + stage * 0.25
	for i: int in range(_fires.size()):
		_fires[i].emitting = stage >= 2 and i < stage
	if stage >= 3:
		_fires[0].amount = 14

func _build_emitters() -> void:
	# One plume off the roof line: the building must stay readable underneath.
	_smoke = CPUParticles2D.new()
	_smoke.texture = _get_puff_texture()
	_smoke.lifetime = 1.9
	_smoke.direction = Vector2.UP
	_smoke.spread = 10.0
	_smoke.initial_velocity_min = 16.0
	_smoke.initial_velocity_max = 30.0
	_smoke.gravity = Vector2(5.0, -22.0)   # slight sideways drift as it rises
	_smoke.scale_amount_curve = _fade_out_curve()
	_smoke.position = Vector2(_half_width * 0.15, -_half_width * 0.9)
	_smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 4.0
	add_child(_smoke)

	# Small flame tongues at spots over the walls; each lights at a later stage.
	for anchor: Vector2 in [Vector2(-0.4, -0.35), Vector2(0.35, -0.55), Vector2(-0.05, -0.2)]:
		var fire: CPUParticles2D = CPUParticles2D.new()
		fire.texture = _get_puff_texture()
		fire.emitting = false
		fire.amount = 10
		fire.lifetime = 0.5
		fire.direction = Vector2.UP
		fire.spread = 14.0
		fire.initial_velocity_min = 18.0
		fire.initial_velocity_max = 36.0
		fire.gravity = Vector2(0.0, -30.0)
		fire.scale_amount_min = 0.2
		fire.scale_amount_max = 0.5
		fire.scale_amount_curve = _fade_out_curve()
		fire.color = FIRE_BRIGHT
		fire.color_ramp = _fire_ramp()
		fire.position = anchor * _half_width * 2.0
		fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		fire.emission_sphere_radius = 3.0
		add_child(fire)
		_fires.append(fire)

## Soft radial puff shared by every emitter (baked once).
static func _get_puff_texture() -> Texture2D:
	if _puff_texture == null:
		var tex: GradientTexture2D = GradientTexture2D.new()
		tex.width = 24
		tex.height = 24
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		tex.gradient = g
		_puff_texture = tex
	return _puff_texture

func _fade_out_curve() -> Curve:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.55))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	return curve

func _fire_ramp() -> Gradient:
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, FIRE_BRIGHT)
	ramp.set_color(1, Color(FIRE_DEEP.r, FIRE_DEEP.g, FIRE_DEEP.b, 0.0))
	ramp.add_point(0.55, FIRE_DEEP)
	return ramp

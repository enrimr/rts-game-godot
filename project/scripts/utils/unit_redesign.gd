class_name UnitRedesign
extends RefCounted

## The REDESIGNED unit style (GameSettings.UnitStyle.REDESIGNED): lore-driven
## from-scratch Polygon2D rigs for every unit, built at runtime as a
## "RedesignBody" sibling of the classic Body (which is hidden, never freed).
## Fully reversible and idempotent: strip() removes the rig and re-shows the
## classic Body. When this style is active, UnitBase calls animate() INSTEAD
## of _animate_body — this file owns the whole redesigned animation.
##
## Structure of every rig:
##   RedesignBody (Node2D, made upright by IsoBillboard; scale.x flips facing)
##     Rig (Node2D — lean/bounce/squash happen here, in screen space)
##       named part pivots (LegFront/LegBack/ArmFront/ArmBack/Head/Weapon...)
## Base pose rotations/positions are stashed in each pivot's meta so the
## animation composes offsets on top without drift.
##
## Team colour: cloth is painted directly from PlayerColors.get_color at
## build time (hue/sat of the owner, brightness modelling our own) — the
## TeamDress pass only touches the hidden classic Body. All randomness here
## is visual-only (randf), never MatchRng.

const META_APPLIED: StringName = &"redesign_applied"
const META_RIG: StringName = &"redesign_rig"
const META_ATTACK: StringName = &"redesign_attack"
const META_BASE_ROT: StringName = &"redesign_base_rot"
const META_BASE_POS: StringName = &"redesign_base_pos"

# ── Shared palette (Canarian / Atlantic material colours) ───────────────────
const SKIN: Color = Color(0.84, 0.63, 0.44)
const SKIN_DARK: Color = Color(0.71, 0.51, 0.35)
const HAIR: Color = Color(0.16, 0.11, 0.07)
const LEATHER: Color = Color(0.47, 0.33, 0.19)
const LEATHER_DARK: Color = Color(0.34, 0.23, 0.13)
const JUNCO: Color = Color(0.78, 0.70, 0.42)
const WOOD: Color = Color(0.50, 0.36, 0.20)
const WOOD_DARK: Color = Color(0.38, 0.26, 0.14)
const PINE_PALE: Color = Color(0.72, 0.60, 0.40)
const FIRE_HARDENED: Color = Color(0.24, 0.17, 0.11)
const STEEL: Color = Color(0.74, 0.76, 0.82)
const STEEL_DARK: Color = Color(0.56, 0.58, 0.66)
const BASALT: Color = Color(0.36, 0.35, 0.38)

# ── Public API ──────────────────────────────────────────────────────────────

static func is_applied(unit: Node2D) -> bool:
	return is_instance_valid(unit) and unit.get_node_or_null("RedesignBody") != null

static func apply(unit: Node2D) -> void:
	if not is_instance_valid(unit) or is_applied(unit):
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null:
		return
	var rbody: Node2D = _build_for(unit)
	if rbody == null:
		return   # no redesigned rig for this unit yet: classic stays visible
	rbody.name = "RedesignBody"
	unit.add_child(rbody)
	unit.move_child(rbody, body.get_index() + 1)
	IsoBillboard.make_upright(rbody)
	body.visible = false
	unit.set_meta(META_APPLIED, true)

static func strip(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var rbody: Node2D = unit.get_node_or_null("RedesignBody") as Node2D
	if rbody != null:
		rbody.get_parent().remove_child(rbody)
		rbody.queue_free()
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body != null:
		body.visible = true
	unit.remove_meta(META_APPLIED)

## Full animation of the redesigned style — replaces _animate_body while the
## style is active. Reads the same inputs the classic animation does
## (current_state, velocity, _anim_time) and the base pose stashed at build.
static func animate(unit: UnitBase, _delta: float) -> void:
	var rbody: Node2D = unit.get_node_or_null("RedesignBody") as Node2D
	if rbody == null:
		return
	unit._update_body_orientation(rbody)
	var rig: Node2D = rbody.get_node_or_null("Rig") as Node2D
	if rig == null:
		return
	match rbody.get_meta(META_RIG, "") as String:
		"humanoid":
			_animate_humanoid(unit, rbody, rig)
		"rider":
			_animate_rider(unit, rbody, rig)
		"dog":
			_animate_dog(unit, rbody, rig)
		"ship":
			_animate_ship(unit, rbody, rig)
		"siege":
			_animate_siege(unit, rbody, rig)

# ── Factory dispatch ────────────────────────────────────────────────────────

static func _build_for(unit: Node2D) -> Node2D:
	var data: UnitResource = unit.get("unit_data") as UnitResource
	if data == null:
		return null
	var team: Color = PlayerColors.get_color(unit.get("player_id") as int)
	var female: bool = unit.get("is_female") as bool
	if data.is_hero:
		return _build_hero(unit, data, team, female)
	match data.id:
		"villager":
			return _villager(team, female)
		"militia":
			return _militia(team, female)
		"man_at_arms":
			return _man_at_arms(team, female)
		"long_swordsman":
			return _long_swordsman(team, female)
		"pikeman":
			return _pikeman(team, female)
		"archer":
			return _archer(team, female)
		"harimaguada":
			return _harimaguada(team)
		"scout":
			return _scout(team, female)
		"heavy_scout":
			return _heavy_scout(team, female)
		"knight":
			return _knight(team)
		"presa_canario":
			return _presa_canario(team)
		"battering_ram":
			return _battering_ram(team)
		"mangonel":
			return _mangonel(team)
		"trebuchet":
			return _trebuchet(team)
		"fishing_boat":
			return _fishing_boat(team, unit.get("civ_id") as String)
		"transport_ship":
			return _transport_ship(team, unit.get("civ_id") as String)
		"war_galley":
			return _war_galley(team, unit.get("civ_id") as String)
		"menceyes_guard":
			return _menceyes_guard(team, female)
		"ravine_archer":
			return _ravine_archer(team)
		"sand_raider":
			return _sand_raider(team)
		"chevalier_normand":
			return _chevalier_normand(team)
		"longbowman":
			return _longbowman(team, female)
		"conquistador":
			return _conquistador(team, female)
		"tidecaller":
			return _tidecaller(team, female)
		"trireme":
			return _trireme(team, unit.get("civ_id") as String)
	return null

const GOLD: Color = Color(0.92, 0.78, 0.28)

## Heroes ride the redesigned warrior rig of their base class (Militia line)
## plus the regalia every hero shares: golden circlet, team cape, +12% size.
## The HeroAura renders behind the whole RedesignBody, so the figure stays
## readable on top of the flame.
static func _build_hero(_unit: Node2D, _data: UnitResource, team: Color, female: bool) -> Node2D:
	var rbody: Node2D = _militia(team, female)
	var rig: Node2D = rbody.get_node("Rig") as Node2D
	rig.scale = rig.scale * 1.12
	# Cape: falls from the shoulders down the back, in a deep team shade.
	var cape: Polygon2D = _poly(rig, "Cape", [Vector2(-3.6, -11.8), Vector2(1.6, -12.0),
		Vector2(-1.6, -6.0), Vector2(-3.2, 2.2), Vector2(-6.6, 4.6), Vector2(-6.8, -3.8),
		Vector2(-5.2, -9.6)], _cloth(team, 0.36))
	rig.move_child(cape, 0)
	var head: Node2D = rig.get_node("Head") as Node2D
	_poly(head, "Circlet", [Vector2(-3.3, -6.0), Vector2(3.1, -6.0), Vector2(3.0, -4.8),
		Vector2(-3.2, -4.8)], GOLD)
	_poly(head, "CircletGem", [Vector2(-0.6, -6.4), Vector2(0.6, -6.4), Vector2(0.6, -5.2),
		Vector2(-0.6, -5.2)], _dim(GOLD, 1.15))
	return rbody

# ── Small geometry/colour helpers ───────────────────────────────────────────

static func _cloth(team: Color, v: float) -> Color:
	return Color.from_hsv(team.h, clampf(team.s, 0.50, 0.85), v)

static func _dim(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

static func _poly(parent: Node, poly_name: String, pts: Array, color: Color) -> Polygon2D:
	var p: Polygon2D = Polygon2D.new()
	p.name = poly_name
	var packed: PackedVector2Array = PackedVector2Array()
	for v: Variant in pts:
		packed.append(v as Vector2)
	p.polygon = packed
	p.color = color
	parent.add_child(p)
	return p

static func _pivot(parent: Node, pivot_name: String, pos: Vector2, rot: float = 0.0) -> Node2D:
	var n: Node2D = Node2D.new()
	n.name = pivot_name
	n.position = pos
	n.rotation = rot
	n.set_meta(META_BASE_ROT, rot)
	n.set_meta(META_BASE_POS, pos)
	parent.add_child(n)
	return n

static func _ellipse_pts(cx: float, cy: float, rx: float, ry: float, steps: int = 10) -> Array:
	var pts: Array = []
	for i: int in range(steps):
		var a: float = TAU * float(i) / float(steps)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

# ── Humanoid part builders (figures face screen-right at scale.x = +1) ─────
# Coordinate space: feet on y=+9, hips y=+1, shoulders y=-11.5, head top y=-20.

## Legs: two hip pivots with a tapered leg + forward foot each. Far leg darker.
static func _legs(rig: Node2D, skin: Color, boots: Color = Color(0, 0, 0, 0),
		stance: float = 0.0) -> void:
	var back: Node2D = _pivot(rig, "LegBack", Vector2(2.0, 1.0), -stance)
	_leg_shape(back, _dim(skin, 0.78), _dim(boots, 0.78) if boots.a > 0.0 else Color(0, 0, 0, 0))
	var front: Node2D = _pivot(rig, "LegFront", Vector2(-2.0, 1.0), stance)
	_leg_shape(front, skin, boots)

static func _leg_shape(leg: Node2D, skin: Color, boots: Color) -> void:
	_poly(leg, "Limb", [Vector2(-1.6, -0.4), Vector2(1.6, -0.4), Vector2(1.3, 4.0),
		Vector2(1.5, 7.4), Vector2(-0.9, 7.4), Vector2(-1.1, 4.0)], skin)
	var foot_col: Color = boots if boots.a > 0.0 else LEATHER_DARK
	_poly(leg, "Foot", [Vector2(-1.1, 6.8), Vector2(2.6, 7.0), Vector2(2.9, 8.6),
		Vector2(-1.3, 8.6)], foot_col)
	if boots.a > 0.0:
		_poly(leg, "Boot", [Vector2(-1.5, 4.2), Vector2(1.6, 4.2), Vector2(1.6, 7.2),
			Vector2(-1.2, 7.2)], boots)

## Arm: shoulder pivot; slightly bent limb ending in a hand at ~(1.6, 7.6).
static func _arm(rig: Node2D, arm_name: String, shoulder: Vector2, sleeve: Color,
		skin: Color, base_rot: float = 0.0) -> Node2D:
	var arm: Node2D = _pivot(rig, arm_name, shoulder, base_rot)
	_poly(arm, "Limb", [Vector2(-1.2, -0.6), Vector2(1.3, -0.6), Vector2(1.7, 3.6),
		Vector2(2.6, 7.0), Vector2(0.9, 7.9), Vector2(-0.3, 3.6)], sleeve)
	_poly(arm, "Hand", _ellipse_pts(1.7, 7.4, 1.2, 1.2, 8), skin)
	return arm

## Head: neck pivot with skull, ear, eye dot and a hair style.
##  hair_style: "curly" | "half" | "long" | "bald"
static func _head(rig: Node2D, skin: Color, hair: Color, hair_style: String) -> Node2D:
	var head: Node2D = _pivot(rig, "Head", Vector2(0.0, -12.2))
	_poly(head, "Neck", [Vector2(-1.2, -0.6), Vector2(1.2, -0.6), Vector2(1.2, 1.4),
		Vector2(-1.2, 1.4)], _dim(skin, 0.9))
	if hair_style == "long":
		_long_hair_back(head, _dim(hair, 0.85))
	_poly(head, "Skull", _ellipse_pts(0.3, -3.6, 3.0, 3.4, 12), skin)
	_poly(head, "Eye", _ellipse_pts(1.9, -3.6, 0.5, 0.6, 6), Color(0.13, 0.10, 0.08))
	match hair_style:
		"curly":
			_poly(head, "Hair", [Vector2(-3.2, -3.4), Vector2(-3.6, -5.6), Vector2(-2.4, -6.9),
				Vector2(-0.4, -7.5), Vector2(1.8, -7.3), Vector2(3.0, -6.2), Vector2(3.2, -5.0),
				Vector2(2.2, -5.4), Vector2(0.8, -6.0), Vector2(-0.8, -6.2),
				Vector2(-1.9, -5.5), Vector2(-2.2, -3.9)], hair)
		"half":
			_poly(head, "Hair", [Vector2(-3.3, -3.2), Vector2(-3.7, -5.8), Vector2(-2.2, -7.1),
				Vector2(0.4, -7.5), Vector2(2.5, -6.6), Vector2(3.1, -5.1), Vector2(1.9, -5.6),
				Vector2(-0.8, -6.0), Vector2(-2.0, -4.6), Vector2(-2.2, -1.0),
				Vector2(-3.3, -0.6)], hair)
		"long":
			# Solid crown: covers the whole top of the skull, sweeps deeper at
			# the back (behind the ear) and leaves only the face open — a thin
			# ring read as a bald forehead at map zoom.
			_poly(head, "Hair", [Vector2(2.7, -5.2), Vector2(2.5, -6.8), Vector2(1.2, -7.7),
				Vector2(-0.4, -7.9), Vector2(-2.0, -7.3), Vector2(-3.0, -6.0),
				Vector2(-3.3, -4.2), Vector2(-3.1, -2.6), Vector2(-2.0, -2.2),
				Vector2(-1.3, -3.5), Vector2(-0.5, -4.7), Vector2(0.7, -5.1),
				Vector2(1.8, -5.0), Vector2(2.3, -4.9)], hair)
			# Face-framing front lock falling from the hairline.
			_poly(head, "HairWisp", [Vector2(2.6, -5.3), Vector2(3.1, -4.4),
				Vector2(2.7, -3.4), Vector2(2.3, -4.5)], _dim(hair, 0.94))
	return head

## Long female hair: one flowing mass from the crown down past the shoulder —
## smooth S-curve on the outer edge, soft inward-curling tip, and a lighter
## strand for volume. The shine is a CHILD of the mass so the walk sway
## (_sway_hair) moves them as one.
static func _long_hair_back(head: Node2D, hair: Color) -> void:
	var mass: Polygon2D = _poly(head, "HairBack", [
		Vector2(0.6, -7.8), Vector2(-1.6, -7.5), Vector2(-3.0, -6.2),
		Vector2(-3.7, -4.4), Vector2(-4.0, -2.2), Vector2(-4.1, 0.2),
		Vector2(-3.8, 2.2), Vector2(-3.1, 3.8), Vector2(-2.0, 4.7),
		Vector2(-1.1, 4.1), Vector2(-1.7, 2.8), Vector2(-1.9, 0.9),
		Vector2(-1.8, -1.2), Vector2(-1.5, -3.0), Vector2(-0.6, -5.2)], hair)
	_poly(mass, "HairShine", [Vector2(-2.4, -5.7), Vector2(-3.2, -3.8), Vector2(-3.5, -1.4),
		Vector2(-3.4, 1.2), Vector2(-2.9, 1.5), Vector2(-2.9, -1.2),
		Vector2(-2.5, -3.5), Vector2(-1.8, -5.1)], _dim(hair, 1.16))

## Gentle lagging sway on the long hair: follows the walk beat, breathes in
## idle. Rotates around the neck pivot so the tip travels more than the root.
static func _sway_hair(head: Node2D, t: float, moving: bool, cadence: float) -> void:
	if head == null:
		return
	var mass: Polygon2D = head.get_node_or_null("HairBack") as Polygon2D
	if mass == null:
		return
	if moving:
		mass.rotation = sin(t * TAU * cadence - 1.1) * 0.10 + 0.05
	else:
		mass.rotation = sin(t * TAU * 0.45 + 0.8) * 0.035

## Tamarco: the goat-hide tunic, painted in the owner's colour. Ragged hem,
## junco belt, bare weapon-side shoulder with a diagonal strap.
static func _tamarco(rig: Node2D, team: Color, skin: Color, skirt_len: float = 3.6) -> void:
	var cloth: Color = _cloth(team, 0.60)
	_poly(rig, "Tunic", [Vector2(-3.5, -11.8), Vector2(2.0, -11.8), Vector2(3.3, -8.6),
		Vector2(3.0, -3.0), Vector2(4.3, skirt_len - 1.0), Vector2(2.4, skirt_len + 0.4),
		Vector2(0.6, skirt_len - 0.6), Vector2(-1.2, skirt_len + 0.6),
		Vector2(-3.0, skirt_len - 0.8), Vector2(-4.4, skirt_len - 1.6),
		Vector2(-3.1, -3.0)], cloth)
	_poly(rig, "TunicShade", [Vector2(-3.5, -11.8), Vector2(-1.8, -11.8),
		Vector2(-1.6, -3.2), Vector2(-3.0, skirt_len - 1.2), Vector2(-4.4, skirt_len - 1.6),
		Vector2(-3.1, -3.0)], _cloth(team, 0.44))
	# Bare shoulder + chest on the weapon side (one-shoulder hide).
	_poly(rig, "Chest", [Vector2(0.4, -11.8), Vector2(2.0, -11.8), Vector2(3.3, -8.6),
		Vector2(2.9, -6.8), Vector2(0.9, -8.4)], skin)
	_poly(rig, "Strap", [Vector2(-3.2, -11.4), Vector2(-2.2, -11.8), Vector2(3.0, -5.2),
		Vector2(2.8, -3.8)], LEATHER_DARK)
	_poly(rig, "Belt", [Vector2(-3.2, -3.2), Vector2(3.1, -3.2), Vector2(3.0, -1.5),
		Vector2(-3.1, -1.5)], JUNCO)
	_poly(rig, "BeltKnot", _ellipse_pts(-0.4, -2.3, 0.9, 1.1, 6), _dim(JUNCO, 0.8))

## Both-shoulder cloth tunic (soldiers under armour, archers).
static func _tunic(rig: Node2D, team: Color, skirt_len: float = 3.0) -> void:
	var cloth: Color = _cloth(team, 0.58)
	_poly(rig, "Tunic", [Vector2(-3.6, -11.8), Vector2(3.6, -11.8), Vector2(3.1, -3.0),
		Vector2(4.2, skirt_len - 0.8), Vector2(0.4, skirt_len + 0.6),
		Vector2(-4.3, skirt_len - 1.0), Vector2(-3.1, -3.0)], cloth)
	_poly(rig, "TunicShade", [Vector2(-3.6, -11.8), Vector2(-1.8, -11.8),
		Vector2(-1.6, -3.0), Vector2(-2.6, skirt_len - 0.4), Vector2(-4.3, skirt_len - 1.0),
		Vector2(-3.1, -3.0)], _cloth(team, 0.42))
	_poly(rig, "Belt", [Vector2(-3.2, -3.2), Vector2(3.1, -3.2), Vector2(3.0, -1.5),
		Vector2(-3.1, -1.5)], LEATHER_DARK)

## The common humanoid frame: legs, torso builder callback, head, both arms.
## Returns { rbody, rig, head, arm_front, arm_back }.
static func _humanoid_frame(attack_kind: String, cadence: float = 2.4) -> Dictionary:
	var rbody: Node2D = Node2D.new()
	rbody.set_meta(META_RIG, "humanoid")
	rbody.set_meta(META_ATTACK, attack_kind)
	rbody.set_meta(&"cadence", cadence)
	var rig: Node2D = _pivot(rbody, "Rig", Vector2.ZERO)
	return {"rbody": rbody, "rig": rig}

# ── Batch A unit builders ───────────────────────────────────────────────────

## Villager — tamarco of goat hide, junco belt, tanned skin, dark curly hair;
## the female wears the saya (longer skirt) and long hair. Multi-tool hand:
## axe / pick / hammer heads toggled by the animation, plus a carry sack.
static func _villager(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("tool")
	var rig: Node2D = f["rig"] as Node2D
	_arm(rig, "ArmBack", Vector2(-2.3, -10.9), _dim(SKIN, 0.80), _dim(SKIN, 0.80), 0.25)
	_legs(rig, SKIN)
	if female:
		_tamarco(rig, team, SKIN, 6.2)
		rig.scale.x = 0.94
	else:
		_tamarco(rig, team, SKIN)
	_head(rig, SKIN, HAIR, "long" if female else "curly")
	# Carry sack (visible only while hauling resources home).
	var sack: Polygon2D = _poly(rig, "Carry", _ellipse_pts(3.4, -6.4, 2.4, 2.9, 8),
		_dim(JUNCO, 0.72))
	sack.visible = false
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.3, -11.0), SKIN, SKIN, -0.35)
	var tool: Node2D = _pivot(arm_front, "Tool", Vector2(1.7, 7.4), 0.55)
	_poly(tool, "Handle", [Vector2(-0.8, 2.6), Vector2(0.8, 2.6), Vector2(0.8, -11.0),
		Vector2(-0.8, -11.0)], WOOD)
	var axe: Polygon2D = _poly(tool, "AxeHead", [Vector2(0.6, -11.2), Vector2(5.4, -10.6),
		Vector2(6.1, -7.8), Vector2(4.4, -6.6), Vector2(0.6, -7.8)], BASALT)
	axe.visible = true
	_poly(axe, "AxeEdge", [Vector2(5.4, -10.6), Vector2(6.1, -7.8), Vector2(4.4, -6.6),
		Vector2(4.9, -9.2)], _dim(BASALT, 1.35))
	var pick: Polygon2D = _poly(tool, "PickHead", [Vector2(-4.4, -9.0), Vector2(-0.6, -12.0),
		Vector2(4.0, -11.0), Vector2(5.8, -7.8), Vector2(4.2, -9.4), Vector2(0.2, -10.2),
		Vector2(-3.4, -7.8)], BASALT)
	pick.visible = false
	var hammer: Polygon2D = _poly(tool, "HammerHead", [Vector2(-2.2, -12.0), Vector2(3.0, -12.0),
		Vector2(3.0, -8.6), Vector2(-2.2, -8.6)], _dim(BASALT, 1.15))
	hammer.visible = false
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Chest",
		"Strap", "Belt", "BeltKnot", "Carry", "Head", "ArmFront"])
	return f["rbody"] as Node2D

## Militia — the island warrior: tamarco, leather headband, wrist band and the
## magado (knobbed hardwood club) held over the shoulder.
static func _militia(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash")
	var rig: Node2D = f["rig"] as Node2D
	_arm(rig, "ArmBack", Vector2(-2.4, -10.9), _dim(SKIN, 0.80), _dim(SKIN, 0.80), 0.3)
	_legs(rig, SKIN)
	_tamarco(rig, team, SKIN)
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "curly")
	_poly(head, "Headband", [Vector2(-3.3, -5.4), Vector2(3.1, -5.4), Vector2(3.0, -4.2),
		Vector2(-3.2, -4.2)], LEATHER_DARK)
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.4, -11.0), SKIN, SKIN, -0.4)
	_poly(arm_front, "WristBand", [Vector2(0.6, 4.6), Vector2(2.4, 4.2), Vector2(2.7, 5.6),
		Vector2(0.9, 6.0)], LEATHER)
	_magado(arm_front, false)
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Chest",
		"Strap", "Belt", "BeltKnot", "Head", "ArmFront"])
	return f["rbody"] as Node2D

## The magado: knobbed hardwood club, cocked over the shoulder at rest.
## heavy=true makes it bulkier with basalt chips (Man-at-Arms).
static func _magado(arm_front: Node2D, heavy: bool) -> void:
	var club: Node2D = _pivot(arm_front, "Weapon", Vector2(1.7, 7.4), 0.9)
	_poly(club, "Shaft", [Vector2(-0.9, 2.6), Vector2(0.9, 2.6), Vector2(1.3, -8.2),
		Vector2(-1.3, -8.2)], WOOD_DARK if heavy else WOOD)
	_poly(club, "Knob", _ellipse_pts(0.0, -9.8, 2.9 if heavy else 2.3, 3.3 if heavy else 2.7, 9),
		WOOD_DARK if heavy else WOOD)
	_poly(club, "KnobLight", _ellipse_pts(0.9, -10.6, 1.1 if heavy else 0.9,
		1.3 if heavy else 1.1, 7), _dim(WOOD, 1.22))
	if heavy:
		_poly(club, "Chip1", [Vector2(-2.6, -9.4), Vector2(-4.2, -10.6), Vector2(-2.2, -11.2)], BASALT)
		_poly(club, "Chip2", [Vector2(2.3, -11.4), Vector2(3.9, -10.4), Vector2(2.1, -9.3)], BASALT)
		_poly(club, "Chip3", [Vector2(-0.8, -12.6), Vector2(1.0, -12.8), Vector2(0.1, -11.0)], BASALT)

## Man-at-Arms — same warrior, now in hardened leather: cuirass over the team
## tunic, leather cap, heavier stone-studded magado, hide shield on the far arm.
static func _man_at_arms(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash")
	var rig: Node2D = f["rig"] as Node2D
	var arm_back: Node2D = _arm(rig, "ArmBack", Vector2(-2.4, -10.9), _dim(SKIN, 0.80),
		_dim(SKIN, 0.80), 0.35)
	_hide_shield(arm_back, team)
	_legs(rig, SKIN)
	_tunic(rig, team)
	_poly(rig, "Cuirass", [Vector2(-3.4, -11.6), Vector2(3.4, -11.6), Vector2(3.0, -4.6),
		Vector2(0.0, -3.8), Vector2(-3.0, -4.6)], LEATHER)
	_poly(rig, "CuirassShade", [Vector2(-3.4, -11.6), Vector2(-1.6, -11.6), Vector2(-1.5, -4.2),
		Vector2(-3.0, -4.6)], LEATHER_DARK)
	_poly(rig, "CuirassSeam", [Vector2(-3.2, -8.4), Vector2(3.1, -8.4), Vector2(3.05, -7.6),
		Vector2(-3.15, -7.6)], LEATHER_DARK)
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "curly")
	_poly(head, "Cap", [Vector2(-3.7, -4.2), Vector2(-3.5, -6.6), Vector2(-1.8, -8.0),
		Vector2(1.4, -8.1), Vector2(3.2, -6.8), Vector2(3.6, -4.2), Vector2(2.4, -5.2),
		Vector2(-0.2, -5.9), Vector2(-2.4, -5.2)], _dim(LEATHER, 1.25))
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.4, -11.0), _dim(LEATHER, 1.05),
		SKIN, -0.4)
	_magado(arm_front, true)
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Belt",
		"Cuirass", "CuirassShade", "CuirassSeam", "Head", "ArmFront"])
	return f["rbody"] as Node2D

static func _hide_shield(arm_back: Node2D, team: Color) -> void:
	var shield: Node2D = _pivot(arm_back, "Shield", Vector2(-1.0, 5.0), 0.0)
	_poly(shield, "Rim", _ellipse_pts(0.0, 0.0, 3.9, 4.9, 12), LEATHER_DARK)
	_poly(shield, "Face", _ellipse_pts(0.0, 0.0, 3.3, 4.2, 12), LEATHER)
	_poly(shield, "Boss", _ellipse_pts(0.0, 0.0, 1.2, 1.5, 8), _cloth(team, 0.62))

## Long Swordsman — the veteran with captured Castilian steel: sword + rodela,
## leather cuirass, open steel capacete.
static func _long_swordsman(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash", 2.4)
	var rig: Node2D = f["rig"] as Node2D
	var arm_back: Node2D = _arm(rig, "ArmBack", Vector2(-2.4, -10.9), _dim(SKIN, 0.80),
		_dim(SKIN, 0.80), 0.35)
	_rodela(arm_back, team)
	_legs(rig, SKIN, LEATHER_DARK)
	_tunic(rig, team)
	_poly(rig, "Cuirass", [Vector2(-3.4, -11.6), Vector2(3.4, -11.6), Vector2(3.0, -4.6),
		Vector2(0.0, -3.8), Vector2(-3.0, -4.6)], LEATHER)
	_poly(rig, "CuirassShade", [Vector2(-3.4, -11.6), Vector2(-1.6, -11.6), Vector2(-1.5, -4.2),
		Vector2(-3.0, -4.6)], LEATHER_DARK)
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "half")
	_poly(head, "Helm", [Vector2(-3.6, -4.6), Vector2(-3.3, -6.6), Vector2(-1.6, -7.9),
		Vector2(1.2, -8.0), Vector2(3.0, -6.8), Vector2(3.4, -4.6), Vector2(4.3, -4.4),
		Vector2(4.2, -3.6), Vector2(-4.4, -3.6), Vector2(-4.4, -4.4)], STEEL)
	_poly(head, "HelmShade", [Vector2(-3.6, -4.6), Vector2(-3.3, -6.6), Vector2(-1.9, -7.7),
		Vector2(-1.6, -3.6), Vector2(-4.4, -3.6), Vector2(-4.4, -4.4)], STEEL_DARK)
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.4, -11.0), _dim(LEATHER, 1.05),
		SKIN, -0.5)
	var sword: Node2D = _pivot(arm_front, "Weapon", Vector2(1.7, 7.4), 0.85)
	_poly(sword, "Grip", [Vector2(-0.5, 1.8), Vector2(0.5, 1.8), Vector2(0.5, -1.2),
		Vector2(-0.5, -1.2)], LEATHER_DARK)
	_poly(sword, "Guard", [Vector2(-2.2, -1.2), Vector2(2.2, -1.2), Vector2(2.2, -2.2),
		Vector2(-2.2, -2.2)], STEEL_DARK)
	_poly(sword, "Blade", [Vector2(-0.8, -2.2), Vector2(0.8, -2.2), Vector2(0.5, -13.2),
		Vector2(0.0, -14.6), Vector2(-0.5, -13.2)], STEEL)
	_poly(sword, "BladeEdge", [Vector2(0.0, -2.2), Vector2(0.8, -2.2), Vector2(0.5, -13.2),
		Vector2(0.0, -14.6)], _dim(STEEL, 0.86))
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Belt",
		"Cuirass", "CuirassShade", "Head", "ArmFront"])
	return f["rbody"] as Node2D

static func _rodela(arm_back: Node2D, team: Color) -> void:
	var shield: Node2D = _pivot(arm_back, "Shield", Vector2(-1.0, 5.0), 0.0)
	_poly(shield, "Rim", _ellipse_pts(0.0, 0.0, 4.0, 5.0, 12), STEEL_DARK)
	_poly(shield, "Face", _ellipse_pts(0.0, 0.0, 3.3, 4.2, 12), WOOD)
	_poly(shield, "Boss", _ellipse_pts(0.0, 0.0, 1.4, 1.8, 8), _cloth(team, 0.62))

## Pikeman — the banot: a long fire-hardened pine spear held two-handed in a
## low defensive crouch.
static func _pikeman(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("thrust", 2.2)
	var rig: Node2D = f["rig"] as Node2D
	rig.position.y = 1.0
	rig.set_meta(META_BASE_POS, rig.position)
	# Far arm reaches forward to the shaft.
	_arm(rig, "ArmBack", Vector2(-2.3, -10.9), _dim(SKIN, 0.80), _dim(SKIN, 0.80), -1.15)
	_legs(rig, SKIN, Color(0, 0, 0, 0), 0.30)
	_tamarco(rig, team, SKIN)
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "curly")
	_poly(head, "Headband", [Vector2(-3.3, -5.4), Vector2(3.1, -5.4), Vector2(3.0, -4.2),
		Vector2(-3.2, -4.2)], _cloth(team, 0.50))
	# The banot is held by the RIG (both hands read as gripping it): a long
	# pale pine shaft with a dark fire-hardened tip, angled forward-down.
	var spear: Node2D = _pivot(rig, "Weapon", Vector2(0.8, -3.5), 1.85)
	_poly(spear, "Shaft", [Vector2(-0.55, 15.0), Vector2(0.55, 15.0), Vector2(0.55, -16.0),
		Vector2(-0.55, -16.0)], PINE_PALE)
	_poly(spear, "Tip", [Vector2(-0.55, -15.0), Vector2(0.55, -15.0), Vector2(0.0, -20.0)],
		FIRE_HARDENED)
	_poly(spear, "Lash", [Vector2(-0.8, -13.6), Vector2(0.8, -13.6), Vector2(0.8, -12.0),
		Vector2(-0.8, -12.0)], LEATHER_DARK)
	_arm(rig, "ArmFront", Vector2(2.3, -11.0), SKIN, SKIN, -0.35)
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Chest",
		"Strap", "Belt", "BeltKnot", "Head", "Weapon", "ArmFront"])
	return f["rbody"] as Node2D

## Archer — simple wooden self bow, leather quiver at the hip, half-length hair.
static func _archer(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("bow", 2.5)
	var rig: Node2D = f["rig"] as Node2D
	# Draw arm (far side): pulls the string during the shot.
	var arm_back: Node2D = _arm(rig, "ArmBack", Vector2(-2.3, -10.9), _dim(SKIN, 0.80),
		_dim(SKIN, 0.80), -0.5)
	arm_back.name = "DrawArm"
	arm_back.set_meta(META_BASE_ROT, -0.5)
	_legs(rig, SKIN)
	_tunic(rig, team, 2.4)
	# Quiver slung on the back: leather tube with straw fletchings poking out
	# above the far shoulder.
	var quiver: Node2D = _pivot(rig, "Quiver", Vector2(-3.6, -8.6), 0.55)
	_poly(quiver, "Tube", [Vector2(-1.5, -3.8), Vector2(1.5, -3.8), Vector2(1.2, 3.8),
		Vector2(-1.2, 3.8)], LEATHER)
	_poly(quiver, "TubeRim", [Vector2(-1.5, -3.8), Vector2(1.5, -3.8), Vector2(1.4, -2.8),
		Vector2(-1.4, -2.8)], LEATHER_DARK)
	_poly(quiver, "Fl1", [Vector2(-1.1, -3.8), Vector2(-0.3, -6.4), Vector2(0.3, -3.8)], JUNCO)
	_poly(quiver, "Fl2", [Vector2(0.3, -4.0), Vector2(1.1, -5.8), Vector2(1.5, -3.8)],
		_dim(JUNCO, 0.85))
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "half")
	_poly(head, "Bracer", [], LEATHER).visible = false
	# Bow arm (near side) holds the bow low-forward at rest.
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.3, -11.0), SKIN, SKIN, -0.55)
	var bow: Node2D = _pivot(arm_front, "Weapon", Vector2(1.7, 7.4), 0.5)
	_poly(bow, "Stave", [Vector2(-0.8, -10.4), Vector2(0.7, -10.8), Vector2(2.6, -6.2),
		Vector2(3.3, 0.0), Vector2(2.6, 6.2), Vector2(0.7, 10.8), Vector2(-0.8, 10.4),
		Vector2(1.2, 5.6), Vector2(1.8, 0.0), Vector2(1.2, -5.6)], WOOD)
	var string: Line2D = Line2D.new()
	string.name = "BowString"
	string.width = 0.8
	string.default_color = Color(0.88, 0.85, 0.74)
	string.points = PackedVector2Array([Vector2(-0.5, -10.4), Vector2(-0.6, 0.0), Vector2(-0.5, 10.4)])
	bow.add_child(string)
	var arrow: Polygon2D = _poly(bow, "Arrow", [Vector2(0.4, -0.4), Vector2(-9.6, -0.4),
		Vector2(-9.6, 0.4), Vector2(0.4, 0.4)], WOOD_DARK)
	_poly(arrow, "ArrowTip", [Vector2(2.2, 0.0), Vector2(0.2, -0.9), Vector2(0.2, 0.9)], BASALT)
	arrow.visible = false
	_reorder(rig, ["Quiver", "DrawArm", "LegBack", "LegFront", "Tunic", "TunicShade",
		"Belt", "Head", "ArmFront"])
	return f["rbody"] as Node2D

## Harimaguada — the Canarii priestess-healer: always female, white gown of
## pale hides, clay-bead necklace, terracotta bowl; the team lives in her sash.
static func _harimaguada(team: Color) -> Node2D:
	var f: Dictionary = _humanoid_frame("heal", 2.0)
	var rig: Node2D = f["rig"] as Node2D
	var gown: Color = Color(0.93, 0.89, 0.80)
	var gown_shade: Color = Color(0.80, 0.76, 0.67)
	_arm(rig, "ArmBack", Vector2(-2.2, -10.9), _dim(gown, 0.85), _dim(SKIN, 0.80), -0.5)
	_legs(rig, SKIN)
	_poly(rig, "Tunic", [Vector2(-3.3, -11.8), Vector2(3.3, -11.8), Vector2(2.9, -3.0),
		Vector2(4.6, 6.6), Vector2(2.2, 7.4), Vector2(-0.2, 6.9), Vector2(-2.6, 7.4),
		Vector2(-4.8, 6.4), Vector2(-2.9, -3.0)], gown)
	_poly(rig, "TunicShade", [Vector2(-3.3, -11.8), Vector2(-1.6, -11.8), Vector2(-1.5, -3.0),
		Vector2(-2.8, 7.0), Vector2(-4.8, 6.4), Vector2(-2.9, -3.0)], gown_shade)
	_poly(rig, "Sash", [Vector2(-3.0, -11.6), Vector2(-1.6, -11.8), Vector2(2.8, -4.4),
		Vector2(2.7, -2.6), Vector2(-3.0, -3.4)], _cloth(team, 0.62))
	_poly(rig, "Belt", [Vector2(-2.9, -3.4), Vector2(2.9, -3.4), Vector2(2.8, -1.8),
		Vector2(-2.8, -1.8)], _cloth(team, 0.48))
	_poly(rig, "Necklace", [Vector2(-1.8, -11.0), Vector2(0.0, -9.2), Vector2(1.8, -11.0),
		Vector2(1.2, -9.4), Vector2(0.0, -8.4), Vector2(-1.2, -9.4)], Color(0.72, 0.42, 0.28))
	_head(rig, SKIN, HAIR, "long")
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.2, -11.0), _dim(gown, 0.95),
		SKIN, -1.15)
	var bowl: Node2D = _pivot(arm_front, "Weapon", Vector2(1.7, 7.2), 1.15)
	_poly(bowl, "Bowl", [Vector2(-3.2, -0.6), Vector2(3.2, -0.6), Vector2(2.2, 2.6),
		Vector2(-2.2, 2.6)], Color(0.58, 0.30, 0.18))
	_poly(bowl, "BowlRim", [Vector2(-3.2, -1.4), Vector2(3.2, -1.4), Vector2(3.2, -0.4),
		Vector2(-3.2, -0.4)], Color(0.46, 0.23, 0.13))
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Sash",
		"Belt", "Necklace", "Head", "ArmFront"])
	return f["rbody"] as Node2D

# ── Batch B: cavalry + the Presa Canario ────────────────────────────────────
# Horse space: hooves on y=+11, back at y=-5, head reaches x=+19. The rider
# sits in a "Rider" pivot at the withers; riders and horses animate decoupled.

const HORSE_DUN: Color = Color(0.60, 0.47, 0.31)
const HORSE_DARK: Color = Color(0.30, 0.22, 0.13)
const DOG_COAT: Color = Color(0.46, 0.34, 0.22)
const DOG_DARK: Color = Color(0.32, 0.23, 0.14)

## Builds the shared horse into `rig`. blanket paints a saddle cloth; the
## caparison flag drapes the whole barrel + neck in team cloth (Knight).
static func _horse(rig: Node2D, coat: Color, blanket: Color = Color(0, 0, 0, 0),
		caparison: bool = false, team: Color = Color.WHITE) -> void:
	var far_coat: Color = _dim(coat, 0.78)
	var tail: Node2D = _pivot(rig, "Tail", Vector2(-12.3, -3.6))
	_poly(tail, "TailHair", [Vector2(0.6, -1.2), Vector2(-2.4, 1.0), Vector2(-3.0, 6.4),
		Vector2(-1.2, 6.0), Vector2(-0.2, 2.0)], HORSE_DARK)
	var back_far: Node2D = _pivot(rig, "LegBackFarP", Vector2(-7.4, 1.0), -0.14)
	back_far.name = "LegBackFar"
	_horse_leg_shape(back_far, far_coat)
	var front_far: Node2D = _pivot(rig, "LegFrontFarP", Vector2(6.8, 1.0), 0.12)
	front_far.name = "LegFrontFar"
	_horse_leg_shape(front_far, far_coat)
	_poly(rig, "HorseBody", [Vector2(-12.6, -2.0), Vector2(-10.8, -5.4), Vector2(-6.0, -7.0),
		Vector2(5.0, -7.0), Vector2(10.0, -5.6), Vector2(12.2, -2.4), Vector2(11.6, 1.0),
		Vector2(8.0, 2.6), Vector2(4.0, 3.6), Vector2(-2.0, 3.9), Vector2(-7.0, 3.2),
		Vector2(-10.2, 2.2), Vector2(-12.4, 0.6)], coat)
	_poly(rig, "BellyShade", [Vector2(-9.4, 1.6), Vector2(7.6, 1.4), Vector2(4.0, 3.5),
		Vector2(-2.0, 3.8), Vector2(-7.0, 3.1)], _dim(coat, 0.80))
	_poly(rig, "Neck", [Vector2(6.0, -3.5), Vector2(9.0, -6.6), Vector2(15.0, -13.4),
		Vector2(11.5, -14.6), Vector2(6.4, -7.0)], _dim(coat, 1.05))
	var head: Node2D = _pivot(rig, "HorseHead", Vector2(13.0, -12.6))
	_poly(head, "Skull", [Vector2(-1.6, -1.8), Vector2(1.4, -2.8), Vector2(4.2, -1.4),
		Vector2(6.6, 0.6), Vector2(6.4, 2.2), Vector2(4.0, 2.6), Vector2(0.4, 1.8),
		Vector2(-1.8, 0.8)], _dim(coat, 1.08) if not caparison else STEEL)
	_poly(head, "Ear", [Vector2(-0.8, -2.4), Vector2(0.4, -4.6), Vector2(1.6, -2.6)],
		_dim(coat, 0.9) if not caparison else STEEL_DARK)
	_poly(head, "Muzzle", [Vector2(4.2, 0.2), Vector2(6.6, 0.6), Vector2(6.4, 2.2),
		Vector2(4.0, 2.6)], _dim(coat, 0.72) if not caparison else STEEL_DARK)
	_poly(head, "HorseEye", _ellipse_pts(0.8, -0.6, 0.55, 0.6, 6), Color(0.10, 0.08, 0.06))
	_poly(rig, "Mane", [Vector2(5.6, -6.4), Vector2(10.6, -13.6), Vector2(13.0, -13.0),
		Vector2(8.2, -5.2)], HORSE_DARK)
	if caparison:
		_poly(rig, "Caparison", [Vector2(-13.2, -2.4), Vector2(-11.0, -5.6), Vector2(-6.0, -7.2),
			Vector2(5.0, -7.2), Vector2(10.0, -5.8), Vector2(12.6, -2.6), Vector2(12.0, 2.4),
			Vector2(9.4, 4.6), Vector2(6.4, 2.8), Vector2(3.4, 4.8), Vector2(0.4, 2.9),
			Vector2(-2.6, 4.9), Vector2(-5.6, 3.0), Vector2(-8.6, 4.8), Vector2(-11.4, 2.4),
			Vector2(-13.0, 0.6)], _cloth(team, 0.58))
		_poly(rig, "CaparisonNeck", [Vector2(6.0, -3.8), Vector2(9.0, -6.8), Vector2(14.6, -13.2),
			Vector2(11.6, -14.4), Vector2(6.2, -7.2)], _cloth(team, 0.48))
	elif blanket.a > 0.0:
		_poly(rig, "Blanket", [Vector2(-6.4, -6.2), Vector2(3.4, -6.2), Vector2(3.0, 1.4),
			Vector2(-6.0, 1.2)], blanket)
	var back_near: Node2D = _pivot(rig, "LegBackNearP", Vector2(-5.8, 1.2), 0.10)
	back_near.name = "LegBackNear"
	_horse_leg_shape(back_near, coat)
	var front_near: Node2D = _pivot(rig, "LegFrontNearP", Vector2(5.6, 1.2), -0.10)
	front_near.name = "LegFrontNear"
	_horse_leg_shape(front_near, coat)

static func _horse_leg_shape(leg: Node2D, coat: Color) -> void:
	_poly(leg, "Limb", [Vector2(-1.5, -0.6), Vector2(1.5, -0.6), Vector2(1.1, 4.6),
		Vector2(1.3, 8.8), Vector2(-0.9, 8.8), Vector2(-1.1, 4.6)], coat)
	_poly(leg, "Hoof", [Vector2(-1.0, 8.4), Vector2(1.4, 8.4), Vector2(1.5, 10.2),
		Vector2(-1.1, 10.2)], HORSE_DARK)

## The rider: a compact humanoid pivot seated at the withers. Returns the
## Rider node; callers add headgear/weapons onto its named parts.
static func _rider(rig: Node2D, cloth: Color, cloth_shade: Color, skin: Color,
		hair_style: String) -> Node2D:
	var rider: Node2D = _pivot(rig, "Rider", Vector2(-1.5, -6.0))
	_poly(rider, "RiderArmBack", [Vector2(-2.4, -8.0), Vector2(-0.6, -8.4), Vector2(1.8, -4.2),
		Vector2(0.4, -3.2)], _dim(skin, 0.8))
	_poly(rider, "RiderTorso", [Vector2(-3.0, 0.4), Vector2(-2.4, -8.6), Vector2(2.4, -8.6),
		Vector2(3.0, 0.4)], cloth)
	_poly(rider, "RiderTorsoShade", [Vector2(-3.0, 0.4), Vector2(-2.4, -8.6),
		Vector2(-0.9, -8.6), Vector2(-1.2, 0.4)], cloth_shade)
	var leg: Node2D = _pivot(rider, "RiderLeg", Vector2(0.6, -0.6))
	_poly(leg, "Thigh", [Vector2(-1.6, -0.4), Vector2(1.6, 0.2), Vector2(2.6, 4.4),
		Vector2(0.8, 5.0), Vector2(-0.8, 4.2)], skin)
	_poly(leg, "RiderFoot", [Vector2(0.6, 4.4), Vector2(3.2, 4.8), Vector2(3.2, 6.2),
		Vector2(0.8, 6.0)], LEATHER_DARK)
	var head: Node2D = _head(rider, skin, HAIR, hair_style)
	head.position = Vector2(0.0, -8.8)
	head.set_meta(META_BASE_POS, head.position)
	head.scale = Vector2(0.92, 0.92)
	var arm: Node2D = _pivot(rider, "ArmFront", Vector2(1.6, -7.6), -0.5)
	_poly(arm, "Limb", [Vector2(-1.1, -0.5), Vector2(1.1, -0.5), Vector2(1.5, 3.0),
		Vector2(2.3, 6.0), Vector2(0.8, 6.8), Vector2(-0.3, 3.0)], skin)
	_poly(arm, "Hand", _ellipse_pts(1.5, 6.3, 1.1, 1.1, 8), skin)
	return rider

## Scout — barefoot rider on a small dun island horse, almost bareback: a
## goat-hide pad, tamarco in team cloth, a light javelin over the shoulder.
static func _scout(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash", 3.0)
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "rider")
	var rig: Node2D = f["rig"] as Node2D
	rig.scale = Vector2(0.92, 0.92)
	_horse(rig, HORSE_DUN, _dim(JUNCO, 0.9))
	var rider: Node2D = _rider(rig, _cloth(team, 0.60), _cloth(team, 0.44), SKIN,
		"long" if female else "curly")
	var arm: Node2D = rider.get_node("ArmFront") as Node2D
	var jav: Node2D = _pivot(arm, "Weapon", Vector2(1.5, 6.3), 0.9)
	_poly(jav, "Shaft", [Vector2(-0.45, 9.0), Vector2(0.45, 9.0), Vector2(0.45, -11.0),
		Vector2(-0.45, -11.0)], PINE_PALE)
	_poly(jav, "Tip", [Vector2(-0.45, -10.4), Vector2(0.45, -10.4), Vector2(0.0, -13.6)],
		FIRE_HARDENED)
	return rbody

## Heavy Scout — the same island horse now padded in leather barding straps,
## team blanket, rider in hardened leather with the banot lowered.
static func _heavy_scout(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash", 3.0)
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "rider")
	var rig: Node2D = f["rig"] as Node2D
	_horse(rig, HORSE_DUN, _cloth(team, 0.55))
	_poly(rig, "ChestStrap", [Vector2(9.6, -5.2), Vector2(11.8, -2.6), Vector2(10.4, -0.8),
		Vector2(8.4, -4.0)], LEATHER_DARK)
	_poly(rig, "RumpStrap", [Vector2(-11.2, -4.6), Vector2(-9.4, -5.8), Vector2(-8.8, 2.4),
		Vector2(-10.6, 2.2)], LEATHER_DARK)
	var rider: Node2D = _rider(rig, _cloth(team, 0.60), _cloth(team, 0.44), SKIN,
		"long" if female else "curly")
	_poly(rider, "RiderCuirass", [Vector2(-2.8, -8.4), Vector2(2.8, -8.4), Vector2(2.5, -3.2),
		Vector2(-2.5, -3.2)], LEATHER)
	var head: Node2D = rider.get_node("Head") as Node2D
	_poly(head, "Cap", [Vector2(-3.5, -4.4), Vector2(-3.3, -6.5), Vector2(-1.7, -7.8),
		Vector2(1.3, -7.9), Vector2(3.1, -6.7), Vector2(3.4, -4.4), Vector2(2.3, -5.3),
		Vector2(-0.2, -5.9), Vector2(-2.3, -5.3)], _dim(LEATHER, 1.25))
	_reorder(rider, ["RiderArmBack", "RiderTorso", "RiderTorsoShade", "RiderCuirass",
		"RiderLeg", "Head", "ArmFront"])
	var arm: Node2D = rider.get_node("ArmFront") as Node2D
	var spear: Node2D = _pivot(arm, "Weapon", Vector2(1.5, 6.3), 1.15)
	_poly(spear, "Shaft", [Vector2(-0.5, 10.0), Vector2(0.5, 10.0), Vector2(0.5, -13.0),
		Vector2(-0.5, -13.0)], PINE_PALE)
	_poly(spear, "Tip", [Vector2(-0.5, -12.2), Vector2(0.5, -12.2), Vector2(0.0, -16.0)],
		FIRE_HARDENED)
	return rbody

## Knight — Castilian heavy cavalry: full caparison in team colour, chanfron
## on the horse's head, steel-armoured rider, great helm, couched lance.
static func _knight(team: Color) -> Node2D:
	var f: Dictionary = _humanoid_frame("lance", 2.8)
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "rider")
	var rig: Node2D = f["rig"] as Node2D
	rig.scale = Vector2(1.06, 1.06)
	_horse(rig, _dim(HORSE_DUN, 0.9), Color(0, 0, 0, 0), true, team)
	var rider: Node2D = _rider(rig, STEEL, STEEL_DARK, STEEL, "bald")
	# Steel boots + gauntlet over the skin parts.
	(rider.get_node("RiderLeg/Thigh") as Polygon2D).color = STEEL_DARK
	(rider.get_node("ArmFront/Limb") as Polygon2D).color = STEEL
	(rider.get_node("ArmFront/Hand") as Polygon2D).color = STEEL_DARK
	var head: Node2D = rider.get_node("Head") as Node2D
	(head.get_node("Skull") as Polygon2D).color = STEEL
	(head.get_node("Neck") as Polygon2D).color = STEEL_DARK
	head.get_node("Eye").queue_free()
	# Great helm: flat-topped, view slit, team plume.
	_poly(head, "Helm", [Vector2(-3.4, -7.6), Vector2(3.2, -7.6), Vector2(3.4, -0.6),
		Vector2(-3.6, -0.6)], STEEL)
	_poly(head, "HelmShade", [Vector2(-3.4, -7.6), Vector2(-1.6, -7.6), Vector2(-1.7, -0.6),
		Vector2(-3.6, -0.6)], STEEL_DARK)
	_poly(head, "Visor", [Vector2(0.6, -4.6), Vector2(3.3, -4.6), Vector2(3.3, -3.4),
		Vector2(0.6, -3.4)], Color(0.12, 0.12, 0.16))
	_poly(head, "Plume", [Vector2(-1.4, -7.2), Vector2(1.2, -7.2), Vector2(0.0, -12.4),
		Vector2(-2.6, -13.0), Vector2(-4.6, -11.2), Vector2(-2.6, -11.0)], _cloth(team, 0.66))
	# Couched lance under the arm, pointing forward past the horse's head.
	var arm: Node2D = rider.get_node("ArmFront") as Node2D
	arm.rotation = -1.05
	arm.set_meta(META_BASE_ROT, -1.05)
	var lance: Node2D = _pivot(arm, "Weapon", Vector2(1.5, 6.3), 1.62)
	_poly(lance, "Shaft", [Vector2(-0.7, 6.0), Vector2(0.7, 6.0), Vector2(0.55, -19.0),
		Vector2(-0.55, -19.0)], WOOD)
	_poly(lance, "LanceTip", [Vector2(-0.55, -18.4), Vector2(0.55, -18.4), Vector2(0.0, -22.4)],
		STEEL)
	_poly(lance, "Vamplate", _ellipse_pts(0.0, 4.4, 1.2, 1.4, 8), STEEL_DARK)
	return rbody

## Presa Canario — broad-chested brindle guard dog, short folded ears, dark
## mask, team collar.
static func _presa_canario(team: Color) -> Node2D:
	var f: Dictionary = _humanoid_frame("bite", 3.4)
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "dog")
	var rig: Node2D = f["rig"] as Node2D
	var tail: Node2D = _pivot(rig, "Tail", Vector2(-7.0, -3.6))
	_poly(tail, "TailTip", [Vector2(0.6, -0.6), Vector2(-2.8, -2.6), Vector2(-3.8, -1.4),
		Vector2(-0.4, 1.0)], DOG_DARK)
	_dog_leg(rig, "LegBackFar", Vector2(-4.8, 0.6), _dim(DOG_COAT, 0.78))
	_dog_leg(rig, "LegFrontFar", Vector2(4.6, 0.6), _dim(DOG_COAT, 0.78))
	_poly(rig, "DogBody", [Vector2(-7.2, -1.4), Vector2(-6.2, -3.8), Vector2(-2.0, -5.0),
		Vector2(3.0, -5.2), Vector2(6.6, -4.2), Vector2(7.6, -1.4), Vector2(6.8, 1.4),
		Vector2(2.0, 2.4), Vector2(-3.0, 2.2), Vector2(-6.6, 1.0)], DOG_COAT)
	_poly(rig, "Brindle1", [Vector2(-4.6, -4.4), Vector2(-3.2, -4.8), Vector2(-4.0, 1.8),
		Vector2(-5.2, 1.4)], DOG_DARK)
	_poly(rig, "Brindle2", [Vector2(-0.4, -5.0), Vector2(1.0, -5.1), Vector2(0.2, 2.3),
		Vector2(-1.2, 2.3)], DOG_DARK)
	_poly(rig, "Brindle3", [Vector2(3.4, -5.0), Vector2(4.6, -4.7), Vector2(4.4, 2.0),
		Vector2(3.2, 2.2)], DOG_DARK)
	_poly(rig, "ChestPatch", [Vector2(5.4, -1.0), Vector2(7.4, -1.2), Vector2(6.8, 1.5),
		Vector2(4.8, 2.1)], Color(0.66, 0.55, 0.42))
	var head: Node2D = _pivot(rig, "Head", Vector2(6.8, -4.2))
	_poly(head, "Skull", [Vector2(-1.8, -2.4), Vector2(1.6, -3.0), Vector2(3.4, -1.8),
		Vector2(3.8, 0.2), Vector2(2.6, 1.6), Vector2(-0.4, 2.0), Vector2(-2.0, 0.8)], DOG_COAT)
	_poly(head, "Mask", [Vector2(1.6, -1.6), Vector2(3.4, -1.8), Vector2(3.8, 0.2),
		Vector2(5.6, 0.4), Vector2(5.7, 1.8), Vector2(2.6, 1.7), Vector2(1.2, 0.6)],
		Color(0.20, 0.15, 0.10))
	_poly(head, "Nose", _ellipse_pts(5.3, 0.9, 0.7, 0.6, 6), Color(0.08, 0.06, 0.05))
	_poly(head, "DogEye", _ellipse_pts(1.6, -0.8, 0.5, 0.55, 6), Color(0.10, 0.08, 0.06))
	_poly(head, "EarFold", [Vector2(-1.4, -2.4), Vector2(-0.2, -3.9), Vector2(1.0, -2.6),
		Vector2(-0.2, -1.8)], DOG_DARK)
	_poly(rig, "Collar", [Vector2(3.8, -5.0), Vector2(6.0, -3.8), Vector2(5.2, -1.2),
		Vector2(3.0, -2.4)], _cloth(team, 0.66))
	_dog_leg(rig, "LegBackNear", Vector2(-3.6, 0.8), DOG_COAT)
	_dog_leg(rig, "LegFrontNear", Vector2(5.4, 0.8), DOG_COAT)
	_reorder(rig, ["Tail", "LegBackFar", "LegFrontFar", "DogBody", "Brindle1", "Brindle2",
		"Brindle3", "ChestPatch", "Head", "Collar", "LegBackNear", "LegFrontNear"])
	return rbody

static func _dog_leg(rig: Node2D, leg_name: String, pos: Vector2, coat: Color) -> void:
	var leg: Node2D = _pivot(rig, leg_name, pos)
	_poly(leg, "Limb", [Vector2(-1.2, -0.4), Vector2(1.2, -0.4), Vector2(0.9, 3.4),
		Vector2(1.1, 6.6), Vector2(-0.7, 6.6), Vector2(-0.9, 3.4)], coat)
	_poly(leg, "Paw", [Vector2(-0.8, 6.0), Vector2(1.7, 6.2), Vector2(1.7, 7.4),
		Vector2(-0.8, 7.4)], _dim(coat, 0.7))

# ── Batch C: siege — tea-pine timber, junco rope, volcanic stone ammo ───────

const TEA: Color = Color(0.55, 0.38, 0.20)
const TEA_DARK: Color = Color(0.42, 0.28, 0.14)
const ROPE: Color = Color(0.74, 0.66, 0.40)

static func _siege_frame(kind: String) -> Dictionary:
	var f: Dictionary = _humanoid_frame("none")
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "siege")
	rbody.set_meta(&"siege_kind", kind)
	return f

## Small owner pennant (redesigned siege/ships hide the classic Body, where
## the default pennant lives).
static func _team_pennant(rig: Node2D, team: Color, top: Vector2, pole_h: float = 7.0) -> void:
	var pen: Node2D = _pivot(rig, "Pennant", top)
	_poly(pen, "Pole", [Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, -pole_h),
		Vector2(-0.5, -pole_h)], TEA_DARK)
	_poly(pen, "Flag", [Vector2(0.5, -pole_h), Vector2(7.0, -pole_h + 1.6),
		Vector2(0.5, -pole_h + 3.4)], team)

static func _wheel(rig: Node2D, wheel_name: String, pos: Vector2, r: float, dark: bool) -> void:
	var wheel: Node2D = _pivot(rig, wheel_name, pos)
	var col: Color = TEA_DARK if dark else TEA
	_poly(wheel, "Disc", _ellipse_pts(0.0, 0.0, r, r, 12), col)
	_poly(wheel, "Hub", _ellipse_pts(0.0, 0.0, r * 0.32, r * 0.32, 8), _dim(col, 0.7))
	_poly(wheel, "Spoke", [Vector2(-r * 0.25, -r * 0.9), Vector2(r * 0.25, -r * 0.9),
		Vector2(r * 0.2, r * 0.9), Vector2(-r * 0.2, r * 0.9)], _dim(col, 1.3))

## Battering Ram — hide-roofed shed on four wheels, a carved log swinging
## below the ridge, junco lashings.
static func _battering_ram(team: Color) -> Node2D:
	var f: Dictionary = _siege_frame("ram")
	var rig: Node2D = f["rig"] as Node2D
	_wheel(rig, "WheelBackFar", Vector2(-8.5, 6.4), 2.6, true)
	_wheel(rig, "WheelFrontFar", Vector2(8.5, 6.4), 2.6, true)
	# The log, pivoted at the roof ridge so it pendulums.
	var log_arm: Node2D = _pivot(rig, "RamLog", Vector2(0.0, -6.0))
	_poly(log_arm, "Log", [Vector2(-13.0, 8.2), Vector2(15.4, 8.2), Vector2(15.4, 11.0),
		Vector2(-13.0, 11.0)], WOOD)
	_poly(log_arm, "LogHead", [Vector2(15.0, 7.6), Vector2(18.2, 8.8), Vector2(18.2, 10.4),
		Vector2(15.0, 11.6)], BASALT)
	_poly(log_arm, "RopeF", [Vector2(6.0, 0.0), Vector2(7.0, 0.0), Vector2(7.6, 8.4),
		Vector2(6.6, 8.4)], ROPE)
	_poly(log_arm, "RopeB", [Vector2(-6.6, 0.0), Vector2(-5.6, 0.0), Vector2(-6.2, 8.4),
		Vector2(-7.2, 8.4)], ROPE)
	# Shed: side wall + solid gabled hide roof (the log head pokes out front).
	_poly(rig, "Wall", [Vector2(-11.4, 2.6), Vector2(11.4, 2.6), Vector2(11.4, 5.4),
		Vector2(-11.4, 5.4)], TEA_DARK)
	_poly(rig, "Roof", [Vector2(-13.4, 3.0), Vector2(-11.8, -3.4), Vector2(0.0, -7.2),
		Vector2(11.8, -3.4), Vector2(13.4, 3.0)], _dim(LEATHER, 1.08))
	_poly(rig, "RoofShade", [Vector2(-13.4, 3.0), Vector2(-11.8, -3.4), Vector2(0.0, -7.2),
		Vector2(0.0, -4.4), Vector2(-10.4, 3.0)], _dim(LEATHER, 0.88))
	_poly(rig, "RoofRidge", [Vector2(-12.2, -3.0), Vector2(0.0, -7.4), Vector2(12.2, -3.0),
		Vector2(11.6, -1.9), Vector2(0.0, -6.1), Vector2(-11.6, -1.9)], TEA_DARK)
	_poly(rig, "RoofSeam", [Vector2(-4.6, 2.9), Vector2(-3.6, -5.4), Vector2(-2.6, -5.7),
		Vector2(-3.6, 2.9)], _dim(LEATHER, 0.8))
	_poly(rig, "RoofSeam2", [Vector2(4.6, 2.9), Vector2(3.6, -5.4), Vector2(4.6, -5.1),
		Vector2(5.6, 2.9)], _dim(LEATHER, 0.8))
	_wheel(rig, "WheelBackNear", Vector2(-8.0, 7.2), 3.0, false)
	_wheel(rig, "WheelFrontNear", Vector2(8.0, 7.2), 3.0, false)
	_team_pennant(rig, team, Vector2(-1.0, -7.0), 6.0)
	_reorder(rig, ["WheelBackFar", "WheelFrontFar", "RamLog", "Wall", "Roof", "RoofShade",
		"RoofRidge", "RoofSeam", "RoofSeam2", "WheelBackNear", "WheelFrontNear", "Pennant"])
	return f["rbody"] as Node2D

## Mangonel — torsion catapult: wheeled platform, throwing arm with a spoon
## cup of volcanic stone, rope torsion bundle.
static func _mangonel(team: Color) -> Node2D:
	var f: Dictionary = _siege_frame("mangonel")
	var rig: Node2D = f["rig"] as Node2D
	_wheel(rig, "WheelFar", Vector2(-6.5, 6.6), 2.8, true)
	_wheel(rig, "WheelFrontFar", Vector2(7.0, 6.6), 2.8, true)
	# Throwing arm: pivot low on the frame; at rest cocked back ~45 degrees.
	var arm: Node2D = _pivot(rig, "ThrowArm", Vector2(1.0, 3.0), -0.85)
	_poly(arm, "Spar", [Vector2(-1.1, 0.8), Vector2(1.1, 0.8), Vector2(0.8, -14.6),
		Vector2(-0.8, -14.6)], TEA)
	_poly(arm, "Spoon", [Vector2(-2.2, -17.6), Vector2(2.2, -17.6), Vector2(1.5, -13.8),
		Vector2(-1.5, -13.8)], TEA_DARK)
	var stone: Polygon2D = _poly(arm, "Stone", _ellipse_pts(0.0, -16.4, 1.8, 1.7, 8), BASALT)
	stone.visible = true
	# Frame: base beams, torsion crossbar with rope bundles.
	_poly(rig, "Base", [Vector2(-9.4, 3.4), Vector2(9.4, 3.4), Vector2(10.4, 6.2),
		Vector2(-10.4, 6.2)], TEA)
	_poly(rig, "BaseShade", [Vector2(-9.4, 3.4), Vector2(-3.0, 3.4), Vector2(-3.4, 6.2),
		Vector2(-10.4, 6.2)], TEA_DARK)
	_poly(rig, "UprightF", [Vector2(4.4, 3.6), Vector2(6.6, 3.6), Vector2(3.4, -4.6),
		Vector2(1.8, -4.6)], TEA_DARK)
	_poly(rig, "Crossbar", [Vector2(-1.0, -5.4), Vector2(4.0, -5.4), Vector2(4.0, -3.4),
		Vector2(-1.0, -3.4)], TEA)
	_poly(rig, "RopeBundle", _ellipse_pts(1.2, 2.2, 2.2, 1.6, 8), ROPE)
	_wheel(rig, "WheelNear", Vector2(-6.0, 7.4), 3.2, false)
	_wheel(rig, "WheelFrontNear", Vector2(7.5, 7.4), 3.2, false)
	_team_pennant(rig, team, Vector2(-8.6, 2.8), 6.0)
	_reorder(rig, ["WheelFar", "WheelFrontFar", "ThrowArm", "Base", "BaseShade", "UprightF",
		"Crossbar", "RopeBundle", "WheelNear", "WheelFrontNear", "Pennant"])
	return f["rbody"] as Node2D

## Trebuchet — tall A-frame with a counterweighted beam and sling. Packed for
## travel (beam flat, on wheels) until the unit deploys; the animator reads
## `is_deployed` live.
static func _trebuchet(team: Color) -> Node2D:
	var f: Dictionary = _siege_frame("trebuchet")
	var rig: Node2D = f["rig"] as Node2D
	_wheel(rig, "WheelFar", Vector2(-7.5, 7.0), 2.6, true)
	_wheel(rig, "WheelFrontFar", Vector2(7.5, 7.0), 2.6, true)
	# Beam pivots at the frame apex: long throwing arm one way, the
	# counterweight box on the short end.
	var beam: Node2D = _pivot(rig, "Beam", Vector2(0.0, -8.0), TREB_COCKED)
	_poly(beam, "Spar", [Vector2(-1.0, 6.4), Vector2(1.0, 6.4), Vector2(0.75, -19.0),
		Vector2(-0.75, -19.0)], TEA)
	_poly(beam, "Counterweight", [Vector2(-3.4, 5.2), Vector2(3.4, 5.2), Vector2(2.8, 11.0),
		Vector2(-2.8, 11.0)], BASALT)
	_poly(beam, "CwStrap", [Vector2(-1.2, 4.6), Vector2(1.2, 4.6), Vector2(1.0, 6.4),
		Vector2(-1.0, 6.4)], ROPE)
	var sling: Line2D = Line2D.new()
	sling.name = "Sling"
	sling.width = 0.9
	sling.default_color = ROPE
	sling.points = PackedVector2Array([Vector2(0.0, -18.6), Vector2(-2.8, -14.0)])
	beam.add_child(sling)
	var pouch: Polygon2D = _poly(beam, "Pouch", _ellipse_pts(-2.8, -13.2, 1.6, 1.3, 8), LEATHER_DARK)
	pouch.visible = true
	# A-frame + base sled.
	_poly(rig, "FrameFar", [Vector2(-5.6, 6.8), Vector2(-3.6, 6.8), Vector2(0.8, -7.6),
		Vector2(-0.8, -7.6)], TEA_DARK)
	_poly(rig, "FrameNear", [Vector2(5.6, 6.8), Vector2(3.6, 6.8), Vector2(-0.8, -7.6),
		Vector2(0.8, -7.6)], TEA)
	_poly(rig, "FrameBrace", [Vector2(-3.2, 1.4), Vector2(3.2, 1.4), Vector2(2.8, 3.2),
		Vector2(-2.8, 3.2)], TEA_DARK)
	_poly(rig, "Base", [Vector2(-10.0, 6.4), Vector2(10.0, 6.4), Vector2(10.8, 8.6),
		Vector2(-10.8, 8.6)], TEA)
	_wheel(rig, "WheelNear", Vector2(-7.0, 7.8), 3.0, false)
	_wheel(rig, "WheelFrontNear", Vector2(7.0, 7.8), 3.0, false)
	_team_pennant(rig, team, Vector2(9.2, 6.2), 7.0)
	_reorder(rig, ["WheelFar", "WheelFrontFar", "Beam", "FrameFar", "FrameNear",
		"FrameBrace", "Base", "WheelNear", "WheelFrontNear", "Pennant"])
	return f["rbody"] as Node2D

# ── Batch D: ships — side-profile hulls in the civ's naval palette ──────────
# Waterline at y=+5; bows face +x. Owner reads from the mast pennant.

static func _naval_style(civ_id: String) -> Dictionary:
	return CivStyle.NAVAL.get(civ_id, CivStyle.DEFAULT_NAVAL) as Dictionary

static func _ship_frame(kind: String) -> Dictionary:
	var f: Dictionary = _humanoid_frame("none")
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "ship")
	rbody.set_meta(&"ship_kind", kind)
	return f

## Fishing boat — small lateen-rigged skiff: curved hull, slanted yard with a
## triangular sail, a net roll and its lone fisher at the stern.
static func _fishing_boat(team: Color, civ_id: String) -> Node2D:
	var f: Dictionary = _ship_frame("fisher")
	var rig: Node2D = f["rig"] as Node2D
	var ns: Dictionary = _naval_style(civ_id)
	var hull: Color = ns["hull"] as Color
	var deck: Color = ns["deck"] as Color
	var sail: Color = ns["sail"] as Color
	# Mast + lateen yard behind the hull side.
	_poly(rig, "Mast", [Vector2(0.4, -2.0), Vector2(1.8, -2.0), Vector2(2.6, -14.5),
		Vector2(1.2, -14.5)], _dim(hull, 1.2))
	_poly(rig, "Yard", [Vector2(-7.8, -5.6), Vector2(-6.8, -6.8), Vector2(9.8, -18.2),
		Vector2(8.8, -19.0)], _dim(hull, 1.35))
	_poly(rig, "Sail", [Vector2(-6.6, -6.6), Vector2(9.0, -17.8), Vector2(1.8, -3.6)], sail)
	_poly(rig, "SailShade", [Vector2(-6.6, -6.6), Vector2(-0.4, -11.1), Vector2(0.4, -3.9),
		Vector2(1.8, -3.6)], _dim(sail, 0.86))
	# Hull profile with sheer line.
	_poly(rig, "Hull", [Vector2(-11.0, -3.6), Vector2(-9.2, 2.4), Vector2(-4.0, 4.8),
		Vector2(4.0, 4.8), Vector2(9.0, 2.4), Vector2(11.4, -4.4), Vector2(8.6, -1.8),
		Vector2(-8.4, -1.8)], hull)
	_poly(rig, "Gunwale", [Vector2(-11.0, -3.6), Vector2(-8.4, -1.8), Vector2(8.6, -1.8),
		Vector2(11.4, -4.4), Vector2(9.4, -3.4), Vector2(8.2, -0.9), Vector2(-8.0, -0.9),
		Vector2(-9.6, -2.8)], deck)
	_poly(rig, "HullShade", [Vector2(-9.2, 2.4), Vector2(-4.0, 4.8), Vector2(4.0, 4.8),
		Vector2(9.0, 2.4), Vector2(7.0, 3.6), Vector2(-6.4, 3.6)], _dim(hull, 0.78))
	# Net roll + the fisher.
	_poly(rig, "Net", _ellipse_pts(-6.6, -3.2, 2.4, 1.5, 8), _dim(JUNCO, 0.9))
	_poly(rig, "NetLine", [Vector2(-8.6, -3.0), Vector2(-4.6, -3.6), Vector2(-4.6, -2.8),
		Vector2(-8.6, -2.2)], _dim(JUNCO, 0.66))
	_poly(rig, "FisherBody", [Vector2(3.2, -2.0), Vector2(6.0, -2.0), Vector2(5.6, -6.8),
		Vector2(3.6, -6.8)], _cloth(team, 0.55))
	_poly(rig, "FisherHead", _ellipse_pts(4.7, -8.4, 1.7, 1.9, 8), SKIN)
	_team_pennant(rig, team, Vector2(2.0, -14.0), 3.5)
	_reorder(rig, ["Yard", "Sail", "SailShade", "Mast", "Net", "NetLine", "FisherBody",
		"FisherHead", "Hull", "Gunwale", "HullShade", "Pennant"])
	return f["rbody"] as Node2D

## Transport — round-bellied cog: tall freeboard, cargo on deck, furled sail.
static func _transport_ship(team: Color, civ_id: String) -> Node2D:
	var f: Dictionary = _ship_frame("transport")
	var rig: Node2D = f["rig"] as Node2D
	var ns: Dictionary = _naval_style(civ_id)
	var hull: Color = ns["hull"] as Color
	var deck: Color = ns["deck"] as Color
	var sail: Color = ns["sail"] as Color
	_poly(rig, "Mast", [Vector2(-0.8, -6.0), Vector2(0.8, -6.0), Vector2(0.8, -21.0),
		Vector2(-0.8, -21.0)], _dim(hull, 1.2))
	_poly(rig, "YardArm", [Vector2(-7.4, -19.6), Vector2(7.4, -19.6), Vector2(7.4, -18.4),
		Vector2(-7.4, -18.4)], _dim(hull, 1.35))
	_poly(rig, "FurledSail", [Vector2(-7.0, -18.4), Vector2(7.0, -18.4), Vector2(6.2, -15.8),
		Vector2(-6.2, -15.8)], sail)
	# Cargo above the bulwark.
	_poly(rig, "Crate1", [Vector2(-7.6, -6.2), Vector2(-3.4, -6.2), Vector2(-3.4, -10.2),
		Vector2(-7.6, -10.2)], WOOD)
	_poly(rig, "Crate1Lid", [Vector2(-7.6, -10.2), Vector2(-3.4, -10.2), Vector2(-3.8, -11.2),
		Vector2(-7.2, -11.2)], WOOD_DARK)
	_poly(rig, "Amphora", _ellipse_pts(3.8, -8.2, 1.9, 2.7, 10), Color(0.62, 0.34, 0.20))
	_poly(rig, "AmphoraNeck", [Vector2(3.0, -10.6), Vector2(4.6, -10.6), Vector2(4.3, -12.0),
		Vector2(3.3, -12.0)], Color(0.52, 0.28, 0.16))
	# Fat hull: tall sides, rounded belly.
	_poly(rig, "Hull", [Vector2(-12.6, -7.0), Vector2(-11.0, 1.6), Vector2(-5.0, 5.2),
		Vector2(5.0, 5.2), Vector2(11.0, 1.6), Vector2(13.0, -7.6), Vector2(9.6, -5.6),
		Vector2(-9.4, -5.6)], hull)
	_poly(rig, "Bulwark", [Vector2(-12.6, -7.0), Vector2(-9.4, -5.6), Vector2(9.6, -5.6),
		Vector2(13.0, -7.6), Vector2(10.6, -6.9), Vector2(9.0, -4.4), Vector2(-8.8, -4.4),
		Vector2(-10.8, -6.2)], deck)
	_poly(rig, "HullBand", [Vector2(-10.6, -1.0), Vector2(10.4, -1.0), Vector2(10.7, -2.4),
		Vector2(-10.9, -2.4)], _dim(hull, 1.22))
	_poly(rig, "HullShade", [Vector2(-11.0, 1.6), Vector2(-5.0, 5.2), Vector2(5.0, 5.2),
		Vector2(11.0, 1.6), Vector2(8.0, 4.0), Vector2(-7.6, 4.0)], _dim(hull, 0.78))
	_team_pennant(rig, team, Vector2(0.0, -20.6), 4.0)
	_reorder(rig, ["Mast", "YardArm", "FurledSail", "Crate1", "Crate1Lid", "Amphora",
		"AmphoraNeck", "Hull", "Bulwark", "HullBand", "HullShade", "Pennant"])
	return f["rbody"] as Node2D

## War Galley — long, low and lean: bronze ram at the waterline, banked oars,
## square sail with the civ accent band.
static func _war_galley(team: Color, civ_id: String) -> Node2D:
	var f: Dictionary = _ship_frame("galley")
	var rig: Node2D = f["rig"] as Node2D
	var ns: Dictionary = _naval_style(civ_id)
	var hull: Color = ns["hull"] as Color
	var deck: Color = ns["deck"] as Color
	var sail: Color = ns["sail"] as Color
	var accent: Color = ns["accent"] as Color
	_poly(rig, "Mast", [Vector2(-0.9, -3.0), Vector2(0.9, -3.0), Vector2(0.9, -20.0),
		Vector2(-0.9, -20.0)], _dim(hull, 1.2))
	_poly(rig, "YardArm", [Vector2(-8.4, -19.2), Vector2(8.4, -19.2), Vector2(8.4, -18.0),
		Vector2(-8.4, -18.0)], _dim(hull, 1.35))
	_poly(rig, "Sail", [Vector2(-7.8, -18.2), Vector2(7.8, -18.2), Vector2(6.8, -8.4),
		Vector2(-6.8, -8.4)], sail)
	_poly(rig, "SailBand", [Vector2(-7.4, -14.6), Vector2(7.4, -14.6), Vector2(7.2, -12.4),
		Vector2(-7.2, -12.4)], accent)
	# Oars (three near-side banks, animated while rowing).
	for i: int in range(3):
		var oar: Node2D = _pivot(rig, "Oar%d" % i, Vector2(-8.0 + float(i) * 6.5, 1.5), 0.45)
		_poly(oar, "Shaft", [Vector2(-0.4, -0.5), Vector2(0.4, -0.5), Vector2(1.6, 5.4),
			Vector2(0.8, 5.6)], _dim(hull, 1.3))
		_poly(oar, "Blade", [Vector2(0.9, 5.0), Vector2(2.4, 6.4), Vector2(1.4, 7.4),
			Vector2(0.4, 6.0)], _dim(hull, 1.1))
	# Long low hull with stern volute and waterline ram.
	_poly(rig, "Hull", [Vector2(-16.6, -6.8), Vector2(-15.0, -3.2), Vector2(-14.6, 1.2),
		Vector2(-8.0, 3.8), Vector2(9.0, 3.8), Vector2(15.4, 1.2), Vector2(17.8, -3.6),
		Vector2(13.8, -2.4), Vector2(-12.6, -2.4), Vector2(-15.2, -5.8)], hull)
	_poly(rig, "SternVolute", [Vector2(-16.6, -6.8), Vector2(-15.2, -5.8), Vector2(-14.4, -8.4),
		Vector2(-16.2, -9.0), Vector2(-17.4, -7.8)], _dim(hull, 1.2))
	_poly(rig, "Gunwale", [Vector2(-14.8, -3.0), Vector2(13.9, -3.0), Vector2(14.6, -4.2),
		Vector2(-15.1, -4.2)], deck)
	_poly(rig, "HullShade", [Vector2(-14.6, 1.2), Vector2(-8.0, 3.8), Vector2(9.0, 3.8),
		Vector2(15.4, 1.2), Vector2(11.0, 2.7), Vector2(-10.4, 2.7)], _dim(hull, 0.78))
	_poly(rig, "RamSpur", [Vector2(16.6, -0.6), Vector2(22.6, 1.4), Vector2(21.6, 3.2),
		Vector2(15.6, 1.9)], Color(0.62, 0.46, 0.24))
	if (ns.get("motif", "") as String) == "eye":
		_poly(rig, "Eye", _ellipse_pts(15.2, -1.4, 1.0, 1.0, 8), Color(0.92, 0.90, 0.84))
		_poly(rig, "EyeDot", _ellipse_pts(15.4, -1.4, 0.45, 0.45, 6), Color(0.10, 0.10, 0.12))
	_team_pennant(rig, team, Vector2(0.0, -19.6), 4.0)
	_reorder(rig, ["Mast", "YardArm", "Sail", "SailBand", "Oar0", "Oar1", "Oar2", "Hull",
		"SternVolute", "Gunwale", "HullShade", "RamSpur", "Eye", "EyeDot", "Pennant"])
	return f["rbody"] as Node2D

# ── Batch E: the eight civilization-unique units ────────────────────────────

## Menceyes Guard — the mencey's bodyguard: noble pelts over the tamarco, a
## bone-bead necklace and a carved ceremonial magado with junco lashings.
static func _menceyes_guard(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash")
	var rig: Node2D = f["rig"] as Node2D
	rig.scale = Vector2(1.06, 1.06)
	_arm(rig, "ArmBack", Vector2(-2.4, -10.9), _dim(SKIN, 0.80), _dim(SKIN, 0.80), 0.3)
	_legs(rig, SKIN)
	_tamarco(rig, team, SKIN)
	# Noble pelt across the shoulders (pale goat fur, jagged hem).
	_poly(rig, "Pelt", [Vector2(-4.4, -12.2), Vector2(2.6, -12.2), Vector2(3.4, -9.0),
		Vector2(1.8, -9.8), Vector2(0.2, -8.6), Vector2(-1.6, -9.8), Vector2(-3.2, -8.6),
		Vector2(-4.6, -9.4)], Color(0.85, 0.79, 0.66))
	_poly(rig, "BoneBeads", [Vector2(-1.6, -10.6), Vector2(0.0, -9.0), Vector2(1.6, -10.6),
		Vector2(1.0, -9.2), Vector2(0.0, -8.2), Vector2(-1.0, -9.2)], Color(0.90, 0.87, 0.78))
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "curly")
	_poly(head, "Headband", [Vector2(-3.4, -5.6), Vector2(3.2, -5.6), Vector2(3.1, -4.3),
		Vector2(-3.3, -4.3)], _cloth(team, 0.55))
	_poly(head, "Feather", [Vector2(-3.0, -5.4), Vector2(-4.6, -10.2), Vector2(-3.4, -10.6),
		Vector2(-2.2, -5.6)], Color(0.88, 0.85, 0.78))
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.4, -11.0), SKIN, SKIN, -0.4)
	var club: Node2D = _pivot(arm_front, "Weapon", Vector2(1.7, 7.4), 0.9)
	_poly(club, "Shaft", [Vector2(-0.9, 2.6), Vector2(0.9, 2.6), Vector2(1.3, -9.2),
		Vector2(-1.3, -9.2)], WOOD_DARK)
	_poly(club, "Knob", _ellipse_pts(0.0, -10.6, 2.7, 3.1, 9), WOOD_DARK)
	_poly(club, "Carving1", [Vector2(-1.1, -3.0), Vector2(1.1, -3.0), Vector2(1.05, -1.8),
		Vector2(-1.05, -1.8)], ROPE)
	_poly(club, "Carving2", [Vector2(-1.2, -6.6), Vector2(1.2, -6.6), Vector2(1.15, -5.4),
		Vector2(-1.15, -5.4)], ROPE)
	_poly(club, "KnobLight", _ellipse_pts(0.9, -11.4, 1.0, 1.2, 7), _dim(WOOD, 1.25))
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Chest",
		"Strap", "Belt", "BeltKnot", "Pelt", "BoneBeads", "Head", "ArmFront"])
	return f["rbody"] as Node2D

## Ravine Archer — barranco ambusher: hooded mottled cloak the colour of dry
## rock over the team tunic; only the bow gives them away.
static func _ravine_archer(team: Color) -> Node2D:
	var f: Dictionary = _humanoid_frame("bow", 2.5)
	var rig: Node2D = f["rig"] as Node2D
	var cloak: Color = Color(0.47, 0.40, 0.29)
	var arm_back: Node2D = _arm(rig, "ArmBack", Vector2(-2.3, -10.9), _dim(cloak, 0.9),
		_dim(SKIN, 0.80), -0.5)
	arm_back.name = "DrawArm"
	arm_back.set_meta(META_BASE_ROT, -0.5)
	_legs(rig, SKIN)
	_tunic(rig, team, 2.4)
	# The manto: a mottled cloak falling from the shoulders down the back.
	_poly(rig, "Cloak", [Vector2(-4.0, -12.6), Vector2(1.6, -12.6), Vector2(2.6, -8.0),
		Vector2(1.4, -1.0), Vector2(2.2, 4.4), Vector2(-1.4, 5.4), Vector2(-5.0, 4.2),
		Vector2(-4.4, -3.0)], cloak)
	_poly(rig, "CloakMottle1", _ellipse_pts(-2.6, -6.0, 1.3, 1.8, 7), _dim(cloak, 0.82))
	_poly(rig, "CloakMottle2", _ellipse_pts(-0.6, 1.4, 1.5, 1.9, 7), _dim(cloak, 0.85))
	_poly(rig, "CloakMottle3", _ellipse_pts(-3.4, 2.6, 1.1, 1.4, 7), _dim(cloak, 1.14))
	var head: Node2D = _head(rig, SKIN, HAIR, "bald")
	# Deep hood shadowing the face.
	_poly(head, "HoodShadow", [Vector2(-2.2, -5.6), Vector2(2.6, -5.4), Vector2(2.4, -3.6),
		Vector2(-2.0, -3.8)], _dim(SKIN, 0.62))
	_poly(head, "Hood", [Vector2(-3.8, 0.6), Vector2(-4.2, -5.2), Vector2(-2.4, -7.8),
		Vector2(1.2, -8.2), Vector2(3.4, -6.4), Vector2(3.0, -4.6), Vector2(1.4, -6.2),
		Vector2(-1.2, -6.4), Vector2(-2.4, -4.4), Vector2(-2.2, 0.8)], _dim(cloak, 0.78))
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.3, -11.0), _dim(cloak, 1.05),
		SKIN, -0.55)
	_build_bow(arm_front, 10.4, WOOD_DARK)
	_reorder(rig, ["Cloak", "CloakMottle1", "CloakMottle2", "CloakMottle3", "DrawArm",
		"LegBack", "LegFront", "Tunic", "TunicShade", "Belt", "Head", "ArmFront"])
	return f["rbody"] as Node2D

## Shared bow build (archer variants): half_len sets the size.
static func _build_bow(arm_front: Node2D, half_len: float, wood: Color) -> void:
	var s: float = half_len / 10.4
	var bow: Node2D = _pivot(arm_front, "Weapon", Vector2(1.7, 7.4), 0.5)
	bow.scale = Vector2(s, s)
	_poly(bow, "Stave", [Vector2(-0.8, -10.4), Vector2(0.7, -10.8), Vector2(2.6, -6.2),
		Vector2(3.3, 0.0), Vector2(2.6, 6.2), Vector2(0.7, 10.8), Vector2(-0.8, 10.4),
		Vector2(1.2, 5.6), Vector2(1.8, 0.0), Vector2(1.2, -5.6)], wood)
	var string: Line2D = Line2D.new()
	string.name = "BowString"
	string.width = 0.8
	string.default_color = Color(0.88, 0.85, 0.74)
	string.points = PackedVector2Array([Vector2(-0.5, -10.4), Vector2(-0.6, 0.0),
		Vector2(-0.5, 10.4)])
	bow.add_child(string)
	var arrow: Polygon2D = _poly(bow, "Arrow", [Vector2(0.4, -0.4), Vector2(-9.6, -0.4),
		Vector2(-9.6, 0.4), Vector2(0.4, 0.4)], WOOD_DARK)
	_poly(arrow, "ArrowTip", [Vector2(2.2, 0.0), Vector2(0.2, -0.9), Vector2(0.2, 0.9)], BASALT)
	arrow.visible = false

## Sand Raider — maho rider wrapped head to toe against the sand: pale head
## wrap and veil, flowing team robes, a javelin ready to throw.
static func _sand_raider(team: Color) -> Node2D:
	var f: Dictionary = _humanoid_frame("slash", 3.2)
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "rider")
	var rig: Node2D = f["rig"] as Node2D
	rig.scale = Vector2(0.96, 0.96)
	_horse(rig, _dim(HORSE_DUN, 1.08), _cloth(team, 0.50))
	var wrap: Color = Color(0.90, 0.86, 0.74)
	var rider: Node2D = _rider(rig, _cloth(team, 0.62), _cloth(team, 0.46), SKIN, "bald")
	# Flowing robe tail behind the rider.
	_poly(rider, "RobeTail", [Vector2(-2.6, -7.6), Vector2(-5.8, -4.2), Vector2(-6.6, 0.8),
		Vector2(-3.0, -0.6)], _cloth(team, 0.52))
	rider.move_child(rider.get_node("RobeTail"), 0)
	var head: Node2D = rider.get_node("Head") as Node2D
	# Head wrap + face veil: only the eye shows.
	_poly(head, "Wrap", [Vector2(-3.4, -1.6), Vector2(-3.6, -5.4), Vector2(-1.8, -7.4),
		Vector2(1.4, -7.5), Vector2(3.2, -5.6), Vector2(3.3, -1.8), Vector2(2.6, -4.6),
		Vector2(0.0, -5.8), Vector2(-2.4, -4.6)], wrap)
	_poly(head, "Veil", [Vector2(-0.4, -2.6), Vector2(3.3, -2.4), Vector2(3.0, 1.2),
		Vector2(-0.6, 0.8)], _dim(wrap, 0.92))
	var arm: Node2D = rider.get_node("ArmFront") as Node2D
	arm.rotation = -1.35
	arm.set_meta(META_BASE_ROT, -1.35)
	var jav: Node2D = _pivot(arm, "Weapon", Vector2(1.5, 6.3), 1.62)
	_poly(jav, "Shaft", [Vector2(-0.45, 8.0), Vector2(0.45, 8.0), Vector2(0.45, -10.0),
		Vector2(-0.45, -10.0)], PINE_PALE)
	_poly(jav, "Tip", [Vector2(-0.45, -9.4), Vector2(0.45, -9.4), Vector2(0.0, -12.6)],
		FIRE_HARDENED)
	return rbody

## Chevalier Normand — Frankish knight: mail hauberk, conical nasal helm,
## kite shield and a lance flying the team pennon.
static func _chevalier_normand(team: Color) -> Node2D:
	var f: Dictionary = _humanoid_frame("lance", 2.8)
	var rbody: Node2D = f["rbody"] as Node2D
	rbody.set_meta(META_RIG, "rider")
	var rig: Node2D = f["rig"] as Node2D
	rig.scale = Vector2(1.04, 1.04)
	var mail: Color = Color(0.60, 0.62, 0.68)
	_horse(rig, Color(0.36, 0.28, 0.22), _cloth(team, 0.55))
	var rider: Node2D = _rider(rig, mail, _dim(mail, 0.8), mail, "bald")
	# Kite shield on the near side, over the rider's leg.
	var shield: Node2D = _pivot(rider, "Shield", Vector2(2.6, -2.6), 0.12)
	_poly(shield, "Face", [Vector2(-2.4, -3.2), Vector2(2.4, -3.2), Vector2(2.0, 1.6),
		Vector2(0.0, 5.4), Vector2(-2.0, 1.6)], _cloth(team, 0.60))
	_poly(shield, "Rim", [Vector2(-2.4, -3.2), Vector2(2.4, -3.2), Vector2(2.2, -2.4),
		Vector2(-2.2, -2.4)], STEEL_DARK)
	_poly(shield, "Cross", [Vector2(-0.5, -2.8), Vector2(0.5, -2.8), Vector2(0.5, 4.0),
		Vector2(-0.5, 4.0)], _dim(Color(0.92, 0.90, 0.84), 1.0))
	var head: Node2D = rider.get_node("Head") as Node2D
	(head.get_node("Skull") as Polygon2D).color = mail
	_poly(head, "Coif", [Vector2(-3.2, -1.0), Vector2(-3.4, -5.0), Vector2(0.2, -6.6),
		Vector2(3.2, -5.0), Vector2(3.2, -1.0), Vector2(2.2, -3.8), Vector2(0.0, -5.0),
		Vector2(-2.2, -3.8)], _dim(mail, 0.88))
	_poly(head, "NasalHelm", [Vector2(-3.0, -4.6), Vector2(0.0, -9.4), Vector2(3.0, -4.6),
		Vector2(1.8, -5.2), Vector2(0.0, -6.6), Vector2(-1.8, -5.2)], STEEL)
	_poly(head, "Nasal", [Vector2(1.4, -5.6), Vector2(2.4, -5.4), Vector2(2.2, -2.6),
		Vector2(1.6, -2.6)], STEEL_DARK)
	var arm: Node2D = rider.get_node("ArmFront") as Node2D
	arm.rotation = -1.05
	arm.set_meta(META_BASE_ROT, -1.05)
	(arm.get_node("Limb") as Polygon2D).color = mail
	var lance: Node2D = _pivot(arm, "Weapon", Vector2(1.5, 6.3), 1.62)
	_poly(lance, "Shaft", [Vector2(-0.6, 6.0), Vector2(0.6, 6.0), Vector2(0.5, -18.0),
		Vector2(-0.5, -18.0)], WOOD)
	_poly(lance, "LanceTip", [Vector2(-0.5, -17.4), Vector2(0.5, -17.4), Vector2(0.0, -21.0)],
		STEEL)
	_poly(lance, "Pennon", [Vector2(0.5, -16.6), Vector2(6.4, -15.2), Vector2(0.5, -13.4)],
		_cloth(team, 0.66))
	return rbody

## Longbowman — the English warbow, taller than its archer: hooded cape,
## back quiver, drawn with the whole body.
static func _longbowman(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("bow", 2.5)
	var rig: Node2D = f["rig"] as Node2D
	var arm_back: Node2D = _arm(rig, "ArmBack", Vector2(-2.3, -10.9), _dim(SKIN, 0.80),
		_dim(SKIN, 0.80), -0.5)
	arm_back.name = "DrawArm"
	arm_back.set_meta(META_BASE_ROT, -0.5)
	var quiver: Node2D = _pivot(rig, "Quiver", Vector2(-3.6, -8.6), 0.55)
	_poly(quiver, "Tube", [Vector2(-1.5, -3.8), Vector2(1.5, -3.8), Vector2(1.2, 3.8),
		Vector2(-1.2, 3.8)], LEATHER)
	_poly(quiver, "Fl1", [Vector2(-1.1, -3.8), Vector2(-0.3, -6.4), Vector2(0.3, -3.8)],
		Color(0.85, 0.83, 0.80))
	_poly(quiver, "Fl2", [Vector2(0.3, -4.0), Vector2(1.1, -5.8), Vector2(1.5, -3.8)],
		Color(0.72, 0.70, 0.66))
	_legs(rig, SKIN, Color(0.34, 0.38, 0.30))
	_tunic(rig, team, 2.6)
	_poly(rig, "Baldric", [Vector2(-3.2, -11.4), Vector2(-2.0, -11.8), Vector2(3.0, -4.6),
		Vector2(2.8, -3.2)], LEATHER_DARK)
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "half")
	_poly(head, "KettleHat", [Vector2(-4.4, -4.2), Vector2(-3.2, -6.8), Vector2(-1.4, -8.0),
		Vector2(1.4, -8.0), Vector2(3.2, -6.8), Vector2(4.4, -4.2), Vector2(2.6, -5.0),
		Vector2(0.0, -5.5), Vector2(-2.6, -5.0)], STEEL_DARK)
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.3, -11.0), SKIN, SKIN, -0.55)
	_poly(arm_front, "Bracer", [Vector2(0.7, 4.2), Vector2(2.5, 3.8), Vector2(2.9, 5.6),
		Vector2(1.1, 6.0)], LEATHER)
	_build_bow(arm_front, 14.0, WOOD)
	_reorder(rig, ["Quiver", "DrawArm", "LegBack", "LegFront", "Tunic", "TunicShade",
		"Belt", "Baldric", "Head", "ArmFront"])
	return f["rbody"] as Node2D

## Conquistador — morrión, breastplate and the arquebus: aim, bang, recoil.
static func _conquistador(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("gun", 2.3)
	var rig: Node2D = f["rig"] as Node2D
	_arm(rig, "ArmBack", Vector2(-2.4, -10.9), _cloth(team, 0.52), _dim(SKIN, 0.80), -1.25)
	_legs(rig, SKIN, Color(0.30, 0.26, 0.22))
	_tunic(rig, team, 2.6)
	# Steel breastplate with peascod ridge.
	_poly(rig, "Cuirass", [Vector2(-3.5, -11.6), Vector2(3.5, -11.6), Vector2(3.1, -5.0),
		Vector2(0.2, -3.6), Vector2(-3.1, -5.0)], STEEL)
	_poly(rig, "CuirassShade", [Vector2(-3.5, -11.6), Vector2(-1.6, -11.6), Vector2(-1.5, -4.2),
		Vector2(-3.1, -5.0)], STEEL_DARK)
	_poly(rig, "CuirassRidge", [Vector2(-0.3, -11.6), Vector2(0.7, -11.6), Vector2(0.5, -3.8),
		Vector2(-0.1, -3.8)], _dim(STEEL, 1.1))
	var head: Node2D = _head(rig, SKIN, HAIR, "long" if female else "half")
	# Morrión: crested comb + swept brim.
	_poly(head, "MorrionBrim", [Vector2(-4.8, -4.0), Vector2(-3.4, -5.2), Vector2(3.4, -5.2),
		Vector2(4.8, -4.0), Vector2(3.0, -4.6), Vector2(-3.0, -4.6)], STEEL)
	_poly(head, "MorrionDome", [Vector2(-3.0, -4.8), Vector2(-2.6, -7.0), Vector2(0.0, -8.0),
		Vector2(2.6, -7.0), Vector2(3.0, -4.8)], STEEL)
	_poly(head, "MorrionComb", [Vector2(-1.6, -7.4), Vector2(0.0, -10.4), Vector2(1.6, -7.4),
		Vector2(0.0, -8.2)], _dim(STEEL, 1.12))
	# The arquebus, held level by both hands (rig-owned like the banot).
	var gun: Node2D = _pivot(rig, "Weapon", Vector2(2.0, -6.0), 1.62)
	_poly(gun, "Stock", [Vector2(-1.2, 6.4), Vector2(0.9, 6.4), Vector2(0.7, 1.0),
		Vector2(-0.9, 1.0)], WOOD_DARK)
	_poly(gun, "Barrel", [Vector2(-0.55, 1.6), Vector2(0.55, 1.6), Vector2(0.55, -11.4),
		Vector2(-0.55, -11.4)], Color(0.32, 0.33, 0.38))
	_poly(gun, "Muzzle", [Vector2(-0.75, -11.4), Vector2(0.75, -11.4), Vector2(0.75, -12.6),
		Vector2(-0.75, -12.6)], Color(0.22, 0.23, 0.27))
	var flash: Polygon2D = _poly(gun, "Flash", [Vector2(-1.6, -13.0), Vector2(0.0, -17.4),
		Vector2(1.6, -13.0), Vector2(0.6, -13.4), Vector2(-0.6, -13.4)],
		Color(0.98, 0.88, 0.46))
	flash.visible = false
	var arm_front: Node2D = _arm(rig, "ArmFront", Vector2(2.4, -11.0), _cloth(team, 0.58),
		SKIN, -1.05)
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Belt",
		"Cuirass", "CuirassShade", "CuirassRidge", "Head", "Weapon", "ArmFront"])
	return f["rbody"] as Node2D

## Tidecaller — Atlantean amphibian: sea-green skin, bronze scale wrap, fin
## crest and a bronze trident.
static func _tidecaller(team: Color, female: bool) -> Node2D:
	var f: Dictionary = _humanoid_frame("thrust", 2.3)
	var rig: Node2D = f["rig"] as Node2D
	var sea_skin: Color = Color(0.52, 0.68, 0.58)
	var bronze: Color = Color(0.72, 0.55, 0.28)
	_arm(rig, "ArmBack", Vector2(-2.3, -10.9), _dim(sea_skin, 0.8), _dim(sea_skin, 0.8), -1.15)
	_legs(rig, sea_skin)
	# Scale wrap: short bronze-banded kilt + chest harness, in team-tinted cloth.
	_poly(rig, "Tunic", [Vector2(-3.4, -6.2), Vector2(3.2, -6.2), Vector2(3.0, -3.0),
		Vector2(4.0, 2.6), Vector2(0.2, 3.4), Vector2(-4.1, 2.4), Vector2(-3.0, -3.0)],
		_cloth(team, 0.55))
	_poly(rig, "TunicShade", [Vector2(-3.4, -6.2), Vector2(-1.6, -6.2), Vector2(-1.5, -3.0),
		Vector2(-2.4, 2.8), Vector2(-4.1, 2.4), Vector2(-3.0, -3.0)], _cloth(team, 0.42))
	_poly(rig, "Torso", [Vector2(-3.3, -11.8), Vector2(3.1, -11.8), Vector2(3.2, -6.0),
		Vector2(-3.2, -6.0)], sea_skin)
	_poly(rig, "Harness", [Vector2(-3.2, -11.4), Vector2(-2.0, -11.8), Vector2(3.0, -5.4),
		Vector2(2.8, -4.0)], bronze)
	_poly(rig, "BeltB", [Vector2(-3.1, -3.4), Vector2(3.0, -3.4), Vector2(2.9, -1.9),
		Vector2(-3.0, -1.9)], bronze)
	# Wave tattoo curl on the chest.
	_poly(rig, "WaveMark", [Vector2(0.0, -9.6), Vector2(1.8, -9.9), Vector2(2.4, -8.9),
		Vector2(1.2, -8.4), Vector2(0.4, -8.8), Vector2(1.4, -9.1)], _dim(sea_skin, 1.3))
	var head: Node2D = _head(rig, sea_skin, _dim(sea_skin, 0.6), "bald")
	# Fin crest instead of hair (bigger on the male; the female wears kelp hair).
	if female:
		_long_hair_back(head, Color(0.24, 0.42, 0.34))
		head.move_child(head.get_node("HairBack"), 0)
	_poly(head, "FinCrest", [Vector2(-2.8, -5.6), Vector2(-1.2, -9.4), Vector2(0.4, -6.8),
		Vector2(1.8, -8.6), Vector2(2.8, -5.4), Vector2(0.4, -6.2), Vector2(-1.4, -6.0)],
		_dim(sea_skin, 0.78))
	# Gill slits.
	_poly(head, "Gills", [Vector2(-2.6, -3.6), Vector2(-1.8, -3.7), Vector2(-1.8, -1.7),
		Vector2(-2.6, -1.8)], _dim(sea_skin, 0.66))
	# Bronze trident held like the banot.
	var trident: Node2D = _pivot(rig, "Weapon", Vector2(0.8, -3.5), 1.80)
	_poly(trident, "Shaft", [Vector2(-0.5, 13.0), Vector2(0.5, 13.0), Vector2(0.5, -13.0),
		Vector2(-0.5, -13.0)], bronze)
	_poly(trident, "ProngMid", [Vector2(-0.5, -13.0), Vector2(0.5, -13.0), Vector2(0.0, -17.6)],
		_dim(bronze, 1.15))
	_poly(trident, "ProngL", [Vector2(-2.2, -12.4), Vector2(-1.2, -12.6), Vector2(-1.6, -16.0),
		Vector2(-2.6, -13.4)], _dim(bronze, 1.15))
	_poly(trident, "ProngR", [Vector2(1.2, -12.6), Vector2(2.2, -12.4), Vector2(2.6, -13.4),
		Vector2(1.6, -16.0)], _dim(bronze, 1.15))
	_poly(trident, "Crossbar", [Vector2(-2.3, -12.9), Vector2(2.3, -12.9), Vector2(2.3, -11.9),
		Vector2(-2.3, -11.9)], bronze)
	_arm(rig, "ArmFront", Vector2(2.3, -11.0), sea_skin, sea_skin, -0.35)
	_reorder(rig, ["ArmBack", "LegBack", "LegFront", "Tunic", "TunicShade", "Torso",
		"Harness", "BeltB", "WaveMark", "Head", "Weapon", "ArmFront"])
	return f["rbody"] as Node2D

## Trireme — the Phoenician ram ship: longer and prouder than the galley,
## three oar banks, Tyrian purple band and the painted eye.
static func _trireme(team: Color, civ_id: String) -> Node2D:
	var f: Dictionary = _ship_frame("galley")
	var rig: Node2D = f["rig"] as Node2D
	var ns: Dictionary = _naval_style(civ_id)
	var hull: Color = ns["hull"] as Color
	var deck: Color = ns["deck"] as Color
	var sail: Color = ns["sail"] as Color
	var tyrian: Color = Color(0.48, 0.16, 0.38)
	rig.scale = Vector2(1.08, 1.08)
	_poly(rig, "Mast", [Vector2(-0.9, -3.0), Vector2(0.9, -3.0), Vector2(0.9, -21.0),
		Vector2(-0.9, -21.0)], _dim(hull, 1.2))
	_poly(rig, "YardArm", [Vector2(-8.8, -20.2), Vector2(8.8, -20.2), Vector2(8.8, -19.0),
		Vector2(-8.8, -19.0)], _dim(hull, 1.35))
	_poly(rig, "Sail", [Vector2(-8.2, -19.2), Vector2(8.2, -19.2), Vector2(7.2, -8.8),
		Vector2(-7.2, -8.8)], sail)
	_poly(rig, "SailBand", [Vector2(-7.8, -15.4), Vector2(7.8, -15.4), Vector2(7.6, -12.8),
		Vector2(-7.6, -12.8)], tyrian)
	for i: int in range(4):
		var oar: Node2D = _pivot(rig, "Oar%d" % i, Vector2(-10.0 + float(i) * 5.6, 1.5), 0.45)
		_poly(oar, "Shaft", [Vector2(-0.4, -0.5), Vector2(0.4, -0.5), Vector2(1.6, 5.6),
			Vector2(0.8, 5.8)], _dim(hull, 1.3))
		_poly(oar, "Blade", [Vector2(0.9, 5.2), Vector2(2.4, 6.6), Vector2(1.4, 7.6),
			Vector2(0.4, 6.2)], _dim(hull, 1.1))
	_poly(rig, "Hull", [Vector2(-18.2, -7.6), Vector2(-16.4, -3.2), Vector2(-15.8, 1.2),
		Vector2(-8.0, 3.9), Vector2(9.0, 3.9), Vector2(16.4, 1.2), Vector2(19.2, -3.6),
		Vector2(14.8, -2.4), Vector2(-13.6, -2.4), Vector2(-16.4, -6.4)], hull)
	_poly(rig, "SternVolute", [Vector2(-18.2, -7.6), Vector2(-16.4, -6.4), Vector2(-15.2, -9.6),
		Vector2(-17.4, -10.4), Vector2(-18.8, -8.8)], tyrian)
	_poly(rig, "Gunwale", [Vector2(-16.0, -3.0), Vector2(14.9, -3.0), Vector2(15.6, -4.4),
		Vector2(-16.4, -4.4)], deck)
	_poly(rig, "PurpleBand", [Vector2(-15.4, -0.4), Vector2(15.0, -0.4), Vector2(15.5, -1.8),
		Vector2(-15.7, -1.8)], tyrian)
	_poly(rig, "HullShade", [Vector2(-15.8, 1.2), Vector2(-8.0, 3.9), Vector2(9.0, 3.9),
		Vector2(16.4, 1.2), Vector2(11.0, 2.8), Vector2(-11.4, 2.8)], _dim(hull, 0.78))
	_poly(rig, "RamSpur", [Vector2(17.8, -0.4), Vector2(24.2, 1.6), Vector2(23.2, 3.6),
		Vector2(16.8, 2.1)], Color(0.72, 0.55, 0.28))
	_poly(rig, "Eye", _ellipse_pts(16.4, -1.4, 1.2, 1.2, 8), Color(0.94, 0.92, 0.86))
	_poly(rig, "EyeDot", _ellipse_pts(16.7, -1.4, 0.55, 0.55, 6), Color(0.10, 0.10, 0.14))
	_team_pennant(rig, team, Vector2(0.0, -20.6), 4.0)
	_reorder(rig, ["Mast", "YardArm", "Sail", "SailBand", "Oar0", "Oar1", "Oar2", "Oar3",
		"Hull", "SternVolute", "Gunwale", "PurpleBand", "HullShade", "RamSpur", "Eye",
		"EyeDot", "Pennant"])
	return f["rbody"] as Node2D

## Re-stacks rig children into explicit paint order (missing names skipped).
static func _reorder(rig: Node2D, order: Array) -> void:
	var idx: int = 0
	for part_name: Variant in order:
		var n: Node = rig.get_node_or_null(part_name as String)
		if n != null:
			rig.move_child(n, idx)
			idx += 1

# ── Animation ───────────────────────────────────────────────────────────────

static func _base_rot(n: Node2D) -> float:
	return n.get_meta(META_BASE_ROT, 0.0) as float

static func _base_pos(n: Node2D) -> Vector2:
	return n.get_meta(META_BASE_POS, Vector2.ZERO) as Vector2

static func _part(rig: Node2D, part_name: String) -> Node2D:
	return rig.get_node_or_null(part_name) as Node2D

## Smooth wind-up -> snap -> recover pulse for strike cycles: 0..1 phase in,
## -1 (full wind-up) .. +1 (full strike) out.
static func _strike_pulse(phase: float) -> float:
	if phase < 0.45:
		return -ease(phase / 0.45, 1.8)            # slow anticipation backwards
	elif phase < 0.62:
		return lerpf(-1.0, 1.0, (phase - 0.45) / 0.17)   # the snap
	return lerpf(1.0, 0.0, ease((phase - 0.62) / 0.38, 0.4))  # recover

static func _animate_humanoid(unit: UnitBase, rbody: Node2D, rig: Node2D) -> void:
	var t: float = unit._anim_time
	var cadence: float = rbody.get_meta(&"cadence", 2.4) as float
	var attack_kind: String = rbody.get_meta(META_ATTACK, "slash") as String
	var leg_f: Node2D = _part(rig, "LegFront")
	var leg_b: Node2D = _part(rig, "LegBack")
	var arm_f: Node2D = _part(rig, "ArmFront")
	var arm_b: Node2D = _part(rig, "ArmBack")
	if arm_b == null:
		arm_b = _part(rig, "DrawArm")
	var head: Node2D = _part(rig, "Head")
	var weapon: Node2D = _part(rig, "Weapon")
	if weapon == null and arm_f != null:
		weapon = arm_f.get_node_or_null("Weapon") as Node2D
	var tool: Node2D = null
	if arm_f != null:
		tool = arm_f.get_node_or_null("Tool") as Node2D
	var carry: Polygon2D = rig.get_node_or_null("Carry") as Polygon2D
	if carry != null:
		carry.visible = unit.current_state == UnitBase.UnitState.RETURNING

	# Reset composables to base each frame; states add on top.
	var lean: float = 0.0
	var bounce: float = 0.0
	var squash: float = 0.0
	var lf: float = 0.0
	var lb: float = 0.0
	var af: float = 0.0
	var ab: float = 0.0
	var head_rot: float = 0.0
	var head_dy: float = 0.0
	var tool_rot: float = 0.0
	var wpn_rot: float = 0.0
	var rig_dx: float = 0.0

	# Arm-rotation sign convention: NEGATIVE offsets swing the hand toward the
	# facing direction (+x), positive swing it up-behind. Strikes wind up
	# (p = -1, arm back) and snap forward (p = +1).
	match unit.current_state:
		UnitBase.UnitState.MOVING, UnitBase.UnitState.RETURNING:
			var w: float = sin(t * TAU * cadence)
			lf = w * 0.72
			lb = -w * 0.72
			af = -w * 0.42
			ab = w * 0.42
			lean = 0.09
			bounce = -absf(cos(t * TAU * cadence)) * 1.3
			squash = absf(cos(t * TAU * cadence)) * 0.03
			head_dy = absf(w) * -0.5
			if unit.current_state == UnitBase.UnitState.RETURNING:
				lean = 0.14
				af *= 0.3   # the near arm steadies the load
		UnitBase.UnitState.ATTACKING:
			var phase: float = fmod(t, 0.8) / 0.8
			var p: float = _strike_pulse(phase)
			match attack_kind:
				"slash":
					af = -p * 1.25
					wpn_rot = p * 2.3   # windup cocks it over the shoulder, strike extends it
					lean = p * 0.14
					ab = p * 0.35
					head_rot = -p * 0.08
					squash = maxf(p, 0.0) * 0.05
				"thrust":
					rig_dx = maxf(p, -0.3) * 3.2
					lean = p * 0.10 + 0.06
					af = -p * 0.28
					ab = -p * 0.22
					if weapon != null:
						weapon.position = _base_pos(weapon) + Vector2(maxf(p, 0.0) * 4.5, 0.0)
				"tool":
					af = -p * 1.1
					lean = p * 0.12
					tool_rot = p * 2.25
				"bow":
					_animate_bow(rig, arm_f, arm_b, weapon, phase)
					lean = 0.04
				"gun":
					var gph: float = fmod(t, 1.2) / 1.2
					var bang: bool = gph > 0.55 and gph < 0.68
					if weapon != null:
						var flash: Polygon2D = weapon.get_node_or_null("Flash") as Polygon2D
						if flash != null:
							flash.visible = bang
					rig_dx = -1.8 if bang else 0.0
					lean = -0.05 if bang else 0.02
				"heal":
					lean = 0.10 + sin(t * TAU * 1.2) * 0.04
					af = -0.8 + sin(t * TAU * 1.2) * 0.15
					ab = -0.6 - sin(t * TAU * 1.2) * 0.15
		UnitBase.UnitState.GATHERING:
			var kind: String = _gather_kind(unit)
			var phase: float = fmod(t, 0.9) / 0.9
			var p: float = _strike_pulse(phase)
			_show_tool_head(tool, kind)
			match kind:
				"forage":
					lean = 0.30 + p * 0.06
					bounce = 1.0
					af = -1.5 - p * 0.4
					ab = -1.2 + p * 0.4
					head_rot = 0.18
				"mine":
					af = -p * 1.35 - 0.25
					lean = p * 0.16
					tool_rot = p * 2.5
					head_rot = -p * 0.10
				_:
					af = -p * 1.15
					lean = p * 0.14
					tool_rot = p * 2.25
					head_rot = -p * 0.08
		UnitBase.UnitState.BUILDING:
			var phase: float = fmod(t, 0.62) / 0.62
			var p: float = _strike_pulse(phase)
			_show_tool_head(tool, "build")
			af = -p * 1.05
			lean = p * 0.12
			tool_rot = p * 2.25
		_:
			# Idle with weight: breathing + micro weight shift.
			squash = sin(t * TAU * 0.45) * 0.015
			rig_dx = sin(t * TAU * 0.11) * 0.5
			af = sin(t * TAU * 0.45) * 0.03
			ab = -sin(t * TAU * 0.45) * 0.03
			head_dy = sin(t * TAU * 0.45 + 0.4) * -0.3
			if tool != null:
				_show_tool_head(tool, "chop")

	rig.rotation = _base_rot(rig) + lean
	rig.position = _base_pos(rig) + Vector2(rig_dx, bounce)
	_apply_squash(rig, squash)
	if leg_f != null:
		leg_f.rotation = _base_rot(leg_f) + lf
	if leg_b != null:
		leg_b.rotation = _base_rot(leg_b) + lb
	# During a bow shot the arms are posed by _animate_bow, not here.
	var bow_shooting: bool = attack_kind == "bow" \
		and unit.current_state == UnitBase.UnitState.ATTACKING
	if arm_f != null and not bow_shooting:
		arm_f.rotation = _base_rot(arm_f) + af
	if arm_b != null and not bow_shooting:
		arm_b.rotation = _base_rot(arm_b) + ab
	if not bow_shooting:
		_reset_bow(arm_f)
	if unit.current_state != UnitBase.UnitState.ATTACKING and weapon != null:
		var idle_flash: Polygon2D = weapon.get_node_or_null("Flash") as Polygon2D
		if idle_flash != null and idle_flash.visible:
			idle_flash.visible = false
	if head != null:
		head.rotation = head_rot
		head.position = _base_pos(head) + Vector2(0.0, head_dy)
		_sway_hair(head, t, unit.current_state == UnitBase.UnitState.MOVING
			or unit.current_state == UnitBase.UnitState.RETURNING, cadence)
	if tool != null:
		tool.rotation = _base_rot(tool) + tool_rot
	if weapon != null:
		weapon.rotation = _base_rot(weapon) + wpn_rot
		if attack_kind == "thrust" and unit.current_state != UnitBase.UnitState.ATTACKING:
			weapon.position = _base_pos(weapon)

## Relax the bowstring/arrow when not shooting.
static func _reset_bow(bow_arm: Node2D) -> void:
	if bow_arm == null:
		return
	var bow: Node2D = bow_arm.get_node_or_null("Weapon") as Node2D
	if bow == null:
		return
	var string: Line2D = bow.get_node_or_null("BowString") as Line2D
	if string != null and string.points.size() == 3:
		var pts: PackedVector2Array = string.points
		if pts[1].x != -0.6:
			pts[1] = Vector2(-0.6, 0.0)
			string.points = pts
	var arrow: Polygon2D = bow.get_node_or_null("Arrow") as Polygon2D
	if arrow != null and arrow.visible:
		arrow.visible = false

## Squash & stretch preserving the authored rig scale (some rigs narrow the
## figure with a base scale.x).
static func _apply_squash(rig: Node2D, squash: float) -> void:
	var base_scale: Vector2 = rig.get_meta(&"redesign_base_scale", Vector2.ZERO) as Vector2
	if base_scale == Vector2.ZERO:
		base_scale = rig.scale
		rig.set_meta(&"redesign_base_scale", base_scale)
	rig.scale = Vector2(base_scale.x * (1.0 - squash * 0.6), base_scale.y * (1.0 + squash))

## Bow shot: raise the bow horizontal, draw arm pulls the string with the
## arrow visible, release snaps back.
static func _animate_bow(rig: Node2D, bow_arm: Node2D, draw_arm: Node2D,
		bow: Node2D, phase: float) -> void:
	if bow_arm == null or bow == null:
		return
	var aim: float = clampf(phase / 0.25, 0.0, 1.0)   # raise to horizontal
	var draw: float = 0.0
	if phase < 0.30:
		draw = 0.0
	elif phase < 0.62:
		draw = ease((phase - 0.30) / 0.32, 0.6)       # pull
	elif phase < 0.68:
		draw = 0.0                                     # release snap
	else:
		draw = 0.0
	bow_arm.rotation = _base_rot(bow_arm) + aim * -0.95
	if draw_arm != null:
		draw_arm.rotation = _base_rot(draw_arm) + aim * -0.85 - draw * 0.30
	var string: Line2D = bow.get_node_or_null("BowString") as Line2D
	if string != null and string.points.size() == 3:
		var pts: PackedVector2Array = string.points
		pts[1] = Vector2(-0.6 - draw * 4.5, 0.0)
		string.points = pts
	var arrow: Polygon2D = bow.get_node_or_null("Arrow") as Polygon2D
	if arrow != null:
		arrow.visible = draw > 0.05
		arrow.position = Vector2(-draw * 4.5, 0.0)

## Which gather animation a villager should play, from its live target.
static func _gather_kind(unit: UnitBase) -> String:
	var target: Variant = unit.get("gather_target")
	if target == null or not is_instance_valid(target as Node):
		return "chop"
	var rtype: Variant = (target as Node).get("resource_type")
	if rtype == null:
		# Farms and other building-borne food read as picking, not chopping.
		return "forage" if target is BuildingBase else "chop"
	match rtype as int:
		ResourceNode.ResourceType.WOOD:
			return "chop"
		ResourceNode.ResourceType.GOLD, ResourceNode.ResourceType.STONE, \
		ResourceNode.ResourceType.OLIVINA:
			return "mine"
		ResourceNode.ResourceType.FOOD_HUNT, ResourceNode.ResourceType.FOOD_FISH, \
		ResourceNode.ResourceType.FOOD_BERRY:
			return "forage"
	return "chop"

static func _show_tool_head(tool: Node2D, kind: String) -> void:
	if tool == null:
		return
	var axe: Polygon2D = tool.get_node_or_null("AxeHead") as Polygon2D
	var pick: Polygon2D = tool.get_node_or_null("PickHead") as Polygon2D
	var hammer: Polygon2D = tool.get_node_or_null("HammerHead") as Polygon2D
	if axe != null:
		axe.visible = kind == "chop"
	if pick != null:
		pick.visible = kind == "mine"
	if hammer != null:
		hammer.visible = kind == "build"
	tool.visible = kind != "forage"

## Cavalry: horse and rider animate decoupled — the horse gallops (leg pairs,
## neck pumping, streaming tail) while the rider bounces half a beat behind.
static func _animate_rider(unit: UnitBase, rbody: Node2D, rig: Node2D) -> void:
	var t: float = unit._anim_time
	var cadence: float = rbody.get_meta(&"cadence", 3.0) as float
	var attack_kind: String = rbody.get_meta(META_ATTACK, "slash") as String
	var rider: Node2D = _part(rig, "Rider")
	var arm: Node2D = null
	var weapon: Node2D = null
	if rider != null:
		arm = rider.get_node_or_null("ArmFront") as Node2D
		if arm != null:
			weapon = arm.get_node_or_null("Weapon") as Node2D
	var lean: float = 0.0
	var bounce: float = 0.0
	var squash: float = 0.0
	var rig_dx: float = 0.0
	var front: float = 0.0
	var back: float = 0.0
	var head_rot: float = 0.0
	var tail_rot: float = 0.0
	var rider_dy: float = 0.0
	var rider_rot: float = 0.0
	var arm_off: float = 0.0
	var wpn_rot: float = 0.0
	match unit.current_state:
		UnitBase.UnitState.MOVING, UnitBase.UnitState.RETURNING:
			var g: float = t * TAU * cadence
			front = sin(g) * 0.62
			back = -sin(g + 0.7) * 0.62
			bounce = -absf(sin(g)) * 1.7
			lean = 0.05
			head_rot = sin(g) * 0.13
			tail_rot = 0.30 + sin(g) * 0.10   # streaming behind
			rider_dy = -absf(sin(g + 0.55)) * 0.8
			rider_rot = 0.08
		UnitBase.UnitState.ATTACKING:
			var phase: float = fmod(t, 0.8) / 0.8
			var p: float = _strike_pulse(phase)
			match attack_kind:
				"lance":
					rig_dx = maxf(p, -0.35) * 4.5
					lean = maxf(p, 0.0) * 0.05
					head_rot = -p * 0.06
					rider_rot = p * 0.10
				_:
					arm_off = -p * 1.0
					wpn_rot = p * 1.9
					rider_rot = p * 0.10
					head_rot = -maxf(p, 0.0) * 0.08
		_:
			squash = sin(t * TAU * 0.4) * 0.012
			tail_rot = sin(t * TAU * 0.30) * 0.18
			head_rot = sin(t * TAU * 0.17) * 0.06
	rig.rotation = _base_rot(rig) + lean
	rig.position = _base_pos(rig) + Vector2(rig_dx, bounce)
	_apply_squash(rig, squash)
	for leg_name: String in ["LegFrontNear", "LegFrontFar"]:
		var leg: Node2D = _part(rig, leg_name)
		if leg != null:
			leg.rotation = _base_rot(leg) + (front if leg_name.ends_with("Near") else front * 0.85)
	for leg_name: String in ["LegBackNear", "LegBackFar"]:
		var leg: Node2D = _part(rig, leg_name)
		if leg != null:
			leg.rotation = _base_rot(leg) + (back if leg_name.ends_with("Near") else back * 0.85)
	var head: Node2D = _part(rig, "HorseHead")
	if head != null:
		head.rotation = _base_rot(head) + head_rot
	var tail: Node2D = _part(rig, "Tail")
	if tail != null:
		tail.rotation = _base_rot(tail) + tail_rot
	if rider != null:
		rider.position = _base_pos(rider) + Vector2(0.0, rider_dy)
		rider.rotation = _base_rot(rider) + rider_rot
		_sway_hair(rider.get_node_or_null("Head") as Node2D, t,
			unit.current_state == UnitBase.UnitState.MOVING, cadence)
	if arm != null:
		arm.rotation = _base_rot(arm) + arm_off
	if weapon != null:
		weapon.rotation = _base_rot(weapon) + wpn_rot

## The Presa Canario: diagonal-pair trot, tail wag at rest, lunging bite.
static func _animate_dog(unit: UnitBase, rbody: Node2D, rig: Node2D) -> void:
	var t: float = unit._anim_time
	var cadence: float = rbody.get_meta(&"cadence", 3.4) as float
	var lean: float = 0.0
	var bounce: float = 0.0
	var squash: float = 0.0
	var rig_dx: float = 0.0
	var diag_a: float = 0.0   # front-near + back-far
	var diag_b: float = 0.0   # front-far + back-near
	var head_rot: float = 0.0
	var tail_rot: float = 0.0
	match unit.current_state:
		UnitBase.UnitState.MOVING, UnitBase.UnitState.RETURNING:
			var g: float = t * TAU * cadence
			diag_a = sin(g) * 0.62
			diag_b = -sin(g) * 0.62
			bounce = -absf(sin(g)) * 1.0
			lean = 0.04
			head_rot = sin(g * 0.5) * 0.06
			tail_rot = 0.28
		UnitBase.UnitState.ATTACKING:
			var phase: float = fmod(t, 0.7) / 0.7
			var p: float = _strike_pulse(phase)
			rig_dx = maxf(p, -0.4) * 3.6
			lean = maxf(p, 0.0) * 0.10
			head_rot = p * 0.30   # the bite
			tail_rot = 0.15
		_:
			squash = sin(t * TAU * 0.5) * 0.015
			tail_rot = sin(t * TAU * 1.3) * 0.30   # the wag
			head_rot = sin(t * TAU * 0.21) * 0.07
	rig.rotation = _base_rot(rig) + lean
	rig.position = _base_pos(rig) + Vector2(rig_dx, bounce)
	_apply_squash(rig, squash)
	for pair: Array in [["LegFrontNear", diag_a], ["LegBackFar", diag_a],
			["LegFrontFar", diag_b], ["LegBackNear", diag_b]]:
		var leg: Node2D = _part(rig, pair[0] as String)
		if leg != null:
			leg.rotation = _base_rot(leg) + (pair[1] as float)
	var head: Node2D = _part(rig, "Head")
	if head != null:
		head.rotation = _base_rot(head) + head_rot
	var tail: Node2D = _part(rig, "Tail")
	if tail != null:
		tail.rotation = _base_rot(tail) + tail_rot

## Ships ride a swell: slow roll + heave, harder while under way; galley oars
## sweep in a staggered rhythm; a fighting ship pitches with the volley.
static func _animate_ship(unit: UnitBase, _rbody: Node2D, rig: Node2D) -> void:
	var t: float = unit._anim_time
	var moving: bool = unit.current_state == UnitBase.UnitState.MOVING \
		or unit.current_state == UnitBase.UnitState.RETURNING
	var roll: float = sin(t * TAU * 0.22) * 0.018
	var heave: float = sin(t * TAU * 0.30) * 0.8
	var oar_sweep: float = 0.0
	if moving:
		roll = sin(t * TAU * 0.45) * 0.030
		heave = sin(t * TAU * 0.60) * 1.1
		oar_sweep = 1.0
	elif unit.current_state == UnitBase.UnitState.ATTACKING:
		roll = sin(t * TAU * 0.8) * 0.035
	rig.rotation = _base_rot(rig) + roll
	rig.position = _base_pos(rig) + Vector2(0.0, heave)
	for i: int in range(4):
		var oar: Node2D = _part(rig, "Oar%d" % i)
		if oar == null:
			break
		if oar_sweep > 0.0:
			oar.rotation = _base_rot(oar) + sin(t * TAU * 0.9 + float(i) * 0.55) * 0.38
		else:
			oar.rotation = _base_rot(oar)

## Siege: wheels roll, the ram log pendulums, the mangonel arm snaps, the
## trebuchet beam whips (and folds flat while packed for travel).
const TREB_COCKED: float = 1.93
const TREB_PACKED: float = 1.45
const TREB_FIRED: float = -0.35

static func _animate_siege(unit: UnitBase, rbody: Node2D, rig: Node2D) -> void:
	var t: float = unit._anim_time
	var kind: String = rbody.get_meta(&"siege_kind", "") as String
	var moving: bool = unit.current_state == UnitBase.UnitState.MOVING \
		or unit.current_state == UnitBase.UnitState.RETURNING
	var attacking: bool = unit.current_state == UnitBase.UnitState.ATTACKING
	if moving:
		for wheel_name: String in ["WheelFar", "WheelFrontFar", "WheelNear", "WheelFrontNear",
				"WheelBackFar", "WheelBackNear"]:
			var wheel: Node2D = _part(rig, wheel_name)
			if wheel != null:
				wheel.rotation = t * 3.2
		rig.position = _base_pos(rig) + Vector2(0.0, sin(t * TAU * 2.0) * 0.5)
		rig.rotation = _base_rot(rig) + sin(t * TAU * 1.1) * 0.015
	else:
		rig.position = _base_pos(rig)
		rig.rotation = _base_rot(rig)
	match kind:
		"ram":
			var log_arm: Node2D = _part(rig, "RamLog")
			if log_arm != null:
				if attacking:
					var p: float = _strike_pulse(fmod(t, 1.0))
					log_arm.rotation = _base_rot(log_arm) - p * 0.22
				else:
					log_arm.rotation = _base_rot(log_arm) \
						+ (sin(t * TAU * 1.0) * 0.04 if moving else 0.0)
		"mangonel":
			var arm: Node2D = _part(rig, "ThrowArm")
			if arm == null:
				return
			var stone: Polygon2D = arm.get_node_or_null("Stone") as Polygon2D
			if attacking:
				var phase: float = fmod(t, 1.1) / 1.1
				var p: float = _strike_pulse(phase)
				arm.rotation = _base_rot(arm) + maxf(p, -0.1) * 1.5
				rig.position.x = _base_pos(rig).x - maxf(p, 0.0) * 1.4
				if stone != null:
					stone.visible = phase < 0.60 or phase > 0.95
			else:
				arm.rotation = _base_rot(arm)
				if stone != null:
					stone.visible = true
		"trebuchet":
			var beam: Node2D = _part(rig, "Beam")
			if beam == null:
				return
			var pouch: Polygon2D = beam.get_node_or_null("Pouch") as Polygon2D
			var sling: Line2D = beam.get_node_or_null("Sling") as Line2D
			var deployed: bool = unit.get("is_deployed") == true
			if not deployed:
				beam.rotation = TREB_PACKED
				if pouch != null:
					pouch.visible = false
				if sling != null:
					sling.visible = false
				return
			if pouch != null:
				pouch.visible = true
			if sling != null:
				sling.visible = true
			if attacking:
				var phase: float = fmod(t, 1.4) / 1.4
				var p: float = _strike_pulse(phase)
				beam.rotation = TREB_COCKED + (maxf(p, 0.0) * (TREB_FIRED - TREB_COCKED) \
					+ minf(p, 0.0) * -0.10)
				if pouch != null:
					pouch.visible = phase < 0.58 or phase > 0.9
			else:
				beam.rotation = TREB_COCKED

static func _animate_bob(unit: UnitBase, rig: Node2D) -> void:
	var t: float = unit._anim_time
	if unit.current_state == UnitBase.UnitState.MOVING:
		rig.position = _base_pos(rig) + Vector2(0.0, -absf(sin(t * TAU * 3.0)) * 1.0)
	else:
		rig.position = _base_pos(rig)

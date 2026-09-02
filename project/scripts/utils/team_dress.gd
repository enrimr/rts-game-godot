class_name TeamDress
extends RefCounted

## Repaints a unit rig's CLOTH into the owner's player colour, AoE2-style:
## the tunic/hood/cap/sleeves (and a knight's caparison) carry the team
## colour, while materials keep their identity — steel armour, leather,
## skin, wood and natural horses are never touched. Each polygon keeps its
## own brightness (HSV value), so the rig's shading survives: sleeves stay
## lighter than the torso, trousers darker.

## Garment nodes: always team-coloured — unless the original paint is
## unsaturated (steel armour like the knight's cuirass stays steel).
const GARMENT_NODES: Array[String] = [
	"Torso", "RiderBody", "Hood", "Cap",
	"SwordArm", "DrawArm", "BowArm", "ArmFront", "ArmLeft", "ArmRight",
	"RiderArm", "RiderLeg", "LegLeft", "LegRight",
	"Plume", "Barding",
]
## Horse/caparison nodes: team-coloured ONLY when the original paint is a
## dyed cloth (a blue caparison), never a natural coat (a brown horse).
const HORSE_NODES: Array[String] = [
	"HorseBody", "HorseNeck", "HorseHead", "Neck", "Muzzle",
	"LegFrontFar", "LegBackFar", "LegFrontNear", "LegBackNear",
	"Tail", "Mane",
]

## Below this saturation the polygon reads as metal/undyed — keep it.
const MIN_DYE_SATURATION: float = 0.22
## Natural coat/leather hue band (browns/oranges), as HSV hue 0..1.
const NATURAL_HUE_MIN: float = 15.0 / 360.0
const NATURAL_HUE_MAX: float = 50.0 / 360.0

static func apply(unit: Node2D, player_id: int) -> void:
	if not is_instance_valid(unit):
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null:
		return
	var team: Color = PlayerColors.get_color(player_id)
	for node_name: String in GARMENT_NODES:
		var poly: Polygon2D = body.get_node_or_null(node_name) as Polygon2D
		if poly != null and poly.color.s >= MIN_DYE_SATURATION:
			poly.color = _team_shade(team, poly.color)
	for node_name: String in HORSE_NODES:
		var poly: Polygon2D = body.get_node_or_null(node_name) as Polygon2D
		if poly == null or poly.color.s < MIN_DYE_SATURATION:
			continue
		if poly.color.h >= NATURAL_HUE_MIN and poly.color.h <= NATURAL_HUE_MAX:
			continue
		poly.color = _team_shade(team, poly.color)

## The team colour at the original polygon's brightness — hue and saturation
## identify the owner, value keeps the rig's own light/shadow modelling.
static func _team_shade(team: Color, original: Color) -> Color:
	return Color.from_hsv(team.h, team.s, original.v, original.a)

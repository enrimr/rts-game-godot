class_name HeroAura extends Node2D

## Dragon Ball-style energy aura around the hero: three additive-blended
## flame layers that flicker upward behind the figure, replacing the old
## static gold ground ring. Drawn in the upright billboard space (local -y is
## up-screen) and inserted BEFORE the Body in tree order, so the figure reads
## on top and the ground shadow (z -1) stays underneath. Purely visual.

const POINTS: int = 26
## Flame envelope around the militia-rig figure (feet at +10, head ~ -17):
## slim and translucent on purpose — the aura frames the hero, the figure
## must stay dominant.
const CENTER: Vector2 = Vector2(0.0, -5.0)
const RX: float = 11.0
const RY: float = 19.0

## [scale, colour] per layer, outermost first.
const LAYERS: Array = [
	[1.15, Color(1.0, 0.55, 0.10, 0.12)],
	[0.92, Color(1.0, 0.80, 0.20, 0.17)],
	[0.62, Color(1.0, 0.95, 0.58, 0.22)],
]

var _t: float = 0.0

func _ready() -> void:
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	for i: int in range(LAYERS.size()):
		var layer: Array = LAYERS[i] as Array
		draw_colored_polygon(
			_flame_points(layer[0] as float, _t + float(i) * 0.7),
			layer[1] as Color)

## Closed flame silhouette: an ellipse whose upper half licks upward with two
## interfering sine bands, plus a slow whole-body pulse. Angle 0 = right,
## -PI/2 = straight up (screen space).
func _flame_points(layer_scale: float, t: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var pulse: float = 1.0 + 0.05 * sin(t * 5.0)
	for i: int in range(POINTS):
		var a: float = TAU * float(i) / float(POINTS)
		var up: float = clampf(-sin(a), 0.0, 1.0)   # 1 at the top of the ellipse
		var lick: float = up * (0.22 * sin(a * 5.0 + t * 9.0)
			+ 0.14 * sin(a * 3.0 - t * 13.0))
		var r: float = (1.0 + maxf(lick, -0.08)) * layer_scale * pulse
		var tip_rise: float = up * up * (3.5 + 2.5 * sin(t * 11.0 + a * 4.0)) * layer_scale
		pts.append(CENTER + Vector2(cos(a) * RX * r, sin(a) * RY * r - tip_rise))
	return pts

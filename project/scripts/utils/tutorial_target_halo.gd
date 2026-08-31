class_name TutorialTargetHalo extends Node2D

## Bright-white pulsing ground halo marking the tutorial's practice target.
## Deliberately DIFFERENT from the hero's golden flame aura: white, low to
## the ground and about half the height, so a new player never confuses the
## dummy with their hero. Attached as a child, so it dies with the unit.

const RINGS: Array[Dictionary] = [
	{"radius": 24.0, "alpha": 0.20},
	{"radius": 17.0, "alpha": 0.32},
	{"radius": 10.0, "alpha": 0.50},
]

func _ready() -> void:
	position = Vector2(0.0, 8.0)   # at the feet
	scale = Vector2(1.0, 0.5)      # flattened: a ground glow, not a flame
	z_index = -1
	var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for ring: Dictionary in RINGS:
		var poly: Polygon2D = Polygon2D.new()
		var pts: PackedVector2Array = PackedVector2Array()
		var r: float = ring["radius"] as float
		for i: int in range(16):
			var a: float = TAU * float(i) / 16.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		poly.polygon = pts
		poly.color = Color(1.0, 1.0, 1.0, ring["alpha"] as float)
		poly.material = add_mat
		add_child(poly)
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(self, "modulate:a", 0.45, 0.55)
	tween.tween_property(self, "modulate:a", 1.0, 0.55)

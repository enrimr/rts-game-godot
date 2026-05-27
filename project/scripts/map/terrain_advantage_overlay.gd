class_name TerrainAdvantageOverlay extends Node2D

## Draws semi-transparent shimmer polygons over terrain zones that benefit
## the player's civilisation, providing immediate visual feedback of civ identity.
##
## Civ → advantaged terrain mapping:
##   atlantes  → OCEAN      (blue shimmer)
##   mahos     → DUNE       (amber shimmer)
##   guanches  → MALPAIS + CALDERA  (red-orange shimmer)
##   canarii   → LAURISILVA (emerald shimmer)
##
## Other civs have no terrain advantage → no overlay drawn.

const BASE_ALPHA: float  = 0.10
const PULSE_AMP:  float  = 0.06
const PULSE_FREQ: float  = 0.55   # Hz

const CIV_TERRAIN_TINTS: Dictionary = {
	"atlantes": {
		"types": [TerrainManager.TerrainType.OCEAN],
		"color": Color(0.20, 0.55, 1.00),
	},
	"mahos": {
		"types": [TerrainManager.TerrainType.DUNE],
		"color": Color(1.00, 0.65, 0.10),
	},
	"guanches": {
		"types": [TerrainManager.TerrainType.MALPAIS, TerrainManager.TerrainType.CALDERA],
		"color": Color(1.00, 0.28, 0.05),
	},
	"canarii": {
		"types": [TerrainManager.TerrainType.LAURISILVA],
		"color": Color(0.15, 0.90, 0.35),
	},
}

var _time: float = 0.0
var _polys: Array[Polygon2D] = []
var _tint_color: Color = Color.WHITE

func _ready() -> void:
	z_index = -5

## Main entry point — call after MapGenerator.generate() finishes.
func build_from_terrain_manager(civ_id: String) -> void:
	if not CIV_TERRAIN_TINTS.has(civ_id):
		return
	var cfg: Dictionary = CIV_TERRAIN_TINTS[civ_id] as Dictionary
	_tint_color = cfg["color"] as Color
	var adv_types: Array = cfg["types"] as Array

	# Special case: Atlantes on island map — ocean covers everything; instead
	# tint the land island polygons to show Atlantes moves freely through the water.
	if civ_id == "atlantes" and TerrainManager.is_island_map():
		_build_island_land_tint()
		return

	# Generic case: zone-based terrain types.
	for zone: Dictionary in TerrainManager.get_zones():
		var ztype: int = zone["type"] as int
		var matched: bool = false
		for t: Variant in adv_types:
			if ztype == (t as int):
				matched = true
				break
		if not matched:
			continue
		var center: Vector2 = zone["center"] as Vector2
		var radius: float   = zone["radius"] as float
		var poly: Polygon2D = _make_shimmer_poly(center, radius)
		add_child(poly)
		_polys.append(poly)

## Island map: tint the land polygons' shorelines to indicate water freedom.
## We draw a shimmer ring around each island perimeter to show coastal mastery.
func _build_island_land_tint() -> void:
	for lp: Variant in TerrainManager.get_land_polys():
		var pts: PackedVector2Array = lp as PackedVector2Array
		if pts.size() < 3:
			continue
		# Compute centroid and average radius
		var centroid: Vector2 = Vector2.ZERO
		for pt: Vector2 in pts:
			centroid += pt
		centroid /= float(pts.size())
		var avg_r: float = 0.0
		for pt: Vector2 in pts:
			avg_r += centroid.distance_to(pt)
		avg_r /= float(pts.size())
		# Draw a slightly larger shimmer polygon that forms a glowing ring at the coast
		var poly: Polygon2D = _make_shimmer_poly(centroid, avg_r * 1.08)
		add_child(poly)
		_polys.append(poly)

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING \
			and GameManager.state != GameManager.GameState.PAUSED:
		return
	_time += delta
	var alpha: float = BASE_ALPHA + PULSE_AMP * sin(_time * TAU * PULSE_FREQ)
	var c: Color = Color(_tint_color.r, _tint_color.g, _tint_color.b, alpha)
	for poly: Polygon2D in _polys:
		if is_instance_valid(poly):
			poly.color = c

func _make_shimmer_poly(center: Vector2, radius: float) -> Polygon2D:
	var poly: Polygon2D = Polygon2D.new()
	const STEPS: int = 32
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(STEPS):
		var a: float = TAU * i / STEPS
		var r: float = radius * (0.90 + 0.12 * sin(a * 3.0 + center.x * 0.01))
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	poly.polygon = pts
	poly.color = Color(_tint_color.r, _tint_color.g, _tint_color.b, BASE_ALPHA)
	return poly

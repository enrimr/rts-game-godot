extends GutTest

## UnitEnhancer contract: the enhanced look is a fully reversible layer on
## top of the finished rig. Applying marks everything it adds/touches with
## meta; stripping removes it and the polygons render exactly as before —
## including a TeamDress-painted rig (colors are NEVER modified, shading
## lives in vertex_colors only).

func _militia(pid: int = 1) -> Node2D:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	autofree(unit)
	TeamDress.apply(unit, pid)
	return unit

func _body_polys(unit: Node2D) -> Array[Polygon2D]:
	var out: Array[Polygon2D] = []
	for child: Node in unit.get_node("Body").get_children():
		if child is Polygon2D and not child.has_meta(UnitEnhancer.META_ENHANCED):
			out.append(child as Polygon2D)
	return out

func _snapshot_colors(unit: Node2D) -> Dictionary:
	var snap: Dictionary = {}
	for poly: Polygon2D in _body_polys(unit):
		snap[poly.name] = poly.color
	return snap

func _count_outlines(unit: Node2D) -> int:
	var n: int = 0
	for poly: Polygon2D in _body_polys(unit):
		for child: Node in poly.get_children():
			if child.has_meta(UnitEnhancer.META_ENHANCED):
				n += 1
	return n

func test_default_setting_is_classic() -> void:
	# A fresh GameSettings (no user cfg loaded) must default to the classic
	# look — the autoload singleton may carry the developer's own preference.
	var fresh: Node = (load("res://scripts/core/game_settings.gd") as GDScript).new() as Node
	assert_false(fresh.get("enhanced_units") as bool,
		"the classic flat look must stay the game's default")
	assert_eq(fresh.get("unit_style") as int, GameSettings.UnitStyle.CLASSIC)
	fresh.free()

func test_apply_adds_marked_nodes_and_shading() -> void:
	var unit: Node2D = _militia()
	UnitEnhancer.apply(unit)
	assert_true(UnitEnhancer.is_applied(unit), "Body carries the applied flag")
	assert_gt(_count_outlines(unit), 0, "outline polygons were added")
	var torso: Polygon2D = unit.get_node("Body/Torso") as Polygon2D
	assert_eq(torso.polygon.size(), torso.vertex_colors.size(),
		"the torso got one shading vertex color per vertex")
	assert_true(torso.has_meta(UnitEnhancer.META_SHADED))

func test_polygon_colors_never_change() -> void:
	var unit: Node2D = _militia(4)
	var before: Dictionary = _snapshot_colors(unit)
	UnitEnhancer.apply(unit)
	for poly: Polygon2D in _body_polys(unit):
		assert_eq(poly.color, before[poly.name] as Color,
			"%s keeps its TeamDress color untouched" % poly.name)

func test_strip_restores_the_classic_rig() -> void:
	var unit: Node2D = _militia()
	var before: Dictionary = _snapshot_colors(unit)
	UnitEnhancer.apply(unit)
	UnitEnhancer.strip(unit)
	assert_false(UnitEnhancer.is_applied(unit))
	assert_eq(_count_outlines(unit), 0, "every added node was removed")
	for poly: Polygon2D in _body_polys(unit):
		assert_eq(poly.vertex_colors.size(), 0,
			"%s shading gradient was cleared" % poly.name)
		assert_eq(poly.color, before[poly.name] as Color,
			"%s renders exactly as before the enhancement" % poly.name)
		assert_false(poly.has_meta(UnitEnhancer.META_SHADED))

func test_apply_is_idempotent() -> void:
	var unit: Node2D = _militia()
	UnitEnhancer.apply(unit)
	var outlines: int = _count_outlines(unit)
	UnitEnhancer.apply(unit)
	assert_eq(_count_outlines(unit), outlines,
		"a second apply must not stack more outlines")

func test_shading_darkens_feet_and_lights_the_head() -> void:
	var unit: Node2D = _militia()
	UnitEnhancer.apply(unit)
	var leg: Polygon2D = unit.get_node("Body/LegLeft") as Polygon2D
	var helmet: Polygon2D = unit.get_node("Body/Helmet") as Polygon2D
	var leg_v: float = leg.vertex_colors[0].v
	for c: Color in leg.vertex_colors:
		leg_v = minf(leg_v, c.v)
	assert_lt(leg_v, leg.color.v, "the feet end of the figure is darkened")
	var top_v: float = 0.0
	for c: Color in helmet.vertex_colors:
		top_v = maxf(top_v, c.v)
	assert_gte(top_v, helmet.color.v, "the head end gets the rim light")

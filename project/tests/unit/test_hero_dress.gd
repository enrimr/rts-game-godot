extends GutTest

## HeroDress contract: every one of the 16 heroes gets at least one signature
## gear node, the team-coloured torso is never repainted, and non-hero data is
## a safe no-op.

const HERO_PATHS: Dictionary = {
	"res://resources/units/hero_bencomo.tres":     false,
	"res://resources/units/hero_dacil.tres":       true,
	"res://resources/units/hero_doramas.tres":     false,
	"res://resources/units/hero_guayarmina.tres":  true,
	"res://resources/units/hero_guadarfia.tres":   false,
	"res://resources/units/hero_tibiabin.tres":    true,
	"res://resources/units/hero_bethencourt.tres": false,
	"res://resources/units/hero_catalina.tres":    true,
	"res://resources/units/hero_drake.tres":       false,
	"res://resources/units/hero_grace.tres":       true,
	"res://resources/units/hero_quijote.tres":     false,
	"res://resources/units/hero_dulcinea.tres":    true,
	"res://resources/units/hero_artaxerax.tres":   false,
	"res://resources/units/hero_cleito.tres":      true,
	"res://resources/units/hero_hanno.tres":       false,
	"res://resources/units/hero_elissa.tres":      true,
}

func _rig(data_path: String) -> Node2D:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as Node2D
	autofree(unit)
	if not data_path.is_empty():
		unit.set("unit_data", load(data_path))
	return unit

func _gear_count(unit: Node2D) -> int:
	var count: int = 0
	var stack: Array = [unit.get_node("Body")]
	while not stack.is_empty():
		var node: Node = stack.pop_back() as Node
		if (node.name as String).begins_with("Hero"):
			count += 1
		stack.append_array(node.get_children())
	return count

func test_every_hero_gets_signature_gear() -> void:
	for path: String in HERO_PATHS:
		var unit: Node2D = _rig(path)
		HeroDress.apply(unit, HERO_PATHS[path] as bool)
		assert_gt(_gear_count(unit), 0,
			"%s must gain at least one Hero* gear node" % path.get_file())
		assert_true(unit.has_meta(HeroDress.META_APPLIED),
			"%s must be marked as dressed" % path.get_file())

func test_torso_is_never_repainted() -> void:
	for path: String in HERO_PATHS:
		var unit: Node2D = _rig(path)
		var torso: Polygon2D = unit.get_node("Body/Torso") as Polygon2D
		var before: Color = torso.color
		HeroDress.apply(unit, HERO_PATHS[path] as bool)
		assert_eq(torso.color, before,
			"%s: the torso stays TeamDress territory" % path.get_file())

func test_identity_survives_duplicated_data() -> void:
	# Quijote's Rocinante passive duplicates unit_data, wiping resource_path;
	# the ability id must still resolve the hero.
	var unit: Node2D = _rig("res://resources/units/hero_quijote.tres")
	var dup: UnitResource = (unit.get("unit_data") as UnitResource).duplicate() as UnitResource
	unit.set("unit_data", dup)
	HeroDress.apply(unit, false)
	assert_gt(_gear_count(unit), 0, "duplicated data must still dress Quijote")

func test_apply_is_idempotent() -> void:
	var unit: Node2D = _rig("res://resources/units/hero_drake.tres")
	HeroDress.apply(unit, false)
	var count: int = _gear_count(unit)
	HeroDress.apply(unit, false)
	assert_eq(_gear_count(unit), count, "a second pass must add nothing")

func test_non_hero_data_is_a_no_op() -> void:
	var unit: Node2D = _rig("")
	HeroDress.apply(unit, false)
	assert_eq(_gear_count(unit), 0, "militia data adds no hero gear")
	assert_false(unit.has_meta(HeroDress.META_APPLIED))

func test_null_and_freed_are_safe() -> void:
	HeroDress.apply(null, false)
	HeroDress.apply(RefCounted.new(), true)
	pass_test("no crash on null / non-node input")

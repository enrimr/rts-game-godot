extends GutTest

## UnitRedesign contract: the REDESIGNED style is a fully reversible layer —
## apply() builds a RedesignBody sibling and hides the classic Body (never
## freeing it), strip() restores the exact classic rig, both idempotent; the
## three GameSettings.unit_style transitions re-dress live units; and the
## Harimaguada stays female in every style.

func before_each() -> void:
	GameSettings.unit_style = GameSettings.UnitStyle.CLASSIC

func after_all() -> void:
	GameSettings.unit_style = GameSettings.UnitStyle.CLASSIC

func _unit(scene: String, pid: int = 1) -> Node2D:
	var unit: Node2D = (load(scene) as PackedScene).instantiate() as Node2D
	unit.set("player_id", pid)
	autofree(unit)
	return unit

func test_default_style_is_classic() -> void:
	assert_eq(GameSettings.unit_style, GameSettings.UnitStyle.CLASSIC,
		"the classic flat look must stay the game's default")
	assert_false(GameSettings.enhanced_units, "the legacy bool alias reads false")

func test_apply_builds_rig_and_hides_classic_body() -> void:
	var unit: Node2D = _unit("res://scenes/units/militia.tscn")
	UnitRedesign.apply(unit)
	assert_true(UnitRedesign.is_applied(unit))
	assert_not_null(unit.get_node_or_null("RedesignBody/Rig"), "the rig was built")
	assert_false((unit.get_node("Body") as Node2D).visible, "classic Body hidden, not freed")

func test_strip_restores_the_classic_rig_exactly() -> void:
	var unit: Node2D = _unit("res://scenes/units/militia.tscn")
	var body: Node2D = unit.get_node("Body") as Node2D
	var children_before: int = body.get_child_count()
	UnitRedesign.apply(unit)
	UnitRedesign.strip(unit)
	assert_false(UnitRedesign.is_applied(unit))
	assert_null(unit.get_node_or_null("RedesignBody"))
	assert_true(body.visible, "classic Body visible again")
	assert_eq(body.get_child_count(), children_before, "classic rig untouched")
	assert_false(unit.has_meta(UnitRedesign.META_APPLIED))

func test_apply_and_strip_are_idempotent() -> void:
	var unit: Node2D = _unit("res://scenes/units/villager.tscn")
	UnitRedesign.apply(unit)
	UnitRedesign.apply(unit)
	var count: int = 0
	for child: Node in unit.get_children():
		if child.name == StringName("RedesignBody"):
			count += 1
	assert_eq(count, 1, "a second apply must not stack another rig")
	UnitRedesign.strip(unit)
	UnitRedesign.strip(unit)
	assert_null(unit.get_node_or_null("RedesignBody"))

func test_unit_without_redesigned_rig_keeps_classic_look() -> void:
	var unit: CharacterBody2D = CharacterBody2D.new()
	unit.set_script(load("res://scripts/units/unit_base.gd"))
	var body: Node2D = Node2D.new()
	body.name = "Body"
	unit.add_child(body)
	autofree(unit)
	UnitRedesign.apply(unit)   # unit_data is null: no factory rig
	assert_false(UnitRedesign.is_applied(unit))
	assert_true(body.visible, "the classic rig stays visible")

func test_live_style_transitions_re_dress_a_live_unit() -> void:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	unit.set("player_id", 1)
	add_child_autofree(unit)
	await wait_frames(5)   # let the deferred paint layers settle
	# classic -> enhanced
	GameSettings.unit_style = GameSettings.UnitStyle.ENHANCED
	assert_true(UnitEnhancer.is_applied(unit))
	assert_false(UnitRedesign.is_applied(unit))
	# enhanced -> redesigned
	GameSettings.unit_style = GameSettings.UnitStyle.REDESIGNED
	assert_false(UnitEnhancer.is_applied(unit), "the enhancer layer was stripped")
	assert_true(UnitRedesign.is_applied(unit))
	# redesigned -> enhanced
	GameSettings.unit_style = GameSettings.UnitStyle.ENHANCED
	assert_true(UnitEnhancer.is_applied(unit))
	assert_false(UnitRedesign.is_applied(unit))
	# enhanced -> classic
	GameSettings.unit_style = GameSettings.UnitStyle.CLASSIC
	assert_false(UnitEnhancer.is_applied(unit))
	assert_false(UnitRedesign.is_applied(unit))
	assert_true((unit.get_node("Body") as Node2D).visible)

func test_harimaguada_is_female_in_both_styles() -> void:
	var unit: Node2D = (load("res://scenes/units/harimaguada.tscn") as PackedScene).instantiate() as Node2D
	unit.set("player_id", 0)
	add_child_autofree(unit)
	await wait_frames(2)
	assert_true(unit.get("is_female") as bool, "the Harimaguada is female by lore")
	UnitRedesign.apply(unit)
	assert_true(UnitRedesign.is_applied(unit))
	assert_not_null(unit.get_node_or_null("RedesignBody/Rig/Head/HairBack"),
		"the redesigned rig wears the long female hair")
	assert_true(unit.get("is_female") as bool)

func test_legacy_enhanced_units_alias_maps_to_the_enum() -> void:
	GameSettings.enhanced_units = true
	assert_eq(GameSettings.unit_style, GameSettings.UnitStyle.ENHANCED)
	GameSettings.enhanced_units = false
	assert_eq(GameSettings.unit_style, GameSettings.UnitStyle.CLASSIC)
	GameSettings.unit_style = GameSettings.UnitStyle.REDESIGNED
	assert_false(GameSettings.enhanced_units,
		"the redesigned style is not the enhanced style")

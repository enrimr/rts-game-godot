extends GutTest

## UnitDress — the civ dress pass that marks shared human units with the
## CivStyle headgear + a trim sash so armies of different civs read apart.
## Pins: gear nodes anchored to the head, sash on the torso, "none" headgear
## adds no gear, idempotency, hero/non-humanoid skip.

func _rig(civ: String, with_hat: bool = true) -> UnitBase:
	var u: UnitBase = autofree(UnitBase.new())
	u.civ_id = civ
	var body: Node2D = Node2D.new()
	body.name = "Body"
	u.add_child(body)
	var torso: Polygon2D = Polygon2D.new()
	torso.name = "Torso"
	torso.polygon = PackedVector2Array([
		Vector2(-5, 4), Vector2(-3, -8), Vector2(3, -8), Vector2(5, 4)])
	body.add_child(torso)
	var head: Polygon2D = Polygon2D.new()
	head.name = "Head"
	head.polygon = PackedVector2Array([
		Vector2(-3, -8), Vector2(-3, -15), Vector2(3, -15), Vector2(3, -8)])
	body.add_child(head)
	if with_hat:
		var hat: Polygon2D = Polygon2D.new()
		hat.name = "Hat"
		hat.polygon = PackedVector2Array([
			Vector2(-6, -13), Vector2(0, -17), Vector2(6, -13)])
		body.add_child(hat)
	return u

func _head(u: UnitBase) -> Polygon2D:
	return u.get_node("Body/Head") as Polygon2D

func test_wrap_civ_adds_headgear_and_sash() -> void:
	var u: UnitBase = _rig("mahos")
	UnitDress.apply(u, 0)
	assert_not_null(_head(u).get_node_or_null("CivHeadgear"), "wrap dome on the head")
	assert_not_null(_head(u).get_node_or_null("CivHeadgearB"), "wrap tail on the head")
	assert_not_null(u.get_node_or_null("Body/Torso/CivSash"), "trim sash on the torso")

func test_crown_gear_replaces_straw_hat() -> void:
	var u: UnitBase = _rig("franks")
	UnitDress.apply(u, 0)
	assert_false((u.get_node("Body/Hat") as Polygon2D).visible,
		"cap replaces the villager straw hat")
	var v: UnitBase = _rig("guanches")
	UnitDress.apply(v, 0)
	assert_true((v.get_node("Body/Hat") as Polygon2D).visible,
		"face-level band keeps the straw hat")

func test_none_headgear_skips_gear_but_keeps_sash() -> void:
	var u: UnitBase = _rig("canarii")
	UnitDress.apply(u, 0)
	assert_null(_head(u).get_node_or_null("CivHeadgear"), "canarii wear no headgear")
	assert_not_null(u.get_node_or_null("Body/Torso/CivSash"), "sash still marks the civ")

func test_apply_is_idempotent() -> void:
	var u: UnitBase = _rig("atlantes")
	UnitDress.apply(u, 0)
	var count: int = _head(u).get_child_count()
	UnitDress.apply(u, 0)
	assert_eq(_head(u).get_child_count(), count, "second apply adds nothing")

func test_hero_is_skipped() -> void:
	var hero: HeroUnit = autofree(HeroUnit.new())
	hero.civ_id = "mahos"
	var body: Node2D = Node2D.new()
	body.name = "Body"
	hero.add_child(body)
	var head: Polygon2D = Polygon2D.new()
	head.name = "Head"
	head.polygon = PackedVector2Array([Vector2(-3, -15), Vector2(3, -15), Vector2(3, -8)])
	body.add_child(head)
	UnitDress.apply(hero, 0)
	assert_null(head.get_node_or_null("CivHeadgear"), "heroes keep their own identity")

func test_headless_rig_is_skipped_without_error() -> void:
	var u: UnitBase = autofree(UnitBase.new())
	u.civ_id = "mahos"
	var body: Node2D = Node2D.new()
	body.name = "Body"
	u.add_child(body)
	UnitDress.apply(u, 0)
	assert_eq(body.get_child_count(), 0, "no head polygon (ship/siege) -> untouched")

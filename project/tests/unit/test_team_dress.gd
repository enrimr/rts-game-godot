extends GutTest

## TeamDress contract: unit cloth reads as the OWNER's colour, materials
## keep their identity. Rows of different players must differ only in dye.

func _rig(scene: String, pid: int) -> Node2D:
	var unit: Node2D = (load(scene) as PackedScene).instantiate() as Node2D
	autofree(unit)
	TeamDress.apply(unit, pid)
	return unit

func _poly(unit: Node2D, node_name: String) -> Polygon2D:
	return unit.get_node("Body/" + node_name) as Polygon2D

func test_tunic_takes_the_player_hue() -> void:
	for pid: int in [0, 1, 4]:
		var unit: Node2D = _rig("res://scenes/units/militia.tscn", pid)
		var torso: Polygon2D = _poly(unit, "Torso")
		assert_almost_eq(torso.color.h, PlayerColors.get_color(pid).h, 0.02,
			"player %d militia tunic must carry the player hue" % pid)

func test_shading_survives_the_recolor() -> void:
	var plain: Node2D = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate() as Node2D
	autofree(plain)
	var original_v: float = (_poly(plain, "Torso") as Polygon2D).color.v
	var dressed: Node2D = _rig("res://scenes/units/villager.tscn", 1)
	assert_almost_eq(_poly(dressed, "Torso").color.v, original_v, 0.01,
		"the polygon keeps its own brightness — only hue/saturation change")

func test_steel_armor_stays_steel() -> void:
	var plain: Node2D = (load("res://scenes/units/knight.tscn") as PackedScene).instantiate() as Node2D
	autofree(plain)
	var steel: Color = _poly(plain, "RiderBody").color
	var dressed: Node2D = _rig("res://scenes/units/knight.tscn", 1)
	assert_eq(_poly(dressed, "RiderBody").color, steel,
		"the knight's cuirass is metal, not cloth — never dyed")

func test_knight_caparison_is_dyed_but_natural_horse_is_not() -> void:
	var knight: Node2D = _rig("res://scenes/units/knight.tscn", 4)
	assert_almost_eq(_poly(knight, "Barding").color.h, PlayerColors.get_color(4).h, 0.02,
		"the knight's caparison carries the team colour")
	var plain_scout: Node2D = (load("res://scenes/units/scout.tscn") as PackedScene).instantiate() as Node2D
	autofree(plain_scout)
	var coat: Color = _poly(plain_scout, "HorseBody").color
	var scout: Node2D = _rig("res://scenes/units/scout.tscn", 4)
	assert_eq(_poly(scout, "HorseBody").color, coat,
		"a natural brown horse is never dyed green")
	assert_almost_eq(_poly(scout, "RiderBody").color.h, PlayerColors.get_color(4).h, 0.02,
		"the scout's rider tunic does take the team colour")

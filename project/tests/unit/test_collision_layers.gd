extends GutTest

## Collision-layer convention (anti-jam fix): units must NOT hard-collide with
## each other — RVO avoidance separates moving units; physics only blocks
## against the world (buildings, scenery, map walls).
##
##   Layer 1 = world (buildings StaticBody2D, scenery, boundary walls)
##   Layer 2 = units (every CharacterBody2D unit/animal/ship)
##
## Units: collision_layer = 2 (they ARE units), collision_mask = 1 (they hit
## only the world). Detection Area2Ds (attack range, gate opening, sheep
## conversion) must include bit 2 in their mask so they still see units.

const UNITS_DIR: String = "res://scenes/units/"

func _unit_scene_paths() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(UNITS_DIR)
	assert_not_null(dir, "units scene dir must exist")
	for f: String in dir.get_files():
		if f.ends_with(".tscn"):
			out.append(UNITS_DIR + f)
	return out

func test_units_do_not_collide_with_each_other() -> void:
	var checked: int = 0
	for path: String in _unit_scene_paths():
		var scene: PackedScene = load(path) as PackedScene
		var inst: Node = scene.instantiate()
		if inst is CharacterBody2D:
			var body: CharacterBody2D = inst as CharacterBody2D
			assert_eq(body.collision_layer, 2, "%s: unit body must live on layer 2" % path)
			assert_eq(body.collision_mask, 1, "%s: unit body must collide only with the world (mask 1)" % path)
			checked += 1
		inst.free()
	assert_gt(checked, 20, "expected to validate the full unit roster")

func test_unit_detection_areas_see_units() -> void:
	for path: String in _unit_scene_paths():
		var scene: PackedScene = load(path) as PackedScene
		var inst: Node = scene.instantiate()
		for child: Node in inst.get_children():
			if child is Area2D:
				var mask: int = (child as Area2D).collision_mask
				assert_true((mask & 2) != 0,
					"%s/%s: detection area mask must include the units layer (bit 2)" % [path, child.name])
		inst.free()

func test_gate_detects_units() -> void:
	var gate: Node = (load("res://scenes/buildings/gate.tscn") as PackedScene).instantiate()
	var area: Area2D = gate.get_node_or_null("DetectArea") as Area2D
	assert_not_null(area, "gate must keep its DetectArea")
	assert_true((area.collision_mask & 2) != 0, "gate must open for units on layer 2")
	gate.free()

extends GutTest

## Last-known-position memory of enemy buildings on the minimap (AoE2-style).
## MinimapRenderer._update_enemy_building_memory runs on the content tick:
## enemy buildings in a VISIBLE fog cell are remembered; while their spot is
## fogged (EXPLORED) the ghost persists — even if the building was destroyed —
## and it is only forgotten when the spot is re-observed without the building.
##
## Fog states are driven through the real FogOfWar node: reveal_all() makes
## every cell VISIBLE, a _tick() with no LOS sources decays them to EXPLORED.

var _mm: MinimapRenderer
var _world: Node2D
var _buildings: Node2D
var _fow: FogOfWar
var _enemy_script: GDScript
var _own_script: GDScript

func before_all() -> void:
	_enemy_script = GDScript.new()
	_enemy_script.source_code = "extends Node2D\nvar player_id: int = 1\n"
	_enemy_script.reload()
	_own_script = GDScript.new()
	_own_script.source_code = "extends Node2D\nvar player_id: int = 0\n"
	_own_script.reload()

func before_each() -> void:
	_mm = MinimapRenderer.new()
	_mm.size = Vector2(200.0, 200.0)
	add_child_autofree(_mm)
	_world = Node2D.new()
	add_child_autofree(_world)
	_buildings = Node2D.new()
	_buildings.name = "BuildingsLayer"
	_world.add_child(_buildings)
	_fow = FogOfWar.new()
	add_child_autofree(_fow)
	_mm.world_node = _world
	_mm.fog = _fow

func _add_building(script: GDScript, pos: Vector2) -> Node2D:
	var b: Node2D = Node2D.new()
	b.set_script(script)
	b.position = pos
	_buildings.add_child(b)
	return b

func _fog_everything() -> void:
	# VISIBLE cells decay to EXPLORED when a tick finds no LOS sources.
	_fow._tick()

# 1 — an enemy building in a visible cell is remembered
func test_visible_enemy_building_is_remembered() -> void:
	var b: Node2D = _add_building(_enemy_script, Vector2(100.0, 50.0))
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 1)
	var entry: Dictionary = _mm._known_enemy_buildings[b.get_instance_id()]
	assert_eq(entry["pos"], Vector2(100.0, 50.0))
	assert_eq(entry["pid"], 1)

# 2 — own buildings are never recorded
func test_own_building_not_remembered() -> void:
	_add_building(_own_script, Vector2(100.0, 50.0))
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 0)

# 3 — a never-seen building (unexplored cell) is not recorded
func test_unseen_building_not_remembered() -> void:
	_add_building(_enemy_script, Vector2(100.0, 50.0))
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 0, "unexplored cells reveal nothing")

# 4 — the memory survives fogging, even if the building dies under fog
func test_ghost_persists_under_fog_after_destruction() -> void:
	var b: Node2D = _add_building(_enemy_script, Vector2(100.0, 50.0))
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	_fog_everything()
	b.free()
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 1,
		"the player has not re-scouted the spot, so the ghost must persist")

# 5 — re-observing the empty spot forgets the ghost
func test_rescouting_empty_spot_forgets_ghost() -> void:
	var b: Node2D = _add_building(_enemy_script, Vector2(100.0, 50.0))
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	_fog_everything()
	b.free()
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 0,
		"seeing the empty spot must clear the stale ghost")

# 6 — re-observing a still-standing building keeps (and refreshes) the entry
func test_rescouting_alive_building_keeps_entry() -> void:
	var b: Node2D = _add_building(_enemy_script, Vector2(100.0, 50.0))
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	_fog_everything()
	_fow.reveal_all()
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 1)
	assert_true(_mm._known_enemy_buildings.has(b.get_instance_id()))

# 7 — without fog assigned the memory system stays inert
func test_no_fog_no_memory() -> void:
	_mm.fog = null
	_add_building(_enemy_script, Vector2(100.0, 50.0))
	_mm._update_enemy_building_memory()
	assert_eq(_mm._known_enemy_buildings.size(), 0)

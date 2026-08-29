extends GutTest

## Progressive damage fire/smoke (BuildingDamageFx) and the watch tower's
## restored auto-attack.
##
## Two regressions live here:
##   - Buildings gave no visual hint of their damage level; DamageFx stages
##     smoke/fire from the HP ratio and walks back down on repair.
##   - The "units" group was empty (no scene declared it, nothing joined it),
##     so WatchTower._find_nearest_enemy never found anyone — towers never
##     attacked. UnitBase._ready now joins the group.

class StubBuilding extends Node2D:
	var player_id: int = 0
	var health: float = 100.0
	var max_health: float = 100.0
	var state: int = BuildingBase.BuildingState.COMPLETE

func _fx_of(b: Node2D) -> BuildingDamageFx:
	return b.get_node("DamageFx") as BuildingDamageFx


# ---------------------------------------------------------------------------
# 1. Stage mapping (pure)
# ---------------------------------------------------------------------------

func test_stage_thresholds() -> void:
	assert_eq(BuildingDamageFx.stage_for(1.0), 0, "full HP: nothing")
	assert_eq(BuildingDamageFx.stage_for(0.8), 0)
	assert_eq(BuildingDamageFx.stage_for(0.74), 1, "under 75%: smoke")
	assert_eq(BuildingDamageFx.stage_for(0.49), 2, "under 50%: fire joins")
	assert_eq(BuildingDamageFx.stage_for(0.10), 3, "under 25%: heavy fire")


# ---------------------------------------------------------------------------
# 2. The component follows the building's HP, state and repairs
# ---------------------------------------------------------------------------

func test_fx_stages_up_with_damage_and_down_with_repair() -> void:
	var b: StubBuilding = StubBuilding.new()
	add_child_autofree(b)
	BuildingDamageFx.attach(b)
	var fx: BuildingDamageFx = _fx_of(b)
	assert_not_null(fx)

	fx._process(1.0)
	assert_eq(fx._stage, 0, "undamaged building shows nothing")

	b.health = 40.0
	fx._process(1.0)
	assert_eq(fx._stage, 2, "40% HP burns at stage 2")
	assert_true(fx._smoke.emitting, "smoke emits while damaged")
	assert_true(fx._fires[0].emitting, "first flame lit at stage 2")
	assert_false(fx._fires[2].emitting, "third flame waits for stage 3")

	b.health = 90.0   # repaired
	fx._process(1.0)
	assert_eq(fx._stage, 0, "repair walks the stage back down")
	assert_false(fx._smoke.emitting, "smoke stops once repaired")

func test_construction_sites_do_not_burn() -> void:
	var b: StubBuilding = StubBuilding.new()
	b.health = 10.0   # construction climbs through low HP by design
	b.state = BuildingBase.BuildingState.UNDER_CONSTRUCTION
	add_child_autofree(b)
	BuildingDamageFx.attach(b)
	var fx: BuildingDamageFx = _fx_of(b)
	fx._process(1.0)
	assert_eq(fx._stage, 0, "an unfinished building never smokes")

func test_attach_is_idempotent() -> void:
	var b: StubBuilding = StubBuilding.new()
	add_child_autofree(b)
	BuildingDamageFx.attach(b)
	BuildingDamageFx.attach(b)
	var count: int = 0
	for child: Node in b.get_children():
		if child is BuildingDamageFx:
			count += 1
	assert_eq(count, 1)


# ---------------------------------------------------------------------------
# 3. Watch tower auto-attack (the empty-group regression)
# ---------------------------------------------------------------------------

class StubEnemy extends Node2D:
	var player_id: int = 1
	func take_damage(_amount: float, _source: Node = null) -> void:
		pass

func test_units_join_the_units_group() -> void:
	var unit: Node2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(unit)
	assert_true(unit.is_in_group("units"),
		"UnitBase must join 'units' — towers, the Menceyes aura and hero abilities scan it")

func test_tower_fires_an_arrow_at_an_enemy_in_range() -> void:
	var holder: Node2D = Node2D.new()
	add_child_autofree(holder)
	var tower: WatchTower = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene).instantiate() as WatchTower
	tower.player_id = 0
	holder.add_child(tower)
	tower.force_complete()
	var enemy: StubEnemy = StubEnemy.new()
	holder.add_child(enemy)
	enemy.global_position = tower.global_position + Vector2(150.0, 0.0)
	enemy.add_to_group("units")

	tower._physics_process(WatchTower.ATTACK_INTERVAL + 0.01)

	var arrow: Arrow = null
	for child: Node in holder.get_children():
		if child is Arrow:
			arrow = child as Arrow
	assert_not_null(arrow, "the tower launches a visible arrow at the enemy")
	if arrow != null:
		assert_gt(arrow.damage, 0.0, "the arrow carries the tower's damage")
		assert_eq(arrow._original_target, enemy)

func test_tower_ignores_enemies_out_of_range() -> void:
	var holder: Node2D = Node2D.new()
	add_child_autofree(holder)
	var tower: WatchTower = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene).instantiate() as WatchTower
	tower.player_id = 0
	holder.add_child(tower)
	tower.force_complete()
	var enemy: StubEnemy = StubEnemy.new()
	holder.add_child(enemy)
	enemy.global_position = tower.global_position + Vector2(WatchTower.ATTACK_RANGE + 100.0, 0.0)
	enemy.add_to_group("units")

	tower._physics_process(WatchTower.ATTACK_INTERVAL + 0.01)

	for child: Node in holder.get_children():
		assert_false(child is Arrow, "no arrow beyond ATTACK_RANGE")

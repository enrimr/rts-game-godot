extends GutTest

## The Presa Canario herding contract: the Mill is a food drop-off that breeds
## the dog, the dog's fetch-and-lead machine takes an animal in tow and
## releases it at home (moving the animal's wander origin — that's the whole
## point), the animal frees ITSELF whenever its dog leaves the job, and the
## "herd" verb is answered by dogs alone.

const PID: int = 7
const DOG_PID: int = 8

func _spawn_dog(pid: int = DOG_PID) -> CharacterBody2D:
	var dog: CharacterBody2D = (load("res://scenes/units/presa_canario.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	dog.set("player_id", pid)
	dog.set("civ_id", "canarii")
	add_child_autofree(dog)
	return dog

func _spawn_sheep() -> CharacterBody2D:
	var sheep: CharacterBody2D = (load("res://scenes/units/sheep.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	add_child_autofree(sheep)
	return sheep

func test_mill_registers_drop_off_and_queues_dogs() -> void:
	var mill: Mill = (load("res://scenes/buildings/mill.tscn") as PackedScene)\
		.instantiate() as Mill
	mill.set("player_id", PID)
	add_child_autofree(mill)
	mill.state = BuildingBase.BuildingState.COMPLETE
	mill.construction_complete.emit()
	var registered: bool = false
	for d: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		if d.get_parent() == mill and (d.get("player_id") as int) == PID:
			registered = true
	assert_true(registered, "a complete Mill is a drop-off like the camps")

	ResourceManager.init_player(PID, {"food": 100, "gold": 100})
	var food_before: float = ResourceManager.get_resources(PID).get("food", 0.0) as float
	assert_true(mill.order_train("presa_canario"))
	assert_eq(mill.get_queue().size(), 1)
	assert_almost_eq(ResourceManager.get_resources(PID).get("food", 0.0) as float, food_before - 30.0, 0.01,
		"the dog is paid at enqueue")
	mill.order_cancel_train(0)
	assert_eq(mill.get_queue().size(), 0)
	assert_almost_eq(ResourceManager.get_resources(PID).get("food", 0.0) as float, food_before, 0.01,
		"cancel refunds in full")

func test_dog_fetches_and_leads_the_animal_home() -> void:
	var dog: CharacterBody2D = _spawn_dog()
	var sheep: CharacterBody2D = _spawn_sheep()
	dog.global_position = Vector2(0, 0)
	sheep.global_position = Vector2(300, 0)
	dog.call("order_herd", sheep)
	assert_eq(dog.get("herd_target"), sheep)
	assert_eq(dog.get("current_state") as int, UnitBase.UnitState.ATTACKING)
	var home: Vector2 = dog.get("_home") as Vector2
	assert_almost_eq(home.x, 0.0, 0.01, "no own drop-off around: home is the start point")

	# Fetch: still far, the sheep is untouched.
	dog.call("_handle_herding")
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.WILD)

	# Arrive at the animal: it goes in tow.
	dog.global_position = sheep.global_position + Vector2(10, 0)
	dog.call("_handle_herding")
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.HERDED,
		"within reach the dog takes it in tow")

	# Lead home and release: the animal's wander origin moves to the base.
	dog.global_position = home
	sheep.global_position = home + Vector2(20, 0)
	dog.call("_handle_herding")
	assert_eq(dog.get("current_state") as int, UnitBase.UnitState.IDLE)
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.WILD,
		"an unconverted animal reverts to WILD at release")
	assert_almost_eq((sheep.get("_origin") as Vector2).x, sheep.global_position.x, 0.01,
		"released at the base, it now wanders THERE — huntable at home")

func test_animal_frees_itself_when_its_dog_leaves_the_job() -> void:
	var dog: CharacterBody2D = _spawn_dog()
	var sheep: CharacterBody2D = _spawn_sheep()
	var decoy: CharacterBody2D = _spawn_sheep()
	dog.global_position = Vector2(0, 0)
	sheep.global_position = Vector2(10, 0)
	decoy.global_position = Vector2(400, 0)
	dog.call("order_herd", sheep)
	dog.call("_handle_herding")
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.HERDED)
	# The dog is sent after another animal — the first one notices herd-side.
	dog.call("order_herd", decoy)
	sheep.call("_handle_herded")
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.WILD,
		"no dog on the job, no tow")

func test_herded_sheep_converting_mid_trip_lands_owned() -> void:
	var dog: CharacterBody2D = _spawn_dog()
	var sheep: CharacterBody2D = _spawn_sheep()
	dog.global_position = Vector2(0, 0)
	sheep.global_position = Vector2(10, 0)
	dog.call("order_herd", sheep)
	dog.call("_handle_herding")
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.HERDED)
	sheep.call("_try_convert", DOG_PID)
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.HERDED,
		"conversion must not break the tow")
	dog.global_position = dog.get("_home") as Vector2
	sheep.global_position = (dog.get("_home") as Vector2) + Vector2(20, 0)
	dog.call("_handle_herding")
	assert_eq(sheep.get("current_state") as int, Animal.AnimalState.OWNED,
		"released as part of the flock")
	assert_eq(sheep.get("player_id") as int, DOG_PID)

func test_herd_verb_is_answered_by_dogs_alone() -> void:
	var dog: CharacterBody2D = _spawn_dog(PID)
	var soldier: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene)\
		.instantiate() as CharacterBody2D
	soldier.set("player_id", PID)
	add_child_autofree(soldier)
	var sheep: CharacterBody2D = _spawn_sheep()
	sheep.global_position = Vector2(200, 0)
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var ids: Array[int] = [EntityRegistry.id_of(dog), EntityRegistry.id_of(soldier)]
	var cmd: UnitTargetCommand = UnitTargetCommand.make(PID, "herd", ids,
		EntityRegistry.id_of(sheep))
	cmd.execute(world)
	assert_eq(dog.get("herd_target"), sheep, "the dog took the order")
	assert_ne(soldier.get("current_state") as int, UnitBase.UnitState.ATTACKING,
		"the soldier ignored a verb that is not his")

func test_the_shepherds_yield_pays_for_net_approach() -> void:
	ResourceManager.init_player(DOG_PID, {"food": 0})
	var dog: CharacterBody2D = _spawn_dog()
	var sheep: CharacterBody2D = _spawn_sheep()
	dog.global_position = Vector2.ZERO
	sheep.global_position = Vector2(400, 0)
	dog.call("order_herd", sheep)   # home = start point (no own drop-off)
	dog.global_position = Vector2(390, 0)
	dog.call("_handle_herding")     # tow taken 400 px from home
	dog.global_position = Vector2.ZERO
	sheep.global_position = Vector2(20, 0)
	dog.call("_handle_herding")     # released 20 px from home
	assert_almost_eq(ResourceManager.get_resources(DOG_PID).get("food", 0.0) as float,
		9.0, 0.01, "380 px of net approach at 1 food / 40 px")

func test_shuttling_a_sheep_in_circles_pays_nothing() -> void:
	ResourceManager.init_player(DOG_PID, {"food": 0})
	var dog: CharacterBody2D = _spawn_dog()
	var sheep: CharacterBody2D = _spawn_sheep()
	dog.global_position = Vector2.ZERO
	sheep.global_position = Vector2(10, 0)
	dog.call("order_herd", sheep)
	dog.call("_handle_herding")     # tow taken right at home
	dog.call("_handle_herding")     # and released right there
	assert_almost_eq(ResourceManager.get_resources(DOG_PID).get("food", 0.0) as float,
		0.0, 0.01, "no approach, no pay — the yield can't be farmed in place")

func test_dog_faces_the_animal_he_was_sent_at() -> void:
	var dog: CharacterBody2D = _spawn_dog()
	var sheep: CharacterBody2D = _spawn_sheep()
	dog.global_position = Vector2.ZERO
	sheep.global_position = Vector2(-300, 300)
	dog.call("order_herd", sheep)
	dog.call("_animate_body", 0.016)
	var expected: float = -1.0 \
		if IsoProjection.world_to_screen(sheep.global_position - dog.global_position).x < 0.0 \
		else 1.0
	assert_eq((dog.get_node("Body") as Node2D).scale.x, expected,
		"the rig flips toward the herd target — he used to stare one way forever")

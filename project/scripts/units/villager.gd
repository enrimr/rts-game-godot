extends UnitBase

class_name Villager

## Villager — gathers resources and constructs buildings.

enum GatherTarget { NONE, FOOD_HUNT, FOOD_FARM, FOOD_FISH, WOOD, GOLD, STONE }

var gather_target: Node = null
var gather_type: GatherTarget = GatherTarget.NONE
var carried_amount: float = 0.0
var carried_resource: String = ""

const CARRY_CAPACITY: float = 10.0
const GATHER_INTERVAL: float = 1.0

var _gather_timer: float = 0.0

func _physics_process(delta: float) -> void:
	match current_state:
		UnitState.MOVING:
			_handle_movement()
		UnitState.GATHERING:
			_handle_gathering(delta)
		UnitState.BUILDING:
			pass  # handled by build task

func gather(target: Node, resource_type: String) -> void:
	gather_target = target
	carried_resource = resource_type
	current_state = UnitState.GATHERING
	move_to(target.global_position)

func _handle_movement() -> void:
	if nav_agent.is_navigation_finished():
		current_state = UnitState.IDLE
		return
	velocity = nav_agent.get_next_path_position() - global_position
	velocity = velocity.normalized() * unit_data.move_speed
	move_and_slide()

func _handle_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		current_state = UnitState.IDLE
		return
	_gather_timer += delta
	if _gather_timer >= GATHER_INTERVAL:
		_gather_timer = 0.0
		var amount: float = minf(gather_target.gather(1.0), CARRY_CAPACITY - carried_amount)
		carried_amount += amount
		if carried_amount >= CARRY_CAPACITY:
			_return_resources()

func _return_resources() -> void:
	ResourceManager.add_resource(player_id, carried_resource, carried_amount)
	carried_amount = 0.0

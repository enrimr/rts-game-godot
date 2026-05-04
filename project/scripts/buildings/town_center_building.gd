extends StaticBody2D

class_name TownCenterBuilding

var player_id: int = 0
var health: float = 2000.0
var max_health: float = 2000.0

@onready var _health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var _drop_off: Node = get_node_or_null("DropOff")

func _ready() -> void:
	pass

func take_damage(amount: float, _source: Node = null) -> void:
	health -= amount
	if is_instance_valid(_health_bar):
		_health_bar.value = (health / max_health) * 100.0
	if health <= 0.0:
		EventBus.building_destroyed.emit(self, player_id)
		queue_free()

func get_drop_off_node() -> Node:
	return _drop_off

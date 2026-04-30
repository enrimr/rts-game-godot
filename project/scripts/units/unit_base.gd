extends CharacterBody2D

class_name UnitBase

## Base class for all controllable units.

enum UnitState { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, DEAD }

@export var unit_data: UnitResource

var player_id: int = 0
var current_state: UnitState = UnitState.IDLE
var health: float = 0.0
var is_selected: bool = false

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var selection_indicator: Node2D = $SelectionIndicator

func _ready() -> void:
	if unit_data:
		health = unit_data.max_health

func set_selected(value: bool) -> void:
	is_selected = value
	selection_indicator.visible = value

func move_to(target_position: Vector2) -> void:
	nav_agent.target_position = target_position
	current_state = UnitState.MOVING

func take_damage(amount: float, source: Node = null) -> void:
	health -= amount
	EventBus.damage_dealt.emit(self, amount, source)
	health_bar.value = health / unit_data.max_health * 100.0
	if health <= 0.0:
		die()

func die() -> void:
	current_state = UnitState.DEAD
	EventBus.unit_died.emit(self, player_id)
	queue_free()

class_name ActionButton
extends Button

signal action_pressed(action_id: String)

@export var action_id: String = ""

func _ready() -> void:
	pressed.connect(func() -> void: action_pressed.emit(action_id))
	custom_minimum_size = Vector2(60.0, 44.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 10)
	focus_mode = FOCUS_NONE

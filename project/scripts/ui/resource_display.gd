class_name ResourceDisplay
extends HBoxContainer

@export var resource_name: String = "food"
@export var icon_text: String = "?"

@onready var _icon_label: Label = $IconLabel
@onready var _amount_label: Label = $AmountLabel

func _ready() -> void:
	_icon_label.text = icon_text
	_amount_label.text = "0"
	_amount_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_icon_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))

func set_amount(value: int) -> void:
	_amount_label.text = str(value)

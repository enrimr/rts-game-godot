class_name ResourceDisplay
extends VBoxContainer

@export var resource_name: String = "food"
@export var icon_text: String = "?"

@onready var _icon_label: Label = $TopRow/IconLabel
@onready var _amount_label: Label = $TopRow/AmountLabel
@onready var _gatherer_label: Label = $GathererLabel

func _ready() -> void:
	_icon_label.text = icon_text
	_amount_label.text = "0"
	_amount_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_icon_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_gatherer_label.text = ""
	_gatherer_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.55, 0.75))

func set_amount(value: int) -> void:
	_amount_label.text = str(value)

func set_gatherer_count(count: int) -> void:
	_gatherer_label.text = "x%d" % count if count > 0 else ""

class_name UnitPortrait
extends PanelContainer

@export var unit_ref: Node

var _name_label: Label
var _hp_bar: ProgressBar

func _ready() -> void:
	custom_minimum_size = Vector2(56.0, 56.0)

	var layout: VBoxContainer = VBoxContainer.new()
	add_child(layout)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 9)
	layout.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.custom_minimum_size = Vector2(0.0, 6.0)
	_hp_bar.show_percentage = false
	layout.add_child(_hp_bar)

func setup(unit: Node) -> void:
	unit_ref = unit

	var display_name: String = "Unit"
	if is_instance_valid(unit):
		var unit_data: Variant = unit.get("unit_data")
		if unit_data != null:
			var name_val: Variant = (unit_data as Resource).get("display_name")
			if name_val != null and not (name_val as String).is_empty():
				display_name = name_val as String

	_name_label.text = display_name.left(6)

	var hp_percent: float = 100.0
	if is_instance_valid(unit):
		var hp_variant: Variant = unit.get("health")
		var hp: float = hp_variant as float if hp_variant != null else 100.0
		var max_hp: float = 100.0
		var unit_data: Variant = unit.get("unit_data")
		if unit_data != null:
			var max_hp_variant: Variant = (unit_data as Resource).get("max_health")
			if max_hp_variant != null:
				max_hp = max_hp_variant as float
		if max_hp > 0.0:
			hp_percent = (hp / max_hp) * 100.0

	_hp_bar.value = hp_percent
	_apply_hp_color(hp_percent)

func set_selected_highlight(is_selected: bool) -> void:
	if is_selected:
		modulate = Color(1.4, 1.4, 0.6)
	else:
		modulate = Color(1.0, 1.0, 1.0)

func _apply_hp_color(hp_percent: float) -> void:
	var bar_color: Color
	if hp_percent > 50.0:
		bar_color = Color(0.2, 0.85, 0.2)
	elif hp_percent > 25.0:
		bar_color = Color(0.9, 0.8, 0.1)
	else:
		bar_color = Color(0.85, 0.15, 0.1)
	_hp_bar.add_theme_color_override("fill_color", bar_color)

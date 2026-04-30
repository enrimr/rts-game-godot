extends Node

## SelectionManager — handles unit/building selection box and groups.

signal selection_changed(selected: Array)

const MAX_SELECTION: int = 40

var selected_units: Array = []
var _selection_groups: Dictionary = {}  # int -> Array

func select(units: Array) -> void:
	_deselect_all()
	for u in units.slice(0, MAX_SELECTION):
		u.set_selected(true)
		selected_units.append(u)
	EventBus.unit_selected.emit(selected_units)
	selection_changed.emit(selected_units)

func add_to_selection(units: Array) -> void:
	for u in units:
		if u not in selected_units and selected_units.size() < MAX_SELECTION:
			u.set_selected(true)
			selected_units.append(u)
	selection_changed.emit(selected_units)

func save_group(group_id: int) -> void:
	_selection_groups[group_id] = selected_units.duplicate()

func recall_group(group_id: int) -> void:
	if _selection_groups.has(group_id):
		select(_selection_groups[group_id])

func _deselect_all() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.set_selected(false)
	selected_units.clear()

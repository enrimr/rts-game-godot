extends Node

## SelectionManager — handles unit/building selection box and groups.

signal selection_changed(selected: Array)
signal groups_changed()

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
	if selected_units.is_empty():
		_selection_groups.erase(group_id)
	else:
		_selection_groups[group_id] = selected_units.duplicate()
	groups_changed.emit()

func recall_group(group_id: int) -> void:
	var members: Array = get_group(group_id)
	if not members.is_empty():
		select(members)

## Live members of a group: dead/freed units are pruned in place and an
## emptied group is unassigned (its chip disappears).
func get_group(group_id: int) -> Array:
	if not _selection_groups.has(group_id):
		return []
	var members: Array = _selection_groups[group_id]
	var pruned: Array = members.filter(_is_alive)
	if pruned.size() != members.size():
		if pruned.is_empty():
			_selection_groups.erase(group_id)
		else:
			_selection_groups[group_id] = pruned
		groups_changed.emit()
	return pruned.duplicate()

func get_assigned_group_ids() -> Array[int]:
	var ids: Array[int] = []
	for group_id: int in _selection_groups.keys():
		if not get_group(group_id).is_empty():
			ids.append(group_id)
	ids.sort()
	return ids

func _is_alive(u: Variant) -> bool:
	# Validity first: `as` on an already-freed object raises an engine error.
	if not is_instance_valid(u):
		return false
	var node: Node = u as Node
	if node == null or node.is_queued_for_deletion():
		return false
	var state: Variant = node.get("current_state")
	return state == null or (state as int) != UnitBase.UnitState.DEAD

func _deselect_all() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.set_selected(false)
	selected_units.clear()

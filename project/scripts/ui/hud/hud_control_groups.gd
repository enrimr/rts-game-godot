class_name HudControlGroups
extends Node

## Control-group chips row, bottom-left just above the command bar. One chip
## per assigned group (Ctrl+1..9): the group number, a live unit-count badge
## and the dominant unit type's baked miniature as chip background. Click
## selects the group (same path as pressing its number key); double-click also
## centres the camera on the group's centroid. Chips appear/disappear as
## groups are assigned or emptied; dead units are pruned by SelectionManager.

const REFRESH_INTERVAL: float = 0.5
const CHIP_SIZE: Vector2 = Vector2(48.0, 44.0)
const ROW_LEFT: float = 12.0
## Gap between the row and the top edge of the bottom command bar.
const ROW_GAP: float = 8.0
## Fallback when the BottomBar node is missing (bar is ~175 px at 1080p).
const ROW_BOTTOM_FALLBACK: float = -182.0
const ICON_DIM: Color = Color(1.0, 1.0, 1.0, 0.8)

var local_player_id: int = 0

var _hud_root: Control = null
var _row: HBoxContainer = null
var _chips: Dictionary = {}       # group_id -> Button
var _chip_icons: Dictionary = {}  # group_id -> String (baked scene path)
var _refresh_timer: float = 0.0

func init(player_id: int, hud_root: Control) -> void:
	local_player_id = player_id
	_hud_root = hud_root

func _ready() -> void:
	if _hud_root == null:
		set_process(false)
		return
	_build_row()
	SelectionManager.groups_changed.connect(_refresh)

func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh()

func _build_row() -> void:
	_row = HBoxContainer.new()
	_row.name = "ControlGroupChips"
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_row.add_theme_constant_override("separation", 6)
	_row.anchor_left = 0.0
	_row.anchor_right = 0.0
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.offset_left = ROW_LEFT
	_row.offset_right = ROW_LEFT + (CHIP_SIZE.x + 6.0) * 9.0
	_hud_root.add_child(_row)
	_reposition()

## The command bar is a PanelContainer that grows with its content (and with
## resolution), so the row tracks its live top edge instead of a fixed offset.
func _reposition() -> void:
	var bar: Control = _hud_root.get_node_or_null("BottomBar") as Control
	var row_bottom: float = -(bar.size.y + ROW_GAP) if bar != null else ROW_BOTTOM_FALLBACK
	_row.offset_top = row_bottom - CHIP_SIZE.y
	_row.offset_bottom = row_bottom

func _refresh() -> void:
	if not is_instance_valid(_row):
		return
	var ids: Array[int] = SelectionManager.get_assigned_group_ids()
	for stale_id: int in _chips.keys():
		if stale_id not in ids:
			var chip: Button = _chips[stale_id] as Button
			if is_instance_valid(chip):
				chip.queue_free()
			_chips.erase(stale_id)
			_chip_icons.erase(stale_id)
	for group_id: int in ids:
		var members: Array = SelectionManager.get_group(group_id)
		if members.is_empty():
			continue
		if not _chips.has(group_id):
			_chips[group_id] = _make_chip(group_id)
		_update_chip(group_id, members)
	_sort_chips()

func _make_chip(group_id: int) -> Button:
	var chip: Button = Button.new()
	chip.name = "GroupChip%d" % group_id
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = CHIP_SIZE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.add_theme_stylebox_override("normal",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "normal"))
	chip.add_theme_stylebox_override("hover",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "hover"))
	chip.add_theme_stylebox_override("pressed",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "pressed"))
	chip.pressed.connect(_on_chip_pressed.bind(group_id))
	chip.gui_input.connect(_on_chip_gui_input.bind(group_id))

	var icon: TextureRect = TextureRect.new()
	icon.name = "TypeIcon"
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3.0
	icon.offset_top = 3.0
	icon.offset_right = -3.0
	icon.offset_bottom = -5.0
	icon.modulate = ICON_DIM
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)

	var number: Label = Label.new()
	number.name = "GroupNumber"
	number.text = str(group_id)
	number.add_theme_font_size_override("font_size", 15)
	number.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	HudStyle.add_text_outline(number, 4)
	number.position = Vector2(4.0, 1.0)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(number)

	var count: Label = Label.new()
	count.name = "UnitCount"
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	HudStyle.add_text_outline(count, 3)
	count.anchor_left = 1.0
	count.anchor_right = 1.0
	count.anchor_top = 1.0
	count.anchor_bottom = 1.0
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.offset_right = -4.0
	count.offset_bottom = -2.0
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(count)

	_row.add_child(chip)
	return chip

func _update_chip(group_id: int, members: Array) -> void:
	var chip: Button = _chips[group_id] as Button
	if not is_instance_valid(chip):
		return
	var count: Label = chip.get_node("UnitCount") as Label
	count.text = str(members.size())
	chip.tooltip_text = "%s %d (%d)" % [tr("UI_CONTROL_GROUP") \
		if tr("UI_CONTROL_GROUP") != "UI_CONTROL_GROUP" else "Group", group_id, members.size()]
	var rep: Node = _dominant_member(members)
	if rep == null:
		return
	# Heroes share the militia rig's scene path, so the cache key must carry
	# the hero identity or a hero chip would keep a plain-militia icon.
	var icon_key: String = str(rep.call("data_source_path")) \
		if rep is HeroUnit else rep.scene_file_path
	if icon_key.is_empty() or _chip_icons.get(group_id, "") == icon_key:
		return
	_chip_icons[group_id] = icon_key
	(chip.get_node("TypeIcon") as TextureRect).texture = \
		IconBaker.get_icon_for(rep, local_player_id)

## Most frequent member: the chip background shows what the group mostly is
## (10 knights + 2 monks reads as a knight chip). Returns a representative
## NODE so hero identity survives the shared-rig scene path.
func _dominant_member(members: Array) -> Node:
	var counts: Dictionary = {}
	var reps: Dictionary = {}
	var best_path: String = ""
	var best_count: int = 0
	for member: Node in members:
		if not is_instance_valid(member):
			continue
		var path: String = member.scene_file_path
		if path.is_empty():
			continue
		counts[path] = (counts.get(path, 0) as int) + 1
		if not reps.has(path) or member is HeroUnit:
			reps[path] = member
		if (counts[path] as int) > best_count:
			best_count = counts[path] as int
			best_path = path
	return reps.get(best_path) as Node if not best_path.is_empty() else null

func _sort_chips() -> void:
	var ids: Array = _chips.keys()
	ids.sort()
	for i: int in range(ids.size()):
		var chip: Button = _chips[ids[i]] as Button
		if is_instance_valid(chip):
			_row.move_child(chip, i)

func _on_chip_pressed(group_id: int) -> void:
	SelectionManager.recall_group(group_id)

func _on_chip_gui_input(event: InputEvent, group_id: int) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click:
		return
	var members: Array = SelectionManager.get_group(group_id)
	if members.is_empty():
		return
	var centroid: Vector2 = Vector2.ZERO
	var counted: int = 0
	for member: Node in members:
		if member is Node2D and is_instance_valid(member):
			centroid += (member as Node2D).global_position
			counted += 1
	if counted == 0:
		return
	centroid /= float(counted)
	var world_nodes: Array[Node] = get_tree().get_nodes_in_group("world")
	if world_nodes.is_empty():
		return
	var world: Node = world_nodes.front() as Node
	if world.has_method("jump_camera_to"):
		world.call("jump_camera_to", centroid)

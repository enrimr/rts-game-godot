extends Control

class_name NotificationDisplay

## Stacking on-screen notifications à-la AoE2.
## Add to HUDRoot; it wires itself to EventBus on _ready.

const MAX_VISIBLE: int = 4
const FADE_IN:  float = 0.20
const FADE_OUT: float = 0.55

# Per-event cooldowns (seconds) to avoid message spam
const CD_UNIT_ATTACK:     float = 6.0
const CD_BUILDING_ATTACK: float = 8.0
const CD_POP_CAP:         float = 10.0

var _cd_unit:     float = 0.0
var _cd_building: float = 0.0
var _cd_pop:      float = 0.0

var _container: VBoxContainer

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# Anchor this node to the bottom of the screen
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Provisional zone; re-anchored above the REAL command bar once it lays
	# out — the bar's height is content-driven (~245 px, not the 175 assumed
	# here before), so the lowest toasts used to sink into it.
	offset_top    = -175.0 - 200.0
	offset_bottom = -175.0 - 12.0
	_reposition_above_bar.call_deferred()

	_container = VBoxContainer.new()
	_container.mouse_filter = MOUSE_FILTER_IGNORE
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.add_theme_constant_override("separation", 6)
	add_child(_container)

	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.age_advance_started.connect(_on_age_advance_started)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	EventBus.building_construction_complete.connect(_on_construction_complete)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.hero_low_hp.connect(_on_hero_low_hp)
	EventBus.ally_message.connect(_on_ally_message)

func _process(delta: float) -> void:
	if _cd_unit     > 0.0: _cd_unit     -= delta
	if _cd_building > 0.0: _cd_building -= delta
	if _cd_pop      > 0.0: _cd_pop      -= delta

func _reposition_above_bar() -> void:
	var bar: Control = get_node_or_null("../BottomBar") as Control
	var bar_h: float = bar.size.y if bar != null and bar.size.y > 0.0 else 175.0
	offset_bottom = -(bar_h + 12.0)
	offset_top    = offset_bottom - 200.0

# --- Public ---

## Attack/loss toasts carry the event's world position: clicking them jumps
## the camera there (world_pos = null keeps the toast click-through) and they
## show an explicit shortcut button for the same jump — the click affordance
## used to be invisible. `action` ({icon, tooltip, callback}) puts a custom
## shortcut button on any toast (build a house on pop cap, locate the hero…).
func push(text: String, color: Color = Color.WHITE, hold: float = 4.0,
		world_pos: Variant = null, action: Dictionary = {}) -> void:
	if _container.get_child_count() >= MAX_VISIBLE:
		return

	if action.is_empty() and world_pos is Vector2:
		action = {
			"icon": "follow",
			"tooltip": tr("NOTIF_ACTION_GO"),
			"callback": _jump_camera.bind(world_pos as Vector2),
		}

	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	if world_pos is Vector2:
		panel.mouse_filter = MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(_on_toast_gui_input.bind(world_pos as Vector2))
	elif not action.is_empty():
		panel.mouse_filter = MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.04, 0.78)
	style.corner_radius_top_left    = 4
	style.corner_radius_top_right   = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 20.0
	style.content_margin_right  = 20.0
	style.content_margin_top    = 5.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var lbl: Label = Label.new()
	lbl.text = text
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	row.add_child(lbl)

	if not action.is_empty():
		row.add_child(_make_action_button(action))

	panel.modulate.a = 0.0
	_container.add_child(panel)

	var tw: Tween = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(hold)
	tw.tween_property(panel, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(panel.queue_free)

## The visible shortcut: a small glyph button in the toast row.
func _make_action_button(action: Dictionary) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(34.0, 28.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = action.get("tooltip", "") as String
	btn.add_child(UiIcons.icon_rect(action.get("icon", "follow") as String, 4.0))
	btn.add_theme_stylebox_override("normal",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "normal"))
	btn.add_theme_stylebox_override("hover",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "hover"))
	btn.add_theme_stylebox_override("pressed",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "pressed"))
	var callback: Callable = action.get("callback", Callable()) as Callable
	btn.pressed.connect(func() -> void:
		if callback.is_valid():
			callback.call())
	return btn

# --- Signal handlers ---

func _on_unit_attacked(_attacker: Node, target: Node) -> void:
	if not is_instance_valid(target):
		return
	var pid: Variant = target.get("player_id")
	if pid == null or (pid as int) != NetworkSession.local_player_id:
		return
	if _cd_unit > 0.0:
		return
	_cd_unit = CD_UNIT_ATTACK
	push(tr("NOTIF_UNIT_ATTACK"), Color(1.0, 0.38, 0.28), 4.0,
		(target as Node2D).global_position if target is Node2D else null)

func _on_damage_dealt(target: Node, _amount: float, source: Node) -> void:
	# Only interested in player 0 buildings being hit by enemies
	if not is_instance_valid(target) or not is_instance_valid(source):
		return
	var t_pid: Variant = target.get("player_id")
	if t_pid == null or (t_pid as int) != NetworkSession.local_player_id:
		return
	# Must be a building (has no unit_data)
	if target.get("unit_data") != null:
		return
	var s_pid: Variant = source.get("player_id")
	if s_pid == null or (s_pid as int) == NetworkSession.local_player_id:
		return
	if _cd_building > 0.0:
		return
	_cd_building = CD_BUILDING_ATTACK
	push(tr("NOTIF_BUILDING_ATTACK"), Color(1.0, 0.55, 0.20), 4.0,
		(target as Node2D).global_position if target is Node2D else null)

func _age_name(age: int) -> String:
	return tr(["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"][clampi(age, 0, 3)])

func _on_age_advance_started(player_id: int, target_age: int) -> void:
	if player_id != NetworkSession.local_player_id:
		return
	var name: String = _age_name(target_age)
	push(tr("NOTIF_AGE_ADVANCING") % name, Color(0.95, 0.85, 0.40), 5.0)

func _on_age_advance_complete(player_id: int, new_age: int) -> void:
	if player_id != NetworkSession.local_player_id:
		return
	AudioManager.play("age_complete")
	var name: String = _age_name(new_age)
	push(tr("NOTIF_AGE_COMPLETE") % name, Color(1.0, 0.92, 0.30), 6.0)

func _on_construction_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid == null or (pid as int) != NetworkSession.local_player_id:
		return
	var bname: String = _building_name(building)
	push(tr("NOTIF_BUILDING_BUILT") % bname, Color(0.60, 0.95, 0.60), 4.0,
		(building as Node2D).global_position if building is Node2D else null)

func _on_building_destroyed(building: Node, owner_id: int) -> void:
	var bname: String = _building_name(building)
	if owner_id == NetworkSession.local_player_id:
		var pos: Variant = (building as Node2D).global_position \
			if building is Node2D and is_instance_valid(building) else null
		push(tr("NOTIF_BUILDING_DESTROYED_PLAYER") % bname, Color(1.0, 0.25, 0.25), 5.0, pos)
	else:
		var epos: Variant = (building as Node2D).global_position \
			if building is Node2D and is_instance_valid(building) else null
		push(tr("NOTIF_BUILDING_DESTROYED_ENEMY"), Color(0.60, 0.95, 0.60), 4.0, epos)

func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id != NetworkSession.local_player_id:
		return
	if current < cap:
		return
	if _cd_pop > 0.0:
		return
	_cd_pop = CD_POP_CAP
	AudioManager.play("pop_cap")
	# The classic reflex to a pop-cap warning, one click away.
	push(tr("NOTIF_POP_CAP"), Color(1.0, 0.70, 0.25), 4.0, null, {
		"icon": "build",
		"tooltip": tr("NOTIF_ACTION_BUILD_HOUSE"),
		"callback": _start_house_placement,
	})

func _on_ally_message(player_id: int, kind: String) -> void:
	if player_id == NetworkSession.local_player_id \
			or not GameManager.are_allied(player_id, NetworkSession.local_player_id):
		return
	var who: String = NetworkSession.display_name_of(player_id)
	match kind:
		"assist":
			push(tr("NOTIF_ALLY_ASSIST") % who, Color(0.55, 0.85, 1.0), 5.0)
		"attack":
			push(tr("NOTIF_ALLY_ATTACK") % who, Color(0.55, 0.85, 1.0), 5.0)

func _on_hero_low_hp(player_id: int) -> void:
	if player_id != NetworkSession.local_player_id:
		return
	AudioManager.play("hero_low_hp")
	push(tr("NOTIF_HERO_LOW_HP"), Color(1.0, 0.20, 0.20), 6.0, null, {
		"icon": "locate_hero",
		"tooltip": tr("UI_LOCATE_HERO"),
		"callback": _locate_hero,
	})

# --- Helpers ---

func _on_toast_gui_input(event: InputEvent, world_pos: Vector2) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_jump_camera(world_pos)

func _world() -> Node:
	var world_nodes: Array[Node] = get_tree().get_nodes_in_group("world")
	return world_nodes.front() as Node if not world_nodes.is_empty() else null

func _jump_camera(world_pos: Vector2) -> void:
	var world: Node = _world()
	if world != null and world.has_method("jump_camera_to"):
		world.call("jump_camera_to", world_pos)

func _start_house_placement() -> void:
	var world: Node = _world()
	if world != null and world.has_method("_start_placement"):
		world.call("_start_placement", "house")

func _locate_hero() -> void:
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if unit is HeroUnit and is_instance_valid(unit) \
				and (unit.get("player_id") as int) == NetworkSession.local_player_id:
			SelectionManager.select([unit])
			_jump_camera((unit as Node2D).global_position)
			return

func _building_name(building: Node) -> String:
	if building is Wonder:
		return tr("ACTION_WONDER").split("\n")[0]
	var bdata: Variant = building.get("building_data")
	if bdata != null:
		var dname: String = EntityNames.building_name(bdata as Resource)
		if not dname.is_empty():
			return dname
	# Fallback: use the node name, stripping trailing digits Godot adds
	var n: String = building.name
	return n.rstrip("0123456789")

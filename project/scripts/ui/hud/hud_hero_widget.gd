class_name HudHeroWidget
extends Node

## Persistent Regicide hero-status widget, top-left under the resource bar:
## the hero's baked miniature, name and a live HP bar. Turns into a lit red
## alert frame when EventBus.hero_low_hp fires and dims while the hero is
## down awaiting the Town Center respawn. Clicking selects the hero and
## centres the camera on them. Hidden entirely in non-Regicide matches.

const REFRESH_INTERVAL: float = 0.5
## The low-HP alert clears once the hero has healed back above this fraction
## (slightly over the 0.25 emit threshold so the frame does not flicker).
const ALERT_CLEAR_FRACTION: float = 0.3
## Heroes are militia-scene instances with a swapped script, so the miniature
## bakes the militia scene in the player's civilization style.
const HERO_ICON_SCENE: String = "res://scenes/units/militia.tscn"
const ALERT_ACCENT: Color = Color(0.92, 0.18, 0.12)
const DEAD_TINT: Color = Color(0.55, 0.55, 0.55)

var local_player_id: int = 0

var _hud_root: Control = null
var _root: Button = null
var _icon: TextureRect = null
var _name_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_fill: StyleBoxFlat = null
var _hero: Node = null
var _alert: bool = false
var _hero_dead: bool = false
var _refresh_timer: float = 0.0

func init(player_id: int, hud_root: Control) -> void:
	local_player_id = player_id
	_hud_root = hud_root

func _ready() -> void:
	if MatchConfig.victory_mode != MatchConfig.VictoryMode.REGICIDE:
		set_process(false)
		return
	_build_widget()
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.hero_died.connect(_on_hero_died)
	EventBus.hero_respawned.connect(_on_hero_respawned)
	EventBus.hero_low_hp.connect(_on_hero_low_hp)

func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh()

func _build_widget() -> void:
	if _hud_root == null:
		return
	_root = Button.new()
	_root.focus_mode = Control.FOCUS_NONE
	_root.anchor_left = 0.0
	_root.anchor_top = 0.0
	_root.anchor_right = 0.0
	_root.anchor_bottom = 0.0
	_root.offset_left = 8.0
	_root.offset_top = 54.0
	_root.offset_right = 188.0
	_root.offset_bottom = 108.0
	_root.tooltip_text = tr("UI_HERO_WIDGET_TOOLTIP") if tr("UI_HERO_WIDGET_TOOLTIP") != "UI_HERO_WIDGET_TOOLTIP" else "Hero (click to view)"
	_root.pressed.connect(_on_pressed)
	_hud_root.add_child(_root)

	_icon = TextureRect.new()
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.position = Vector2(5.0, 5.0)
	_icon.size = Vector2(44.0, 44.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_icon)
	# Deferred: baking during _ready would add the offscreen viewport while the
	# scene tree root is still setting up its children.
	call_deferred("_bake_icon")

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	HudStyle.add_text_outline(_name_label, 3)
	_name_label.text = tr("UI_HERO") if tr("UI_HERO") != "UI_HERO" else "Hero"
	_name_label.position = Vector2(56.0, 6.0)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.show_percentage = false
	_hp_bar.anchor_left = 0.0
	_hp_bar.anchor_top = 0.0
	_hp_bar.anchor_right = 1.0
	_hp_bar.anchor_bottom = 0.0
	_hp_bar.offset_left = 56.0
	_hp_bar.offset_top = 30.0
	_hp_bar.offset_right = -8.0
	_hp_bar.offset_bottom = 42.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var well: StyleBoxFlat = HudStyle.panel(Color(0.05, 0.04, 0.03, 0.95), 3)
	_hp_bar.add_theme_stylebox_override("background", well)
	_hp_fill = HudStyle.panel(Color(0.30, 0.70, 0.25), 3)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	_root.add_child(_hp_bar)
	_restyle()

func _bake_icon() -> void:
	if is_instance_valid(_icon):
		_icon.texture = IconBaker.get_icon(HERO_ICON_SCENE, local_player_id)

func _restyle() -> void:
	if not is_instance_valid(_root):
		return
	var accent: Color = ALERT_ACCENT if _alert else HudStyle.ACCENT_COMBAT
	var normal: StyleBoxFlat = HudStyle.command_button(accent, "active" if _alert else "normal")
	if _alert:
		normal.bg_color = Color(0.28, 0.07, 0.05, 0.97)
	_root.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = HudStyle.command_button(accent, "active" if _alert else "hover")
	if _alert:
		hover.bg_color = Color(0.36, 0.10, 0.07, 0.97)
	_root.add_theme_stylebox_override("hover", hover)
	_root.add_theme_stylebox_override("pressed", HudStyle.command_button(accent, "pressed"))
	_root.modulate = DEAD_TINT if _hero_dead else Color.WHITE

func _refresh() -> void:
	if not is_instance_valid(_root):
		return
	if not is_instance_valid(_hero):
		_hero = _find_hero()
	if _hero_dead or not is_instance_valid(_hero):
		_hp_bar.value = 0.0
		return
	var data: UnitResource = _hero.get("unit_data") as UnitResource
	if data != null:
		_name_label.text = data.display_name
	var fraction: float = _hero_hp_fraction(data)
	_hp_bar.value = fraction * 100.0
	_hp_fill.bg_color = Color(0.30, 0.70, 0.25) if fraction > 0.5 \
		else (Color(0.85, 0.65, 0.15) if fraction > 0.25 else Color(0.85, 0.20, 0.12))
	if _alert and fraction >= ALERT_CLEAR_FRACTION:
		_alert = false
		_restyle()

func _hero_hp_fraction(data: UnitResource) -> float:
	if data == null:
		return 0.0
	var max_hp: float = data.max_health \
		* CivBonusManager.get_unit_hp_multiplier(local_player_id, data.id)
	if max_hp <= 0.0:
		return 0.0
	var hp_v: Variant = _hero.get("health")
	var hp: float = hp_v as float if hp_v != null else 0.0
	return clampf(hp / max_hp, 0.0, 1.0)

func _find_hero() -> Node:
	var world_nodes: Array[Node] = get_tree().get_nodes_in_group("world")
	if world_nodes.is_empty():
		return null
	var units_layer: Node = (world_nodes.front() as Node).get_node_or_null("UnitsLayer")
	if units_layer == null:
		return null
	for unit: Node in units_layer.get_children():
		if unit is HeroUnit and unit.get("player_id") == local_player_id:
			return unit
	return null

func _on_unit_spawned(unit: Node, player_id: int) -> void:
	if player_id != local_player_id or not (unit is HeroUnit):
		return
	_hero = unit
	_hero_dead = false
	_alert = false
	_restyle()
	_refresh()

func _on_hero_died(player_id: int, _hero_data: UnitResource) -> void:
	if player_id != local_player_id:
		return
	_hero = null
	_hero_dead = true
	_alert = false
	_restyle()
	if is_instance_valid(_hp_bar):
		_hp_bar.value = 0.0

func _on_hero_respawned(player_id: int) -> void:
	if player_id != local_player_id:
		return
	_hero_dead = false
	_restyle()
	_refresh()

func _on_hero_low_hp(player_id: int) -> void:
	if player_id != local_player_id or _hero_dead:
		return
	_alert = true
	_restyle()

func _on_pressed() -> void:
	if _hero_dead or not is_instance_valid(_hero):
		return
	SelectionManager.select([_hero])
	# Manual centring must win over camera-follow of the previous selection.
	EventBus.camera_follow_cancelled.emit()
	var cam: Camera2D = _camera()
	if cam != null:
		cam.position = (_hero as Node2D).global_position

func _camera() -> Camera2D:
	var world_nodes: Array[Node] = get_tree().get_nodes_in_group("world")
	if world_nodes.is_empty():
		return null
	return (world_nodes.front() as Node).get_node_or_null("Camera2D") as Camera2D

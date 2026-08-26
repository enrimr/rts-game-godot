class_name UnitPortrait
extends PanelContainer

@export var unit_ref: Node

var _name_label: Label
var _hp_bar: ProgressBar
var _icon_backdrop: ColorRect
var _icon_rect: TextureRect

func _ready() -> void:
	custom_minimum_size = Vector2(74.0, 74.0)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 2)
	add_child(layout)

	# Baked entity icon over a player-colour backdrop fills most of the portrait
	var icon_holder: Control = Control.new()
	icon_holder.custom_minimum_size = Vector2(0.0, 50.0)
	icon_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(icon_holder)

	_icon_backdrop = ColorRect.new()
	_icon_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_icon_backdrop)

	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_icon_rect)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 11)
	HudStyle.add_text_outline(_name_label, 3)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	var pid: int = 0
	if is_instance_valid(unit):
		var pid_v: Variant = unit.get("player_id")
		if pid_v != null:
			pid = pid_v as int
		var unit_data: Variant = unit.get("unit_data")
		if unit_data != null:
			var name_val: Variant = (unit_data as Resource).get("display_name")
			if name_val != null and not (name_val as String).is_empty():
				display_name = name_val as String

	_icon_backdrop.color = PlayerColors.get_color(pid).darkened(0.55)
	var scene_path: String = unit.scene_file_path if is_instance_valid(unit) else ""
	if not scene_path.is_empty():
		_icon_rect.texture = IconBaker.get_icon(scene_path, pid)
	_name_label.text = display_name.left(8)

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
	# Non-empty tooltip_text triggers _make_custom_tooltip; the string itself is unused.
	tooltip_text = " "

func refresh() -> void:
	if not is_instance_valid(unit_ref):
		return
	var hp_variant: Variant = unit_ref.get("health")
	var hp: float = hp_variant as float if hp_variant != null else 100.0
	var max_hp: float = 100.0
	var unit_data: Variant = unit_ref.get("unit_data")
	if unit_data != null:
		var max_hp_variant: Variant = (unit_data as Resource).get("max_health")
		if max_hp_variant != null:
			max_hp = max_hp_variant as float
	if max_hp > 0.0:
		var pct: float = (hp / max_hp) * 100.0
		_hp_bar.value = pct
		_apply_hp_color(pct)

func _make_custom_tooltip(_for_text: String) -> Object:
	if not is_instance_valid(unit_ref):
		return null
	var bbcode: String = _build_tooltip(unit_ref)
	if bbcode.is_empty():
		return null

	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	style.border_color = Color(0.30, 0.30, 0.45)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left     = 5
	style.corner_radius_top_right    = 5
	style.corner_radius_bottom_left  = 5
	style.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",     8)
	margin.add_theme_constant_override("margin_bottom",  8)
	panel.add_child(margin)

	var rtl: RichTextLabel = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = bbcode
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(180.0, 0.0)
	rtl.add_theme_font_size_override("normal_font_size", 14)
	margin.add_child(rtl)
	return panel

func _build_tooltip(u: Node) -> String:
	if not is_instance_valid(u):
		return ""
	var udata: Variant = u.get("unit_data")
	if udata == null:
		return ""
	var d: UnitResource = udata as UnitResource
	var pid: int = (u.get("player_id") as int) if u.get("player_id") != null else 0
	var uid: String = d.id
	var world_pos: Vector2 = (u as Node2D).global_position if u is Node2D else Vector2.ZERO

	var hp: float = (u.get("health") as float) if u.get("health") != null else d.max_health
	var hp_mult: float = CivBonusManager.get_unit_hp_multiplier(pid, uid)
	var max_hp: float = d.max_health * hp_mult

	var spd_civ: float = CivBonusManager.get_unit_speed_multiplier(pid, uid) \
		* CivBonusManager.get_unit_move_speed_multiplier(pid)
	var spd_weather: float = WeatherManager.get_move_speed_multiplier(world_pos, pid)
	var spd_total: float = spd_civ * spd_weather
	var spd: float = d.move_speed * spd_total

	var atk_mult: float = CivBonusManager.get_unit_attack_multiplier(pid, uid)
	var atk: float = d.attack * atk_mult

	var armor_m: float = d.armor_melee + CivBonusManager.get_unit_armor_bonus(pid)
	var armor_p: float = d.armor_pierce + CivBonusManager.get_archer_armor_pierce_bonus(pid)

	var los_mult: float = WeatherManager.get_vision_multiplier(world_pos, pid)
	var los: float = d.line_of_sight * los_mult

	var b: String = ""
	b += "[b]%s[/b]\n" % d.display_name
	b += "HP: %d / %d%s\n" % [int(hp), int(max_hp), _bonus_bbcode(hp_mult, 1.0)]
	b += "Ataque: %d%s\n" % [int(atk), _bonus_bbcode(atk_mult, 1.0)]
	var armor_delta: float = (armor_m - d.armor_melee) + (armor_p - d.armor_pierce)
	b += "Armadura: %d mel / %d pie%s\n" % [int(armor_m), int(armor_p), _bonus_bbcode_flat(armor_delta)]
	b += "Velocidad: %.1f%s\n" % [spd, _bonus_bbcode(spd_total, 1.0)]
	if d.attack_range > 1.0:
		var rng_mult: float = CivBonusManager.get_archer_range_multiplier(pid)
		var rng_flat: float = CivBonusManager.get_archer_range_flat(pid)
		var rng: float = d.attack_range * rng_mult + rng_flat
		b += "Rango: %.0f px%s\n" % [rng, _bonus_bbcode_flat(rng - d.attack_range)]
	b += "Visión: %.0f px%s" % [los, _bonus_bbcode(los_mult, 1.0)]
	return b

func _bonus_bbcode(mult: float, baseline: float) -> String:
	var diff: float = mult - baseline
	if absf(diff) < 0.01:
		return ""
	var pct: int = int(roundf(diff * 100.0))
	if pct > 0:
		return "  [color=#55dd77]▲+%d%%[/color]" % pct
	return "  [color=#ee5555]▼%d%%[/color]" % pct

func _bonus_bbcode_flat(delta: float) -> String:
	if absf(delta) < 0.5:
		return ""
	var n: int = int(roundf(delta))
	if n > 0:
		return "  [color=#55dd77]▲+%d[/color]" % n
	return "  [color=#ee5555]▼%d[/color]" % n

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

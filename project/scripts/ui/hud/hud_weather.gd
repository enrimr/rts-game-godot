class_name HudWeather
extends Node

## Weather HUD: the big fading announcement banner plus the persistent
## name+countdown pill. Self-contained — wires itself to WeatherManager and
## renders into its parent CanvasLayer. Added as a child of the HUD by HudManager.

const WEATHER_LABELS: Dictionary = {
	"calima":          "☁ Calima",
	"atlantic_storm":  "⛈ Tormenta atlántica",
	"sea_fog":         "🌫 Niebla marina",
	"trade_winds":     "💨 Vientos alisios",
	"volcanic_ash":    "🌋 Ceniza volcánica",
}

const WEATHER_COLORS: Dictionary = {
	"calima":          Color(0.85, 0.62, 0.18),
	"atlantic_storm":  Color(0.35, 0.55, 0.80),
	"sea_fog":         Color(0.70, 0.80, 0.88),
	"trade_winds":     Color(0.55, 0.80, 0.95),
	"volcanic_ash":    Color(0.55, 0.40, 0.30),
}

var _banner: Label = null
var _banner_tween: Tween = null
var _pill: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	WeatherManager.weather_changed.connect(_on_weather_changed)
	WeatherManager.weather_cleared.connect(hide_weather)
	WeatherManager.weather_incoming.connect(_on_weather_incoming)

func _process(_delta: float) -> void:
	_update_pill()

func _on_weather_changed(weather_id: String, _intensity: float) -> void:
	if weather_id != "clear":
		show_weather(weather_id)

## Pre-arrival warning so the player can react (reposition, rush the fleet…).
func _on_weather_incoming(weather_id: String, seconds_until: float) -> void:
	var name_text: String = WEATHER_LABELS.get(weather_id, weather_id) as String
	var color: Color = WEATHER_COLORS.get(weather_id, Color.WHITE) as Color
	_show_banner("⚠ " + name_text + tr(" se acerca") + " (%ds)" % int(round(seconds_until)), color.lightened(0.15))

# Full-width fading banner near the top of the screen. Reused by both the
# "incoming" warning and the arrival announcement.
func _show_banner(text: String, color: Color) -> void:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	if not is_instance_valid(_banner):
		_banner = Label.new()
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_banner.add_theme_font_size_override("font_size", 36)
		_banner.modulate.a = 0.0
		get_parent().add_child(_banner)
	_banner.position = Vector2(0.0, 110.0)
	_banner.size = Vector2(vp_w, 60.0)
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if is_instance_valid(_banner_tween):
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.5)
	_banner_tween.tween_interval(3.0)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 1.2)

func show_weather(weather_id: String) -> void:
	var text: String = WEATHER_LABELS.get(weather_id, weather_id) as String
	var color: Color = WEATHER_COLORS.get(weather_id, Color.WHITE) as Color
	_show_banner(text, color)

	# CanvasLayer children must be positioned with absolute px coords, not anchors.
	# Use the actual viewport width so centering works at any resolution.
	var vp_w: float = get_viewport().get_visible_rect().size.x
	# --- persistent pill: just below the top bar (~44 px) ---
	if not is_instance_valid(_pill):
		_pill = Label.new()
		_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pill.add_theme_font_size_override("font_size", 15)
		_pill.modulate.a = 0.0
		get_parent().add_child(_pill)
	_pill.position = Vector2(0.0, 44.0)
	_pill.size = Vector2(vp_w, 22.0)
	_pill.add_theme_color_override("font_color", color)
	var tw: Tween = create_tween()
	tw.tween_property(_pill, "modulate:a", 1.0, 0.8)

func hide_weather() -> void:
	# Banner: kill any pending tween and fade out (it may already be fading)
	if is_instance_valid(_banner):
		if is_instance_valid(_banner_tween):
			_banner_tween.kill()
		var tw_b: Tween = create_tween()
		tw_b.tween_property(_banner, "modulate:a", 0.0, 0.6)
		tw_b.tween_callback(func() -> void:
			if is_instance_valid(_banner):
				_banner.queue_free()
				_banner = null)

	# Pill: fade out then free
	if is_instance_valid(_pill):
		var tw_p: Tween = create_tween()
		tw_p.tween_property(_pill, "modulate:a", 0.0, 1.5)
		tw_p.tween_callback(func() -> void:
			if is_instance_valid(_pill):
				_pill.queue_free()
				_pill = null)

func _update_pill() -> void:
	if not is_instance_valid(_pill):
		return
	var secs: float = WeatherManager.get_remaining_seconds()
	if secs <= 0.0:
		return
	var mins: int = int(secs) / 60
	var s: int = int(secs) % 60
	var name_text: String = WEATHER_LABELS.get(WeatherManager.get_weather_id(), "") as String
	_pill.text = "%s  %d:%02d" % [name_text, mins, s]

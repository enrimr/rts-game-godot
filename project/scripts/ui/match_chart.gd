class_name MatchChart
extends Control

## Renders a single line, step, or bar chart for post-game statistics.

enum Mode { LINES, STEPS, BARS }

var mode: Mode = Mode.LINES
var series_a: Array = []         # Array of float — player (blue)
var series_b: Array = []         # Array of float — first rival (red, legacy)
var spikes_a: Array = []         # snapshot indices where player launched an offensive
var spikes_b: Array = []         # snapshot indices where first rival launched an offensive
var color_a: Color = Color(0.40, 0.70, 1.0)
var color_b: Color = Color(1.0,  0.45, 0.45)
var total_time: float = 1.0
var chart_title: String = ""
# Additional rival series: parallel arrays of (Array[float], Color)
var extra_series: Array = []     # Array of Array[float] — one per extra rival
var extra_colors: Array = []     # Array of Color — matching extra_series

const _PL: float = 40.0   # left padding  (y labels)
const _PR: float = 8.0
const _PT: float = 20.0   # top padding   (title row)
const _PB: float = 20.0   # bottom padding (x labels)

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var pw: float = size.x - _PL - _PR
	var ph: float = size.y - _PT - _PB
	if pw <= 0.0 or ph <= 0.0:
		return

	draw_string(font, Vector2(_PL + pw * 0.5, _PT - 5.0), chart_title,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.78, 0.74, 0.52))

	draw_rect(Rect2(_PL, _PT, pw, ph), Color(0.07, 0.07, 0.10))
	draw_rect(Rect2(_PL, _PT, pw, ph), Color(0.22, 0.22, 0.28), false, 1.0)

	var max_v: float = _max_value()

	# Horizontal grid + y-axis labels
	for gi: int in range(1, 5):
		var gy: float = _PT + ph - (gi as float / 4.0) * ph
		draw_line(Vector2(_PL, gy), Vector2(_PL + pw, gy), Color(0.17, 0.17, 0.23), 1.0)
		draw_string(font, Vector2(_PL - 3.0, gy + 4.0),
			_fmt(gi as float / 4.0 * max_v, max_v),
			HORIZONTAL_ALIGNMENT_RIGHT, int(_PL - 3.0), 9, Color(0.46, 0.46, 0.52))

	# Attack offensive bands
	for idx: Variant in spikes_a:
		_draw_band(idx as int, series_a.size(), pw, ph, Color(0.40, 0.70, 1.0, 0.14))
	for idx: Variant in spikes_b:
		_draw_band(idx as int, series_b.size(), pw, ph, Color(1.0, 0.45, 0.45, 0.14))

	match mode:
		Mode.LINES, Mode.STEPS:
			_draw_polyline(series_b, color_b, pw, ph, max_v, false)
			for ei: int in range(extra_series.size()):
				var ecol: Color = extra_colors[ei] as Color if ei < extra_colors.size() else Color(0.6, 0.6, 0.6)
				_draw_polyline(extra_series[ei] as Array, ecol, pw, ph, max_v, false)
			_draw_polyline(series_a, color_a, pw, ph, max_v, mode == Mode.STEPS)
		Mode.BARS:
			_draw_bars(pw, ph, max_v)

	# X-axis time labels
	draw_string(font, Vector2(_PL, _PT + ph + 13.0), "0:00",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.40, 0.40, 0.46))
	var ts: int = int(total_time)
	draw_string(font, Vector2(_PL + pw, _PT + ph + 13.0),
		"%d:%02d" % [ts / 60, ts % 60],
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(0.40, 0.40, 0.46))

func _max_value() -> float:
	var mv: float = 1.0
	for v: Variant in series_a:
		if (v as float) > mv:
			mv = v as float
	for v: Variant in series_b:
		if (v as float) > mv:
			mv = v as float
	for s: Variant in extra_series:
		for v: Variant in (s as Array):
			if (v as float) > mv:
				mv = v as float
	return mv

func _draw_band(idx: int, n: int, pw: float, ph: float, col: Color) -> void:
	if n < 2 or idx < 0 or idx >= n:
		return
	var slot: float = pw / maxf(n - 1, 1)
	var cx: float = _PL + idx * slot
	draw_rect(Rect2(cx - slot * 0.5, _PT, slot, ph), col)

func _draw_polyline(series: Array, col: Color, pw: float, ph: float, max_v: float, steps: bool) -> void:
	var sn: int = series.size()
	if sn < 2:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(sn):
		var fx: float = _PL + (i as float / (sn - 1)) * pw
		var fy: float = _PT + ph - clampf((series[i] as float) / max_v, 0.0, 1.0) * ph
		pts.append(Vector2(fx, fy))
	if not steps:
		draw_polyline(pts, col, 2.0, true)
		return
	var stepped: PackedVector2Array = PackedVector2Array()
	for i: int in range(pts.size()):
		if i > 0:
			stepped.append(Vector2(pts[i].x, stepped[stepped.size() - 1].y))
		stepped.append(pts[i])
	draw_polyline(stepped, col, 2.0, true)

func _draw_bars(pw: float, ph: float, max_v: float) -> void:
	var n: int = maxi(series_a.size(), series_b.size())
	if n < 1:
		return
	var slot: float = pw / n
	var bw: float = slot * 0.38
	for i: int in range(series_a.size()):
		var v: float = series_a[i] as float
		if v > 0.0:
			var bh: float = (v / max_v) * ph
			draw_rect(Rect2(_PL + i * slot + slot * 0.5 - bw, _PT + ph - bh, bw, bh), color_a)
	for i: int in range(series_b.size()):
		var v: float = series_b[i] as float
		if v > 0.0:
			var bh: float = (v / max_v) * ph
			draw_rect(Rect2(_PL + i * slot + slot * 0.5, _PT + ph - bh, bw, bh), color_b)

func _fmt(v: float, max_v: float) -> String:
	if max_v >= 5000.0:
		return "%dk" % [int(v / 1000.0)]
	if max_v >= 1000.0:
		return "%.1fk" % [v / 1000.0]
	return str(int(v))

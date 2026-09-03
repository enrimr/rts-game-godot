extends Control

## Visual review of the technology research glyphs (real renderer): every tech
## id from TECH_GLYPHS plus the unknown-id fallback, each rendered at 32 px and
## 24 px over the HUD button backdrop, labeled with its id.
##   CALIMA_SHOT_DIR=/tmp/calima-glyphs $GODOT --path project \
##     --resolution 1400x900 res://tools/check_tech_glyphs.tscn

const COLS: int = 6
const CELL: Vector2 = Vector2(228.0, 148.0)

var _shot_dir: String = ""

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		_shot_dir = "/tmp/calima-glyphs"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	RenderingServer.set_default_clear_color(Color(0.13, 0.13, 0.15))

	var ids: Array[String] = UiIcons.TECH_GLYPHS.duplicate()
	ids.append("some_future_tech")
	for i: int in range(ids.size()):
		var cell: Control = _make_cell(ids[i])
		cell.position = Vector2(30.0 + float(i % COLS) * CELL.x,
			20.0 + float(i / COLS) * CELL.y)
		add_child(cell)
	_run()

func _make_cell(tech_id: String) -> Control:
	var cell: Control = Control.new()
	var lbl: Label = Label.new()
	lbl.text = tech_id
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = Vector2(0.0, 0.0)
	cell.add_child(lbl)
	var tex: Texture2D = UiIcons.tech_glyph(tech_id)
	for spec: Array in [[96.0, Vector2(0.0, 20.0)], [32.0, Vector2(116.0, 20.0)],
			[24.0, Vector2(116.0, 70.0)]]:
		var px: float = spec[0] as float
		var well: Panel = Panel.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.20, 0.21, 0.24)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		well.add_theme_stylebox_override("panel", style)
		well.position = spec[1] as Vector2
		well.size = Vector2(px + 12.0, px + 12.0)
		cell.add_child(well)
		var rect: TextureRect = TextureRect.new()
		rect.texture = tex
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.position = Vector2(6.0, 6.0)
		rect.size = Vector2(px, px)
		well.add_child(rect)
	return cell

func _run() -> void:
	await get_tree().create_timer(1.2).timeout
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/tech_glyphs.png" % _shot_dir)
	print("CHECK_TECH_GLYPHS: saved tech_glyphs.png")
	get_tree().quit(0)

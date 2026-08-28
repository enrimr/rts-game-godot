class_name TerrainDetail extends RefCounted

## Ground-detail painters: the per-terrain, per-variant decoration scattered on
## top of a base terrain colour (grass clumps, dune ripples, malpais cracks,
## risco rubble, laurel undergrowth, caldera embers) plus the tile-grid stain
## batching every variant draws through.
##
## Detail squares snap to MapMaterials.STAIN_TILE, the same grid the terrain
## shader mottles on, so decals and shader noise read as one tileset. Batching
## keeps a whole patch of hundreds of squares down to one Polygon2D.

var _rng: RandomNumberGenerator = null
var _mat: MapMaterials = null

func setup(rng: RandomNumberGenerator, mat: MapMaterials) -> void:
	_rng = rng
	_mat = mat

# Appends one MapMaterials.STAIN_TILE-grid square to a batched multi-square polygon,
# bridging back through the first point (same degenerate-edge batching used by
# the laurisilva canopies) so hundreds of squares cost one Polygon2D.
func append_tile_square(pts: PackedVector2Array, origin: Vector2) -> void:
	if pts.size() > 0:
		pts.append(pts[0])
	var t: float = MapMaterials.STAIN_TILE
	pts.append(origin)
	pts.append(origin + Vector2(t, 0.0))
	pts.append(origin + Vector2(t, t))
	pts.append(origin + Vector2(0.0, t))
	pts.append(origin)

# Tile-quantised stain: squares snapped to the shader's tile grid, dense at the
# centre and dithering out toward `radius` — the classic RTS tileset dirt patch
# instead of an amorphous soft-alpha blob. Appends into `pts` for batching.
func append_tile_stain(pts: PackedVector2Array, center: Vector2,
		radius: float, coverage: float) -> void:
	var t: float = MapMaterials.STAIN_TILE
	var x: float = floor((center.x - radius) / t) * t
	while x < center.x + radius:
		var y: float = floor((center.y - radius) / t) * t
		while y < center.y + radius:
			var d: float = (Vector2(x, y) + Vector2(t, t) * 0.5).distance_to(center) / maxf(radius, 1.0)
			if d < 1.0 and _rng.randf() < coverage * (1.0 - d * d):
				append_tile_square(pts, Vector2(x, y))
			y += t
		x += t

# Covers the whole map base with overlapping scatter patches so the flat
# background shows terrain variants instead of a single solid colour.
# Patches are large (15–25 % of map_half radius) and laid on a loose grid
# with random offset so every area gets coverage.
func paint_ground_scatter(parent: Node2D, map_half: float,
		terrain: TerrainManager.TerrainType) -> void:
	var patch_r: float = map_half * 0.22
	var step: float = map_half * 0.30
	# Keep centers inset by patch_r so no polygon vertex escapes the map bounds.
	var inner: float = map_half - patch_r
	var x: float = -map_half
	while x <= map_half:
		var y: float = -map_half
		while y <= map_half:
			var jx: float = _rng.randf_range(-step * 0.45, step * 0.45)
			var jy: float = _rng.randf_range(-step * 0.45, step * 0.45)
			var center: Vector2 = Vector2(x + jx, y + jy).clamp(
				Vector2(-inner, -inner), Vector2(inner, inner))
			var v: int = _rng.randi() % 3
			paint_variant(parent, center, patch_r, terrain, v)
			y += step
		x += step

func paint_variant(parent: Node2D, center: Vector2,
		radius: float, terrain: int, variant: int) -> void:
	match terrain:
		TerrainManager.TerrainType.GRASS:
			match variant:
				0: _paint_grass_v0(parent, center, radius)
				1: _paint_grass_v1(parent, center, radius)
				_: _paint_grass_v2(parent, center, radius)
		TerrainManager.TerrainType.DUNE:
			match variant:
				0: _paint_dune_v0(parent, center, radius)
				1: _paint_dune_v1(parent, center, radius)
				_: _paint_dune_v2(parent, center, radius)
		TerrainManager.TerrainType.MALPAIS:
			match variant:
				0: _paint_malpais_detail_v0(parent, center, radius)
				1: _paint_malpais_detail_v1(parent, center, radius)
				_: _paint_malpais_detail_v2(parent, center, radius)
		TerrainManager.TerrainType.RISCO:
			match variant:
				0: _paint_risco_detail_v0(parent, center, radius)
				1: _paint_risco_detail_v1(parent, center, radius)
				_: _paint_risco_detail_v2(parent, center, radius)
		TerrainManager.TerrainType.LAURISILVA:
			match variant:
				0: _paint_laurisilva_detail_v0(parent, center, radius)
				1: _paint_laurisilva_detail_v1(parent, center, radius)
				_: _paint_laurisilva_detail_v2(parent, center, radius)
		TerrainManager.TerrainType.CALDERA:
			match variant:
				0: _paint_caldera_detail_v0(parent, center, radius)
				1: _paint_caldera_detail_v1(parent, center, radius)
				_: _paint_caldera_detail_v2(parent, center, radius)

# Adds one batched multi-square stain polygon (no-op for empty batches).
func add_stain_poly(parent: Node2D, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -7
	poly.polygon = pts
	parent.add_child(poly)

# Grass v0: tile-dithered dark/light clumps + blade strokes. The clumps used to
# be soft-alpha blobs that read as amorphous stains; snapping them to the
# shader's tile grid makes mid-zoom ground read like a tileset.
func _paint_grass_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var blob_count: int = _rng.randi_range(6, 10)
	var light_pts: PackedVector2Array = PackedVector2Array()
	var dark_pts: PackedVector2Array = PackedVector2Array()
	for _gi: int in range(blob_count):
		var ga: float = _rng.randf() * TAU
		var gd: float = _rng.randf_range(0.0, radius * 0.82)
		var gr: float = radius * _rng.randf_range(0.07, 0.16)
		var gpos: Vector2 = center + Vector2(cos(ga), sin(ga)) * gd
		var target: PackedVector2Array = light_pts if _rng.randi() % 3 == 0 else dark_pts
		append_tile_stain(target, gpos, maxf(gr, MapMaterials.STAIN_TILE), 0.85)
	add_stain_poly(parent, light_pts, Color(0.28, 0.52, 0.18, 0.45))
	add_stain_poly(parent, dark_pts, Color(0.16, 0.36, 0.12, 0.55))
	var blade_count: int = _rng.randi_range(12, 20)
	for _bi: int in range(blade_count):
		var ba: float = _rng.randf() * TAU
		var bd: float = _rng.randf_range(0.0, radius * 0.75)
		var bpos: Vector2 = center + Vector2(cos(ba), sin(ba)) * bd
		var blade: Line2D = Line2D.new()
		blade.default_color = Color(0.20, 0.50, 0.14, 0.35)
		blade.width = 1.2
		blade.z_index = -7
		var blade_len: float = _rng.randf_range(radius * 0.025, radius * 0.055)
		var blade_angle: float = _rng.randf_range(-PI * 0.3, PI * 0.3) - PI * 0.5
		blade.add_point(bpos)
		blade.add_point(bpos + Vector2(cos(blade_angle), sin(blade_angle)) * blade_len)
		parent.add_child(blade)

# Grass v1: scattered wildflower dots (tiny coloured circles — white, yellow, violet)
func _paint_grass_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var base_count: int = _rng.randi_range(4, 7)
	var base_pts: PackedVector2Array = PackedVector2Array()
	for _gi: int in range(base_count):
		var ga: float = _rng.randf() * TAU
		var gd: float = _rng.randf_range(0.0, radius * 0.85)
		var gr: float = radius * _rng.randf_range(0.08, 0.18)
		var gpos: Vector2 = center + Vector2(cos(ga), sin(ga)) * gd
		append_tile_stain(base_pts, gpos, maxf(gr, MapMaterials.STAIN_TILE), 0.8)
	add_stain_poly(parent, base_pts, Color(0.14, 0.34, 0.10, 0.50))
	var flower_colors: Array = [
		Color(0.95, 0.95, 0.90, 0.85),
		Color(0.95, 0.85, 0.15, 0.80),
		Color(0.70, 0.40, 0.80, 0.75),
		Color(0.95, 0.45, 0.45, 0.75),
	]
	var flower_count: int = _rng.randi_range(10, 18)
	var all_fpts: PackedVector2Array = PackedVector2Array()
	var cur_col_idx: int = 0
	for _fi: int in range(flower_count):
		var fa: float = _rng.randf() * TAU
		var fd: float = _rng.randf_range(0.0, radius * 0.85)
		var fpos: Vector2 = center + Vector2(cos(fa), sin(fa)) * fd
		var fr: float = _rng.randf_range(radius * 0.012, radius * 0.028)
		if all_fpts.size() > 0:
			all_fpts.append(all_fpts[0])
		for fsi: int in range(6):
			var fsa: float = TAU * fsi / 6.0
			all_fpts.append(fpos + Vector2(cos(fsa), sin(fsa)) * fr)
		cur_col_idx = (cur_col_idx + 1) % flower_colors.size()
	if all_fpts.size() >= 3:
		var fpoly: Polygon2D = Polygon2D.new()
		fpoly.color = flower_colors[_rng.randi() % flower_colors.size()]
		fpoly.z_index = -7
		fpoly.polygon = all_fpts
		parent.add_child(fpoly)

# Grass v2: dry/golden-tint patches — late-summer burnt look, tile-dithered so
# the dry ground reads as tileset patches instead of muddy olive stains.
func _paint_grass_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var patch_count: int = _rng.randi_range(5, 9)
	var gold_pts: PackedVector2Array = PackedVector2Array()
	var olive_pts: PackedVector2Array = PackedVector2Array()
	for _pi: int in range(patch_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.80)
		var pr: float = radius * _rng.randf_range(0.09, 0.20)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var target: PackedVector2Array = gold_pts if _rng.randi() % 2 == 0 else olive_pts
		append_tile_stain(target, ppos, maxf(pr, MapMaterials.STAIN_TILE), 0.8)
	add_stain_poly(parent, gold_pts, Color(0.52, 0.48, 0.18, 0.45))
	add_stain_poly(parent, olive_pts, Color(0.42, 0.38, 0.14, 0.40))
	var blade_count: int = _rng.randi_range(10, 16)
	for _bi: int in range(blade_count):
		var ba: float = _rng.randf() * TAU
		var bd: float = _rng.randf_range(0.0, radius * 0.75)
		var bpos: Vector2 = center + Vector2(cos(ba), sin(ba)) * bd
		var blade: Line2D = Line2D.new()
		blade.default_color = Color(0.55, 0.50, 0.20, 0.38)
		blade.width = 1.2
		blade.z_index = -7
		var blade_len: float = _rng.randf_range(radius * 0.030, radius * 0.060)
		var blade_angle: float = _rng.randf_range(-PI * 0.25, PI * 0.25) - PI * 0.5
		blade.add_point(bpos)
		blade.add_point(bpos + Vector2(cos(blade_angle), sin(blade_angle)) * blade_len)
		parent.add_child(blade)

# Dune v0: sine ripple lines + grain dots (current style)
func _paint_dune_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var ripple_count: int = _rng.randi_range(5, 8)
	for ri: int in range(ripple_count):
		var ry: float = center.y - radius * 0.8 + (radius * 1.6 / float(ripple_count)) * float(ri) \
				+ _rng.randf_range(-radius * 0.06, radius * 0.06)
		var line: Line2D = Line2D.new()
		line.default_color = Color(0.68, 0.58, 0.33, 0.28)
		line.width = _rng.randf_range(1.5, 3.0)
		line.z_index = -7
		var seg_count: int = _rng.randi_range(7, 10)
		for si: int in range(seg_count):
			var sx: float = center.x - radius * 0.9 + (radius * 1.8 / float(seg_count - 1)) * float(si)
			var sy: float = ry + sin(float(si) * 1.4) * 3.5 + _rng.randf_range(-2.5, 2.5)
			line.add_point(Vector2(sx, sy))
		parent.add_child(line)
	var grain_count: int = _rng.randi_range(20, 35)
	var grain_pts: PackedVector2Array = PackedVector2Array()
	for _gri: int in range(grain_count):
		var gra: float = _rng.randf() * TAU
		var grd: float = _rng.randf_range(0.0, radius * 0.88)
		var grpos: Vector2 = center + Vector2(cos(gra), sin(gra)) * grd
		var grr: float = _rng.randf_range(radius * 0.008, radius * 0.022)
		if grain_pts.size() > 0:
			grain_pts.append(grain_pts[0])
		for gsi: int in range(5):
			var gsa: float = TAU * gsi / 5.0
			grain_pts.append(grpos + Vector2(cos(gsa), sin(gsa)) * grr)
	if grain_pts.size() >= 3:
		var grain_poly: Polygon2D = Polygon2D.new()
		grain_poly.color = Color(0.88, 0.80, 0.55, 0.55)
		grain_poly.z_index = -7
		grain_poly.polygon = grain_pts
		parent.add_child(grain_poly)

# Dune v1: crescent dunes — curved arc shapes suggesting wind-blown sand mounds
func _paint_dune_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var dune_count: int = _rng.randi_range(3, 5)
	for _di: int in range(dune_count):
		var da: float = _rng.randf() * TAU
		var dd: float = _rng.randf_range(0.0, radius * 0.70)
		var dpos: Vector2 = center + Vector2(cos(da), sin(da)) * dd
		var dw: float = _rng.randf_range(radius * 0.25, radius * 0.45)
		var dh: float = dw * _rng.randf_range(0.18, 0.32)
		var dpts: PackedVector2Array = PackedVector2Array()
		var arc_steps: int = 10
		for i: int in range(arc_steps + 1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 2.0
			var ay: float = dpos.y - sin(t * PI) * dh
			dpts.append(Vector2(ax, ay))
		for i: int in range(arc_steps, -1, -1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 2.0
			var ay: float = dpos.y - sin(t * PI) * dh * 0.4
			dpts.append(Vector2(ax, ay))
		var dpoly: Polygon2D = Polygon2D.new()
		dpoly.color = Color(0.82, 0.72, 0.44, 0.45)
		dpoly.z_index = -7
		dpoly.polygon = dpts
		parent.add_child(dpoly)
		var shadow_pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(arc_steps + 1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 1.8
			var ay: float = dpos.y - sin(t * PI) * dh * 0.4
			shadow_pts.append(Vector2(ax, ay))
		for i: int in range(arc_steps, -1, -1):
			var t: float = float(i) / float(arc_steps)
			var ax: float = dpos.x + (t - 0.5) * dw * 1.8
			var ay: float = dpos.y - sin(t * PI) * dh * 0.05 + dh * 0.35
			shadow_pts.append(Vector2(ax, ay))
		var spoly: Polygon2D = Polygon2D.new()
		spoly.color = Color(0.60, 0.50, 0.28, 0.35)
		spoly.z_index = -7
		spoly.polygon = shadow_pts
		parent.add_child(spoly)

# Dune v2: rocky desert floor — small flat pebbles and gravel patches on sand
func _paint_dune_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var streak_count: int = _rng.randi_range(4, 7)
	for _si: int in range(streak_count):
		var sa: float = _rng.randf_range(-0.3, 0.3)
		var sd: float = _rng.randf_range(0.0, radius * 0.80)
		var spos: Vector2 = center + Vector2(cos(sa + PI * 0.5), sin(sa + PI * 0.5)) * sd
		var streak: Line2D = Line2D.new()
		streak.default_color = Color(0.72, 0.62, 0.38, 0.22)
		streak.width = _rng.randf_range(2.0, 4.5)
		streak.z_index = -7
		var slen: float = _rng.randf_range(radius * 0.20, radius * 0.55)
		streak.add_point(spos + Vector2(-slen, 0.0))
		streak.add_point(spos + Vector2( slen, _rng.randf_range(-4.0, 4.0)))
		parent.add_child(streak)
	var pebble_count: int = _rng.randi_range(8, 14)
	var pebble_pts: PackedVector2Array = PackedVector2Array()
	for _pi: int in range(pebble_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.82)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var pr: float = _rng.randf_range(radius * 0.015, radius * 0.040)
		if pebble_pts.size() > 0:
			pebble_pts.append(pebble_pts[0])
		for psi: int in range(6):
			var psa: float = TAU * psi / 6.0
			pebble_pts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.6, 1.3))
	if pebble_pts.size() >= 3:
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.58, 0.50, 0.32, 0.60)
		ppoly.z_index = -7
		ppoly.polygon = pebble_pts
		parent.add_child(ppoly)

# Malpais v0: cooled lava surface — flat dark polygonal plates
func _paint_malpais_detail_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var plate_count: int = _rng.randi_range(4, 7)
	for _pi: int in range(plate_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.80)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var pr: float = _rng.randf_range(radius * 0.08, radius * 0.18)
		var ppts: PackedVector2Array = PackedVector2Array()
		var sides: int = _rng.randi_range(5, 7)
		for psi: int in range(sides):
			var psa: float = TAU * psi / sides + _rng.randf_range(-0.3, 0.3)
			ppts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.7, 1.2))
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.18, 0.15, 0.13, 0.70)
		ppoly.z_index = -7
		ppoly.polygon = ppts
		parent.add_child(ppoly)

# Malpais v1: obsidian sheen — small bright-edged dark blobs suggesting glassy rock
func _paint_malpais_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var shard_count: int = _rng.randi_range(6, 10)
	for _si: int in range(shard_count):
		var sa: float = _rng.randf() * TAU
		var sd: float = _rng.randf_range(0.0, radius * 0.85)
		var spos: Vector2 = center + Vector2(cos(sa), sin(sa)) * sd
		var sr: float = _rng.randf_range(radius * 0.04, radius * 0.10)
		var spts: PackedVector2Array = PackedVector2Array()
		for ssi: int in range(5):
			var ssa: float = TAU * ssi / 5.0 + _rng.randf_range(-0.4, 0.4)
			spts.append(spos + Vector2(cos(ssa), sin(ssa)) * sr * _rng.randf_range(0.5, 1.2))
		var spoly: Polygon2D = Polygon2D.new()
		spoly.color = Color(0.08, 0.07, 0.08, 0.85)
		spoly.z_index = -7
		spoly.polygon = spts
		parent.add_child(spoly)
		if spts.size() >= 3:
			var shine: Polygon2D = Polygon2D.new()
			shine.color = Color(0.55, 0.55, 0.60, 0.30)
			shine.z_index = -7
			shine.polygon = PackedVector2Array([spts[0], spts[1], spts[2]])
			parent.add_child(shine)

# Malpais v2: ash dusting — light grey powder patches over the dark rock
func _paint_malpais_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var ash_count: int = _rng.randi_range(5, 9)
	for _ai: int in range(ash_count):
		var aa: float = _rng.randf() * TAU
		var ad: float = _rng.randf_range(0.0, radius * 0.85)
		var ar: float = _rng.randf_range(radius * 0.06, radius * 0.16)
		var apos: Vector2 = center + Vector2(cos(aa), sin(aa)) * ad
		var apts: PackedVector2Array = PackedVector2Array()
		for asi: int in range(10):
			var asa: float = TAU * asi / 10.0
			apts.append(apos + Vector2(cos(asa), sin(asa)) * ar * _rng.randf_range(0.70, 1.25))
		var apoly: Polygon2D = Polygon2D.new()
		apoly.color = Color(0.40, 0.38, 0.36, 0.30)
		apoly.z_index = -7
		apoly.polygon = apts
		parent.add_child(apoly)

# Risco v0: current style (pebbles already drawn in _paint_risco); no-op variant
func _paint_risco_detail_v0(_parent: Node2D, _center: Vector2, _radius: float) -> void:
	pass

# Risco v1: scree field — dense small angular rubble scattered across the base
func _paint_risco_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var scree_count: int = _rng.randi_range(18, 28)
	var all_pts: PackedVector2Array = PackedVector2Array()
	for _si: int in range(scree_count):
		var sa: float = _rng.randf() * TAU
		var sd: float = _rng.randf_range(0.0, radius * 0.92)
		var spos: Vector2 = center + Vector2(cos(sa), sin(sa)) * sd
		var sr: float = _rng.randf_range(radius * 0.015, radius * 0.038)
		if all_pts.size() > 0:
			all_pts.append(all_pts[0])
		for ssi: int in range(4):
			var ssa: float = TAU * ssi / 4.0 + _rng.randf_range(-0.5, 0.5)
			all_pts.append(spos + Vector2(cos(ssa), sin(ssa)) * sr * _rng.randf_range(0.5, 1.4))
	if all_pts.size() >= 3:
		var spoly: Polygon2D = Polygon2D.new()
		spoly.color = Color(0.32, 0.29, 0.26, 0.75)
		spoly.z_index = -7
		spoly.polygon = all_pts
		parent.add_child(spoly)

# Risco v2: mossy rock — pale green lichen patches on the stone surface
func _paint_risco_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var lichen_count: int = _rng.randi_range(6, 10)
	for _li: int in range(lichen_count):
		var la: float = _rng.randf() * TAU
		var ld: float = _rng.randf_range(0.0, radius * 0.85)
		var lr: float = _rng.randf_range(radius * 0.05, radius * 0.14)
		var lpos: Vector2 = center + Vector2(cos(la), sin(la)) * ld
		var lpts: PackedVector2Array = PackedVector2Array()
		for lsi: int in range(9):
			var lsa: float = TAU * lsi / 9.0
			lpts.append(lpos + Vector2(cos(lsa), sin(lsa)) * lr * _rng.randf_range(0.65, 1.30))
		var lpoly: Polygon2D = Polygon2D.new()
		lpoly.color = Color(0.30, 0.42, 0.18, 0.45)
		lpoly.z_index = -7
		lpoly.polygon = lpts
		parent.add_child(lpoly)

# Laurisilva v0: dark undergrowth blobs (dense shadow floor)
func _paint_laurisilva_detail_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var blob_count: int = _rng.randi_range(5, 8)
	for _bi: int in range(blob_count):
		var ba: float = _rng.randf() * TAU
		var bd: float = _rng.randf_range(0.0, radius * 0.75)
		var br: float = _rng.randf_range(radius * 0.08, radius * 0.18)
		var bpos: Vector2 = center + Vector2(cos(ba), sin(ba)) * bd
		var bpts: PackedVector2Array = PackedVector2Array()
		for bsi: int in range(8):
			var bsa: float = TAU * bsi / 8.0
			bpts.append(bpos + Vector2(cos(bsa), sin(bsa)) * br * _rng.randf_range(0.70, 1.25))
		var bpoly: Polygon2D = Polygon2D.new()
		bpoly.color = Color(0.04, 0.18, 0.05, 0.55)
		bpoly.z_index = -7
		bpoly.polygon = bpts
		parent.add_child(bpoly)

# Laurisilva v1: fern fronds — thin radiating lines from scattered points
func _paint_laurisilva_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var fern_count: int = _rng.randi_range(6, 10)
	for _fi: int in range(fern_count):
		var fa: float = _rng.randf() * TAU
		var fd: float = _rng.randf_range(0.0, radius * 0.80)
		var fpos: Vector2 = center + Vector2(cos(fa), sin(fa)) * fd
		var frond_count: int = _rng.randi_range(5, 8)
		var flen: float = _rng.randf_range(radius * 0.06, radius * 0.14)
		for fri: int in range(frond_count):
			var fra: float = TAU * fri / frond_count
			var fline: Line2D = Line2D.new()
			fline.default_color = Color(0.10, 0.38, 0.10, 0.50)
			fline.width = 1.0
			fline.z_index = -7
			fline.add_point(fpos)
			fline.add_point(fpos + Vector2(cos(fra), sin(fra)) * flen)
			parent.add_child(fline)

# Laurisilva v2: moss patches + fallen log hint
func _paint_laurisilva_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var moss_count: int = _rng.randi_range(4, 7)
	for _mi: int in range(moss_count):
		var ma: float = _rng.randf() * TAU
		var md: float = _rng.randf_range(0.0, radius * 0.78)
		var mr: float = _rng.randf_range(radius * 0.07, radius * 0.16)
		var mpos: Vector2 = center + Vector2(cos(ma), sin(ma)) * md
		var mpts: PackedVector2Array = PackedVector2Array()
		for msi: int in range(9):
			var msa: float = TAU * msi / 9.0
			mpts.append(mpos + Vector2(cos(msa), sin(msa)) * mr * _rng.randf_range(0.65, 1.30))
		var mpoly: Polygon2D = Polygon2D.new()
		mpoly.color = Color(0.18, 0.48, 0.14, 0.45)
		mpoly.z_index = -7
		mpoly.polygon = mpts
		parent.add_child(mpoly)
	var log_angle: float = _rng.randf() * PI
	var log_len: float = _rng.randf_range(radius * 0.20, radius * 0.40)
	var log_w: float = _rng.randf_range(radius * 0.025, radius * 0.055)
	var log_center: Vector2 = center + Vector2(
		_rng.randf_range(-radius * 0.45, radius * 0.45),
		_rng.randf_range(-radius * 0.45, radius * 0.45))
	var perp: Vector2 = Vector2(-sin(log_angle), cos(log_angle)) * log_w
	var fwd: Vector2  = Vector2( cos(log_angle), sin(log_angle)) * log_len
	var log_poly: Polygon2D = Polygon2D.new()
	log_poly.color = Color(0.22, 0.14, 0.07, 0.65)
	log_poly.z_index = -7
	log_poly.polygon = PackedVector2Array([
		log_center - fwd + perp,
		log_center + fwd + perp,
		log_center + fwd - perp,
		log_center - fwd - perp,
	])
	parent.add_child(log_poly)

# Caldera v0: extra central lava pool
func _paint_caldera_detail_v0(parent: Node2D, center: Vector2, radius: float) -> void:
	var pool_pts: PackedVector2Array = PackedVector2Array()
	var pool_r: float = radius * _rng.randf_range(0.10, 0.18)
	for i: int in range(12):
		var a: float = TAU * i / 12.0
		pool_pts.append(center + Vector2(cos(a), sin(a)) * pool_r * _rng.randf_range(0.80, 1.20))
	var pool: Polygon2D = Polygon2D.new()
	pool.color = Color(1.0, 0.35, 0.02, 0.75)
	pool.z_index = -5
	pool.material = _mat.lava()
	pool.polygon = pool_pts
	parent.add_child(pool)

# Caldera v1: solidified lava ripple rings — concentric faint circles
func _paint_caldera_detail_v1(parent: Node2D, center: Vector2, radius: float) -> void:
	var ring_count: int = _rng.randi_range(3, 5)
	for ri: int in range(ring_count):
		var rr: float = radius * (0.15 + float(ri) * 0.15) * _rng.randf_range(0.88, 1.12)
		var ring_line: Line2D = Line2D.new()
		ring_line.default_color = Color(0.55, 0.18, 0.04, 0.35)
		ring_line.width = _rng.randf_range(1.5, 3.0)
		ring_line.z_index = -6
		var ring_segs: int = 24
		for rsi: int in range(ring_segs + 1):
			var ra: float = TAU * rsi / ring_segs
			ring_line.add_point(center + Vector2(cos(ra), sin(ra)) * rr * _rng.randf_range(0.92, 1.08))
		parent.add_child(ring_line)

# Caldera v2: sulphur deposits — pale yellow-green patches near the rim
func _paint_caldera_detail_v2(parent: Node2D, center: Vector2, radius: float) -> void:
	var patch_count: int = _rng.randi_range(4, 7)
	for _pi: int in range(patch_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(radius * 0.30, radius * 0.80)
		var pr: float = _rng.randf_range(radius * 0.06, radius * 0.14)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var ppts: PackedVector2Array = PackedVector2Array()
		for psi: int in range(8):
			var psa: float = TAU * psi / 8.0
			ppts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.65, 1.35))
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.62, 0.58, 0.10, 0.45)
		ppoly.z_index = -6
		ppoly.polygon = ppts
		parent.add_child(ppoly)

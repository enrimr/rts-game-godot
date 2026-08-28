class_name TerrainPainter extends RefCounted

## Paints the visual terrain of a generated map: the base background, the ocean
## shelf and shoreline, and one styled patch per TerrainManager zone
## (laurisilva canopy, risco cliff, malpais lava field, caldera crater).
##
## The painter only draws — zone *gameplay* data lives in TerrainManager, which
## is why the per-map-type entry points register zones there first and then
## flush them to Polygon2Ds in one pass. Ground decoration inside a patch is
## delegated to TerrainDetail; shader materials come from MapMaterials.

var _rng: RandomNumberGenerator = null
var _map_half: float = 1800.0
var _mat: MapMaterials = MapMaterials.new()
var _detail: TerrainDetail = TerrainDetail.new()

func setup(rng: RandomNumberGenerator, map_half: float) -> void:
	_rng = rng
	_map_half = map_half
	_detail.setup(rng, _mat)

## Ground-variant scatter over the whole map base (delegated to TerrainDetail,
## exposed here so callers only need the painter).
func paint_ground_scatter(parent: Node2D, half: float,
		terrain: TerrainManager.TerrainType) -> void:
	_detail.paint_ground_scatter(parent, half, terrain)

# Builds a blob outline. A smooth low-frequency base (sum of sine harmonics with
# random phases) gives soft lobes, and a small per-vertex `jitter` adds irregular
# bite on top — a middle ground between a perfectly round blob and the old spiky
# per-vertex random radius. `roughness` scales the smooth lobe depth; `jitter`
# scales the fine random wobble; `steps` controls vertex density.
func _smooth_blob(center: Vector2, radius: float, steps: int = 40,
		roughness: float = 0.16, jitter: float = 0.06) -> PackedVector2Array:
	# Three harmonics: a few big lobes + gentle medium + faint fine detail.
	var freq_a: int = _rng.randi_range(2, 3)
	var freq_b: int = _rng.randi_range(4, 5)
	var freq_c: int = _rng.randi_range(6, 8)
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	var phase_c: float = _rng.randf() * TAU
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps):
		var a: float = TAU * float(i) / float(steps)
		var wave: float = sin(a * float(freq_a) + phase_a) * 0.60 \
				+ sin(a * float(freq_b) + phase_b) * 0.28 \
				+ sin(a * float(freq_c) + phase_c) * 0.12
		var r: float = radius * (1.0 + wave * roughness + _rng.randf_range(-jitter, jitter))
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

# Build a bumpy circle polygon for an island
func make_island_poly(center: Vector2, radius: float) -> PackedVector2Array:
	return _smooth_blob(center, radius, 52, 0.17, 0.045)

func scatter_island_terrain(center: Vector2, island_radius: float) -> void:
	var inner: float = island_radius * 0.70
	# 1–2 laurisilva patches
	for _i: int in range(_rng.randi_range(1, 2)):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, inner * 0.6)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var r: float = _rng.randf_range(island_radius * 0.12, island_radius * 0.22)
		TerrainManager.add_zone(pos, r, TerrainManager.TerrainType.LAURISILVA)
	# 1 malpaís or risco on edge
	for _i: int in range(1):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(inner * 0.5, inner)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var r: float = _rng.randf_range(island_radius * 0.08, island_radius * 0.15)
		var t: TerrainManager.TerrainType = TerrainManager.TerrainType.MALPAIS \
			if _rng.randf() > 0.5 else TerrainManager.TerrainType.RISCO
		TerrainManager.add_zone(pos, r, t)

# ── Standard terrain painting ────────────────────────────────────────────────

func paint_standard(parent: Node2D) -> void:
	var h: float = _map_half
	paint_rect_bg(parent, h, MapMaterials.color_for(TerrainManager.TerrainType.GRASS))
	_detail.paint_ground_scatter(parent, h, TerrainManager.TerrainType.GRASS)
	var configs: Array = [
		[3, h * 0.06, h * 0.14, TerrainManager.TerrainType.LAURISILVA],
		[2, h * 0.08, h * 0.18, TerrainManager.TerrainType.MALPAIS],
		[2, h * 0.07, h * 0.15, TerrainManager.TerrainType.DUNE],
		[4, h * 0.03, h * 0.07, TerrainManager.TerrainType.RISCO],
	]
	for cfg: Array in configs:
		for _i: int in range(cfg[0] as int):
			var pos: Vector2 = Vector2(
				_rng.randf_range(-h * 0.80, h * 0.80),
				_rng.randf_range(-h * 0.80, h * 0.80))
			var r: float = _rng.randf_range(cfg[1] as float, cfg[2] as float)
			TerrainManager.add_zone(pos, r, cfg[3] as TerrainManager.TerrainType)
	flush_zone_visuals(parent)

func paint_volcanic_coast(parent: Node2D) -> void:
	var h: float = _map_half
	_paint_coastal_ocean(parent, h, MapMaterials.color_for(TerrainManager.TerrainType.GRASS))
	paint_rect_bg(parent, h, MapMaterials.color_for(TerrainManager.TerrainType.GRASS))
	_detail.paint_ground_scatter(parent, h, TerrainManager.TerrainType.GRASS)
	# Large central caldera + malpaís bands radiating from it
	var caldera_pos: Vector2 = Vector2(_rng.randf_range(-h * 0.1, h * 0.1),
		_rng.randf_range(-h * 0.1, h * 0.1))
	TerrainManager.add_zone(caldera_pos, h * 0.16, TerrainManager.TerrainType.CALDERA)
	# 3–4 malpaís rings around caldera
	for i: int in range(4):
		var a: float = TAU * i / 4.0 + _rng.randf_range(-0.3, 0.3)
		var d: float = _rng.randf_range(h * 0.18, h * 0.35)
		var pos: Vector2 = caldera_pos + Vector2(cos(a), sin(a)) * d
		TerrainManager.add_zone(pos, _rng.randf_range(h * 0.06, h * 0.12),
			TerrainManager.TerrainType.MALPAIS)
	# Risco edges
	for _i: int in range(4):
		var pos: Vector2 = Vector2(_rng.randf_range(-h * 0.7, h * 0.7),
			_rng.randf_range(-h * 0.7, h * 0.7))
		TerrainManager.add_zone(pos, _rng.randf_range(h * 0.03, h * 0.07),
			TerrainManager.TerrainType.RISCO)
	# Some laurisilva on northern half
	for _i: int in range(2):
		var pos: Vector2 = Vector2(_rng.randf_range(-h * 0.6, h * 0.6),
			_rng.randf_range(-h * 0.6, -h * 0.1))
		TerrainManager.add_zone(pos, _rng.randf_range(h * 0.08, h * 0.15),
			TerrainManager.TerrainType.LAURISILVA)
	flush_zone_visuals(parent)

func paint_desert_coast(parent: Node2D) -> void:
	var h: float = _map_half
	_paint_coastal_ocean(parent, h, MapMaterials.color_for(TerrainManager.TerrainType.DUNE))
	paint_rect_bg(parent, h, MapMaterials.color_for(TerrainManager.TerrainType.DUNE),
		TerrainManager.TerrainType.DUNE)
	_detail.paint_ground_scatter(parent, h, TerrainManager.TerrainType.DUNE)
	# Register full map as dune zone so TerrainManager knows
	TerrainManager.add_zone(Vector2.ZERO, h * 1.5, TerrainManager.TerrainType.DUNE)
	# Add small grass oases near TCs (registered last = highest priority)
	for side: int in [-1, 1]:
		var oasis: Vector2 = Vector2(side * h * 0.35, _rng.randf_range(-h * 0.2, h * 0.2))
		TerrainManager.add_zone(oasis, h * 0.18, TerrainManager.TerrainType.GRASS)
		_paint_circle_patch(parent, oasis, h * 0.18,
			MapMaterials.color_for(TerrainManager.TerrainType.GRASS), _rng.randi() % 3)
	# Risco ridge on east edge
	for _i: int in range(3):
		var rpos: Vector2 = Vector2(_rng.randf_range(h * 0.55, h * 0.75),
			_rng.randf_range(-h * 0.5, h * 0.5))
		var rr: float = _rng.randf_range(h * 0.04, h * 0.09)
		TerrainManager.add_zone(rpos, rr, TerrainManager.TerrainType.RISCO)
		_paint_risco(parent, rpos, rr, _rng.randi() % 3)

# ── Terrain visual helpers ───────────────────────────────────────────────────

# Paints all registered terrain zones with type-specific visuals.
func flush_zone_visuals(parent: Node2D) -> void:
	var zones: Array = TerrainManager._zones
	for z: Dictionary in zones:
		var t: TerrainManager.TerrainType = z["type"] as TerrainManager.TerrainType
		var center: Vector2 = z["center"] as Vector2
		var radius: float   = z["radius"] as float
		var variant: int = _rng.randi() % 3
		match t:
			TerrainManager.TerrainType.LAURISILVA:
				_paint_laurisilva(parent, center, radius, variant)
			TerrainManager.TerrainType.RISCO:
				_paint_risco(parent, center, radius, variant)
			TerrainManager.TerrainType.MALPAIS:
				_paint_malpais(parent, center, radius, variant)
			TerrainManager.TerrainType.CALDERA:
				_paint_caldera(parent, center, radius, variant)
			_:
				_paint_circle_patch(parent, center, radius, MapMaterials.color_for(t), variant)

# ── Per-terrain painters ──────────────────────────────────────────────────────

func _paint_laurisilva(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	# Base: dark green blob
	_paint_circle_patch(parent, center, radius, MapMaterials.color_for(TerrainManager.TerrainType.LAURISILVA), variant, TerrainManager.TerrainType.LAURISILVA)
	# Batch all canopies into a single Polygon2D per colour group to minimise
	# scene-tree nodes. We use 3 colour groups; each gets one Polygon2D with
	# all canopy outlines appended as a single closed polygon (separated by a
	# degenerate edge back to the first point, which is invisible at this scale).
	const CSTEPS: int = 6   # hexagonal canopy — fewer vertices, still round
	const GROUPS: int = 3
	var group_pts: Array = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var group_colors: Array[Color] = [
		Color(0.06, 0.44, 0.08),
		Color(0.10, 0.52, 0.10),
		Color(0.14, 0.38, 0.08),
	]

	var tree_count: int = _rng.randi_range(10, 16)
	for _i: int in range(tree_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.90)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var tr_r: float = _rng.randf_range(radius * 0.05, radius * 0.10)
		var group: int = _rng.randi() % GROUPS
		var pts: PackedVector2Array = group_pts[group] as PackedVector2Array
		# Append canopy polygon; if not empty, add a degenerate bridge back
		if pts.size() > 0:
			pts.append(pts[0])   # close previous sub-polygon
		var start_pt: Vector2 = pos + Vector2(tr_r, 0.0)
		for ci: int in range(CSTEPS):
			var ca: float = TAU * float(ci) / float(CSTEPS)
			var cr: float = tr_r * _rng.randf_range(0.80, 1.20)
			pts.append(pos + Vector2(cos(ca), sin(ca)) * cr)
		pts.append(start_pt)   # close this sub-polygon

	for g: int in range(GROUPS):
		var pts: PackedVector2Array = group_pts[g] as PackedVector2Array
		if pts.size() < 3:
			continue
		var canopy: Polygon2D = Polygon2D.new()
		canopy.color = group_colors[g]
		canopy.z_index = -6
		canopy.polygon = pts
		parent.add_child(canopy)
	_detail.paint_variant(parent, center, radius, TerrainManager.TerrainType.LAURISILVA, variant)

func _paint_risco(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	_paint_circle_patch(parent, center, radius, MapMaterials.color_for(TerrainManager.TerrainType.RISCO), variant, TerrainManager.TerrainType.RISCO)

	# Scattered ground pebbles across the rock zone base for texture
	var pebble_count: int = _rng.randi_range(14, 22)
	for _pi: int in range(pebble_count):
		var pa: float = _rng.randf() * TAU
		var pd: float = _rng.randf_range(0.0, radius * 0.90)
		var ppos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pd
		var pr: float = _rng.randf_range(radius * 0.018, radius * 0.045)
		var ppoly: Polygon2D = Polygon2D.new()
		ppoly.color = Color(0.38, 0.35, 0.31, 0.85)
		ppoly.z_index = -7
		var ppts: PackedVector2Array = PackedVector2Array()
		const PBSTEPS: int = 6
		for psi: int in range(PBSTEPS):
			var psa: float = TAU * psi / PBSTEPS + _rng.randf_range(-0.3, 0.3)
			ppts.append(ppos + Vector2(cos(psa), sin(psa)) * pr * _rng.randf_range(0.6, 1.2))
		ppoly.polygon = ppts
		parent.add_child(ppoly)
	_detail.paint_variant(parent, center, radius, TerrainManager.TerrainType.RISCO, variant)

	# Peaks — upright rock outcrops. The silhouette is authored in screen space
	# and mounted on an IsoBillboard-uprighted child so the camera projection
	# doesn't shear it into a smeared grey parallelogram; only the cast shadow
	# stays ground-flat (projected). Each peak anchor sits in the entity depth
	# band so units in front of / behind the crag occlude correctly.
	var peak_count: int = _rng.randi_range(3, 6)
	for _pi: int in range(peak_count):
		# Spread peaks across most of the zone so the base is well covered
		var spread: float = _rng.randf_range(0.0, radius * 0.60)
		var dir_angle: float = _rng.randf() * TAU
		var peak_center: Vector2 = center + Vector2(cos(dir_angle), sin(dir_angle)) * spread

		var ph: float = _rng.randf_range(radius * 0.45, radius * 0.85)
		var pw: float = _rng.randf_range(radius * 0.70, radius * 1.1)
		var tilt: float = _rng.randf_range(-0.18, 0.18)

		# Cast shadow: flat ellipse pooled at the peak base, offset toward the
		# shadow side (left, since the sunlit face is the right flank). Stays in
		# world space so it hugs the ground plane under projection.
		var shadow_cast: Polygon2D = Polygon2D.new()
		shadow_cast.color = Color(0.10, 0.09, 0.08, 0.30)
		shadow_cast.z_index = -8
		var sh_rx: float = pw * 0.55
		var sh_ry: float = pw * 0.30
		var sh_center: Vector2 = peak_center + Vector2(-pw * 0.20, pw * 0.05)
		var sh_pts: PackedVector2Array = PackedVector2Array()
		for ssi: int in range(14):
			var ssa: float = TAU * float(ssi) / 14.0
			sh_pts.append(sh_center + Vector2(cos(ssa) * sh_rx, sin(ssa) * sh_ry))
		shadow_cast.polygon = sh_pts
		parent.add_child(shadow_cast)

		var anchor: Node2D = Node2D.new()
		anchor.position = peak_center
		anchor.z_index = IsoBillboard.depth_z(peak_center)
		parent.add_child(anchor)
		var body: Node2D = Node2D.new()
		anchor.add_child(body)
		IsoBillboard.make_upright(body)

		# Silhouette vertices relative to the base centre, screen space (Y up).
		var tip: Vector2 = Vector2(tilt * pw, -ph)
		var base_l: Vector2 = Vector2(-pw * 0.5 + _rng.randf_range(-pw * 0.08, pw * 0.08), _rng.randf_range(-ph * 0.05, ph * 0.10))
		var base_r: Vector2 = Vector2( pw * 0.5 + _rng.randf_range(-pw * 0.08, pw * 0.08), _rng.randf_range(-ph * 0.05, ph * 0.10))
		# Extra mid-flank jagged vertices for more craggy silhouette
		var jag_l: Vector2 = Vector2(-pw * 0.30 + _rng.randf_range(-pw * 0.08, pw * 0.06), -ph * _rng.randf_range(0.38, 0.58))
		var jag_r: Vector2 = Vector2( pw * 0.30 + _rng.randf_range(-pw * 0.06, pw * 0.08), -ph * _rng.randf_range(0.35, 0.55))
		var jag2_l: Vector2 = Vector2(-pw * 0.42 + _rng.randf_range(-pw * 0.05, pw * 0.05), -ph * _rng.randf_range(0.15, 0.32))
		var jag2_r: Vector2 = Vector2( pw * 0.42 + _rng.randf_range(-pw * 0.05, pw * 0.05), -ph * _rng.randf_range(0.12, 0.30))

		# Dark rock base — full wide mountain silhouette
		var base_poly: Polygon2D = Polygon2D.new()
		base_poly.color = Color(0.32, 0.29, 0.25)
		base_poly.polygon = PackedVector2Array([base_l, jag2_l, jag_l, tip, jag_r, jag2_r, base_r])
		body.add_child(base_poly)

		# Mid-slope face — right half lighter (sunlit side)
		var face: Polygon2D = Polygon2D.new()
		face.color = Color(0.54, 0.50, 0.45)
		var mid_base: Vector2 = (tip + base_r) * 0.5 + Vector2(0.0, ph * 0.08)
		face.polygon = PackedVector2Array([tip, jag_r, jag2_r, base_r, mid_base])
		body.add_child(face)

		# Shadow side — left darker area
		var shadow: Polygon2D = Polygon2D.new()
		shadow.color = Color(0.18, 0.16, 0.14, 0.75)
		var mid_left: Vector2 = base_l + (tip - base_l) * 0.38
		shadow.polygon = PackedVector2Array([base_l, jag2_l, jag_l, mid_left])
		body.add_child(shadow)

		# Snow cap — only the taller crags carry one
		if ph > radius * 0.62:
			var snow_h: float = ph * _rng.randf_range(0.20, 0.32)
			var snow_w: float = pw * _rng.randf_range(0.18, 0.28)
			var snow: Polygon2D = Polygon2D.new()
			snow.color = Color(0.90, 0.89, 0.87, 0.92)
			snow.polygon = PackedVector2Array([
				tip,
				tip + Vector2(-snow_w * 0.6, snow_h * 0.4) + Vector2(_rng.randf_range(-2.0, 2.0), 0.0),
				tip + Vector2(-snow_w, snow_h),
				tip + Vector2( snow_w, snow_h),
				tip + Vector2( snow_w * 0.6, snow_h * 0.4) + Vector2(_rng.randf_range(-2.0, 2.0), 0.0),
			])
			body.add_child(snow)

func _paint_malpais(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	_paint_circle_patch(parent, center, radius, MapMaterials.color_for(TerrainManager.TerrainType.MALPAIS), variant, TerrainManager.TerrainType.MALPAIS)

	# Dark lava rock fragments scattered across the zone
	var all_pts: PackedVector2Array = PackedVector2Array()
	var frag_count: int = _rng.randi_range(10, 18)
	for _i: int in range(frag_count):
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, radius * 0.88)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * d
		var fr: float = _rng.randf_range(radius * 0.04, radius * 0.10)
		var fsides: int = _rng.randi_range(4, 6)
		if all_pts.size() > 0:
			all_pts.append(all_pts[0])
		for fi: int in range(fsides):
			var fa: float = TAU * fi / fsides + _rng.randf_range(-0.2, 0.2)
			all_pts.append(pos + Vector2(cos(fa), sin(fa)) * fr * _rng.randf_range(0.5, 1.0))

	if all_pts.size() >= 3:
		var frag: Polygon2D = Polygon2D.new()
		frag.color = Color(0.24, 0.21, 0.20)
		frag.z_index = -7
		frag.polygon = all_pts
		parent.add_child(frag)

	# Glowing crack lines — thin orange-red veins suggesting cooling lava
	var crack_count: int = _rng.randi_range(3, 6)
	for _ci: int in range(crack_count):
		var start_a: float = _rng.randf() * TAU
		var start_d: float = _rng.randf_range(0.0, radius * 0.55)
		var crack_start: Vector2 = center + Vector2(cos(start_a), sin(start_a)) * start_d
		var crack_line: Line2D = Line2D.new()
		crack_line.default_color = Color(0.72, 0.22, 0.05, 0.65)
		crack_line.width = _rng.randf_range(1.0, 2.0)
		crack_line.z_index = -6
		crack_line.material = _mat.lava()
		crack_line.add_point(crack_start)
		var seg_len: float = _rng.randf_range(radius * 0.15, radius * 0.35)
		var dir_a: float = _rng.randf() * TAU
		var segs: int = _rng.randi_range(3, 5)
		var cur: Vector2 = crack_start
		for _si: int in range(segs):
			dir_a += _rng.randf_range(-0.6, 0.6)
			cur += Vector2(cos(dir_a), sin(dir_a)) * (seg_len / segs)
			crack_line.add_point(cur)
		parent.add_child(crack_line)
	_detail.paint_variant(parent, center, radius, TerrainManager.TerrainType.MALPAIS, variant)

func _paint_caldera(parent: Node2D, center: Vector2, radius: float, variant: int = 0) -> void:
	_paint_circle_patch(parent, center, radius, MapMaterials.color_for(TerrainManager.TerrainType.CALDERA), 0, TerrainManager.TerrainType.CALDERA)
	_paint_circle_patch(parent, center, radius * 0.55, Color(0.06, 0.04, 0.04))

	var crack_count: int = _rng.randi_range(3, 5)
	# Collect glow dot positions to place at crack tips and branch junctions
	var glow_positions: PackedVector2Array = PackedVector2Array()

	for ci: int in range(crack_count):
		var ca: float = TAU * ci / crack_count + _rng.randf_range(-0.2, 0.2)
		var segments: int = _rng.randi_range(3, 5)

		# Build main crack point list
		var main_pts: PackedVector2Array = PackedVector2Array()
		main_pts.append(center)
		var cp: Vector2 = center
		for _si: int in range(segments):
			cp += Vector2(cos(ca), sin(ca)) * _rng.randf_range(radius * 0.10, radius * 0.20)
			cp += Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
			main_pts.append(cp)
		glow_positions.append(cp)   # tip

		# Draw main crack: dark wide underlay then bright narrow overlay
		var crack_dark: Line2D = Line2D.new()
		crack_dark.default_color = Color(0.15, 0.05, 0.02, 0.9)
		crack_dark.width = _rng.randf_range(3.5, 5.0)
		crack_dark.z_index = -6
		for pt: Vector2 in main_pts:
			crack_dark.add_point(pt)
		parent.add_child(crack_dark)

		var crack_bright: Line2D = Line2D.new()
		crack_bright.default_color = Color(1.0, 0.45, 0.05, 0.85)
		crack_bright.width = _rng.randf_range(1.5, 3.0)
		crack_bright.z_index = -6
		crack_bright.material = _mat.lava()
		for pt: Vector2 in main_pts:
			crack_bright.add_point(pt)
		parent.add_child(crack_bright)

		# 1–2 branches from random points along the main crack
		var branch_count: int = _rng.randi_range(1, 2)
		for _bi: int in range(branch_count):
			if main_pts.size() < 2:
				break
			var branch_start_idx: int = _rng.randi_range(0, main_pts.size() - 2)
			var branch_start: Vector2 = main_pts[branch_start_idx]
			var branch_angle: float = ca + _rng.randf_range(PI * 0.25, PI * 0.65) * (1.0 if _rng.randf() > 0.5 else -1.0)
			var branch_segs: int = _rng.randi_range(2, 3)
			var bp: Vector2 = branch_start
			var branch_pts: PackedVector2Array = PackedVector2Array()
			branch_pts.append(bp)
			for _bs: int in range(branch_segs):
				bp += Vector2(cos(branch_angle), sin(branch_angle)) * _rng.randf_range(radius * 0.06, radius * 0.14)
				bp += Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
				branch_pts.append(bp)
			glow_positions.append(bp)   # branch tip
			glow_positions.append(branch_start)   # junction

			var bdark: Line2D = Line2D.new()
			bdark.default_color = Color(0.15, 0.05, 0.02, 0.9)
			bdark.width = _rng.randf_range(2.5, 3.5)
			bdark.z_index = -6
			for pt: Vector2 in branch_pts:
				bdark.add_point(pt)
			parent.add_child(bdark)

			var bbright: Line2D = Line2D.new()
			bbright.default_color = Color(1.0, 0.45, 0.05, 0.85)
			bbright.width = _rng.randf_range(1.0, 2.0)
			bbright.z_index = -6
			bbright.material = _mat.lava()
			for pt: Vector2 in branch_pts:
				bbright.add_point(pt)
			parent.add_child(bbright)

	# Glowing dots at crack tips and junctions — batch all into one Polygon2D per group
	# to minimise scene-tree nodes: pick up to 6 positions, draw circles individually
	var dot_limit: int = mini(glow_positions.size(), 6)
	# Shuffle by picking random indices without replacement via rng
	var available_indices: Array[int] = []
	for di: int in range(glow_positions.size()):
		available_indices.append(di)
	var dot_pts: PackedVector2Array = PackedVector2Array()
	for _d: int in range(dot_limit):
		if available_indices.is_empty():
			break
		var pick: int = _rng.randi() % available_indices.size()
		var chosen_idx: int = available_indices[pick]
		available_indices.remove_at(pick)
		var dpos: Vector2 = glow_positions[chosen_idx]
		var dot_r: float = _rng.randf_range(3.0, 6.0)
		const DOT_STEPS: int = 8
		if dot_pts.size() > 0:
			dot_pts.append(dot_pts[0])
		for di2: int in range(DOT_STEPS):
			var da: float = TAU * di2 / DOT_STEPS
			dot_pts.append(dpos + Vector2(cos(da), sin(da)) * dot_r)

	if dot_pts.size() >= 3:
		var dot_poly: Polygon2D = Polygon2D.new()
		dot_poly.color = Color(1.0, 0.6, 0.1, 0.7)
		dot_poly.z_index = -5
		dot_poly.material = _mat.lava()
		dot_poly.polygon = dot_pts
		parent.add_child(dot_poly)
	_detail.paint_variant(parent, center, radius, TerrainManager.TerrainType.CALDERA, variant)

func _paint_circle_patch(parent: Node2D, center: Vector2,
		radius: float, col: Color, variant: int = 0, terrain: int = -1) -> void:
	# Main feathered-edge blob — 32 vertices with larger noise-driven jitter so
	# zone boundaries bleed organically into adjacent terrain instead of
	# cutting as hard circles.
	# A terrain-tuned grain/variation shader runs on the base blobs so the zone
	# floor isn't a flat colour beneath its detail decals.
	var base_mat: ShaderMaterial = _mat.terrain_for(terrain) if terrain >= 0 else null

	# Smooth, rounded base outline (low-frequency harmonics instead of per-vertex
	# jitter so the edge undulates in soft lobes rather than spikes).
	var pts: PackedVector2Array = _smooth_blob(center, radius, 40, 0.15)

	# Soft edge: blend the zone colour into the surrounding terrain so the
	# boundary isn't a hard cut. Follows the base outline exactly (scaled bands)
	# so the blend hugs the real silhouette instead of a circle. Drawn first
	# (below the opaque base blob) so only the outer fringe shows. Only
	# contrasting special zones get this — grass/dune patches don't need it.
	if terrain in MapMaterials.GRADIENT_TERRAINS:
		_paint_edge_gradient(parent, pts, center, col)

	var pts_clipped: PackedVector2Array = _clip_poly_to_map(pts)
	if pts_clipped.size() >= 3:
		var poly: Polygon2D = Polygon2D.new()
		poly.color = col
		poly.z_index = -8
		poly.material = base_mat
		poly.polygon = pts_clipped
		parent.add_child(poly)

	# Fringe blobs — small rounded overlap patches around the perimeter that
	# break the edge and fray softly into adjacent terrain.
	var fringe_count: int = _rng.randi_range(8, 12)
	for _fi: int in range(fringe_count):
		var fa: float = _rng.randf() * TAU
		var fd: float = radius * _rng.randf_range(0.75, 1.0)
		var fr: float = radius * _rng.randf_range(0.15, 0.30)
		var fpos: Vector2 = center + Vector2(cos(fa), sin(fa)) * fd
		var fpts: PackedVector2Array = _smooth_blob(fpos, fr, 16, 0.18)
		var fpts_clipped: PackedVector2Array = _clip_poly_to_map(fpts)
		if fpts_clipped.size() < 3:
			continue
		var fpoly: Polygon2D = Polygon2D.new()
		fpoly.color = col
		fpoly.z_index = -8
		fpoly.material = base_mat
		fpoly.polygon = fpts_clipped
		parent.add_child(fpoly)

	# Terrain-specific surface detail variants — only for grass/dune callers that
	# rely on colour inference. The special painters (malpaís, risco, laurisilva,
	# caldera) invoke _paint_terrain_variant themselves, so the explicit `terrain`
	# arg here drives ONLY the base material, never the variant (avoids painting
	# the detail decals twice).
	var t_int: int = -1
	if col.r > 0.70 and col.g > 0.60 and col.b < 0.55:
		t_int = TerrainManager.TerrainType.DUNE
	elif col.r < 0.30 and col.g > 0.38 and col.b < 0.25:
		t_int = TerrainManager.TerrainType.GRASS
	if t_int >= 0:
		_detail.paint_variant(parent, center, radius, t_int, variant)

# Dithers a zone's edge into the surrounding terrain: tile-grid squares of the
# zone colour scattered just outside the outline, thinning outward — the hard,
# dithered tileset transition of classic isometric RTS maps instead of the old
# soft alpha halo (which read as a stain around every zone).
func _paint_edge_gradient(parent: Node2D, outline: PackedVector2Array,
		center: Vector2, col: Color, _rings: int = 3, _spread: float = 0.14, z: int = -8) -> void:
	if outline.size() < 3:
		return
	var t: float = MapMaterials.STAIN_TILE
	var limit: float = _map_half - t
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = outline.size()
	for i: int in range(n):
		# Sample each outline vertex and the segment midpoint so big zones have
		# no dither gaps between vertices.
		for sample: Vector2 in [outline[i], (outline[i] + outline[(i + 1) % n]) * 0.5]:
			var dir: Vector2 = (sample - center).normalized()
			for ring: int in range(3):
				var prob: float = 0.85 / float(ring + 1) - 0.15
				if _rng.randf() >= prob:
					continue
				var pos: Vector2 = sample + dir * t * (float(ring) * 0.9 + 0.25)
				var origin: Vector2 = (pos / t).floor() * t
				if absf(origin.x) > limit or absf(origin.y) > limit:
					continue
				_detail.append_tile_square(pts, origin)
	if pts.size() < 3:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.color = Color(col.r, col.g, col.b, minf(col.a, 0.92))
	poly.z_index = z
	poly.polygon = pts
	parent.add_child(poly)

func paint_rect_bg(parent: Node2D, half: float, col: Color,
		terrain: int = TerrainManager.TerrainType.GRASS) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -9
	poly.material = _mat.terrain_for(terrain)
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	parent.add_child(poly)

func paint_ocean_bg(parent: Node2D, half: float) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = Color(1, 1, 1, 1)   # tinted by shader
	poly.z_index = -9
	poly.material = _mat.water()
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	parent.add_child(poly)

# Surrounds a coast-type map with animated ocean. The water sheet sits behind
# the opaque land background (z -10), so it only shows in the outer ring beyond
# the playable rectangle — the continent reads as sea-girt without any walkable
# water inside the play area. The land-water transition is built from irregular
# multi-harmonic outlines (never a ruler-straight frame): sand beach, a thin
# surf-foam rim, then an animated turquoise shallow-water shelf fading into the
# deep ocean.
func _paint_coastal_ocean(parent: Node2D, half: float, land_col: Color) -> void:
	var ocean_half: float = half * 1.35
	var water: Polygon2D = Polygon2D.new()
	water.color = Color(1, 1, 1, 1)   # tinted by shader
	water.z_index = -10
	water.material = _mat.water()
	water.polygon = PackedVector2Array([
		Vector2(-ocean_half, -ocean_half), Vector2(ocean_half, -ocean_half),
		Vector2(ocean_half, ocean_half),   Vector2(-ocean_half, ocean_half),
	])
	parent.add_child(water)

	# Shallow-water shelf: brighter animated water hugging the coast so the map
	# border reads as shoals. Translucent so the deep ocean tints it and the
	# outer boundary blends instead of stepping.
	var shallow: Polygon2D = Polygon2D.new()
	shallow.color = Color(1, 1, 1, 0.85)
	shallow.z_index = -10
	shallow.material = _mat.shallow()
	shallow.polygon = _wavy_rect_outline(half * 1.055, half * 0.10)
	parent.add_child(shallow)

	# Surf-foam rim: pale sliver between the beach and the shallows. Its outline
	# wanders independently of the sand's, so the rim breathes from nothing to a
	# wide wash along the coast.
	var foam: Polygon2D = Polygon2D.new()
	foam.color = SHORE_FOAM
	foam.z_index = -9
	foam.polygon = _wavy_rect_outline(half * 1.030, half * 0.045)
	parent.add_child(foam)

	# Sand beach: opaque band from the land edge out into the surf.
	var sand: Polygon2D = Polygon2D.new()
	sand.color = SHORE_SAND
	sand.z_index = -9
	sand.material = _mat.terrain()
	sand.polygon = _wavy_rect_outline(half * 1.005, half * 0.050)
	parent.add_child(sand)

	# Irregular shoreline fringe: a band of land-coloured blobs hugging the inner
	# edge of the border so the coast bleeds organically into the sea.
	var step: float = half * 0.12
	var t: float = -half
	while t <= half:
		for side: int in range(4):
			var base: Vector2
			match side:
				0: base = Vector2(t, -half)   # top
				1: base = Vector2(t,  half)   # bottom
				2: base = Vector2(-half, t)   # left
				_: base = Vector2( half, t)   # right
			var inward: Vector2 = base.normalized() * -1.0 * _rng.randf_range(0.0, half * 0.04)
			var blob_pos: Vector2 = base + inward
			var br: float = _rng.randf_range(half * 0.04, half * 0.085)
			var bpts: PackedVector2Array = _smooth_blob(blob_pos, br, 14, 0.20)
			var bpoly: Polygon2D = Polygon2D.new()
			bpoly.color = land_col
			bpoly.z_index = -9
			bpoly.material = _mat.terrain()
			bpoly.polygon = bpts
			parent.add_child(bpoly)
		t += step

# Returns pts intersected with the map rectangle — i.e. clipped to map bounds.
func _clip_poly_to_map(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var mh: float = _map_half
	var map_rect: PackedVector2Array = PackedVector2Array([
		Vector2(-mh, -mh), Vector2(mh, -mh),
		Vector2(mh,  mh),  Vector2(-mh, mh),
	])
	var result: Array[PackedVector2Array] = Geometry2D.intersect_polygons(pts, map_rect)
	if result.is_empty():
		return PackedVector2Array()
	return result[0]

func paint_polygon(parent: Node2D, pts: PackedVector2Array, col: Color) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = -8
	poly.material = _mat.terrain_for(TerrainManager.TerrainType.GRASS)
	poly.polygon = pts
	parent.add_child(poly)

# Paints a beach + foam ring around a land outline so land meets water through a
# soft sand band instead of a hard green/blue cut. The land polygon is drawn on
# top afterwards (z -8), covering the inner part of these rings; only the outer
# sand and foam show beyond the shoreline.
const SHORE_SAND: Color = Color(0.80, 0.72, 0.48, 1.0)
const SHORE_FOAM: Color = Color(0.82, 0.90, 0.94, 0.45)

func paint_shore(parent: Node2D, land_pts: PackedVector2Array, center: Vector2) -> void:
	if land_pts.size() < 3:
		return
	# Outside-in: an animated turquoise shallow-water shelf (widest, translucent
	# so the deep ocean blends through), a pale surf-foam rim, then the opaque
	# sand beach hugging the land edge. All three widths breathe independently
	# around the coastline (variation arg) so the shore is broad in places and
	# thin in others, like a real coast.
	_paint_shore_ring(parent, land_pts, center, 1.17, 0.055, Color(1, 1, 1, 0.85), -9,
		_mat.shallow())
	_paint_shore_ring(parent, land_pts, center, 1.085, 0.030, SHORE_FOAM, -9)
	_paint_shore_ring(parent, land_pts, center, 1.06, 0.035, SHORE_SAND, -9)

# Draws one ring by scaling the land outline outward from `center`. The scale
# isn't constant: it wanders by `variation` via low-frequency harmonics around
# the perimeter, so the band's width varies along the coast instead of being a
# uniform offset. Follows the (already smooth) land outline so no new spikes.
func _paint_shore_ring(parent: Node2D, land_pts: PackedVector2Array,
		center: Vector2, base_scale: float, variation: float, col: Color, z: int,
		mat: ShaderMaterial = null) -> void:
	var n: int = land_pts.size()
	var freq_a: int = _rng.randi_range(2, 3)
	var freq_b: int = _rng.randi_range(4, 6)
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		var w: float = sin(a * float(freq_a) + phase_a) * 0.65 \
				+ sin(a * float(freq_b) + phase_b) * 0.35
		var scale: float = base_scale + w * variation
		var out: Vector2 = (land_pts[i] - center) * scale
		pts.append(center + out)
	var clipped: PackedVector2Array = _clip_poly_to_map(pts)
	if clipped.size() < 3:
		return
	var poly: Polygon2D = Polygon2D.new()
	poly.color = col
	poly.z_index = z
	if mat != null:
		poly.material = mat
	elif col.a >= 0.99:
		poly.material = _mat.terrain()
	poly.polygon = clipped
	parent.add_child(poly)

# Closed outline of a square of half-extent `base_half` whose border bulges
# outward by up to `amp`, driven by two sine harmonics plus a slow width
# envelope. Enough low- and mid-frequency movement that the coast undulates in
# capes and coves instead of reading as a straight frame. The bulge is always
# >= 0 so the outline never dents inside the base square.
func _wavy_rect_outline(base_half: float, amp: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	const PER_SIDE: int = 36
	var corners: Array = [
		[Vector2(-base_half, -base_half), Vector2( base_half, -base_half)],
		[Vector2( base_half, -base_half), Vector2( base_half,  base_half)],
		[Vector2( base_half,  base_half), Vector2(-base_half,  base_half)],
		[Vector2(-base_half,  base_half), Vector2(-base_half, -base_half)],
	]
	# Random phases/frequencies per call so no two bands are identical.
	var freq_a: float = float(_rng.randi_range(4, 6))
	var freq_b: float = float(_rng.randi_range(9, 14))
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	# A slow wave modulates the bulge amplitude so the band's width varies
	# along the coast (broad here, thin there) rather than a uniform roll.
	var amp_freq: float = float(_rng.randi_range(2, 3))
	var amp_phase: float = _rng.randf() * TAU
	var total: int = PER_SIDE * corners.size()
	var idx: float = 0.0
	for edge: Array in corners:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		for s: int in range(PER_SIDE):
			var f: float = float(s) / float(PER_SIDE)
			var p: Vector2 = a.lerp(b, f)
			var perim: float = idx / float(total)   # 0..1 around the whole frame
			# Width envelope wanders between ~30% and 100% of amp.
			var env: float = 0.30 + (sin(perim * TAU * amp_freq + amp_phase) * 0.5 + 0.5) * 0.70
			var wave: float = sin(perim * TAU * freq_a + phase_a) * 0.62 \
					+ sin(perim * TAU * freq_b + phase_b) * 0.38
			var bulge: float = (wave * 0.5 + 0.5) * amp * env
			var n: Vector2 = p.normalized()
			pts.append(p + n * bulge)
			idx += 1.0
	return pts

class_name HeroDress

## Hero signature-gear pass for the 16 legendary heroes (8 civs x M/F).
##
## Runs on top of the shared militia rig (plus HeroUnit's queen restyle for
## heroines) and adds each hero's ONE bold identity piece — Bencomo's horned
## anepa staff, Guayarmina's tall bow, Drake's captain hat — as 2-4 small
## Polygon2Ds, so a hero reads apart from its civ's regular soldiers and from
## every other hero at gameplay zoom. Purely cosmetic: no physics, nothing
## outside the Body rig.
##
## Contracts honoured:
##  - The Torso/gown is NEVER repainted — TeamDress owns it, armies keep
##    reading by player colour.
##  - Node names avoid TeamDress.GARMENT_NODES so a later dress pass cannot
##    dye the signature gear.
##  - Every added polygon stays smaller than the torso (~100 px^2) so
##    VisualFx.apply_owner_tint keeps picking the tunic as the tint target.
##  - Pieces are children of Body: the shared attack/walk rotation and the
##    facing flip carry them for free.

const META_APPLIED: StringName = &"hero_dress_applied"

## unit_data.resource_path is lost when a hero duplicates its data (Quijote's
## Rocinante passive), so the ability id doubles as the identity key.
const _KEY_BY_ABILITY: Dictionary = {
	"menceyes_charge":      "bencomo",
	"mountain_voice":       "dacil",
	"challenge":            "doramas",
	"fates_arrow":          "guayarmina",
	"ambush":               "guadarfia",
	"sandstorm":            "tibiabin",
	"forced_diplomacy":     "bethencourt",
	"honor_duel":           "catalina",
	"plunder":              "drake",
	"boarding_action":      "grace",
	"knight_errant_charge": "quijote",
	"call_to_arms":         "dulcinea",
	"calima":               "artaxerax",
	"rising_tide":          "cleito",
	"trade_route":          "hanno",
	"mercenary_pact":       "elissa",
}

## Heroes that ride into battle spawn on a mount rig instead of the militia
## foot rig; every hero spawner (setup, TC respawns, save restore, gallery)
## picks its scene through scene_path_for so the choice lives in ONE place.
## Rocinante is the scout's lean brown nag, not the knight's armoured charger.
const _MOUNTED_HEROES: Dictionary = {"hero_quijote": true}
const FOOT_SCENE: String = "res://scenes/units/militia.tscn"
const MOUNT_SCENE: String = "res://scenes/units/scout.tscn"

static func scene_path_for(hero_data_path: String) -> String:
	if _MOUNTED_HEROES.has(hero_data_path.get_file().get_basename()):
		return MOUNT_SCENE
	return FOOT_SCENE

const _GOLD: Color = Color(0.85, 0.70, 0.30)
const _GOLD_DARK: Color = Color(0.70, 0.56, 0.24)
const _BRONZE: Color = Color(0.78, 0.62, 0.32)
const _STEEL: Color = Color(0.62, 0.62, 0.68)
const _WOOD: Color = Color(0.42, 0.30, 0.16)
const _BONE: Color = Color(0.90, 0.87, 0.78)
const _CREAM: Color = Color(0.93, 0.89, 0.78)
const _WHITE: Color = Color(0.92, 0.92, 0.90)
const _HAIR_DARK: Color = Color(0.16, 0.12, 0.09)
const _SAND: Color = Color(0.85, 0.74, 0.52)
const _OCHRE: Color = Color(0.74, 0.52, 0.28)
const _TEAL: Color = Color(0.22, 0.48, 0.46)
const _PLUM: Color = Color(0.42, 0.20, 0.38)
const _SLATE: Color = Color(0.33, 0.36, 0.44)
const _CHARCOAL: Color = Color(0.16, 0.17, 0.20)

# unit_ref is untyped for the same reason as UnitDress.apply: the call is
# deferred from _ready and a unit freed the same frame would fail the typed
# argument conversion inside the message queue.
static func apply(unit_ref: Variant, _is_female: bool) -> void:
	if not is_instance_valid(unit_ref) or not (unit_ref is Node2D):
		return
	var unit: Node2D = unit_ref as Node2D
	if unit.has_meta(META_APPLIED):
		return
	var body: Node2D = unit.get_node_or_null("Body") as Node2D
	if body == null or VisualFx.find_head(unit) == null:
		return
	var key: String = _hero_key(unit)
	if key.is_empty():
		return
	unit.set_meta(META_APPLIED, true)
	match key:
		"bencomo":     _dress_bencomo(body)
		"dacil":       _dress_dacil(body)
		"doramas":     _dress_doramas(body)
		"guayarmina":  _dress_guayarmina(body)
		"guadarfia":   _dress_guadarfia(body)
		"tibiabin":    _dress_tibiabin(body)
		"bethencourt": _dress_bethencourt(body)
		"catalina":    _dress_catalina(body)
		"drake":       _dress_drake(body)
		"grace":       _dress_grace(body)
		"quijote":     _dress_quijote(body)
		"dulcinea":    _dress_dulcinea(body)
		"artaxerax":   _dress_artaxerax(body)
		"cleito":      _dress_cleito(body)
		"hanno":       _dress_hanno(body)
		"elissa":      _dress_elissa(body)

static func _hero_key(unit: Node2D) -> String:
	var data: Variant = unit.get("unit_data")
	if data == null or not (data is Resource):
		return ""
	var res: Resource = data as Resource
	var file: String = res.resource_path.get_file().get_basename()
	if file.begins_with("hero_"):
		return file.trim_prefix("hero_")
	var ability: Variant = res.get("hero_ability_id")
	if ability is String:
		return _KEY_BY_ABILITY.get(ability as String, "") as String
	return ""

const _BACKING: Color = Color(0.13, 0.11, 0.08, 0.95)

## Gear over the figure: appended last (draws over earlier siblings) at z 1
## so it also clears Helmet/hair/UnitDress pieces at z 0-1.
static func _piece(body: Node2D, piece_name: String, col: Color,
		pts: PackedVector2Array, z: int = 1) -> Polygon2D:
	var poly: Polygon2D = Polygon2D.new()
	poly.name = piece_name
	poly.color = col
	poly.polygon = pts
	poly.z_index = z
	body.add_child(poly)
	return poly

## Bright gear (gold crowns, bone horns, pearls) sits inside the hero aura's
## golden glow and washes out — a dark silhouette copy grown ~25% around the
## piece's centroid restores the contrast.
static func _backed_piece(body: Node2D, piece_name: String, col: Color,
		pts: PackedVector2Array, z: int = 1) -> Polygon2D:
	var centroid: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		centroid += p
	centroid /= float(pts.size())
	var back: Polygon2D = _piece(body, piece_name + "Back", _BACKING, pts, z)
	back.scale = Vector2(1.25, 1.25)
	back.position = centroid * -0.25
	return _piece(body, piece_name, col, pts, z)

## Cloaks/capes: child index 0 puts them behind the whole figure (heroines'
## HairBack included, which is also inserted at 0 — later inserts win).
## `backed` adds the same dark silhouette as _backed_piece — pale cloth
## otherwise melts into the aura glow.
static func _back_piece(body: Node2D, piece_name: String, col: Color,
		pts: PackedVector2Array, backed: bool = false) -> Polygon2D:
	if backed:
		var centroid: Vector2 = Vector2.ZERO
		for p: Vector2 in pts:
			centroid += p
		centroid /= float(pts.size())
		var back: Polygon2D = _piece(body, piece_name + "Back", _BACKING, pts, 0)
		back.scale = Vector2(1.18, 1.12)
		back.position = centroid * Vector2(-0.18, -0.12)
		body.move_child(back, 0)
	var poly: Polygon2D = _piece(body, piece_name, col, pts, 0)
	body.move_child(poly, 1 if backed else 0)
	return poly

static func _hide(body: Node2D, names: Array) -> void:
	for n: String in names:
		var node: CanvasItem = body.get_node_or_null(n) as CanvasItem
		if node != null:
			node.visible = false

static func _recolor(body: Node2D, poly_name: String, col: Color) -> void:
	var poly: Polygon2D = body.get_node_or_null(poly_name) as Polygon2D
	if poly != null:
		poly.color = col

## Trailing back cloak panel, shoulder to hem (rig back is -x).
static func _cloak_pts() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-6, -8), Vector2(-1, -8), Vector2(-2, 7), Vector2(-7, 6)])

# ── GUANCHES ──────────────────────────────────────────────────────────────

## Bencomo, mencey of Taoro: white goatskin tamarco cloak and the horned
## anepa royal staff instead of the militia steel-and-shield.
static func _dress_bencomo(body: Node2D) -> void:
	_hide(body, ["Helmet", "Shield", "ShieldBoss"])
	_piece(body, "HeroHair", Color(0.28, 0.19, 0.10), PackedVector2Array([
		Vector2(-4, -11), Vector2(-4, -14), Vector2(-2, -16), Vector2(2, -16),
		Vector2(4, -14), Vector2(4, -11), Vector2(2, -13), Vector2(-2, -13)]))
	_back_piece(body, "HeroCloak", Color(0.94, 0.92, 0.86), PackedVector2Array([
		Vector2(-7.5, -8), Vector2(-1.5, -8), Vector2(-2.5, 7), Vector2(-8.5, 6)]), true)
	_piece(body, "HeroStaff", _WOOD, PackedVector2Array([
		Vector2(-8, 8), Vector2(-6.8, 8), Vector2(-6.8, -18), Vector2(-8, -18)]))
	_backed_piece(body, "HeroStaffHorn", _BONE, PackedVector2Array([
		Vector2(-9.8, -18.6), Vector2(-8.6, -22.4), Vector2(-7.4, -19.6),
		Vector2(-6.2, -22.4), Vector2(-5.0, -18.6), Vector2(-7.4, -17.8)]))

## Dacil, queen of the valley: flower circlet over her hair and a pale
## flowing shawl — the peacemaker in white and blossom.
static func _dress_dacil(body: Node2D) -> void:
	_recolor(body, "Circlet", Color(0.30, 0.52, 0.26))
	var flower_cols: Array = [
		Color(0.94, 0.62, 0.74), Color(0.96, 0.94, 0.88), Color(0.94, 0.62, 0.74)]
	var flower_x: Array = [-2.0, 0.0, 2.0]
	var flower_y: Array = [-14.6, -16.2, -14.6]
	for i: int in range(3):
		var cx: float = flower_x[i] as float
		var cy: float = flower_y[i] as float
		_piece(body, "HeroFlower%d" % i, flower_cols[i] as Color, PackedVector2Array([
			Vector2(cx, cy - 1.0), Vector2(cx + 1.0, cy),
			Vector2(cx, cy + 1.0), Vector2(cx - 1.0, cy)]), 2)
	_back_piece(body, "HeroShawl", Color(0.88, 0.92, 0.88), PackedVector2Array([
		Vector2(-4, -7), Vector2(-8, -2), Vector2(-9, 6), Vector2(-5, 2)]), true)
	_piece(body, "HeroShawlWrap", Color(0.88, 0.92, 0.88), PackedVector2Array([
		Vector2(-4.5, -8), Vector2(4.5, -8), Vector2(3, -5.4), Vector2(-3, -5.4)]))

# ── CANARII ───────────────────────────────────────────────────────────────

## Doramas, guardian of Tamar: the oversized round war shield he tanked
## Spanish steel with, under a wild uncut mane.
static func _dress_doramas(body: Node2D) -> void:
	_hide(body, ["Helmet", "Shield", "ShieldBoss"])
	_piece(body, "HeroMane", _HAIR_DARK, PackedVector2Array([
		Vector2(-5, -9), Vector2(-5.5, -15), Vector2(-3, -17), Vector2(3, -17),
		Vector2(5.5, -15), Vector2(5, -9), Vector2(3, -12), Vector2(-3, -12)]))
	_piece(body, "HeroBigShieldRim", Color(0.36, 0.26, 0.14), PackedVector2Array([
		Vector2(-7, -8.5), Vector2(-3.4, -6.5), Vector2(-2.2, -1),
		Vector2(-3.4, 4.5), Vector2(-7, 6.5), Vector2(-10.6, 4.5),
		Vector2(-11.8, -1), Vector2(-10.6, -6.5)]))
	_piece(body, "HeroBigShield", Color(0.62, 0.48, 0.28), PackedVector2Array([
		Vector2(-7, -7.4), Vector2(-4.2, -5.8), Vector2(-3.2, -1),
		Vector2(-4.2, 3.8), Vector2(-7, 5.4), Vector2(-9.8, 3.8),
		Vector2(-10.8, -1), Vector2(-9.8, -5.8)]))
	_piece(body, "HeroBigShieldBoss", _BONE, PackedVector2Array([
		Vector2(-7, -2.6), Vector2(-5.4, -1), Vector2(-7, 0.6), Vector2(-8.6, -1)]))

## Guayarmina, the archeress of Tara: sword and shield swapped for a tall
## recurve bow and a feathered quiver on her back.
static func _dress_guayarmina(body: Node2D) -> void:
	_hide(body, ["Sword", "SwordGuard", "Shield", "ShieldBoss"])
	_piece(body, "HeroBowString", Color(0.85, 0.84, 0.78), PackedVector2Array([
		Vector2(4.8, -15.6), Vector2(5.4, -15.6), Vector2(5.4, 3.6), Vector2(4.8, 3.6)]))
	_piece(body, "HeroBow", Color(0.24, 0.15, 0.08), PackedVector2Array([
		Vector2(5, -16), Vector2(7.6, -13), Vector2(9, -6), Vector2(7.6, 1),
		Vector2(5, 4), Vector2(4.2, 3), Vector2(6.4, 0.4), Vector2(7.7, -6),
		Vector2(6.4, -12.4), Vector2(4.2, -15)]))
	_piece(body, "HeroQuiver", Color(0.46, 0.32, 0.18), PackedVector2Array([
		Vector2(-5, -13), Vector2(-2.6, -13.8), Vector2(-1.6, -7), Vector2(-4, -6.2)]))
	_piece(body, "HeroQuiverPlume", Color(0.22, 0.42, 0.24), PackedVector2Array([
		Vector2(-5.2, -13.2), Vector2(-4.4, -17.4), Vector2(-3.6, -13.6),
		Vector2(-2.8, -17.8), Vector2(-2.2, -13.8)]), 0)

# ── MAHOS ─────────────────────────────────────────────────────────────────

## Guadarfia, the desert shadow: sand turban and face veil (the only masked
## hero) with a dust-grey ambush cloak.
static func _dress_guadarfia(body: Node2D) -> void:
	_hide(body, ["Helmet"])
	_backed_piece(body, "HeroTurban", Color(0.55, 0.30, 0.16), PackedVector2Array([
		Vector2(-4.5, -11), Vector2(-3.5, -16), Vector2(0, -17.2),
		Vector2(3.5, -16), Vector2(4.5, -11)]))
	_piece(body, "HeroVeil", Color(0.72, 0.60, 0.40), PackedVector2Array([
		Vector2(-3.2, -9.8), Vector2(3.2, -9.8), Vector2(3.2, -7.6), Vector2(-3.2, -7.6)]), 2)
	_back_piece(body, "HeroDustCloak", Color(0.44, 0.38, 0.30), _cloak_pts())

## Tibiabin, queen of the dunes: a tall ochre desert wrap crowned with a
## golden crescent, sand veil streaming behind her.
static func _dress_tibiabin(body: Node2D) -> void:
	_hide(body, ["Circlet"])
	_backed_piece(body, "HeroTallWrap", _OCHRE, PackedVector2Array([
		Vector2(-3.6, -12.5), Vector2(-3, -18.5), Vector2(-1, -21),
		Vector2(1, -21), Vector2(3, -18.5), Vector2(3.6, -12.5)]), 2)
	_piece(body, "HeroCrescent", _GOLD, PackedVector2Array([
		Vector2(2.2, -20.6), Vector2(4.2, -18.8), Vector2(2.2, -17.2),
		Vector2(3.2, -18.8)]), 3)
	_back_piece(body, "HeroSandVeil", Color(0.90, 0.80, 0.60), PackedVector2Array([
		Vector2(-3.5, -14), Vector2(-8, -6), Vector2(-9, 5), Vector2(-5, -3)]), true)

# ── FRANKS ────────────────────────────────────────────────────────────────

## Jean de Bethencourt, the Norman lord: slate chaperon hat under a gold
## coronet and a cloak with an ermine collar — conquest by title, not blade.
static func _dress_bethencourt(body: Node2D) -> void:
	_hide(body, ["Helmet"])
	_piece(body, "HeroChaperon", _SLATE, PackedVector2Array([
		Vector2(-5, -11.2), Vector2(-4.4, -14.4), Vector2(0, -15.6),
		Vector2(4.4, -14.4), Vector2(5, -11.2), Vector2(0, -12.6)]), 2)
	_backed_piece(body, "HeroCoronet", _GOLD, PackedVector2Array([
		Vector2(-3.2, -14.2), Vector2(-3.2, -15.2), Vector2(-2, -17),
		Vector2(-1, -15.2), Vector2(0, -17.6), Vector2(1, -15.2),
		Vector2(2, -17), Vector2(3.2, -15.2), Vector2(3.2, -14.2)]), 3)
	_back_piece(body, "HeroCloak", _SLATE, _cloak_pts())
	_piece(body, "HeroErmineCollar", _WHITE, PackedVector2Array([
		Vector2(-5, -8), Vector2(5, -8), Vector2(3.8, -5.4), Vector2(-3.8, -5.4)]))

## Catalina de Bethencourt, the duellist: plumed cavalier hat and a steel
## pauldron on her sword shoulder — dressed for single combat.
static func _dress_catalina(body: Node2D) -> void:
	_hide(body, ["Circlet"])
	_piece(body, "HeroPlumeFthr", _WHITE, PackedVector2Array([
		Vector2(-2.5, -15.5), Vector2(-7, -19), Vector2(-9, -17), Vector2(-4.5, -14.4)]), 2)
	_piece(body, "HeroHatBrim", Color(0.26, 0.28, 0.34), PackedVector2Array([
		Vector2(-5.8, -12.8), Vector2(5.8, -12.8), Vector2(4.4, -14.8), Vector2(-4.4, -14.8)]), 3)
	_piece(body, "HeroHatCrown", Color(0.26, 0.28, 0.34), PackedVector2Array([
		Vector2(-3, -14.4), Vector2(-2.2, -17.6), Vector2(2.2, -17.6), Vector2(3, -14.4)]), 3)
	_piece(body, "HeroPauldron", _STEEL, PackedVector2Array([
		Vector2(2.8, -8.2), Vector2(6.2, -7.2), Vector2(5.6, -4.6), Vector2(2.8, -5.4)]), 2)

# ── BRITONS ───────────────────────────────────────────────────────────────

## Francis Drake, El Draque: gold-trimmed captain's hat, white ruff and a
## gilded cutlass guard — the privateer come ashore.
static func _dress_drake(body: Node2D) -> void:
	_hide(body, ["Helmet"])
	_recolor(body, "SwordGuard", _GOLD)
	_piece(body, "HeroHatBrim", _CHARCOAL, PackedVector2Array([
		Vector2(-5.4, -11.6), Vector2(5.4, -11.6), Vector2(4.2, -14.4), Vector2(-4.2, -14.4)]), 2)
	_piece(body, "HeroHatCrown", _CHARCOAL, PackedVector2Array([
		Vector2(-3, -14), Vector2(-2.4, -18), Vector2(2.4, -18), Vector2(3, -14)]), 2)
	_piece(body, "HeroHatTrim", _GOLD, PackedVector2Array([
		Vector2(-4.2, -14.4), Vector2(4.2, -14.4), Vector2(4.2, -13.4), Vector2(-4.2, -13.4)]), 3)
	_piece(body, "HeroRuff", _WHITE, PackedVector2Array([
		Vector2(-3.6, -8.8), Vector2(3.6, -8.8), Vector2(2.6, -6.6), Vector2(-2.6, -6.6)]))

## Grace O'Malley, the pirate queen: knotted black kerchief over her hair,
## a boarding baldric across the gown and a gilded cutlass.
static func _dress_grace(body: Node2D) -> void:
	_hide(body, ["Circlet"])
	_recolor(body, "SwordGuard", _GOLD)
	_piece(body, "HeroKerchief", Color(0.20, 0.20, 0.24), PackedVector2Array([
		Vector2(-4.5, -12), Vector2(-4, -15.5), Vector2(0, -17),
		Vector2(4, -15.5), Vector2(4.5, -12), Vector2(0, -13.5)]), 2)
	_piece(body, "HeroKerchiefTail", Color(0.20, 0.20, 0.24), PackedVector2Array([
		Vector2(-4.2, -14), Vector2(-7.2, -11), Vector2(-6.2, -9.6), Vector2(-3.6, -12.6)]), 2)
	_piece(body, "HeroBaldric", Color(0.32, 0.23, 0.14), PackedVector2Array([
		Vector2(-4, -7), Vector2(-2, -7.8), Vector2(5, 5), Vector2(3, 5.8)]))

# ── CASTELLANOS ───────────────────────────────────────────────────────────

## Don Quijote, knight errant: the golden barber's basin — the yelmo de
## Mambrino — and a couched tilting lance. Normally mounted on Rocinante
## (scout rig, see scene_path_for); the foot variant survives as a fallback
## for legacy saves that restored him onto the militia rig.
static func _dress_quijote(body: Node2D) -> void:
	if body.get_node_or_null("RiderHead") != null:
		_hide(body, ["Cap"])
		_backed_piece(body, "HeroBasinBrim", _GOLD_DARK, PackedVector2Array([
			Vector2(-3.8, -16.2), Vector2(3.8, -16.2), Vector2(2.8, -17.6), Vector2(-2.8, -17.6)]), 2)
		_piece(body, "HeroBasin", _GOLD, PackedVector2Array([
			Vector2(-2.6, -17.2), Vector2(-1.8, -19.6), Vector2(0.0, -20.4),
			Vector2(1.8, -19.6), Vector2(2.6, -17.2)]), 2)
		_piece(body, "HeroLance", Color(0.48, 0.34, 0.18), PackedVector2Array([
			Vector2(3.0, -8.6), Vector2(3.4, -10.2), Vector2(20.0, -12.4), Vector2(20.0, -10.8)]), 1)
		_backed_piece(body, "HeroLanceTip", _STEEL, PackedVector2Array([
			Vector2(20.0, -12.4), Vector2(24.5, -11.4), Vector2(20.0, -10.4)]), 1)
		return
	_hide(body, ["Helmet", "Sword", "SwordGuard"])
	_backed_piece(body, "HeroBasinBrim", _GOLD_DARK, PackedVector2Array([
		Vector2(-5.6, -11.4), Vector2(5.6, -11.4), Vector2(4.4, -13.2), Vector2(-4.4, -13.2)]), 2)
	_piece(body, "HeroBasin", _GOLD, PackedVector2Array([
		Vector2(-4, -12.4), Vector2(-3, -15.4), Vector2(0, -16.4),
		Vector2(3, -15.4), Vector2(4, -12.4)]), 2)
	_piece(body, "HeroLance", Color(0.48, 0.34, 0.18), PackedVector2Array([
		Vector2(3.4, 1.2), Vector2(5.2, 1.8), Vector2(13.7, -19.4), Vector2(11.9, -20.2)]))
	_backed_piece(body, "HeroLanceTip", _STEEL, PackedVector2Array([
		Vector2(11.9, -20.2), Vector2(13.7, -19.4), Vector2(14.8, -23.6)]))

## Dulcinea del Toboso: the raised rallying standard — a cream banner with a
## crimson heart — that calls the militias to arms.
static func _dress_dulcinea(body: Node2D) -> void:
	_piece(body, "HeroStandard", _WOOD, PackedVector2Array([
		Vector2(-6.8, 8), Vector2(-5.6, 8), Vector2(-5.6, -20), Vector2(-6.8, -20)]))
	_piece(body, "HeroBanner", _CREAM, PackedVector2Array([
		Vector2(-6.8, -20), Vector2(-13, -18.6), Vector2(-10.4, -17),
		Vector2(-13, -15.4), Vector2(-6.8, -14)]))
	_piece(body, "HeroBannerHeart", Color(0.72, 0.16, 0.20), PackedVector2Array([
		Vector2(-9.4, -18.2), Vector2(-8.2, -17.2), Vector2(-9.4, -16),
		Vector2(-10.6, -17.2)]), 2)

# ── ATLANTES ──────────────────────────────────────────────────────────────

## Artaxerax, the sea king: bronze fin crown, bronze trident held high and a
## teal cloak of the sunken kingdom.
static func _dress_artaxerax(body: Node2D) -> void:
	_hide(body, ["Helmet", "Sword", "SwordGuard"])
	_backed_piece(body, "HeroFinCrown", _BRONZE, PackedVector2Array([
		Vector2(-3.8, -11.5), Vector2(-3.8, -13), Vector2(-2, -16.5),
		Vector2(-1, -13.5), Vector2(0, -17.5), Vector2(1, -13.5),
		Vector2(2, -16.5), Vector2(3.8, -13), Vector2(3.8, -11.5)]), 2)
	_piece(body, "HeroTridentPole", Color(0.36, 0.28, 0.16), PackedVector2Array([
		Vector2(5.6, 6), Vector2(6.8, 6), Vector2(6.8, -14), Vector2(5.6, -14)]))
	_backed_piece(body, "HeroTridentHead", _BRONZE, PackedVector2Array([
		Vector2(3.4, -14), Vector2(3.4, -19), Vector2(4.6, -19), Vector2(4.6, -15.6),
		Vector2(5.6, -15.6), Vector2(5.6, -20.5), Vector2(6.8, -20.5), Vector2(6.8, -15.6),
		Vector2(7.8, -15.6), Vector2(7.8, -19), Vector2(9, -19), Vector2(9, -14)]))
	_back_piece(body, "HeroSeaCloak", Color(0.20, 0.44, 0.42), _cloak_pts())

## Cleito, mistress of tides: pearl diadem and a teal wave-shawl, with a
## driftwood staff bearing the pearl of Poseidon's rings.
static func _dress_cleito(body: Node2D) -> void:
	_recolor(body, "Circlet", Color(0.90, 0.90, 0.86))
	_backed_piece(body, "HeroPearl", Color(0.96, 0.96, 0.98), PackedVector2Array([
		Vector2(0, -18.6), Vector2(1.1, -17.4), Vector2(0, -16.2), Vector2(-1.1, -17.4)]), 2)
	_back_piece(body, "HeroTideShawl", _TEAL, PackedVector2Array([
		Vector2(-4, -8), Vector2(-8, -3), Vector2(-9, 6), Vector2(-5, 1)]))
	_piece(body, "HeroTideCollar", _TEAL, PackedVector2Array([
		Vector2(-4.5, -8), Vector2(4.5, -8), Vector2(3, -5.4), Vector2(-3, -5.4)]))
	_piece(body, "HeroOrbStaff", Color(0.40, 0.36, 0.28), PackedVector2Array([
		Vector2(-6.6, 6), Vector2(-5.4, 6), Vector2(-5.4, -16), Vector2(-6.6, -16)]))
	_backed_piece(body, "HeroOrb", Color(0.85, 0.92, 0.94), PackedVector2Array([
		Vector2(-6, -20), Vector2(-4.2, -18), Vector2(-6, -16), Vector2(-7.8, -18)]))

# ── FENICIOS ──────────────────────────────────────────────────────────────

## Hannon the navigator: pointed Phoenician cap, purple merchant stole and a
## staff crowned with a golden astrolabe disc.
static func _dress_hanno(body: Node2D) -> void:
	_hide(body, ["Helmet"])
	_piece(body, "HeroCap", _PLUM, PackedVector2Array([
		Vector2(-3.8, -11.4), Vector2(-3.2, -14), Vector2(-0.6, -18.4),
		Vector2(1.6, -14.4), Vector2(3.8, -11.4)]), 2)
	_piece(body, "HeroStole", _PLUM, PackedVector2Array([
		Vector2(-3.2, -8), Vector2(-1.6, -8), Vector2(-1.6, 3), Vector2(-3.2, 3)]))
	_piece(body, "HeroAstroStaff", _WOOD, PackedVector2Array([
		Vector2(-6.6, 7), Vector2(-5.4, 7), Vector2(-5.4, -15), Vector2(-6.6, -15)]))
	_backed_piece(body, "HeroAstroDisc", _GOLD, PackedVector2Array([
		Vector2(-6, -20.2), Vector2(-4.2, -19.4), Vector2(-3.4, -17.6),
		Vector2(-4.2, -15.8), Vector2(-6, -15), Vector2(-7.8, -15.8),
		Vector2(-8.6, -17.6), Vector2(-7.8, -19.4)]))
	_piece(body, "HeroAstroBar", _PLUM.darkened(0.3), PackedVector2Array([
		Vector2(-8.2, -18), Vector2(-3.8, -18), Vector2(-3.8, -17.2), Vector2(-8.2, -17.2)]), 2)

## Elissa, founder of Carthage: the gold mural crown — city walls worn as a
## diadem — over a deep purple royal mantle with gold trim.
static func _dress_elissa(body: Node2D) -> void:
	_hide(body, ["Circlet"])
	_backed_piece(body, "HeroMuralCrown", _GOLD, PackedVector2Array([
		Vector2(-3.6, -13), Vector2(-3.6, -16.4), Vector2(-2.4, -16.4),
		Vector2(-2.4, -15), Vector2(-0.6, -15), Vector2(-0.6, -16.4),
		Vector2(0.6, -16.4), Vector2(0.6, -15), Vector2(2.4, -15),
		Vector2(2.4, -16.4), Vector2(3.6, -16.4), Vector2(3.6, -13)]), 2)
	var mantle: Polygon2D = _back_piece(body, "HeroMantle", Color(0.38, 0.16, 0.34), _cloak_pts())
	var trim: Polygon2D = Polygon2D.new()
	trim.name = "HeroMantleTrim"
	trim.color = _GOLD
	trim.polygon = PackedVector2Array([
		Vector2(-7, 6), Vector2(-2, 7), Vector2(-2, 5.6), Vector2(-7, 4.6)])
	mantle.add_child(trim)

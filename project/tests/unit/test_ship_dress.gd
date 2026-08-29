extends GutTest

## Naval civ identity: the shared hulls (fishing boat, transport, war galley) are
## painted by ShipDress from CivStyle.NAVAL, so an Atlantes fleet never looks like
## a Guanches one. Ships used to force civ_id = "atlantes" to make the ocean
## passable, which left every civ sailing the same generic brown boat.

const WAR_GALLEY: String = "res://scenes/units/war_galley.tscn"
const TRANSPORT: String = "res://scenes/units/transport_ship.tscn"
const FISHING_BOAT: String = "res://scenes/units/fishing_boat.tscn"
const TRIREME: String = "res://scenes/units/trireme.tscn"

var _saved_player_civ: String = ""

func before_each() -> void:
	_saved_player_civ = MatchConfig.player_civ_id

func after_each() -> void:
	MatchConfig.player_civ_id = _saved_player_civ

## A dressed ship of `civ`. The dress pass is deferred from _ready; calling it
## here makes the test deterministic (it stamps the meta, so the deferred call
## that follows is a no-op).
func _dressed(scene_path: String, civ: String) -> Node2D:
	var ship: Node2D = (load(scene_path) as PackedScene).instantiate() as Node2D
	ship.set("player_id", 0)
	ship.set("civ_id", civ)
	add_child_autofree(ship)
	ShipDress.apply(ship, 0)
	return ship

func _poly(ship: Node2D, path: String) -> Polygon2D:
	return ship.get_node_or_null(path) as Polygon2D

# 1 — the hull material is civ data, not one shared brown boat
func test_hull_is_painted_from_the_civ_palette() -> void:
	var atlantes: Node2D = _dressed(WAR_GALLEY, "atlantes")
	var guanches: Node2D = _dressed(WAR_GALLEY, "guanches")
	assert_eq(_poly(atlantes, "Body/Hull").color,
		CivStyle.NAVAL["atlantes"]["hull"] as Color, "Atlantes sea-stone hull")
	assert_ne(_poly(atlantes, "Body/Hull").color, _poly(guanches, "Body/Hull").color,
		"two civs never share a hull colour")
	assert_ne(_poly(atlantes, "Body/Sail").color, _poly(guanches, "Body/Sail").color,
		"nor a sail colour")

# 2 — the naval civ also differs in silhouette, not only in tint
func test_atlantes_hull_carries_a_bronze_prow_fin() -> void:
	var atlantes: Node2D = _dressed(WAR_GALLEY, "atlantes")
	var fin: Polygon2D = _poly(atlantes, "Body/Hull/CivProw")
	assert_not_null(fin, "the Atlantes hull grows a prow ornament")
	assert_eq(fin.color, CivStyle.NAVAL["atlantes"]["accent"] as Color, "in bronze")
	assert_not_null(_poly(atlantes, "Body/Hull/CivProwB"), "plus a bronze waterline stripe")
	assert_null(_poly(_dressed(WAR_GALLEY, "guanches"), "Body/Hull/CivProw"),
		"a civ with motif 'none' stays plain")

func test_fenicios_hull_carries_the_painted_eye() -> void:
	assert_not_null(_poly(_dressed(WAR_GALLEY, "fenicios"), "Body/Hull/CivProw"),
		"Fenicios hulls are marked with their eye")

# 3 — sails: a plain one gets a civ band, an existing stripe is recoloured
func test_sail_band_is_added_only_when_missing() -> void:
	var galley: Node2D = _dressed(WAR_GALLEY, "britons")
	assert_not_null(_poly(galley, "Body/Sail/CivSailBand"),
		"the war galley sail has no stripe of its own, so one is added")
	var transport: Node2D = _dressed(TRANSPORT, "britons")
	assert_eq(_poly(transport, "Body/SailStripe").color,
		CivStyle.NAVAL["britons"]["accent"] as Color, "an existing stripe is retinted")
	assert_null(_poly(transport, "Body/Sail/CivSailBand"), "and not duplicated")

# 4 — hulls without a sail (fishing boat) must not break the pass
func test_sailless_hull_is_still_dressed() -> void:
	var boat: Node2D = _dressed(FISHING_BOAT, "mahos")
	assert_eq(_poly(boat, "Body/Hull").color, CivStyle.NAVAL["mahos"]["hull"] as Color)
	assert_eq(_poly(boat, "Body/Deck").color, CivStyle.NAVAL["mahos"]["deck"] as Color)

# 5 — applying twice (e.g. deferred call after a direct one) adds nothing
func test_dress_is_idempotent() -> void:
	var ship: Node2D = _dressed(WAR_GALLEY, "atlantes")
	var before: int = _poly(ship, "Body/Hull").get_child_count()
	ShipDress.apply(ship, 0)
	assert_eq(_poly(ship, "Body/Hull").get_child_count(), before,
		"the META_APPLIED stamp blocks a second pass")

# 6 — the civ-unique hull keeps the art it was drawn with
func test_trireme_keeps_its_own_art() -> void:
	var trireme: Node2D = (load(TRIREME) as PackedScene).instantiate() as Node2D
	trireme.set("player_id", 0)
	add_child_autofree(trireme)
	var hull_before: Color = _poly(trireme, "Body/Hull").color
	ShipDress.apply(trireme, 0)
	assert_eq(_poly(trireme, "Body/Hull").color, hull_before,
		"the Trireme opts out: it is already painted in Fenicios colours")
	assert_null(_poly(trireme, "Body/Hull/CivProw"), "no generic ornament on top of the eye")

# 7 — the hull belongs to the civ that built it, not to "atlantes"
func test_ship_civ_id_follows_the_owner() -> void:
	MatchConfig.player_civ_id = "britons"
	var ship: Node2D = (load(WAR_GALLEY) as PackedScene).instantiate() as Node2D
	ship.set("player_id", 0)
	add_child_autofree(ship)
	assert_eq(ship.get("civ_id") as String, "britons",
		"ShipBase derives civ_id from the owner (water access is is_amphibious() now)")
	assert_true(ship.call("is_amphibious") as bool, "and a British galley still sails")

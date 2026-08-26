class_name CivStyle

## Per-civilization visual identity for the procedural Polygon2D art.
##
## Ownership vs identity: the PLAYER colour (PlayerColors) keeps marking
## ownership (flags, trims, selection); the CIVILIZATION is identified by
## silhouette and material — roof shape, wall material, dress accents — so two
## players of the same civ still read apart, and two civs of similar colour
## still read apart at a glance.
##
## Consumed by IsoBuildingMassing (buildings) and the unit dress pass (units).
## All values are original art direction for this game.

## Roof silhouettes available to the building massing pass.
enum Roof {
	HIPPED,     # two visible sloped facets meeting at a ridge
	FLAT,       # flat slab with a low parapet
	DOMED,      # low rounded dome
	STEPPED,    # two stacked slabs, ziggurat-like
	GABLED,     # steep single ridge, tall profile
}

## style fields:
##   wall:        base wall colour (material identity)
##   wall_shade:  darker wall side
##   roof:        Roof enum silhouette
##   roof_color:  roof material colour (NOT the player colour)
##   trim:        secondary accent (awnings, beams, parapets, sashes)
##   headgear:    unit headwear id consumed by the dress pass
##                ("wrap", "hood", "cap", "crest", "circlet", "band", "none")
const STYLES: Dictionary = {
	"guanches": {   # volcanic stone builders
		"wall": Color(0.38, 0.35, 0.33), "wall_shade": Color(0.27, 0.25, 0.24),
		"roof": Roof.FLAT, "roof_color": Color(0.45, 0.42, 0.38),
		"trim": Color(0.78, 0.70, 0.55), "headgear": "band",
	},
	"canarii": {    # laurel-forest villages, whitewash + green wood
		"wall": Color(0.88, 0.86, 0.80), "wall_shade": Color(0.70, 0.68, 0.62),
		"roof": Roof.HIPPED, "roof_color": Color(0.22, 0.42, 0.24),
		"trim": Color(0.45, 0.32, 0.20), "headgear": "none",
	},
	"mahos": {      # desert adobe, domes and ochre
		"wall": Color(0.82, 0.70, 0.50), "wall_shade": Color(0.66, 0.54, 0.38),
		"roof": Roof.DOMED, "roof_color": Color(0.74, 0.60, 0.42),
		"trim": Color(0.55, 0.30, 0.16), "headgear": "wrap",
	},
	"franks": {     # timber-frame, steep slate roofs
		"wall": Color(0.85, 0.82, 0.74), "wall_shade": Color(0.68, 0.65, 0.58),
		"roof": Roof.GABLED, "roof_color": Color(0.35, 0.38, 0.46),
		"trim": Color(0.32, 0.24, 0.18), "headgear": "cap",
	},
	"britons": {    # grey ashlar keeps, near-black charcoal roofs
		# Charcoal (not slate) so the roof-first read never collides with the
		# franks slate gable — flagged by the blind identifiability critic.
		"wall": Color(0.60, 0.60, 0.62), "wall_shade": Color(0.45, 0.45, 0.48),
		"roof": Roof.GABLED, "roof_color": Color(0.15, 0.16, 0.18),
		"trim": Color(0.50, 0.42, 0.30), "headgear": "hood",
	},
	"castellanos": {  # cream stucco, terracotta hips
		"wall": Color(0.90, 0.85, 0.72), "wall_shade": Color(0.74, 0.68, 0.55),
		"roof": Roof.HIPPED, "roof_color": Color(0.72, 0.36, 0.22),
		"trim": Color(0.42, 0.30, 0.22), "headgear": "crest",
	},
	"atlantes": {   # pale sea-stone, stepped bronze
		"wall": Color(0.72, 0.78, 0.76), "wall_shade": Color(0.55, 0.62, 0.61),
		"roof": Roof.STEPPED, "roof_color": Color(0.62, 0.48, 0.28),
		"trim": Color(0.28, 0.55, 0.52), "headgear": "circlet",
	},
	"fenicios": {   # sandstone traders, purple awnings
		# Purple-washed roof plane: the trim line alone is 1-2 px and vanishes
		# at medium zoom, leaving fenicios confusable with the guanches flat
		# roof — flagged by the blind identifiability critic.
		"wall": Color(0.80, 0.72, 0.58), "wall_shade": Color(0.64, 0.56, 0.44),
		"roof": Roof.FLAT, "roof_color": Color(0.60, 0.46, 0.56),
		"trim": Color(0.45, 0.20, 0.42), "headgear": "wrap",
	},
}

const DEFAULT_STYLE: Dictionary = {
	"wall": Color(0.66, 0.63, 0.58), "wall_shade": Color(0.52, 0.49, 0.45),
	"roof": Roof.HIPPED, "roof_color": Color(0.36, 0.44, 0.58),
	"trim": Color(0.42, 0.34, 0.26), "headgear": "none",
}

static func civ_id_for_player(player_id: int) -> String:
	if player_id == 0:
		return MatchConfig.player_civ_id
	return MatchConfig.get_rival_civ_id(player_id)

static func style_for_civ(civ_id: String) -> Dictionary:
	return STYLES.get(civ_id, DEFAULT_STYLE) as Dictionary

static func style_for_player(player_id: int) -> Dictionary:
	return style_for_civ(civ_id_for_player(player_id))

class_name CampaignData
extends RefCounted

## The Canarii campaign: four missions of the Atlante invasion of Tamarán,
## played start to finish. Every mission is a deterministic world (fixed
## seed + MatchConfig fields) plus a script: side objectives the director
## tracks, scripted attack waves, and a victory kind.
##
## victory kinds:
##   "conquest" — the standard mode decides (VictoryMode.CONQUEST)
##   "regicide" — kill the enemy hero(es) (VictoryMode.REGICIDE)
##   "survive"  — hold out `survive_sec` of game time; the director declares
##                the win (mode stays CONQUEST so losing everything still loses)
## objective types (side objectives, informational checkmarks):
##   {"type":"train","unit":"Militia","count":8}
##   {"type":"build","building":"Dock","count":1}
##   {"type":"destroy","building":"Dock"}   (any enemy building of that class)
##   {"type":"herd","unit":"Sheep","count":2}   (dog trips completed home)
## wave: {"at_sec": 240.0, "units": {"Militia": 3, "Archer": 2}} — spawns at
## the FIRST rival's town center and attack-moves the player's base.
##
## Map/resource/victory values are raw MatchConfig enum ints (const tables
## cannot reference an autoload): map_type 0=Plains 1=Standard 2=Volcanic
## 3=Desert 4=Islands; map_size 0=S 1=M 2=L; resources 0=Scarce 1=Normal
## 2=Abundant; victory_mode 0=Conquest 1=Regicide.

const MISSIONS: Array = [
	{
		# The prologue IS the tutorial: a guided first settlement for players
		# who start at the campaign. Optional — mission 1 is open regardless.
		"id": "prologo",
		"title_key": "CAMP_M0_TITLE",
		"intro_key": "CAMP_M0_INTRO",
		"outro_key": "CAMP_M0_OUTRO",
		"tutorial": true,
		"seed": 0,
		"map_type": 0, "map_size": 0, "resources": 4,
		# The prologue used to play Guanches vs Castellanos — a different
		# protagonist AND enemy than the campaign it introduces. It now
		# opens the same war: Canarii against an Atlante scouting party.
		"player_civ": "canarii", "rival_civs": ["atlantes"],
		"starting_age": 0, "victory": "conquest", "weather": false,
		"objectives": [], "waves": [],
	},
	{
		"id": "vanguardia",
		"title_key": "CAMP_M1_TITLE",
		"intro_key": "CAMP_M1_INTRO",
		"outro_key": "CAMP_M1_OUTRO",
		"seed": 91101,
		"map_type": 1, "map_size": 0, "resources": 1,
		"player_civ": "canarii", "rival_civs": ["atlantes"],
		"starting_age": 0, "victory": "conquest", "weather": false,
		"hold_offense": true,
		"objectives": [
			{"type": "train", "unit": "Militia", "count": 8, "key": "CAMP_M1_OBJ_TRAIN"},
			{"type": "build", "building": "Mill", "count": 1, "key": "CAMP_M1_OBJ_MILL"},
			{"type": "herd", "unit": "Sheep", "count": 2, "key": "CAMP_M1_OBJ_HERD"},
		],
		"waves": [
			{"at_sec": 300.0, "units": {"Militia": 3}},
			{"at_sec": 600.0, "units": {"Militia": 3, "Archer": 2}},
		],
	},
	{
		"id": "tierra_de_fuego",
		"title_key": "CAMP_M2_TITLE",
		"intro_key": "CAMP_M2_INTRO",
		"outro_key": "CAMP_M2_OUTRO",
		"seed": 91202,
		"map_type": 2, "map_size": 1, "resources": 0,
		"player_civ": "canarii", "rival_civs": ["atlantes"],
		"starting_age": 1, "victory": "survive", "survive_sec": 720.0,
		"weather": true, "hold_offense": true,
		"objectives": [
			{"type": "build", "building": "WatchTower", "count": 2, "key": "CAMP_M2_OBJ_TOWERS"},
		],
		"waves": [
			{"at_sec": 150.0, "units": {"Militia": 4}},
			{"at_sec": 330.0, "units": {"Militia": 4, "Archer": 3}},
			{"at_sec": 510.0, "units": {"ManAtArms": 4, "Archer": 3}},
			{"at_sec": 650.0, "units": {"ManAtArms": 5, "Archer": 4, "Scout": 2}},
		],
	},
	{
		"id": "el_estrecho",
		"title_key": "CAMP_M3_TITLE",
		"intro_key": "CAMP_M3_INTRO",
		"outro_key": "CAMP_M3_OUTRO",
		"seed": 91303,
		"map_type": 4, "map_size": 1, "resources": 1,
		"player_civ": "canarii", "rival_civs": ["atlantes"],
		"starting_age": 2, "victory": "conquest", "weather": true,
		"objectives": [
			{"type": "build", "building": "Dock", "count": 1, "key": "CAMP_M3_OBJ_DOCK"},
			{"type": "destroy", "building": "Dock", "key": "CAMP_M3_OBJ_SINK"},
		],
		"waves": [],
	},
	{
		"id": "la_ultima_montana",
		"title_key": "CAMP_M4_TITLE",
		"intro_key": "CAMP_M4_INTRO",
		"outro_key": "CAMP_M4_OUTRO",
		"seed": 91404,
		"map_type": 2, "map_size": 2, "resources": 2,
		"player_civ": "canarii", "rival_civs": ["atlantes", "atlantes"],
		"starting_age": 2, "victory": "regicide", "weather": true,
		"objectives": [],
		"waves": [
			{"at_sec": 420.0, "units": {"ManAtArms": 5, "Knight": 2}},
			{"at_sec": 900.0, "units": {"Knight": 4, "Archer": 4}},
		],
	},
]

static func mission(index: int) -> Dictionary:
	if index < 0 or index >= MISSIONS.size():
		return {}
	return MISSIONS[index] as Dictionary

static func size() -> int:
	return MISSIONS.size()

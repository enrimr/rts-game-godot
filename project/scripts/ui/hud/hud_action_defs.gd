class_name HudActionDefs
extends RefCounted

## Static action-table data and pure helpers for the HUD command grid.
## Costs are NOT baked into these tables: build buttons resolve through
## WorldPlacement.building_costs (the single .tres-backed table player and AI
## both pay) and train buttons read each unit's UnitResource — a rebalance can
## never make a button lie about the price the simulation will charge.

## Destroy shows a skull for units and a crumbling building for structures.
const DESTROY_ACTION: Dictionary = {"id": "destroy", "label": "ACTION_DESTROY", "glyph": "destroy_unit", "cost": {}, "key": KEY_DELETE, "description": "TOOLTIP_DESTROY"}
const DESTROY_BUILDING_ACTION: Dictionary = {"id": "destroy", "label": "ACTION_DESTROY", "glyph": "destroy", "cost": {}, "key": KEY_DELETE, "description": "TOOLTIP_DESTROY"}

## Command id -> UiIcons glyph. Entity actions (train:/build:/market:hire:)
## use IconBaker miniatures instead; anything else falls back to a short
## text abbreviation. Per-action dicts may override with a "glyph" key.
const ACTION_GLYPHS: Dictionary = {
	"gather_wood": "gather_wood",
	"gather_gold": "gather_gold",
	"gather_stone": "gather_stone",
	"gather_food": "gather_food",
	"build_menu": "build",
	"repair": "repair",
	"move_to": "move",
	"stop": "stop",
	"attack_move": "attack",
	"patrol": "move",
	"attack_ground": "attack_ground",
	"cover_fire": "cover_fire",
	"show_path": "patrol_route",
	"scout_explore": "patrol_route",
	"scout_explore_stop": "patrol_route",
	"advance_age": "age_up",
	"hero_ability": "ability",
	"unload": "unload",
	"ungarrison": "unload",
	"garrison_into": "garrison_into",
	"town_bell": "town_bell",
	"stance:aggressive": "stance_aggressive",
	"stance:defensive": "stance_defensive",
	"stance:stand_ground": "stance_stand_ground",
	"stance:passive": "stance_passive",
	"formation:line": "formation_line",
	"formation:box": "formation_box",
	"formation:spread": "formation_spread",
	"formation:rings": "formation_rings",
	"back": "page_prev",
	"gate_lock": "gate_lock",
}

const VILLAGER_ACTIONS: Array = [
	{"id": "gather_wood",  "label": "ACTION_WOOD",         "color": Color(0.20, 0.55, 0.15), "cost": {}, "key": KEY_C, "description": "TOOLTIP_GATHER_WOOD"},
	{"id": "gather_gold",  "label": "ACTION_GOLD",         "color": Color(0.75, 0.65, 0.10), "cost": {}, "key": KEY_G, "description": "TOOLTIP_GATHER_GOLD"},
	{"id": "gather_stone", "label": "ACTION_STONE",        "color": Color(0.55, 0.55, 0.55), "cost": {}, "key": KEY_T, "description": "TOOLTIP_GATHER_STONE"},
	{"id": "gather_food",  "label": "ACTION_FOOD",         "color": Color(0.60, 0.20, 0.15), "cost": {}, "key": KEY_H, "description": "TOOLTIP_GATHER_FOOD"},
	{"id": "build_menu",   "label": "ACTION_BUILD",        "color": Color(0.20, 0.30, 0.60), "cost": {}, "key": KEY_B, "description": "TOOLTIP_BUILD_MENU"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",      "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE",  "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "patrol",       "label": "ACTION_PATROL",       "color": Color(0.25, 0.35, 0.60), "cost": {}, "key": KEY_R, "description": "TOOLTIP_PATROL"},
	{"id": "stop",         "label": "ACTION_STOP",         "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	{"id": "garrison_into", "label": "ACTION_GARRISON",    "color": Color(0.45, 0.38, 0.20), "cost": {}, "key": KEY_E, "description": "TOOLTIP_GARRISON"},
	{"id": "show_path",    "label": "ACTION_SHOW_PATH",    "color": Color(0.15, 0.45, 0.55), "cost": {}, "key": KEY_P, "description": "TOOLTIP_SHOW_PATH"},
	DESTROY_ACTION,
]

## Build-menu entries: the cost is resolved per open through
## WorldPlacement.building_costs — see build_action().
const BUILD_ACTIONS: Array = [
	{"id": "build:house",           "label": "ACTION_HOUSE",          "color": Color(0.50, 0.38, 0.22), "key": KEY_H, "description": "TOOLTIP_BUILD_HOUSE",          "min_age": 0},
	{"id": "build:barracks",        "label": "ACTION_BARRACKS",       "color": Color(0.45, 0.22, 0.18), "key": KEY_B, "description": "TOOLTIP_BUILD_BARRACKS",       "min_age": 0},
	{"id": "build:archery_range",   "label": "ACTION_ARCHERY_RANGE",  "color": Color(0.25, 0.45, 0.20), "key": KEY_A, "description": "TOOLTIP_BUILD_ARCHERY_RANGE",  "min_age": 1},
	{"id": "build:blacksmith",      "label": "ACTION_BLACKSMITH",     "color": Color(0.55, 0.40, 0.20), "key": KEY_K, "description": "TOOLTIP_BUILD_BLACKSMITH",     "min_age": 1},
	{"id": "build:stable",          "label": "ACTION_STABLE",         "color": Color(0.40, 0.30, 0.15), "key": KEY_J, "description": "TOOLTIP_BUILD_STABLE",         "min_age": 1},
	{"id": "build:lumber_camp",     "label": "ACTION_LUMBER",         "color": Color(0.30, 0.20, 0.08), "key": KEY_L, "description": "TOOLTIP_BUILD_LUMBER",         "min_age": 0},
	{"id": "build:mining_camp",     "label": "ACTION_MINING",         "color": Color(0.50, 0.46, 0.34), "key": KEY_N, "description": "TOOLTIP_BUILD_MINING",         "min_age": 0},
	{"id": "build:farm",            "label": "ACTION_FARM",           "color": Color(0.60, 0.52, 0.18), "key": KEY_F, "description": "TOOLTIP_BUILD_FARM",           "min_age": 0},
	{"id": "build:mill",            "label": "ACTION_MILL",           "color": Color(0.68, 0.56, 0.30), "key": KEY_M, "description": "TOOLTIP_BUILD_MILL",           "min_age": 0},
	{"id": "build:wall_segment",    "label": "ACTION_WALL",           "color": Color(0.55, 0.52, 0.48), "key": KEY_Q, "description": "TOOLTIP_BUILD_WALL",           "min_age": 0},
	{"id": "build:gate",            "label": "ACTION_GATE",           "color": Color(0.42, 0.30, 0.12), "key": KEY_G, "description": "TOOLTIP_BUILD_GATE",           "min_age": 0},
	{"id": "build:watch_tower",     "label": "ACTION_WATCH_TOWER",    "color": Color(0.45, 0.42, 0.38), "key": KEY_O, "description": "TOOLTIP_WATCH_TOWER",          "min_age": 1},
	{"id": "build:dock",            "label": "ACTION_DOCK",           "color": Color(0.18, 0.32, 0.55), "key": KEY_C, "description": "TOOLTIP_BUILD_DOCK",           "min_age": 0},
	{"id": "build:market",          "label": "ACTION_MARKET",         "color": Color(0.65, 0.50, 0.10), "key": KEY_R, "description": "TOOLTIP_BUILD_MARKET",         "min_age": 1},
	{"id": "build:university",      "label": "ACTION_UNIVERSITY",     "color": Color(0.20, 0.30, 0.50), "key": KEY_U, "description": "TOOLTIP_BUILD_UNIVERSITY",     "min_age": 2},
	{"id": "build:temple",          "label": "ACTION_TEMPLE",         "color": Color(0.50, 0.30, 0.55), "key": KEY_T, "description": "TOOLTIP_BUILD_TEMPLE",         "min_age": 2},
	{"id": "build:siege_workshop",  "label": "ACTION_SIEGE_WORKSHOP", "color": Color(0.42, 0.32, 0.18), "key": KEY_I, "description": "TOOLTIP_BUILD_SIEGE_WORKSHOP", "min_age": 2},
	{"id": "build:town_center",     "label": "ACTION_TOWN_CENTER",    "color": Color(0.55, 0.18, 0.12), "key": KEY_Y, "description": "TOOLTIP_BUILD_TOWN_CENTER",    "min_age": 2},
	{"id": "build:wonder",          "label": "ACTION_WONDER",         "color": Color(0.75, 0.62, 0.12), "key": KEY_V, "description": "TOOLTIP_BUILD_WONDER",         "min_age": 3},
	{"id": "back",                  "label": "ACTION_BACK",           "color": Color(0.25, 0.25, 0.25), "cost": {}, "key": KEY_ESCAPE, "description": "TOOLTIP_BUILD_BACK"},
]

const TOWN_BELL_ACTION: Dictionary = {"id": "town_bell", "label": "ACTION_TOWN_BELL", "color": Color(0.70, 0.55, 0.15), "cost": {}, "key": KEY_G, "description": "TOOLTIP_TOWN_BELL"}

const UNIT_ACTIONS: Array = [
	{"id": "move_to",      "label": "ACTION_MOVE_TO",      "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE",  "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "patrol",       "label": "ACTION_PATROL",       "color": Color(0.25, 0.35, 0.60), "cost": {}, "key": KEY_R, "description": "TOOLTIP_PATROL"},
	{"id": "stop",         "label": "ACTION_STOP",         "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	{"id": "show_path",    "label": "ACTION_SHOW_PATH",    "color": Color(0.15, 0.45, 0.55), "cost": {}, "key": KEY_P, "description": "TOOLTIP_SHOW_PATH"},
	DESTROY_ACTION,
]

const RANGED_ACTIONS: Array = [
	{"id": "cover_fire",   "label": "ACTION_COVER_FIRE",  "color": Color(0.60, 0.45, 0.10), "cost": {}, "key": KEY_C, "description": "TOOLTIP_COVER_FIRE"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "attack_move",  "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
	{"id": "patrol",       "label": "ACTION_PATROL",      "color": Color(0.25, 0.35, 0.60), "cost": {}, "key": KEY_R, "description": "TOOLTIP_PATROL"},
	{"id": "stop",         "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	DESTROY_ACTION,
]

const SIEGE_ACTIONS: Array = [
	{"id": "cover_fire",   "label": "ACTION_COVER_FIRE",  "color": Color(0.65, 0.40, 0.08), "cost": {}, "key": KEY_C, "description": "TOOLTIP_COVER_FIRE"},
	{"id": "move_to",      "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
	{"id": "stop",         "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	DESTROY_ACTION,
]

const ANIMAL_ACTIONS: Array = [
	{"id": "move_to", "label": "ACTION_MOVE_TO", "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
]

## AoE2 stances + formations, appended to every military selection. Stances
## submit a command per selected unit; the formation buttons only set which
## layout the NEXT group move fans out into (local UI state).
const COMBAT_MODE_ACTIONS: Array = [
	{"id": "stance:aggressive",   "label": "ACTION_STANCE_AGGRESSIVE",   "color": Color(0.55, 0.16, 0.10), "cost": {}, "description": "TOOLTIP_STANCE_AGGRESSIVE"},
	{"id": "stance:defensive",    "label": "ACTION_STANCE_DEFENSIVE",    "color": Color(0.16, 0.35, 0.55), "cost": {}, "description": "TOOLTIP_STANCE_DEFENSIVE"},
	{"id": "stance:stand_ground", "label": "ACTION_STANCE_STAND_GROUND", "color": Color(0.35, 0.32, 0.18), "cost": {}, "description": "TOOLTIP_STANCE_STAND_GROUND"},
	{"id": "stance:passive",      "label": "ACTION_STANCE_PASSIVE",      "color": Color(0.30, 0.30, 0.34), "cost": {}, "description": "TOOLTIP_STANCE_PASSIVE"},
	{"id": "formation:line",   "label": "ACTION_FORMATION_LINE",   "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_LINE"},
	{"id": "formation:box",    "label": "ACTION_FORMATION_BOX",    "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_BOX"},
	{"id": "formation:spread", "label": "ACTION_FORMATION_SPREAD", "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_SPREAD"},
	{"id": "formation:rings",  "label": "ACTION_FORMATION_RINGS",  "color": Color(0.22, 0.40, 0.28), "cost": {}, "description": "TOOLTIP_FORMATION_RINGS"},
]

const BUILDING_ACTIONS: Array = [
	DESTROY_BUILDING_ACTION,
]

const GATE_ACTIONS: Array = [
	{"id": "gate_lock", "label": "UI_GATE_LOCK", "cost": {}, "key": KEY_O, "description": "TOOLTIP_GATE_LOCK"},
	DESTROY_BUILDING_ACTION,
]

const MERCENARY_UNIT_DEFS: Array[Dictionary] = [
	{"id": "militia",     "display": "Militia",     "age": 0},
	{"id": "scout",       "display": "Scout",       "age": 0},
	{"id": "archer",      "display": "Archer",      "age": 1},
	{"id": "heavy_scout", "display": "Heavy Scout", "age": 1},
	{"id": "knight",      "display": "Knight",      "age": 2},
	{"id": "mangonel",    "display": "Mangonel",    "age": 2},
]

const STANCE_NAMES: Array[String] = ["aggressive", "defensive", "stand_ground", "passive"]

## Train hotkeys by unit id. Only one building's buttons show at a time, so
## the same key may repeat across building types without conflict.
const TRAIN_KEYS: Dictionary = {
	"villager": KEY_V,
	"militia": KEY_M, "archer": KEY_R, "pikeman": KEY_P,
	"menceyes_guard": KEY_U, "ravine_archer": KEY_U, "longbowman": KEY_U,
	"conquistador": KEY_U, "tidecaller": KEY_U,
	"heavy_scout": KEY_H, "knight": KEY_K,
	"sand_raider": KEY_U, "chevalier_normand": KEY_U,
	"fishing_boat": KEY_F, "transport_ship": KEY_T, "war_galley": KEY_G, "trireme": KEY_U,
	"battering_ram": KEY_B, "mangonel": KEY_M, "trebuchet": KEY_T,
	"presa_canario": KEY_P, "harimaguada": KEY_H,
}

static func key_label(keycode: int) -> String:
	match keycode:
		KEY_DELETE: return "Del"
		KEY_ESCAPE: return "Esc"
		_: return char(keycode)

## Short fallback code for glyph-less actions: word initials, or the first
## three letters of a single-word name. The full name lives in the tooltip.
static func abbreviate(title: String) -> String:
	var words: PackedStringArray = title.strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return words[0].substr(0, 3).to_upper()
	var abbr: String = ""
	for w: String in words.slice(0, 3):
		abbr += w.substr(0, 1).to_upper()
	return abbr

## True when a label extra is nothing but "500F 175W"-style cost tokens, which
## the cost strip and the plain-text tooltip line now cover.
static func is_cost_tokens(text: String) -> bool:
	var parts: PackedStringArray = text.split(" ", false)
	if parts.is_empty():
		return false
	for p: String in parts:
		if p.length() < 2:
			return false
		# English (Food/Wood/Gold/Stone) and Spanish (Comida/Madera/Oro/
		# Piedra) label suffixes — the Spanish "50C" was leaking into
		# tooltips next to the glyph cost row.
		if p.substr(p.length() - 1) not in ["F", "W", "G", "S", "C", "M", "O", "P"]:
			return false
		if not p.substr(0, p.length() - 1).is_valid_int():
			return false
	return true

## Thin accent edge colour by action category: economy green, combat red,
## production gold, everything else utility blue.
static func accent_for_action(action_id: String) -> Color:
	if action_id.begins_with("market:hire:") or action_id.begins_with("train:") \
			or action_id.begins_with("research:") or action_id == "advance_age":
		return HudStyle.ACCENT_PRODUCTION
	if action_id.begins_with("gather_") or action_id.begins_with("build") \
			or action_id.begins_with("market:") or action_id == "repair":
		return HudStyle.ACCENT_ECONOMY
	if action_id in ["attack_move", "attack_ground", "cover_fire", "stop",
			"destroy", "hero_ability", "patrol"]:
		return HudStyle.ACCENT_COMBAT
	return HudStyle.ACCENT_UTILITY

## Maps an entity-creating action to the scene it spawns; icons come from
## rendering that real scene (IconBaker), so they follow the player's civ style.
static func action_icon_scene(action_id: String) -> String:
	var path: String = ""
	if action_id.begins_with("train:"):
		path = "res://scenes/units/%s.tscn" % action_id.trim_prefix("train:")
	elif action_id.begins_with("build:"):
		path = "res://scenes/buildings/%s.tscn" % action_id.trim_prefix("build:")
	elif action_id.begins_with("market:hire:"):
		path = "res://scenes/units/%s.tscn" % action_id.trim_prefix("market:hire:")
	else:
		return ""
	return path if ResourceLoader.exists(path) else ""

static func unit_costs(data: UnitResource) -> Dictionary:
	var costs: Dictionary = {}
	if data.cost_food > 0: costs["food"] = data.cost_food
	if data.cost_wood > 0: costs["wood"] = data.cost_wood
	if data.cost_gold > 0: costs["gold"] = data.cost_gold
	return costs

static func unit_cost_label(data: UnitResource) -> String:
	var parts: Array[String] = []
	if data.cost_food > 0: parts.append("%dF" % data.cost_food)
	if data.cost_wood > 0: parts.append("%dW" % data.cost_wood)
	if data.cost_gold > 0: parts.append("%dG" % data.cost_gold)
	return " ".join(PackedStringArray(parts))

## One train button from a building's get_available_units() def: localized
## name, cost from the unit's .tres, hotkey from TRAIN_KEYS.
static func train_action(def: Dictionary) -> Dictionary:
	var uid: String = def["id"] as String
	var data: UnitResource = load(def["data"] as String) as UnitResource
	return {
		"id": "train:" + uid,
		"label": EntityNames.unit_name(data) + "\n" + unit_cost_label(data),
		"color": def["color"] as Color,
		"cost": unit_costs(data),
		"key": TRAIN_KEYS.get(uid, KEY_NONE) as Key,
		"description": def.get("description", "") as String,
	}

## One build-menu button with its cost resolved from the single .tres-backed
## table the placement command will actually charge — filtered through the
## player's civ discounts so the button never lies (Mahos timber).
static func build_action(def: Dictionary, player_id: int) -> Dictionary:
	var bid: String = def.get("id", "") as String
	if not bid.begins_with("build:"):
		return def
	return def.merged({"cost": CivBonusManager.get_building_costs(player_id,
		WorldPlacement.building_costs(bid.trim_prefix("build:")))}, true)

## Per-civ age unlocks: the Fenicios open their market in the Dark Age.
static func build_min_age(def: Dictionary, player_id: int) -> int:
	if def.get("id", "") as String == "build:market" \
			and CivBonusManager.has_bonus(player_id, "market_available_dark_age"):
		return 0
	return def.get("min_age", 0) as int

## One research button entry: localized name + cost lines, description in the
## tooltip, upgrade accent. With queueing, an ACTIVE research no longer locks
## the button — only a tech already pending (active or queued) HERE does.
static func tech_action(tech: TechnologyResource, pending: Array) -> Dictionary:
	var cost_str: String = ""
	if tech.cost_food > 0: cost_str += "\n%dF" % tech.cost_food
	if tech.cost_wood > 0: cost_str += "\n%dW" % tech.cost_wood
	if tech.cost_gold > 0: cost_str += "\n%dG" % tech.cost_gold
	var tech_costs: Dictionary = {}
	if tech.cost_food > 0: tech_costs["food"] = tech.cost_food
	if tech.cost_wood > 0: tech_costs["wood"] = tech.cost_wood
	if tech.cost_gold > 0: tech_costs["gold"] = tech.cost_gold
	var is_upgrade: bool = tech.upgrade_from_unit_id != ""
	return {
		"id": "research:%s" % tech.id,
		"label": EntityNames.tech_name(tech) + cost_str,
		"color": Color(0.45, 0.32, 0.10) if is_upgrade else Color(0.25, 0.45, 0.55),
		"cost": tech_costs,
		"key": 0,
		"raw_label": true,
		"is_upgrade": is_upgrade,
		"locked": tech.id in pending,
		"description": EntityNames.tech_description(tech),
	}

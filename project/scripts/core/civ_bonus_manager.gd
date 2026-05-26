extends Node

var _multipliers: Dictionary = {}  # {player_id: Dictionary}

func _ready() -> void:
	EventBus.age_advance_complete.connect(_on_age_advance_complete)

func _on_age_advance_complete(player_id: int, _new_age: int) -> void:
	on_age_advanced(player_id)

func init_player(player_id: int, civ_id: String) -> void:
	var path: String = "res://resources/civilizations/%s.tres" % civ_id
	var civ: CivilizationResource = load(path) as CivilizationResource
	if civ == null:
		_multipliers[player_id] = {}
		return
	_multipliers[player_id] = (civ.stat_multipliers as Dictionary).duplicate()

func get_multiplier(player_id: int, key: String) -> float:
	var player_mults: Variant = _multipliers.get(player_id)
	if player_mults == null:
		return 0.0 if key in _ADDITIVE_KEYS else 1.0
	var val: Variant = (player_mults as Dictionary).get(key)
	if val == null:
		return 0.0 if key in _ADDITIVE_KEYS else 1.0
	return val as float

const _ADDITIVE_KEYS: Array[String] = [
	"unit_armor_melee", "archer_armor_pierce", "archer_range_flat",
	"archer_range_bonus_per_age", "free_blacksmith_tech_per_age",
]

func apply_tech_effect(player_id: int, effect_key: String, value: float) -> void:
	if not _multipliers.has(player_id):
		_multipliers[player_id] = {}
	var current: float = get_multiplier(player_id, effect_key)
	if effect_key in _ADDITIVE_KEYS:
		# Armor bonuses accumulate as flat points, not as multipliers
		(_multipliers[player_id] as Dictionary)[effect_key] = current + value
	else:
		(_multipliers[player_id] as Dictionary)[effect_key] = current * value

const _ARCHER_IDS: Array[String] = ["archer", "ravine_archer", "longbowman"]

func get_unit_cost_multiplier(player_id: int, unit_id: String) -> Dictionary:
	var result: Dictionary = {}
	# canarii archer_food_cost applies to all archer-class units
	if unit_id in _ARCHER_IDS:
		var mult: float = get_multiplier(player_id, "archer_food_cost")
		if mult != 1.0:
			result["food"] = mult
	# mahos building_wood_cost — not a unit cost, skip for units
	return result

func get_gather_rate_multiplier(player_id: int, resource: String) -> float:
	match resource:
		"food":
			return get_multiplier(player_id, "villager_food_gather_rate")
		"wood":
			return get_multiplier(player_id, "villager_wood_gather_rate")
		"gold":
			return get_multiplier(player_id, "villager_gold_gather_rate")
		"stone":
			return get_multiplier(player_id, "villager_stone_gather_rate")
	return 1.0

func get_age_advance_cost_multiplier(player_id: int) -> float:
	return get_multiplier(player_id, "age_advance_cost")

func get_unit_hp_multiplier(player_id: int, unit_id: String) -> float:
	if unit_id == "villager":
		return get_multiplier(player_id, "villager_hp")
	if unit_id == "scout" or unit_id == "heavy_scout" or unit_id == "knight" or unit_id == "sand_raider":
		return get_multiplier(player_id, "cavalry_hp")
	if unit_id == "militia" or unit_id == "pikeman":
		return get_multiplier(player_id, "swordsman_hp")
	if unit_id == "fishing_boat" or unit_id == "transport_ship" or unit_id == "war_galley" or unit_id == "tidecaller" or unit_id == "trireme":
		return get_multiplier(player_id, "ship_hp")
	return 1.0

func get_unit_speed_multiplier(player_id: int, unit_id: String) -> float:
	# mahos scout_speed — also applies to sand_raider (their light cavalry unique unit)
	if unit_id == "scout" or unit_id == "sand_raider":
		return get_multiplier(player_id, "scout_speed")
	# mahos light_cavalry_speed (for any light cavalry unit)
	if unit_id == "light_cavalry":
		return get_multiplier(player_id, "light_cavalry_speed")
	return 1.0

func get_unit_attack_multiplier(player_id: int, unit_id: String) -> float:
	if unit_id in _ARCHER_IDS:
		var base: float = get_multiplier(player_id, "archer_attack")
		var global_mult: float = get_multiplier(player_id, "unit_attack")
		return base * global_mult
	if unit_id == "war_galley" or unit_id == "tidecaller" or unit_id == "trireme":
		return get_multiplier(player_id, "ship_attack") * get_multiplier(player_id, "unit_attack")
	return get_multiplier(player_id, "unit_attack")

func get_archer_range_multiplier(player_id: int) -> float:
	return get_multiplier(player_id, "archer_range")

## Flat tile bonus accumulated via archer_range_bonus_per_age (e.g. Britons +1/age).
## Stored separately from the × multiplier so the two don't interfere.
func get_archer_range_flat(player_id: int) -> float:
	return get_multiplier(player_id, "archer_range_flat")

## Called on each age advance — accumulates archer_range_bonus_per_age into the
## flat tile bucket rather than onto the × multiplier, and grants the oldest
## unresearched Blacksmith tech free to Castellanos players.
func on_age_advanced(player_id: int) -> void:
	var bonus: float = get_multiplier(player_id, "archer_range_bonus_per_age")
	if bonus > 0.0:
		var current: float = get_multiplier(player_id, "archer_range_flat")
		(_multipliers[player_id] as Dictionary)["archer_range_flat"] = current + bonus
	var free_bs: float = get_multiplier(player_id, "free_blacksmith_tech_per_age")
	if free_bs > 0.0:
		var new_age: int = AgeManager.get_age(player_id)
		var tech_id: String = TechManager.get_oldest_unresearched_blacksmith_tech(player_id, new_age)
		if not tech_id.is_empty():
			TechManager.grant_tech(player_id, tech_id)

func get_siege_attack_bonus(player_id: int) -> float:
	return get_multiplier(player_id, "siege_attack_bonus")

func get_ship_cost_multiplier(player_id: int) -> float:
	return get_multiplier(player_id, "ship_cost")

func get_unit_armor_bonus(player_id: int) -> float:
	# unit_armor_melee is stored as a multiplier but used additively as extra armor
	# scale_barding adds 15% of base armor — we expose the raw multiplier for the caller
	return get_multiplier(player_id, "unit_armor_melee")

func get_attack_speed_multiplier(player_id: int, unit_id: String) -> float:
	# britons warship_attack_speed, atlantes ship_attack_speed (also naval unique units)
	if unit_id == "war_galley" or unit_id == "warship" or unit_id == "tidecaller" or unit_id == "trireme":
		var britons_mult: float = get_multiplier(player_id, "warship_attack_speed")
		var atlantes_mult: float = get_multiplier(player_id, "ship_attack_speed")
		# Return the one that actually has a bonus (differs from 1.0)
		if britons_mult != 1.0:
			return britons_mult
		return atlantes_mult
	if unit_id in _ARCHER_IDS:
		return get_multiplier(player_id, "archer_attack_speed")
	return 1.0

func get_archer_armor_pierce_bonus(player_id: int) -> float:
	return get_multiplier(player_id, "archer_armor_pierce")

func get_unit_move_speed_multiplier(player_id: int) -> float:
	return get_multiplier(player_id, "unit_move_speed")

func get_building_hp_multiplier(player_id: int, building_id: String) -> float:
	# guanches stone_building_hp for wall_segment and mining_camp
	if building_id == "wall_segment" or building_id == "mining_camp":
		return get_multiplier(player_id, "stone_building_hp")
	return 1.0

extends BuildingBase

class_name Market

## Base exchange rates — the floor/ceiling the price recovers toward.
const BASE_SELL_RATE: int = 15   # resources spent per 1 gold received
const BASE_BUY_RATE:  int = 20   # resources received per 1 gold spent

## Each lot traded degrades the price by this many steps.
const DEGRADE_PER_LOT: int = 3

## Maximum degradation: sell rate climbs to 30, buy rate falls to 5.
const MAX_SELL_RATE: int = 30
const MIN_BUY_RATE:  int = 5

## Recovery: 1 step every RECOVERY_INTERVAL seconds back toward base.
const RECOVERY_INTERVAL: float = 30.0

const MERCENARY_COOLDOWN: float = 120.0

## Per-player, per-resource price offsets (positive = degraded).
## Key: player_id → { resource_name: int offset }
var _sell_offsets: Dictionary = {}  # int -> { String: int }
var _buy_offsets:  Dictionary = {}  # int -> { String: int }
var _recovery_timers: Dictionary = {}  # int -> float

## unit_id -> seconds remaining on cooldown (per Market instance)
var _mercenary_cooldowns: Dictionary = {}  # String -> float

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	for pid: int in _recovery_timers.keys():
		_recovery_timers[pid] = (_recovery_timers[pid] as float) + delta
		if (_recovery_timers[pid] as float) >= RECOVERY_INTERVAL:
			_recovery_timers[pid] = 0.0
			_recover_rates(pid)
	for unit_id: String in _mercenary_cooldowns.keys():
		_mercenary_cooldowns[unit_id] = maxf(0.0, (_mercenary_cooldowns[unit_id] as float) - delta)

## Current sell rate for player/resource (how much to spend per 1 gold).
func get_sell_rate(pid: int, resource: String) -> int:
	var off: int = ((_sell_offsets.get(pid, {}) as Dictionary).get(resource, 0) as int)
	return mini(BASE_SELL_RATE + off, MAX_SELL_RATE)

## Current buy rate for player/resource (how much resource received per 1 gold).
func get_buy_rate(pid: int, resource: String) -> int:
	var off: int = ((_buy_offsets.get(pid, {}) as Dictionary).get(resource, 0) as int)
	return maxi(BASE_BUY_RATE - off, MIN_BUY_RATE)

## Single-unit sell (1 gold for SELL_RATE resources), used by internal helpers.
func sell_resource(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	var rate: int = get_sell_rate(player_id, resource)
	var costs: Dictionary = {resource: rate}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, "gold", 1)
	_degrade_sell(player_id, resource)
	return true

func buy_resource(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	var costs: Dictionary = {"gold": 1}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, resource, get_buy_rate(player_id, resource))
	_degrade_buy(player_id, resource)
	return true

## Bulk sell: spend 100 units of resource, receive gold at current rate.
func sell_lot(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	const LOT: int = 100
	var rate: int = get_sell_rate(player_id, resource)
	var costs: Dictionary = {resource: LOT}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, "gold", LOT / rate)
	_degrade_sell(player_id, resource)
	EventBus.market_rate_changed.emit(player_id, self)
	return true

## Bulk buy: spend 5 gold, receive resources at current rate.
func buy_lot(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	const LOT_GOLD: int = 5
	var costs: Dictionary = {"gold": LOT_GOLD}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, resource, LOT_GOLD * get_buy_rate(player_id, resource))
	_degrade_buy(player_id, resource)
	EventBus.market_rate_changed.emit(player_id, self)
	return true

func _ensure_player(pid: int) -> void:
	if not _sell_offsets.has(pid):
		_sell_offsets[pid] = {}
		_buy_offsets[pid] = {}
		_recovery_timers[pid] = 0.0

func _degrade_sell(pid: int, resource: String) -> void:
	_ensure_player(pid)
	var off: int = ((_sell_offsets[pid] as Dictionary).get(resource, 0) as int)
	(_sell_offsets[pid] as Dictionary)[resource] = mini(off + DEGRADE_PER_LOT, MAX_SELL_RATE - BASE_SELL_RATE)

func _degrade_buy(pid: int, resource: String) -> void:
	_ensure_player(pid)
	var off: int = ((_buy_offsets[pid] as Dictionary).get(resource, 0) as int)
	(_buy_offsets[pid] as Dictionary)[resource] = mini(off + DEGRADE_PER_LOT, BASE_BUY_RATE - MIN_BUY_RATE)

func _recover_rates(pid: int) -> void:
	var changed: bool = false
	for resource: String in (_sell_offsets.get(pid, {}) as Dictionary).keys():
		var off: int = ((_sell_offsets[pid] as Dictionary)[resource] as int)
		if off > 0:
			(_sell_offsets[pid] as Dictionary)[resource] = off - 1
			changed = true
	for resource: String in (_buy_offsets.get(pid, {}) as Dictionary).keys():
		var off: int = ((_buy_offsets[pid] as Dictionary)[resource] as int)
		if off > 0:
			(_buy_offsets[pid] as Dictionary)[resource] = off - 1
			changed = true
	if changed:
		EventBus.market_rate_changed.emit(pid, self)

## Returns the gold cost to hire a mercenary of unit_id.
## Formula: (food_cost + wood_cost) * 1.5, rounded to nearest 5, minimum 20.
func get_mercenary_cost(unit_id: String) -> int:
	var res_path: String = "res://resources/units/%s_data.tres" % unit_id
	var unit_res: UnitResource = load(res_path) as UnitResource
	if unit_res == null:
		return 0
	var base: int = unit_res.cost_food + unit_res.cost_wood
	var gold: int = int(round(base * 1.5 / 5.0)) * 5
	return maxi(gold, 20)

## 0.0 = no cooldown, 1.0 = just hired (full cooldown). For UI progress display.
func get_mercenary_cooldown_fraction(unit_id: String) -> float:
	var remaining: float = _mercenary_cooldowns.get(unit_id, 0.0) as float
	return remaining / MERCENARY_COOLDOWN

func can_hire_mercenary(unit_id: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	if PopulationManager.at_cap(player_id):
		return false
	if (_mercenary_cooldowns.get(unit_id, 0.0) as float) > 0.0:
		return false
	var gold_cost: int = get_mercenary_cost(unit_id)
	if gold_cost <= 0:
		return false
	return ResourceManager.can_afford(player_id, {"gold": gold_cost})

func hire_mercenary(unit_id: String) -> bool:
	if not can_hire_mercenary(unit_id):
		return false
	var gold_cost: int = get_mercenary_cost(unit_id)
	if not ResourceManager.spend_resource(player_id, {"gold": gold_cost}):
		return false
	_mercenary_cooldowns[unit_id] = MERCENARY_COOLDOWN
	EventBus.mercenary_hired.emit(player_id, unit_id, self)
	return true

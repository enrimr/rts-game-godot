extends BuildingBase

class_name Market

## Exchange rate: how many units of the sold resource per 1 gold received.
## Selling food/wood/stone gives gold; buying gold costs food/wood/stone.
const SELL_RATE: int = 15
const BUY_RATE: int  = 20

func _ready() -> void:
	super._ready()

func sell_resource(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	var costs: Dictionary = {resource: SELL_RATE}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, "gold", 1)
	return true

func buy_resource(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	var costs: Dictionary = {"gold": 1}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, resource, BUY_RATE)
	return true

## Bulk convenience: trade a standard lot (100 units sold → gold).
func sell_lot(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	const LOT: int = 100
	var costs: Dictionary = {resource: LOT}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, "gold", int(LOT / SELL_RATE))
	return true

func buy_lot(player_id: int, resource: String) -> bool:
	if state != BuildingState.COMPLETE:
		return false
	const LOT_GOLD: int = 5
	var costs: Dictionary = {"gold": LOT_GOLD}
	if not ResourceManager.spend_resource(player_id, costs):
		return false
	ResourceManager.add_resource(player_id, resource, LOT_GOLD * BUY_RATE)
	return true

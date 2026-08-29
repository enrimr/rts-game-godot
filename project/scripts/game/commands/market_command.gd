class_name MarketCommand extends GameCommand

## A market transaction: sell or buy a resource lot, or hire a mercenary
## (which validates cost/cooldown via Market.hire_mercenary and then spawns
## the unit at the market's rally point).

var verb: String = "buy"   # "buy" | "sell" | "hire"
var building_id: int = 0
var item: String = ""      # resource name, or mercenary unit_id for "hire"

static func make(p_player: int, p_verb: String, p_building: int, p_item: String) -> MarketCommand:
	var cmd: MarketCommand = MarketCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.building_id = p_building
	cmd.item = p_item
	return cmd

func kind() -> String:
	return "market"

func _payload() -> Dictionary:
	return {"verb": verb, "building": building_id, "item": item}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "buy") as String
	building_id = d.get("building", 0) as int
	item = d.get("item", "") as String

func execute(world: Node2D) -> void:
	var building: Node = _own_entity(building_id)
	if not (building is Market):
		return
	var market: Market = building as Market
	match verb:
		"sell":
			market.sell_lot(player_id, item)
		"buy":
			market.buy_lot(player_id, item)
		"hire":
			_hire_mercenary(world, market)

func _hire_mercenary(world: Node2D, market: Market) -> void:
	if not market.hire_mercenary(item):
		return
	var packed: PackedScene = load("res://scenes/units/%s.tscn" % item) as PackedScene
	if packed == null:
		return
	var unit: Node2D = packed.instantiate() as Node2D
	unit.set("player_id", player_id)
	# Mercenaries are Fenicios sellswords regardless of who hires them.
	unit.set("civ_id", "fenicios")
	(world.get("units_layer") as Node).add_child(unit)
	var spawn_pos: Vector2 = market.rally_point if market.rally_point != Vector2.ZERO \
		else market.global_position + Vector2(60.0, 0.0)
	unit.global_position = spawn_pos
	PopulationManager.add_unit(player_id)
	if unit.has_method("order_move") and market.rally_point != Vector2.ZERO:
		unit.call("order_move", market.rally_point)
	if player_id == 0:
		AudioManager.play("unit_ready")
	EventBus.unit_spawned.emit(unit, player_id)

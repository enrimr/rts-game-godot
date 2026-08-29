class_name ProductionCommand extends GameCommand

## A production order to one own building: queue a unit, cancel a queue slot,
## or start a technology. The building's own order_train validates the roster
## and cost, so the command stays generic across every production building.

var verb: String = "train"   # "train" | "cancel_train" | "research"
var building_id: int = 0
var item: String = ""        # unit_id for "train", tech_id for "research"
var index: int = -1          # queue slot for "cancel_train"

static func make(p_player: int, p_verb: String, p_building: int,
		p_item: String = "", p_index: int = -1) -> ProductionCommand:
	var cmd: ProductionCommand = ProductionCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.building_id = p_building
	cmd.item = p_item
	cmd.index = p_index
	return cmd

func kind() -> String:
	return "production"

func _payload() -> Dictionary:
	return {"verb": verb, "building": building_id, "item": item, "index": index}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "train") as String
	building_id = d.get("building", 0) as int
	item = d.get("item", "") as String
	index = d.get("index", -1) as int

func execute(_world: Node2D) -> void:
	var building: Node = _own_entity(building_id)
	if building == null:
		return
	match verb:
		"train":
			if not building.has_method("order_train"):
				return
			# Town Centers train villagers with the no-argument signature.
			if item.is_empty():
				building.call("order_train")
			else:
				building.call("order_train", item)
		"cancel_train":
			if building.has_method("order_cancel_train"):
				building.call("order_cancel_train", index)
		"research":
			TechManager.start_research(player_id, item, building)

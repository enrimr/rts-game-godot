class_name UnitActionCommand extends GameCommand

## A no-target order over a set of units: stop, delete (kill own units),
## hero ability, trebuchet deploy/undeploy toggle and scout auto-explore.
## Hero and trebuchet verbs act on the first matching unit only, mirroring
## the single-hero / single-toggle HUD buttons.

var verb: String = "stop"   # "stop" | "delete" | "hero_ability" | "trebuchet_toggle"
                            # | "scout_explore" | "scout_explore_stop"
var unit_ids: Array[int] = []

static func make(p_player: int, p_verb: String, p_units: Array[int]) -> UnitActionCommand:
	var cmd: UnitActionCommand = UnitActionCommand.new()
	cmd.player_id = p_player
	cmd.verb = p_verb
	cmd.unit_ids = p_units
	return cmd

func kind() -> String:
	return "unit_action"

func _payload() -> Dictionary:
	return {"verb": verb, "units": encode_ids(unit_ids)}

func _read_payload(d: Dictionary) -> void:
	verb = d.get("verb", "stop") as String
	unit_ids = decode_ids(d.get("units"))

func execute(_world: Node2D) -> void:
	var units: Array[Node] = _own_entities(unit_ids)
	match verb:
		"stop":
			for unit: Node in units:
				if unit.has_method("order_move"):
					unit.call("order_move", (unit as Node2D).global_position)
		"delete":
			for unit: Node in units:
				if unit.has_method("die"):
					unit.call("die")
		"hero_ability":
			for unit: Node in units:
				if unit is HeroUnit:
					(unit as HeroUnit).use_ability()
					break
		"trebuchet_toggle":
			for unit: Node in units:
				if unit is Trebuchet:
					var treb: Trebuchet = unit as Trebuchet
					if treb.is_deployed:
						treb.order_undeploy()
					else:
						treb.order_deploy()
					break
		"scout_explore":
			for unit: Node in units:
				if unit is Scout:
					(unit as Scout).start_auto_explore()
		"scout_explore_stop":
			for unit: Node in units:
				if unit is Scout:
					(unit as Scout).stop_auto_explore()

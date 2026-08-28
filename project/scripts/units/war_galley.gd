extends ShipBase

class_name WarGalley

## War Galley — naval combat unit. Ranged attack against ships and coastal
## targets. The whole move/chase/strike cycle comes from UnitBase; this class
## only opts into auto-retaliation and the ranged impact sound.

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

func _strike_sound() -> String:
	return "hit_ranged"

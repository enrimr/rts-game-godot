extends UnitBase

class_name HeavyScout


func get_selection_sound() -> String:
	return "select_cavalry"

func _ready() -> void:
	super._ready()
	UnitDress.apply.call_deferred(self, player_id)

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 9.9, 12.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 15.0, 4.5, 11.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

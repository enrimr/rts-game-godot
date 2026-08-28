extends UnitBase

class_name Knight


func get_selection_sound() -> String:
	return "select_cavalry"

func _ready() -> void:
	super._ready()
	UnitDress.apply.call_deferred(self, player_id)

# Stripe under the warhorse's hooves; wider/lower shadow to match its footprint.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 11.0, 13.0)

func _add_ground_shadow() -> void:
	VisualFx.add_ground_shadow(self, 16.0, 5.0, 12.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

extends UnitBase

class_name Pikeman


func get_selection_sound() -> String:
	return "select_infantry"

func _ready() -> void:
	super._ready()
	UnitDress.apply.call_deferred(self, player_id)

# Narrower stripe at the feet so the team colour doesn't cover the soldier body.
func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 6.6, 10.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

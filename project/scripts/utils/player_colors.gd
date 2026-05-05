class_name PlayerColors

const COLORS: Array[Color] = [
	Color(0.20, 0.45, 0.90, 1.0),  # player 0 — blue
	Color(0.85, 0.15, 0.15, 1.0),  # player 1 — red
]

const FALLBACK: Color = Color(0.7, 0.7, 0.7, 1.0)

static func get_color(player_id: int) -> Color:
	if player_id >= 0 and player_id < COLORS.size():
		return COLORS[player_id]
	return FALLBACK

## Adds a 4-px colored stripe at the bottom of `parent_node`.
## Must be called after `parent_node` is inside the scene tree.
static func apply_color_stripe(parent_node: Node2D, player_id: int, width: float, bottom: float) -> void:
	var stripe: ColorRect = ColorRect.new()
	stripe.name = "PlayerColorStripe"
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.color = get_color(player_id)
	stripe.offset_left   = -width * 0.5
	stripe.offset_top    = bottom - 4.0
	stripe.offset_right  = width * 0.5
	stripe.offset_bottom = bottom
	parent_node.add_child(stripe)

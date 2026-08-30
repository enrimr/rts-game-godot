class_name PlayerColors

const COLORS: Array[Color] = [
	Color(0.20, 0.45, 0.90, 1.0),  # player 0 — blue
	Color(0.85, 0.15, 0.15, 1.0),  # player 1 — red
	Color(0.95, 0.65, 0.10, 1.0),  # player 2 — orange
	Color(0.55, 0.20, 0.90, 1.0),  # player 3 — purple
	Color(0.15, 0.80, 0.35, 1.0),  # player 4 — green
	Color(0.90, 0.20, 0.75, 1.0),  # player 5 — pink
	Color(0.15, 0.80, 0.85, 1.0),  # player 6 — cyan
	Color(0.90, 0.85, 0.15, 1.0),  # player 7 — yellow
]

const FALLBACK: Color = Color(0.7, 0.7, 0.7, 1.0)

# Outward offset of the iso ownership trim from the footprint edges (world px).
const TRIM_OFF: float = 4.5

## Multiplayer colour picks: player_id → COLORS index, set from the lobby
## roster by NetworkSession at match start (and cleared when the session
## ends). Offline matches keep the classic id → colour mapping.
static var _overrides: Dictionary = {}

static func set_override(player_id: int, color_idx: int) -> void:
	if color_idx >= 0 and color_idx < COLORS.size():
		_overrides[player_id] = color_idx

static func clear_overrides() -> void:
	_overrides.clear()

static func get_color(player_id: int) -> Color:
	if _overrides.has(player_id):
		return COLORS[_overrides[player_id] as int]
	if player_id >= 0 and player_id < COLORS.size():
		return COLORS[player_id]
	return FALLBACK

## Ground-projected ownership trim for iso-massed buildings: a team-colour
## line laid flat in WORLD space just outside the footprint's two camera-facing
## edges (+y and +x sides), so the projection renders it as an L along the
## near edges of the ground diamond. Replaces the screen-space ColorRect
## stripe, which cut horizontally through the lower wall corner. Idempotent:
## re-calling recolours the existing trim.
static func apply_iso_ownership_trim(parent_node: Node2D, player_id: int, half: Vector2) -> void:
	var existing: Node = parent_node.get_node_or_null("PlayerColorStripe")
	if existing is Line2D:
		(existing as Line2D).default_color = get_color(player_id)
		return
	if existing != null:
		existing.name = "PlayerColorStripeOld"
		existing.queue_free()
	var trim: Line2D = Line2D.new()
	trim.name = "PlayerColorStripe"
	trim.width = 4.5
	trim.default_color = get_color(player_id)
	trim.z_index = -1
	trim.joint_mode = Line2D.LINE_JOINT_ROUND
	trim.points = PackedVector2Array([
		Vector2(-half.x - TRIM_OFF * 0.5, half.y + TRIM_OFF),
		Vector2(half.x + TRIM_OFF, half.y + TRIM_OFF),
		Vector2(half.x + TRIM_OFF, -half.y - TRIM_OFF * 0.5),
	])
	trim.set_meta(IsoBillboard.META_GROUND, true)
	parent_node.add_child(trim)

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

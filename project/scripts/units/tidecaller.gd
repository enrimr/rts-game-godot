extends UnitBase

class_name Tidecaller


const TIDAL_SPLASH_RADIUS: float = 65.0
## Splash deals a fraction of the primary hit, before armor
const TIDAL_SPLASH_FRACTION: float = 0.40

func get_selection_sound() -> String:
	return "select_naval"

func _ready() -> void:
	# Tidecaller is Atlantes' amphibious unit — treat it as ocean-capable so
	# TerrainManager does not block movement on water tiles.
	civ_id = "atlantes"
	super._ready()

func _add_player_color_stripe() -> void:
	VisualFx.add_ground_plinth(self, player_id, 6.6, 10.0)

func _on_auto_attack_target(target: Node) -> void:
	order_attack(target)

# ── Combat machine hooks ──

func _strike_sound() -> String:
	return "hit_ranged"

func _after_strike(_target: Node) -> void:
	_apply_tidal_pulse()

func _apply_tidal_pulse() -> void:
	# Use physics query so we hit actual physics bodies rather than a group that
	# units are never added to. Same pattern as Mangonel splash.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = TIDAL_SPLASH_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 3
	var results: Array[Dictionary] = space.intersect_shape(query, 32)
	var splash_base: float = _get_effective_attack() * TIDAL_SPLASH_FRACTION
	for result: Dictionary in results:
		var body: Node = result["collider"] as Node
		if not is_instance_valid(body):
			continue
		if body == attack_target:
			continue
		var pid: Variant = body.get("player_id")
		if pid == null or (pid as int) == player_id:
			continue
		if body.get("unit_data") == null and not (body is Animal):
			continue
		var splash_dmg: float = maxf(splash_base - _get_target_armor(body), 0.0)
		if body.has_method("take_damage"):
			body.take_damage(splash_dmg, self)

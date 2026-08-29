extends UnitBase

class_name ShipBase

## Base class for all naval units. Water-only movement, no terrain speed penalty.
## Ocean access comes from is_amphibious(), not from the owning civ.

func get_selection_sound() -> String:
	return "select_naval"

func is_amphibious() -> bool:
	return true

func _ready() -> void:
	# Cosmetic only since ocean access moved to is_amphibious(): every hull is
	# dressed in Atlantes style by UnitDress.
	civ_id = "atlantes"
	super._ready()

## Ships can only follow the ocean navmesh, but the base implementation only asks
## whether the destination is *impassable* — and water is passable for anything
## amphibious. A target on land (a dock's own origin, a coastal click) therefore
## stayed off-mesh, so the agent reported navigation finished immediately and the
## ship sat still.
func _safe_destination(destination: Vector2) -> Vector2:
	if TerrainManager.is_ocean(destination):
		return destination
	var water: Vector2 = TerrainManager.nearest_ocean(destination)
	return water if water != Vector2.ZERO else destination

func _nav_velocity() -> Vector2:
	if nav_agent.is_navigation_finished():
		return Vector2.ZERO
	var next: Vector2 = nav_agent.get_next_path_position()
	var dir: Vector2 = next - global_position
	if dir.length_squared() < 1.0:
		return Vector2.ZERO
	var spd: float = unit_data.move_speed \
		* WeatherManager.get_naval_speed_multiplier(dir.normalized(), player_id)
	return dir.normalized() * spd

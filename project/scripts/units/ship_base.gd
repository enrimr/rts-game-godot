extends UnitBase

class_name ShipBase

## Base class for all naval units. Water-only movement, no terrain speed penalty.
## Ships use civ_id = "atlantes" internally so TerrainManager considers ocean passable.

func get_selection_sound() -> String:
	return "select_naval"

func _ready() -> void:
	# Ships are always ocean-capable regardless of player civ
	civ_id = "atlantes"
	super._ready()

## Ships can only follow the ocean navmesh, but the base implementation only asks
## whether the destination is *impassable* — and land is passable for the
## "atlantes" civ ships pretend to be. A target on land (a dock's own origin, a
## coastal click) therefore stayed off-mesh, so the agent reported navigation
## finished immediately and the ship sat still.
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

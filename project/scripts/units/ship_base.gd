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

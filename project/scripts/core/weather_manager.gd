extends Node

## WeatherManager — drives periodic weather events for Calima: Flames of the Atlantic.
## Autoload: access by name anywhere in the codebase.
##
## Each weather event is global (affects all players equally) and composed of:
##   • A ramp-in / ramp-out period (RAMP_TIME seconds each)
##   • A peak period at full intensity
##   • Stat modifiers queried by other systems each frame
##
## Integration points:
##   unit_base.gd   — _nav_velocity multiplies by get_move_speed_multiplier
##   fog_of_war.gd  — _mark_circle scales radius by get_vision_multiplier
##   villager.gd    — gather_rate multiplies by get_gather_rate_multiplier
##   trebuchet.gd   — _spawn_projectile drifts final position by get_projectile_drift
##   mangonel.gd    — same drift applied to _fire_at target_pos
##   building_base.gd — _process applies get_building_damage_rate HP drain
##   fog_of_war.gd  — _apply_visibility calls is_unit_cloaked_by_weather

enum WeatherType {
	CLEAR         = 0,
	CALIMA        = 1,   # Saharan dust haze — visibility/gather/speed penalty
	ATLANTIC_STORM = 2,  # Rain & wind — naval/siege penalty
	SEA_FOG       = 3,   # Coastal fog — coastal visibility/cloaking
	TRADE_WINDS   = 4,   # NE→SW wind — naval speed bonus/penalty, projectile drift
	VOLCANIC_ASH  = 5,   # Central volcanic zone — building HP drain, area visibility
}

signal weather_changed(weather_id: String, intensity: float)
signal weather_cleared()
## Emitted when the next weather has been chosen but hasn't started yet, so the
## HUD can warn the player ("Calima incoming in Ns") and they can react.
signal weather_incoming(weather_id: String, seconds_until: float)

const RAMP_TIME: float = 10.0       # seconds to fade in / fade out
const FORECAST_TIME: float = 8.0    # warning window before a weather event ramps in

# Minimum and maximum duration of the PEAK phase (seconds)
const PEAK_DURATION: Dictionary = {
	WeatherType.CALIMA:          [70.0, 130.0],
	WeatherType.ATLANTIC_STORM:  [40.0,  90.0],
	WeatherType.SEA_FOG:         [60.0, 120.0],
	WeatherType.TRADE_WINDS:     [100.0, 160.0],
	WeatherType.VOLCANIC_ASH:    [40.0,  80.0],
}

# Clear pause between events (seconds)
const CLEAR_DURATION_MIN: float = 60.0
const CLEAR_DURATION_MAX: float = 120.0

# Relative weights for picking the next weather type
const WEATHER_WEIGHTS: Dictionary = {
	WeatherType.CALIMA:          4,
	WeatherType.ATLANTIC_STORM:  3,
	WeatherType.SEA_FOG:         3,
	WeatherType.TRADE_WINDS:     2,
	WeatherType.VOLCANIC_ASH:    2,
}

# Map-type exclusions: certain weather only appears on certain map types
const WEATHER_MAP_ALLOWED: Dictionary = {
	WeatherType.SEA_FOG:        [MatchConfig.MapType.ISLANDS, MatchConfig.MapType.VOLCANIC_COAST,
	                              MatchConfig.MapType.DESERT_COAST],
	WeatherType.TRADE_WINDS:    [MatchConfig.MapType.ISLANDS, MatchConfig.MapType.VOLCANIC_COAST,
	                              MatchConfig.MapType.DESERT_COAST, MatchConfig.MapType.STANDARD,
	                              MatchConfig.MapType.PLAINS],
	WeatherType.VOLCANIC_ASH:   [MatchConfig.MapType.VOLCANIC_COAST],
}

# Distance beyond a caldera's edge still affected by volcanic ash (px)
const VOLCANIC_ZONE_RADIUS: float = 800.0
# Distance from coast (ocean-land boundary) inside which SEA_FOG applies to units
const COASTAL_ZONE_DEPTH: float = 400.0
# How close one of your own units/buildings has to be to spot an enemy hidden by
# sea fog. Without this the cloak hid every enemy in the coastal band regardless
# of line of sight — and on an Islands map the whole map is coastal, so entire
# armies simply vanished. Scaled per civ by the "fog_stealth" multiplier: the
# Atlantes are harder to find in their own fog.
const FOG_SPOT_RANGE: float = 180.0

var current_weather: WeatherType = WeatherType.CLEAR
var intensity: float = 0.0   # 0.0 → 1.0 (smoothly ramped)

var _phase: String = "clear"   # "clear" | "forecast" | "ramp_in" | "peak" | "ramp_out"
var _pending_weather: WeatherType = WeatherType.CLEAR   # chosen during "forecast"
var _phase_timer: float = 0.0
var _phase_duration: float = 0.0   # used for CLEAR and PEAK phases
var _peak_duration: float = 0.0    # pre-generated when weather is picked; stable during ramp_in

# Trade-wind drift vector (world space, changes each TRADE_WINDS event)
var _wind_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_clear()

func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if not MatchConfig.weather_enabled:
		return
	_phase_timer += delta
	match _phase:
		"clear":
			if _phase_timer >= _phase_duration:
				_pick_next_weather()
		"forecast":
			if _phase_timer >= FORECAST_TIME:
				_begin_incoming_weather()
		"ramp_in":
			intensity = clampf(_phase_timer / RAMP_TIME, 0.0, 1.0)
			if _phase_timer >= RAMP_TIME:
				intensity = 1.0
				_phase = "peak"
				_phase_timer = 0.0
				_phase_duration = _peak_duration
		"peak":
			if _phase_timer >= _phase_duration:
				_phase = "ramp_out"
				_phase_timer = 0.0
		"ramp_out":
			intensity = clampf(1.0 - _phase_timer / RAMP_TIME, 0.0, 1.0)
			if _phase_timer >= RAMP_TIME:
				intensity = 0.0
				current_weather = WeatherType.CLEAR
				weather_cleared.emit()
				_start_clear()

func _start_clear() -> void:
	_phase = "clear"
	_phase_timer = 0.0
	_phase_duration = MatchRng.randf_range(CLEAR_DURATION_MIN, CLEAR_DURATION_MAX)
	match MatchConfig.weather_frequency:
		0:
			_phase_duration *= 999.0  # effectively off
		2:
			_phase_duration *= 0.6
		3:
			_phase_duration *= 0.3

func _pick_next_weather() -> void:
	var candidates: Array = []
	var weights: Array = []
	for wtype: WeatherType in WEATHER_WEIGHTS.keys():
		if _is_allowed_on_current_map(wtype):
			candidates.append(wtype)
			weights.append(WEATHER_WEIGHTS[wtype] as int)
	if candidates.is_empty():
		_start_clear()
		return
	var total: int = 0
	for w: int in weights:
		total += w
	var roll: int = MatchRng.randi() % total
	var acc: int = 0
	var chosen: WeatherType = candidates[0]
	for i: int in range(candidates.size()):
		acc += weights[i] as int
		if roll < acc:
			chosen = candidates[i]
			break
	# Enter the forecast window: the weather is chosen and announced, but not yet
	# active (current_weather stays CLEAR so no penalties apply during the warning).
	_pending_weather = chosen
	_phase = "forecast"
	_phase_timer = 0.0
	intensity = 0.0
	weather_incoming.emit(_weather_id_of(chosen), FORECAST_TIME)

# Activates the weather chosen during the forecast window and starts its ramp-in.
func _begin_incoming_weather() -> void:
	var chosen: WeatherType = _pending_weather
	current_weather = chosen
	_peak_duration = MatchRng.randf_range(
		(PEAK_DURATION[chosen] as Array)[0],
		(PEAK_DURATION[chosen] as Array)[1])
	if chosen == WeatherType.TRADE_WINDS:
		var angle: float = MatchRng.randf_range(0.0, TAU)
		_wind_dir = Vector2(cos(angle), sin(angle))
	_phase = "ramp_in"
	_phase_timer = 0.0
	intensity = 0.0
	weather_changed.emit(get_weather_id(), 0.0)

## Seconds remaining in the current weather event (ramp_in + peak + ramp_out combined).
## Returns 0.0 when weather is CLEAR.
func get_remaining_seconds() -> float:
	match _phase:
		"ramp_in":
			return (RAMP_TIME - _phase_timer) + _peak_duration + RAMP_TIME
		"peak":
			return (_phase_duration - _phase_timer) + RAMP_TIME
		"ramp_out":
			return maxf(RAMP_TIME - _phase_timer, 0.0)
	return 0.0

func _is_allowed_on_current_map(wtype: WeatherType) -> bool:
	if not WEATHER_MAP_ALLOWED.has(wtype):
		return true  # no restriction
	var allowed: Array = WEATHER_MAP_ALLOWED[wtype] as Array
	return allowed.has(MatchConfig.map_type)

func get_weather_id() -> String:
	return _weather_id_of(current_weather)

func _weather_id_of(wtype: WeatherType) -> String:
	match wtype:
		WeatherType.CALIMA:          return "calima"
		WeatherType.ATLANTIC_STORM:  return "atlantic_storm"
		WeatherType.SEA_FOG:         return "sea_fog"
		WeatherType.TRADE_WINDS:     return "trade_winds"
		WeatherType.VOLCANIC_ASH:    return "volcanic_ash"
	return "clear"

# ── Stat query API ────────────────────────────────────────────────────────────

## Per-civ penalty scaling for the CURRENT weather. 1.0 = full penalty (also for
## player_id == -1 / unknown), 0.0 = immune. Multiply any penalty fraction by this.
func _resistance(player_id: int) -> float:
	if player_id < 0:
		return 1.0
	return CivBonusManager.get_weather_resistance(player_id, get_weather_id())

## Land movement speed multiplier for a unit at world_pos owned by player_id.
func get_move_speed_multiplier(world_pos: Vector2, player_id: int = -1) -> float:
	if intensity <= 0.0:
		return 1.0
	match current_weather:
		WeatherType.CALIMA:
			return 1.0 - 0.15 * intensity * _resistance(player_id)
		WeatherType.ATLANTIC_STORM:
			return 1.0   # only affects naval in gather/attack; land units unaffected
		WeatherType.TRADE_WINDS:
			return 1.0   # trade-wind direction bonus handled separately for ships
	return 1.0

## Naval (ship) movement speed multiplier for a ship moving in direction move_dir.
## Trade winds give a bonus when sailing with the wind, penalty against it.
func get_naval_speed_multiplier(move_dir: Vector2, player_id: int = -1) -> float:
	if intensity <= 0.0 or current_weather != WeatherType.TRADE_WINDS:
		if current_weather == WeatherType.ATLANTIC_STORM:
			return 1.0 - 0.30 * intensity * _resistance(player_id)
		return 1.0
	var alignment: float = move_dir.normalized().dot(_wind_dir)  # -1..1
	# A favourable wind is a bonus (never scaled down); only the headwind penalty
	# is softened by affinity.
	var effect: float = alignment * 0.20 * intensity
	if effect < 0.0:
		effect *= _resistance(player_id)
	return 1.0 + effect

## Gather rate multiplier for resource type at world_pos owned by player_id.
func get_gather_rate_multiplier(resource: String, world_pos: Vector2, player_id: int = -1) -> float:
	if intensity <= 0.0:
		return 1.0
	match current_weather:
		WeatherType.CALIMA:
			if resource == "wood" or resource == "food":
				return 1.0 - 0.20 * intensity * _resistance(player_id)
		WeatherType.ATLANTIC_STORM:
			if resource == "food":   # fishing affected
				return 1.0 - 0.50 * intensity * _resistance(player_id)
		WeatherType.VOLCANIC_ASH:
			if _in_volcanic_zone(world_pos):
				return 1.0 - 0.30 * intensity * _resistance(player_id)
	return 1.0

## Vision radius multiplier for a unit at world_pos owned by player_id.
func get_vision_multiplier(world_pos: Vector2, player_id: int = -1) -> float:
	if intensity <= 0.0:
		return 1.0
	match current_weather:
		WeatherType.CALIMA:
			return 1.0 - 0.40 * intensity * _resistance(player_id)
		WeatherType.SEA_FOG:
			if _in_coastal_zone(world_pos):
				return 1.0 - 0.60 * intensity * _resistance(player_id)
		WeatherType.VOLCANIC_ASH:
			if _in_volcanic_zone(world_pos):
				return 1.0 - 0.50 * intensity * _resistance(player_id)
	return 1.0

## World-space drift applied to projectile final position (trebuchet, mangonel).
## Multiply by flight_time for a proportional displacement.
func get_projectile_drift() -> Vector2:
	if intensity <= 0.0:
		return Vector2.ZERO
	match current_weather:
		WeatherType.TRADE_WINDS:
			return _wind_dir * 40.0 * intensity
		WeatherType.ATLANTIC_STORM:
			# Random cross-wind; evaluated once per projectile since it's called at fire time
			var perp: Vector2 = Vector2(-_wind_dir.y, _wind_dir.x) if _wind_dir != Vector2.ZERO \
				else Vector2(MatchRng.randf_range(-1.0, 1.0), MatchRng.randf_range(-1.0, 1.0)).normalized()
			return perp * 30.0 * intensity
	return Vector2.ZERO

## True if an enemy unit at world_pos should be hidden due to sea fog. The cloak
## still breaks at close range (fog_spot_range) or when the unit attacks — see
## FogOfWar._apply_visibility, the only caller that can answer those.
func is_unit_cloaked_by_weather(world_pos: Vector2) -> bool:
	if intensity < 0.5:
		return false
	if current_weather != WeatherType.SEA_FOG:
		return false
	return _in_coastal_zone(world_pos)

## Distance at which a hidden unit owned by `player_id` is spotted anyway.
func fog_spot_range(player_id: int = -1) -> float:
	return FOG_SPOT_RANGE * CivBonusManager.get_multiplier(player_id, "fog_stealth")

## HP drain per second for a building at world_pos from volcanic ash.
func get_building_damage_rate(world_pos: Vector2, player_id: int = -1) -> float:
	if intensity <= 0.0 or current_weather != WeatherType.VOLCANIC_ASH:
		return 0.0
	if not _in_volcanic_zone(world_pos):
		return 0.0
	return 2.0 * intensity * _resistance(player_id)

# ── Internal helpers ──────────────────────────────────────────────────────────

func _in_volcanic_zone(world_pos: Vector2) -> bool:
	var has_caldera: bool = false
	for z: Dictionary in TerrainManager.get_zones():
		if (z["type"] as TerrainManager.TerrainType) != TerrainManager.TerrainType.CALDERA:
			continue
		has_caldera = true
		if world_pos.distance_to(z["center"] as Vector2) <= (z["radius"] as float) + VOLCANIC_ZONE_RADIUS:
			return true
	# A map without calderas (legacy save mid-event) keeps the old whole-map
	# behaviour so an active ash event is never a silent no-op.
	return not has_caldera

func _in_coastal_zone(world_pos: Vector2) -> bool:
	return TerrainManager.distance_to_coast(world_pos) <= COASTAL_ZONE_DEPTH

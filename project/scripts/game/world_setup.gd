class_name WorldSetup extends RefCounted

## Match bootstrap: ambient lighting, civ bonus/tech init, starting town
## centers, starting units + heroes, AI coordinator nodes, and the tutorial
## spawn/highlight hooks. Everything here runs once from GameWorld._ready
## (tutorial handlers excepted); state it produces (drop_off,
## _ai_town_centers, _fog seed, …) lives on the world node.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const SCOUT_SCENE: PackedScene = preload("res://scenes/units/scout.tscn")
const AI_TOWN_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/town_center_ai.tscn")
const PLAYER_TOWN_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/town_center.tscn")

const HERO_MALE_DATA: Dictionary = {
	"guanches":    "res://resources/units/hero_bencomo.tres",
	"canarii":     "res://resources/units/hero_doramas.tres",
	"mahos":       "res://resources/units/hero_guadarfia.tres",
	"franks":      "res://resources/units/hero_bethencourt.tres",
	"britons":     "res://resources/units/hero_drake.tres",
	"castellanos": "res://resources/units/hero_quijote.tres",
	"atlantes":    "res://resources/units/hero_artaxerax.tres",
	"fenicios":    "res://resources/units/hero_hanno.tres",
}

const HERO_FEMALE_DATA: Dictionary = {
	"guanches":    "res://resources/units/hero_dacil.tres",
	"canarii":     "res://resources/units/hero_guayarmina.tres",
	"mahos":       "res://resources/units/hero_tibiabin.tres",
	"franks":      "res://resources/units/hero_catalina.tres",
	"britons":     "res://resources/units/hero_grace.tres",
	"castellanos": "res://resources/units/hero_dulcinea.tres",
	"atlantes":    "res://resources/units/hero_cleito.tres",
	"fenicios":    "res://resources/units/hero_elissa.tres",
}

# Starting-villager offsets are planned in SCREEN space and unprojected: the
# old straight world row (i*40) projected onto the squashed diagonal, so the
# figures half-overlapped in front of the TC.
const _STARTING_VILLAGER_SCREEN_OFFSETS: Array[Vector2] = [
	Vector2(-55.0, 38.0), Vector2(0.0, 52.0), Vector2(55.0, 38.0),
]

const TUTORIAL_SPAWN_MIN_DIST: float = 190.0
const TUTORIAL_UNIT_CLEAR_RADIUS: float = 40.0

var _world  # GameWorld — untyped so dynamic access works

func setup(world) -> void:
	_world = world

## Adds a per-map-type ambient colour wash (CanvasModulate) and a full-screen
## vignette. Both are subtle — they tint and frame the scene without obscuring it.
func _setup_ambient_lighting() -> void:
	# Out-of-map void matches the unexplored fog shroud — one consistent
	# darkness instead of the engine-default light-gray backdrop.
	RenderingServer.set_default_clear_color(FogOfWar.SHROUD_RGB)
	var ambient: Color = Color(1.0, 1.0, 1.0, 1.0)
	match MatchConfig.map_type:
		MatchConfig.MapType.DESERT_COAST:
			ambient = Color(1.06, 1.00, 0.88, 1.0)   # warm sun
		MatchConfig.MapType.VOLCANIC_COAST:
			ambient = Color(1.04, 0.94, 0.86, 1.0)   # dusky ember
		MatchConfig.MapType.ISLANDS:
			ambient = Color(0.96, 0.99, 1.04, 1.0)   # cool sea light
		_:
			ambient = Color(0.99, 1.00, 0.97, 1.0)   # neutral daylight
	var modulate_node: CanvasModulate = CanvasModulate.new()
	modulate_node.name = "AmbientModulate"
	modulate_node.color = ambient
	_world.add_child(modulate_node)

	# HUD defaults to layer 0; lift it above the vignette so edge-darkening
	# never bleeds over the resource/command bars.
	_world.hud.layer = 5

	var vignette_layer: CanvasLayer = CanvasLayer.new()
	vignette_layer.name = "VignetteLayer"
	vignette_layer.layer = 1   # above world (layer 0), below HUD (layer 5)
	var rect: ColorRect = ColorRect.new()
	rect.name = "Vignette"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/vignette.gdshader") as Shader
	rect.material = mat
	vignette_layer.add_child(rect)
	_world.add_child(vignette_layer)

func _apply_civilization() -> void:
	var civ_path: String = "res://resources/civilizations/%s.tres" % MatchConfig.player_civ_id
	var civ: CivilizationResource = load(civ_path) as CivilizationResource
	if civ != null:
		for key: String in (civ.starting_bonuses as Dictionary):
			ResourceManager.add_resource(0, key, (civ.starting_bonuses as Dictionary)[key] as float)
		MatchConfig.set_meta("civ", civ)
	CivBonusManager.init_player(0, MatchConfig.player_civ_id)
	TechManager.init_player(0)
	for rival_id: int in MatchConfig.get_rival_player_ids():
		CivBonusManager.init_player(rival_id, MatchConfig.get_rival_civ_id(rival_id))
		TechManager.init_player(rival_id)

func _get_civ_id_for_player(player_id: int) -> String:
	if player_id == 0:
		return MatchConfig.player_civ_id
	return MatchConfig.get_rival_civ_id(player_id)

func _create_player_town_center() -> void:
	# Same scene as buildable TCs, so the starting TC has the current visuals and
	# a real collision body (blocks placement on top of it). Kept as a sibling
	# named "DropOffNode" and marked COMPLETE so it can train villagers from the
	# start (the buildable TC gates training on COMPLETE).
	var tc: Node2D = PLAYER_TOWN_CENTER_SCENE.instantiate() as Node2D
	tc.name = "DropOffNode"
	tc.set("player_id", 0)
	_world.add_child(tc)
	# Already built — full progress, COMPLETE state, no blueprint tint or
	# progress bar (set('state', COMPLETE) alone left it translucent/unbuilt).
	tc.call("force_complete")
	_world.drop_off = tc

## Starting villagers + scout + hero for the human player, around the TC.
func spawn_player_start() -> void:
	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		_world.units_layer.add_child(v)
		v.global_position = _world.drop_off.global_position + _starting_villager_offset(i)
		v.set("player_id", 0)
		v.set("civ_id", MatchConfig.player_civ_id)
		PopulationManager.add_unit(0)
		EventBus.unit_spawned.emit(v, 0)

	var scout0: CharacterBody2D = SCOUT_SCENE.instantiate()
	_world.units_layer.add_child(scout0)
	scout0.global_position = _world.drop_off.global_position + Vector2(80.0, -60.0)
	scout0.set("player_id", 0)
	scout0.set("civ_id", MatchConfig.player_civ_id)
	PopulationManager.add_unit(0)
	EventBus.unit_spawned.emit(scout0, 0)

	_spawn_hero(0, _world.drop_off.global_position)

func _spawn_hero(player_id: int, tc_pos: Vector2) -> void:
	var civ_id: String = _get_civ_id_for_player(player_id)
	# Select hero gender based on MatchConfig setting
	var use_female: bool = false
	match MatchConfig.hero_gender:
		MatchConfig.HeroGender.RANDOM:
			use_female = _world._rng.randi() % 2 == 0
		MatchConfig.HeroGender.MALE:
			use_female = false
		MatchConfig.HeroGender.FEMALE:
			use_female = true

	var hero_map: Dictionary = HERO_FEMALE_DATA if use_female else HERO_MALE_DATA
	var data_path: String = hero_map.get(civ_id, "") as String
	if data_path.is_empty():
		return
	var hero_data: UnitResource = load(data_path) as UnitResource
	if hero_data == null:
		return
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var hero: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	hero.set_script(load("res://scripts/units/hero_unit.gd"))
	hero.set("unit_data", hero_data)
	hero.set("player_id", player_id)
	hero.set("civ_id", civ_id)
	hero.set("is_female", use_female)
	# South-east of the TC in world space = in FRONT of it on screen under
	# the iso projection. The old (-80,-60) offset landed the hero BEHIND the
	# building's massing: correctly occluded by y-sort, i.e. invisible and
	# seemingly unselectable. (No spawn-spiral here: physics hasn't synced
	# the TC body yet during _ready, so the query would misreport "free".)
	hero.global_position = tc_pos + Vector2(85.0, 85.0)
	_world.units_layer.add_child(hero)
	EventBus.unit_spawned.emit(hero, player_id)
	_settle_hero_spawn(hero, tc_pos)

# The starting offset can land on a villager: the spawn spiral would avoid it,
# but physics hasn't synced any body yet during _ready. Settle the hero onto a
# properly distributed free spot around the TC once the space is queryable.
func _settle_hero_spawn(hero: Node2D, tc_pos: Vector2) -> void:
	await _world.get_tree().physics_frame
	await _world.get_tree().physics_frame
	if not is_instance_valid(hero):
		return
	# Wider spiral step than trained units: more clearance so the hero never
	# reads as glued to a starting villager.
	hero.global_position = BuildingBase.find_spawn_pos(tc_pos,
		_world.get_world_2d().direct_space_state, 46.0)

func _on_tutorial_spawn_enemy_scout(near_pos: Vector2) -> void:
	var militia_scene: PackedScene = load("res://scenes/units/militia.tscn") as PackedScene
	if militia_scene == null:
		return
	var civ_id: String = MatchConfig.get_rival_civ_id(1)
	var spawn_pos: Vector2 = _find_tutorial_spawn_pos(near_pos, civ_id)
	var militia: CharacterBody2D = militia_scene.instantiate() as CharacterBody2D
	militia.set("player_id", 1)
	militia.set("civ_id", civ_id)
	militia.global_position = spawn_pos
	_world.units_layer.add_child(militia)
	PopulationManager.add_unit(1)
	EventBus.unit_spawned.emit(militia, 1)
	# Practice dummy, not a threat: it never fights back or chases, it is
	# half-HP so it dies fast, and a low white ground halo marks it (white +
	# flat on purpose — the hero's aura is a tall golden flame).
	militia.set("stance", UnitBase.Stance.PASSIVE)
	militia.set("health", (militia.get("health") as float) * 0.5)
	militia.add_child(TutorialTargetHalo.new())

# Returns a passable spawn position near near_pos, avoiding buildings and other units.
# Tries candidate offsets at increasing distances until a clear spot is found.
func _find_tutorial_spawn_pos(near_pos: Vector2, civ_id: String) -> Vector2:
	# PI/4 first: world (+x,+y) projects to screen-south — in FRONT of the
	# TC where the tutorial camera is already looking.
	var angles: Array[float] = [PI * 0.25, 0.0, PI * 0.5, PI, PI * 1.5, PI * 0.75, PI * 1.25, PI * 1.75]
	for dist_mult: int in range(1, 6):
		var dist: float = TUTORIAL_SPAWN_MIN_DIST + dist_mult * 60.0
		for angle: float in angles:
			var candidate: Vector2 = near_pos + Vector2(cos(angle), sin(angle)) * dist
			var passable: Vector2 = TerrainManager.nearest_passable(candidate, civ_id)
			if passable.distance_to(candidate) > 80.0:
				continue  # snapped too far — terrain blocked the whole area
			# Check no building overlaps
			var blocked: bool = false
			for b: Node in _world.buildings_layer.get_children():
				if not is_instance_valid(b):
					continue
				if (b as Node2D).global_position.distance_to(passable) < TUTORIAL_UNIT_CLEAR_RADIUS + 48.0:
					blocked = true
					break
			if not blocked:
				return passable
	# Fallback: just use nearest_passable from default offset
	return TerrainManager.nearest_passable(near_pos + Vector2(320.0, 0.0), civ_id)

func _on_tutorial_highlight_unit(unit_type: String) -> void:
	var target: Node2D = null
	for unit: Node in _world.units_layer.get_children():
		if not is_instance_valid(unit):
			continue
		if unit.get("player_id") != 0:
			continue
		if unit_type == "hero" and unit is HeroUnit:
			target = unit as Node2D
			break
		if unit_type == "scout" and unit is Scout:
			target = unit as Node2D
			break
	if target == null:
		return
	_world.camera.position = target.global_position
	# Golden pulse: cycle modulate between white and gold several times
	var tween: Tween = target.create_tween()
	tween.set_loops(4)
	tween.tween_property(target, "modulate", Color(1.0, 0.85, 0.1, 1.0), 0.25)
	tween.tween_property(target, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _setup_ai_node_only(rival_id: int, _tc_pos: Vector2) -> void:
	# Creates only the AI controller node; buildings are restored by SaveManager.
	# town_center will be wired up in restore_world() after buildings are recreated.
	var ai: Node = Node.new()
	ai.set_script(load("res://scripts/ai/ai_player.gd"))
	ai.set("player_id", rival_id)
	ai.set_name("AIPlayer_%d" % rival_id)
	_world.add_child(ai)
	ai.set("town_center", null)
	ai.set("units_layer", _world.units_layer)
	ai.set("buildings_layer", _world.buildings_layer)
	ai.set("drop_off", _world.drop_off)
	ai.set("enemy_town_center", _world.drop_off)

func _setup_ai(rival_id: int, tc_pos: Vector2) -> void:
	var rival_civ: String = MatchConfig.get_rival_civ_id(rival_id)
	var tc: Node2D = AI_TOWN_CENTER_SCENE.instantiate() as Node2D
	tc.global_position = tc_pos
	tc.set("player_id", rival_id)
	_world.buildings_layer.add_child(tc)
	_world._ai_town_centers[rival_id] = tc

	var ai_drop_off: Node = tc.get_node_or_null("DropOff")

	for i: int in range(3):
		var v: CharacterBody2D = VILLAGER_SCENE.instantiate()
		_world.units_layer.add_child(v)
		v.global_position = tc.global_position + _starting_villager_offset(i)
		v.set("player_id", rival_id)
		v.set("civ_id", rival_civ)
		PopulationManager.add_unit(rival_id)
		EventBus.unit_spawned.emit(v, rival_id)

	var scout: CharacterBody2D = SCOUT_SCENE.instantiate()
	_world.units_layer.add_child(scout)
	scout.global_position = tc.global_position + Vector2(80.0, -60.0)
	scout.set("player_id", rival_id)
	scout.set("civ_id", rival_civ)
	PopulationManager.add_unit(rival_id)
	EventBus.unit_spawned.emit(scout, rival_id)

	# Multiplayer HUMAN rivals get the same starting assets (TC, villagers,
	# scout, hero) but no AI brain — their orders arrive over the network.
	# AI slots configured in the LAN lobby (and every skirmish rival) DO get
	# their brain, but only on the simulation authority: a client-side brain
	# would submit through the redirected CommandBus and reach the host
	# stamped with the CLIENT's player id.
	if not NetworkSession.is_client() and not NetworkSession.is_human_player(rival_id):
		var ai: Node = Node.new()
		ai.set_script(load("res://scripts/ai/ai_player.gd"))
		ai.set("player_id", rival_id)
		_world.add_child(ai)
		ai.set("town_center", tc)
		ai.set("units_layer", _world.units_layer)
		ai.set("buildings_layer", _world.buildings_layer)
		ai.set("drop_off", ai_drop_off if ai_drop_off != null else tc)
		# AI targets player TC initially; will switch dynamically in Fase 4
		ai.set("enemy_town_center", _world.drop_off)

	_spawn_hero(rival_id, tc_pos)

func _starting_villager_offset(i: int) -> Vector2:
	var idx: int = clampi(i, 0, _STARTING_VILLAGER_SCREEN_OFFSETS.size() - 1)
	return IsoProjection.screen_to_world(_STARTING_VILLAGER_SCREEN_OFFSETS[idx])

func _setup_ai_debug_overlay() -> void:
	var overlay: AIDebugOverlay = AIDebugOverlay.new()
	_world.add_child(overlay)
	for child: Node in _world.get_children():
		if child.get_script() != null and (child.get_script() as Script).resource_path.contains("ai_player"):
			overlay.register_ai(child)

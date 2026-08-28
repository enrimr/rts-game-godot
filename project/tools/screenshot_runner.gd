extends Node

## Visual-review harness: boots a real match (real renderer, NOT --headless)
## and saves viewport PNGs so a reviewer can inspect the actual running game.
##
## Run:
##   CALIMA_SHOT_DIR=/tmp/calima-shots CALIMA_SEED=42 \
##   $GODOT --path project --resolution 1600x900 res://tools/screenshot_runner.tscn
##
## Env vars:
##   CALIMA_SHOT_DIR   output directory for PNGs (required, absolute path)
##   CALIMA_SEED       fixed map seed (optional; default 42)
##   CALIMA_MAP        MatchConfig.MapType int (optional; default STANDARD)
##   CALIMA_WARMUP     seconds of gameplay before the first shot (default 6)
##   CALIMA_TIMESCALE  Engine.time_scale during warmup (default 3.0)
##   CALIMA_VICTORY    MatchConfig.VictoryMode int (optional; 1 = REGICIDE)
##
## Shots taken (viewport captures — window occlusion does not matter):
##   01_tc_close.png     player TC close-up (units readable), zoom 2.4
##   02_tc_medium.png    player TC + surroundings, zoom 1.4
##   03_overview.png     whole map diamond, fog revealed, fit-to-frame zoom
##   04_tc_late.png      player TC after more in-game seconds (units moving)
##
## CALIMA_SELECT=1 adds two HUD-review shots:
##   06_selection.png       starting villagers selected (portraits + actions)
##   07_building_panel.png  player TC selected (train button + action grid)

var _shot_dir: String = ""
var _world: Node2D = null
var _camera: Camera2D = null

func _ready() -> void:
	_shot_dir = OS.get_environment("CALIMA_SHOT_DIR")
	if _shot_dir.is_empty():
		push_error("SCREENSHOT_RUNNER: CALIMA_SHOT_DIR not set")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	if OS.get_environment("CALIMA_SEED").is_empty():
		OS.set_environment("CALIMA_SEED", "42")

	MatchConfig.weather_enabled = false   # deterministic visuals
	MatchConfig.rival_count = 1
	var map_env: String = OS.get_environment("CALIMA_MAP")
	MatchConfig.map_type = int(map_env) if not map_env.is_empty() else MatchConfig.MapType.STANDARD
	# CALIMA_VICTORY: MatchConfig.VictoryMode int (e.g. 1 = REGICIDE) so mode-
	# gated HUD elements like the hero widget can be captured.
	var victory_env: String = OS.get_environment("CALIMA_VICTORY")
	if not victory_env.is_empty():
		MatchConfig.victory_mode = int(victory_env)
	# Optional civ overrides so reviewers can capture each civilization's look.
	var civ_env: String = OS.get_environment("CALIMA_CIV")
	if not civ_env.is_empty():
		MatchConfig.player_civ_id = civ_env
	# CALIMA_RIVAL_CIV accepts a comma-separated list; its length sets the
	# rival count (multi-player review matches), overridable via CALIMA_RIVALS.
	var rival_env: String = OS.get_environment("CALIMA_RIVAL_CIV")
	if not rival_env.is_empty():
		var civ_list: PackedStringArray = rival_env.split(",", false)
		MatchConfig.rival_civ_ids.clear()
		for c: String in civ_list:
			MatchConfig.rival_civ_ids.append(c.strip_edges())
		MatchConfig.rival_count = MatchConfig.rival_civ_ids.size()
	var rivals_env: String = OS.get_environment("CALIMA_RIVALS")
	if not rivals_env.is_empty():
		MatchConfig.rival_count = int(rivals_env)

	_world = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	add_child(_world)
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_camera = _find_camera()
	if _camera == null:
		push_error("SCREENSHOT_RUNNER: camera not found")
		get_tree().quit(1)
		return

	var warmup: float = float(OS.get_environment("CALIMA_WARMUP")) if not OS.get_environment("CALIMA_WARMUP").is_empty() else 6.0
	var tscale: float = float(OS.get_environment("CALIMA_TIMESCALE")) if not OS.get_environment("CALIMA_TIMESCALE").is_empty() else 3.0
	Engine.time_scale = tscale
	await get_tree().create_timer(warmup).timeout
	Engine.time_scale = 1.0

	var tc_pos: Vector2 = _player_tc_position()
	await _shoot(tc_pos, 2.4, "01_tc_close")
	await _shoot(tc_pos, 1.4, "02_tc_medium")
	Engine.time_scale = tscale
	await get_tree().create_timer(4.0).timeout
	Engine.time_scale = 1.0
	await _shoot(tc_pos, 2.0, "04_tc_late")

	if OS.get_environment("CALIMA_SELECT") == "1":
		await _shoot_selection_panels(tc_pos)

	if OS.get_environment("CALIMA_PREVIEW") == "1":
		await _shoot_placement_preview(tc_pos)

	if OS.get_environment("CALIMA_CURSOR") == "1":
		await _check_cursor_context(tc_pos)

	if OS.get_environment("CALIMA_PATH") == "1":
		await _check_path_display(tc_pos)

	# Overview goes last: fog is revealed so the reviewer can inspect the whole
	# projected map, which would otherwise be near-black unexplored fog.
	var fog: Node = _world.get("_fog") as Node
	if fog != null and fog.has_method("reveal_all"):
		fog.call("reveal_all")
	var center: Vector2 = _landmass_center()
	print("SCREENSHOT_RUNNER: overview centre = ", center)
	await _shoot(center, _overview_zoom(), "03_overview")

	print("SCREENSHOT_RUNNER: done -> ", _shot_dir)
	get_tree().quit(0)

func _find_camera() -> Camera2D:
	for c: Node in _world.get_children():
		if c is Camera2D:
			return c as Camera2D
	return _world.get_node_or_null("Camera2D") as Camera2D

# Zoom that fits the whole projected map diamond in the viewport with a margin.
# Under the iso projection a square map of side S spans S*sqrt(2)*zoom on screen.
func _overview_zoom() -> float:
	var side: float = MatchConfig.get_map_half() * 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(vp.x / (side * sqrt(2.0)),
		vp.y / (side * sqrt(2.0) * 0.5))
	return fit * 0.92

# The generated continent is an organic blob, not centred on the world origin;
# the resource-node centroid tracks where the actual landmass sits.
func _landmass_center() -> Vector2:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("resource_nodes")
	if nodes.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for n: Node in nodes:
		sum += (n as Node2D).global_position
	return sum / float(nodes.size())

func _player_tc_position() -> Vector2:
	var drop_off: Node2D = _world.get_node_or_null("DropOffNode") as Node2D
	if drop_off != null:
		return drop_off.global_position
	for b: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		if (b.get("player_id") as int) == 0:
			return (b as Node2D).global_position
	return Vector2.ZERO

# CALIMA_PREVIEW=1: exercises the real Barracks placement path (ghost building
# + ground-diamond footprint + snap-grid lattice) near the TC and captures it
# as 05_preview.png, then cancels so the flow leaves no side effects.
func _shoot_placement_preview(tc_pos: Vector2) -> void:
	ResourceManager.add_resource(0, "wood", 200.0)
	_camera.global_position = tc_pos
	_camera.zoom = IsoProjection.camera_zoom(2.0)
	if not _world.has_method("_start_placement"):
		push_error("SCREENSHOT_RUNNER: game world lacks _start_placement")
		return
	_world.call("_start_placement", "barracks")
	# The ghost follows the mouse each frame; park the cursor over a clear spot
	# beside the TC so the preview and its snap grid land on open ground.
	var offset_screen: Vector2 = IsoProjection.world_to_screen(Vector2(260.0, -60.0), 2.0)
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5 + offset_screen)
	for _i: int in range(6):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _shot_dir.path_join("05_preview.png")
	if img.save_png(path) == OK:
		print("SCREENSHOT_RUNNER: saved ", path)
	else:
		push_error("SCREENSHOT_RUNNER: failed to save " + path)
	_world.call("_cancel_placement")

# CALIMA_SELECT=1: selects the starting villagers, then the player TC, and
# captures the bottom HUD (baked-icon portraits + action grid) for review.
func _shoot_selection_panels(tc_pos: Vector2) -> void:
	_camera.global_position = tc_pos
	_camera.zoom = IsoProjection.camera_zoom(2.0)

	var villagers: Array = []
	for node: Node in _world.find_children("*", "CharacterBody2D", true, false):
		if node is Villager and (node.get("player_id") as int) == 0:
			villagers.append(node)
	if villagers.is_empty():
		push_error("SCREENSHOT_RUNNER: no player villagers found for CALIMA_SELECT")
	else:
		SelectionManager.select(villagers)
		# Same code path as Ctrl+1: makes the control-group chip visible in shot 06.
		SelectionManager.save_group(1)
		# Generous settle: portrait/action icons bake asynchronously over frames.
		await _grab("06_selection", 40)
		# Single selection adds the compact stat-chip row to the detail panel.
		SelectionManager.select([villagers[0]])
		await _grab("06b_single_villager", 40)
		# Large selection (>10) switches portraits to the compact 40 px tiles;
		# repeating the same villagers is enough to exercise the layout.
		var many_hud: Node = _find_hud()
		if many_hud != null and many_hud.has_method("update_selection"):
			var many: Array = []
			for i: int in range(15):
				many.append(villagers[i % villagers.size()])
			many_hud.update_selection(many)
			await _grab("06c_many_selected", 40)
			SelectionManager.select([villagers[0]])

	# Group members are the DropOff marker children; the selectable building
	# (with the training queue) is their parent TC root.
	var tc: Node = null
	for marker: Node in get_tree().get_nodes_in_group("drop_off_buildings"):
		var building: Node = marker.get_parent()
		if building == null or not building.has_method("get_hero_respawn_fraction"):
			continue
		# Ownership must come from the BUILDING root: the DropOff marker child
		# has no player_id, and (null as int) == 0 made this pick the AI's TC
		# depending on group iteration order (intermittent empty panel).
		var pid: Variant = building.get("player_id")
		if pid == null or (pid as int) != 0:
			continue
		tc = building
		break
	if tc == null:
		push_error("SCREENSHOT_RUNNER: player TC not found for CALIMA_SELECT")
		return
	SelectionManager.select([])
	EventBus.building_selected.emit(tc)
	# Queue a couple of villagers so the training-queue slots (entity icons)
	# are visible in the capture. Starting food covers them.
	if tc.has_method("order_train"):
		tc.call("order_train")
		tc.call("order_train")
	# The cost strip normally appears on action-button hover; drive it directly
	# so the capture can verify the icon+amount price row in the detail panel.
	var hud: Node = _find_hud()
	if hud != null:
		# Native tooltip popups are focus/idle dependent and unreliable in
		# automated captures: mount the rich tooltip CONTENT directly (same
		# control _make_custom_tooltip returns) and grab it as 08_tooltip.
		var grid: Node = hud.get_node_or_null("%ActionButtonsGrid")
		if grid != null:
			for child: Node in grid.get_children():
				if child is ActionButton and not (child as ActionButton).action_costs.is_empty():
					var btn: ActionButton = child as ActionButton
					var content: Control = btn._make_custom_tooltip(btn.tooltip_text) as Control
					if content != null:
						var frame: PanelContainer = PanelContainer.new()
						frame.position = Vector2(500, 400)
						hud.add_child(frame)
						frame.add_child(content)
						await _grab("08_tooltip", 10)
						frame.queue_free()
					break
	await _grab("07_building_panel", 40)
	EventBus.building_selected.emit(null)

func _find_hud() -> Node:
	for layer: Node in _world.find_children("*", "CanvasLayer", true, false):
		if layer.has_method("update_selection"):
			return layer
	return null

func _shoot(world_pos: Vector2, zoom: float, name_base: String) -> void:
	_camera.global_position = world_pos
	# Compose with the isometric Y squash so shots match real gameplay framing.
	_camera.zoom = IsoProjection.camera_zoom(zoom)
	await _grab(name_base, 6)

func _grab(name_base: String, settle_frames: int) -> void:
	# Let the renderer settle (interpolation, redraws) before grabbing pixels.
	for _i: int in range(settle_frames):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _shot_dir.path_join(name_base + ".png")
	var err: int = img.save_png(path)
	if err != OK:
		push_error("SCREENSHOT_RUNNER: failed to save " + path)
	else:
		print("SCREENSHOT_RUNNER: saved ", path)

# CALIMA_CURSOR=1: end-to-end cursor-context check — selects the villagers,
# warps the real mouse over the nearest tree, and prints the resolved cursor
# id plus the hovered-control gate state.
func _check_cursor_context(tc_pos: Vector2) -> void:
	var villagers: Array = []
	for node: Node in _world.find_children("*", "CharacterBody2D", true, false):
		if node is Villager and (node.get("player_id") as int) == 0:
			villagers.append(node)
	print("CURSOR_CHECK: selecting ", villagers.size(), " villagers")
	SelectionManager.select(villagers)
	_camera.global_position = tc_pos
	_camera.zoom = IsoProjection.camera_zoom(1.4)
	await get_tree().process_frame
	var best: Node2D = null
	var best_d: float = INF
	for rn: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if (rn.get("resource_type") as int) != ResourceNode.ResourceType.WOOD:
			continue
		var d: float = (rn as Node2D).global_position.distance_to(tc_pos)
		if d < best_d:
			best_d = d
			best = rn as Node2D
	if best == null:
		print("CURSOR_CHECK: no wood node found")
		return
	var screen: Vector2 = get_viewport().get_canvas_transform() * best.global_position
	get_viewport().warp_mouse(screen)
	await get_tree().create_timer(0.4).timeout
	var hovered: Control = get_viewport().gui_get_hovered_control()
	print("CURSOR_CHECK: over tree -> id=", CursorManager.current_id,
		" hovered_control=", hovered.name if hovered != null else "<none>")
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	await get_tree().create_timer(0.4).timeout
	print("CURSOR_CHECK: over ground -> id=", CursorManager.current_id)
	SelectionManager.select([])
	await get_tree().create_timer(0.3).timeout
	print("CURSOR_CHECK: no selection -> id=", CursorManager.current_id)

# CALIMA_PATH=1: toggles the show-path display on a villager, orders a long
# move, and captures mid-journey so the route line is reviewable.
func _check_path_display(tc_pos: Vector2) -> void:
	var villager: Node2D = null
	for node: Node in _world.find_children("*", "CharacterBody2D", true, false):
		if node is Villager and (node.get("player_id") as int) == 0:
			villager = node as Node2D
			break
	if villager == null:
		print("PATH_CHECK: no villager")
		return
	villager.call("toggle_path_display")
	villager.call("order_move", tc_pos + Vector2(700.0, 500.0))
	await get_tree().create_timer(1.0).timeout
	# Read the actual path line property: the first Line2D child is the
	# selection ring (28 ellipse segments), which fooled an earlier probe.
	var line: Line2D = villager.get("_path_line") as Line2D
	print("PATH_CHECK: line=", line != null,
		" visible=", line.visible if line != null else false,
		" points=", line.points.size() if line != null else -1,
		" path_visible_flag=", villager.get("_path_visible"),
		" nav_pts_now=", (villager.get("nav_agent") as NavigationAgent2D).get_current_navigation_path().size(),
		" unit_z=", villager.z_index)
	if line != null:
		line.visible = true
	await _shoot(villager.global_position, 1.4, "09_path")
	if line != null:
		print("PATH_CHECK: after grab visible=", line.visible)
	# Force the give-up path style (red fading route) and capture it.
	villager.call("_abandon_movement")
	await get_tree().create_timer(0.4).timeout
	print("PATH_CHECK: failed style color=", line.default_color if line != null else null,
		" failed_flag=", villager.get("_path_failed"))
	await _shoot(villager.global_position, 1.4, "10_path_failed")
	# After the fade the line must STAY hidden (a stale nav path used to
	# repaint the cyan route on an idle unit).
	await get_tree().create_timer(3.2).timeout
	print("PATH_CHECK: post-fade visible=", line.visible if line != null else null,
		" points_now=", (villager.get("nav_agent") as NavigationAgent2D).get_current_navigation_path().size())

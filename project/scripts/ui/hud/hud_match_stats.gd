class_name HudMatchStats
extends Node

## Owns the match clock, per-player/rival stat counters, timeline snapshots,
## and the end-of-match game-over + charts overlays. Self-wires to GameManager,
## EventBus and ResourceManager. The authoritative source for elapsed time —
## HudManager reads get_clock_text() each frame to paint the %GameClock label.

const SNAPSHOT_INTERVAL: float = 15.0
const OFFENSE_THRESHOLD: int = 2   # kills in one interval to count as an offensive

var local_player_id: int = 0
var _clock_label: Label = null
var _hud_root: Control = null

var _elapsed_seconds: float = 0.0
var _clock_running: bool = false
var _snapshot_timer: float = 0.0

# --- Stats tracking ---
var _stat_units_trained: int = 0
var _stat_buildings_built: int = 0
var _stat_enemies_killed: int = 0
var _stat_resources_gathered: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}

# Legacy player_id 1 vars kept for fallback in the game-over panel
var _ai_stat_units_trained: int = 0
var _ai_stat_buildings_built: int = 0
var _ai_stat_units_lost: int = 0
var _ai_stat_resources_gathered: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}
var _ai_last_resources: Dictionary = {}

# Extended per-rival stats: rival_player_id → stat dict
var _rival_stats: Dictionary = {}       # int → Dictionary
var _rival_last_res: Dictionary = {}    # int → Dictionary
var _last_resources: Dictionary = {}

# --- Timeline snapshots ---
var _snap_pop_a:       Array = []
var _snap_res_a:       Array = []
var _snap_age_a:       Array = []
var _snap_kills_a:      Array = []
var _snap_kills_a_prev: int = 0
var _offense_snaps_a: Array = []

var _snap_pop_rivals:    Dictionary = {}
var _snap_res_rivals:    Dictionary = {}
var _snap_age_rivals:    Dictionary = {}
var _snap_kills_rivals:  Dictionary = {}
var _snap_kills_rivals_prev: Dictionary = {}
var _offense_snaps_rivals:   Dictionary = {}

func init(player_id: int, clock_label: Label, hud_root: Control) -> void:
	local_player_id = player_id
	_clock_label = clock_label
	_hud_root = hud_root

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_over.connect(_on_game_over)
	EventBus.player_eliminated.connect(_on_player_eliminated_maybe_local)
	EventBus.unit_spawned.connect(_on_stat_unit_spawned)
	EventBus.building_construction_complete.connect(_on_stat_building_complete)
	EventBus.unit_died.connect(_on_stat_unit_died)
	ResourceManager.resources_updated.connect(_on_stat_resources_updated)

func _process(delta: float) -> void:
	if not _clock_running:
		return
	_elapsed_seconds += delta
	if is_instance_valid(_clock_label):
		var total_secs: int = int(_elapsed_seconds)
		_clock_label.text = "%02d:%02d" % [total_secs / 60, total_secs % 60]
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = 0.0
		_take_snapshot()

func get_clock_text() -> String:
	var total_secs: int = int(_elapsed_seconds)
	return "%02d:%02d" % [total_secs / 60, total_secs % 60]

func _init_rival_stats(rival_id: int) -> void:
	_rival_stats[rival_id] = {
		"units_trained": 0, "buildings_built": 0,
		"units_lost": 0,
		"resources": {"food": 0, "wood": 0, "gold": 0, "stone": 0},
	}
	_rival_last_res[rival_id] = {}

func _on_game_started() -> void:
	_elapsed_seconds = 0.0
	_clock_running = true
	var starting: Dictionary = ResourceManager.get_resources(local_player_id)
	_last_resources = starting.duplicate()
	for rival_id: int in MatchConfig.get_rival_player_ids():
		_init_rival_stats(rival_id)
		_snap_pop_rivals[rival_id]          = []
		_snap_res_rivals[rival_id]          = []
		_snap_age_rivals[rival_id]          = []
		_snap_kills_rivals[rival_id]        = []
		_snap_kills_rivals_prev[rival_id]   = 0
		_offense_snaps_rivals[rival_id]     = []

# --- Stats signal handlers ---

func _on_stat_unit_spawned(_unit: Node, player_id: int) -> void:
	if not _clock_running:
		return
	if player_id == local_player_id:
		_stat_units_trained += 1
	else:
		if player_id == 1:
			_ai_stat_units_trained += 1
		if _rival_stats.has(player_id):
			(_rival_stats[player_id] as Dictionary)["units_trained"] = \
				((_rival_stats[player_id] as Dictionary)["units_trained"] as int) + 1

func _on_stat_building_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid == null:
		return
	if (pid as int) == local_player_id:
		_stat_buildings_built += 1
	else:
		if (pid as int) == 1:
			_ai_stat_buildings_built += 1
		if _rival_stats.has(pid as int):
			(_rival_stats[pid as int] as Dictionary)["buildings_built"] = \
				((_rival_stats[pid as int] as Dictionary)["buildings_built"] as int) + 1

func _on_stat_unit_died(unit: Node, player_id: int) -> void:
	var udata: Variant = unit.get("unit_data")
	if udata == null:
		return
	if player_id != local_player_id:
		_stat_enemies_killed += 1
		if player_id == 1:
			_ai_stat_units_lost += 1
		if _rival_stats.has(player_id):
			(_rival_stats[player_id] as Dictionary)["units_lost"] = \
				((_rival_stats[player_id] as Dictionary)["units_lost"] as int) + 1
	else:
		if _rival_stats.has(1):
			(_rival_stats[1] as Dictionary)["units_lost"] = \
				((_rival_stats[1] as Dictionary)["units_lost"] as int) + 1

func _take_snapshot() -> void:
	# Player
	var pop_a: Dictionary = PopulationManager.get_population(local_player_id)
	_snap_pop_a.append(float(pop_a.get("current", 0) as int))
	var total_a: int = 0
	for k: String in ["food", "wood", "gold", "stone"]:
		total_a += _stat_resources_gathered.get(k, 0) as int
	_snap_res_a.append(float(total_a))
	_snap_age_a.append(float(AgeManager.get_age(local_player_id)))
	var kills_delta_a: int = _stat_enemies_killed - _snap_kills_a_prev
	_snap_kills_a.append(float(kills_delta_a))
	var snap_idx: int = _snap_kills_a.size() - 1
	if kills_delta_a >= OFFENSE_THRESHOLD:
		_offense_snaps_a.append(snap_idx)
	_snap_kills_a_prev = _stat_enemies_killed

	# Per-rival
	for rival_id: int in MatchConfig.get_rival_player_ids():
		var pop_r: Dictionary = PopulationManager.get_population(rival_id)
		(_snap_pop_rivals[rival_id] as Array).append(float(pop_r.get("current", 0) as int))

		var rival_res_dict: Dictionary = {}
		if _rival_stats.has(rival_id):
			rival_res_dict = (_rival_stats[rival_id] as Dictionary).get("resources", {}) as Dictionary
		var total_r: int = 0
		for k: String in ["food", "wood", "gold", "stone"]:
			total_r += rival_res_dict.get(k, 0) as int
		(_snap_res_rivals[rival_id] as Array).append(float(total_r))

		(_snap_age_rivals[rival_id] as Array).append(float(AgeManager.get_age(rival_id)))

		var prev_kills_r: int = _snap_kills_rivals_prev.get(rival_id, 0) as int
		var rival_lost: int = 0
		if _rival_stats.has(rival_id):
			rival_lost = (_rival_stats[rival_id] as Dictionary).get("units_lost", 0) as int
		var kills_delta_r: int = rival_lost - prev_kills_r
		(_snap_kills_rivals[rival_id] as Array).append(float(kills_delta_r))
		var snap_idx_r: int = (_snap_kills_rivals[rival_id] as Array).size() - 1
		if kills_delta_r >= OFFENSE_THRESHOLD:
			(_offense_snaps_rivals[rival_id] as Array).append(snap_idx_r)
		_snap_kills_rivals_prev[rival_id] = rival_lost

func _on_stat_resources_updated(player_id: int, resources: Dictionary) -> void:
	for res: String in ["food", "wood", "gold", "stone"]:
		var current: float = resources.get(res, 0.0) as float
		if player_id == local_player_id:
			var last: float = _last_resources.get(res, current) as float
			if current > last:
				_stat_resources_gathered[res] = (_stat_resources_gathered[res] as int) + int(current - last)
			_last_resources[res] = current
		else:
			# Legacy player_id 1 path
			if player_id == 1:
				var last: float = _ai_last_resources.get(res, current) as float
				if current > last:
					_ai_stat_resources_gathered[res] = (_ai_stat_resources_gathered[res] as int) + int(current - last)
				_ai_last_resources[res] = current
			# Generic rival path
			if _rival_stats.has(player_id):
				var rival_last: Dictionary = _rival_last_res.get(player_id, {}) as Dictionary
				var last_r: float = rival_last.get(res, current) as float
				if current > last_r:
					var rival_res: Dictionary = (_rival_stats[player_id] as Dictionary)["resources"] as Dictionary
					rival_res[res] = (rival_res.get(res, 0) as int) + int(current - last_r)
				if not _rival_last_res.has(player_id):
					_rival_last_res[player_id] = {}
				(_rival_last_res[player_id] as Dictionary)[res] = current

# --- Game over screen ---

# Overlay pieces of the current result panel (defeat-while-spectating or
# final): freed and rebuilt when the definitive game-over arrives.
var _result_nodes: Array[Node] = []
var _local_defeat_shown: bool = false

## The local player fell (resigned or conquered) while hostile sides keep
## fighting: show the defeat panel now — the match plays on and "view map"
## turns into spectating. The definitive game_over rebuilds the panel later.
func _on_player_eliminated_maybe_local(pid: int) -> void:
	if pid != local_player_id or _local_defeat_shown:
		return
	if GameManager.state == GameManager.GameState.GAME_OVER:
		return
	_local_defeat_shown = true
	_show_result_panel(-1, false)

func _on_game_over(winner_player_id: int) -> void:
	_clock_running = false
	_take_snapshot()
	_show_result_panel(winner_player_id, true)

func _show_result_panel(winner_player_id: int, final: bool) -> void:
	for stale: Node in _result_nodes:
		if is_instance_valid(stale):
			stale.queue_free()
	_result_nodes.clear()

	var root: Node = _hud_root
	if root == null:
		return

	# Dark overlay — blocks clicks on world but NOT on our panel
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(overlay)
	_result_nodes.append(overlay)

	# Centred panel
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(center)
	_result_nodes.append(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.08, 0.08, 0.10, 0.97)))
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = tr("GAMEOVER_VICTORY") if winner_player_id >= 0 and GameManager.are_allied(winner_player_id, local_player_id) else tr("GAMEOVER_DEFEAT")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	var title_col: Color = Color(0.25, 1.0, 0.35) if winner_player_id >= 0 and GameManager.are_allied(winner_player_id, local_player_id) else Color(1.0, 0.25, 0.25)
	title.add_theme_color_override("font_color", title_col)
	vbox.add_child(title)

	if not final:
		var hint: Label = Label.new()
		hint.text = tr("GAMEOVER_SPECTATE_HINT")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 17)
		hint.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
		vbox.add_child(hint)

	# Separator
	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# Stats header
	var stats_header: Label = Label.new()
	stats_header.text = tr("GAMEOVER_SUMMARY")
	stats_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_header.add_theme_font_size_override("font_size", 22)
	stats_header.add_theme_color_override("font_color", Color(0.80, 0.75, 0.55))
	vbox.add_child(stats_header)

	# Stats grid — 3 columns: stat label | player value | rival value
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	var total_secs: int = int(_elapsed_seconds)
	var time_str: String = "%02d:%02d" % [total_secs / 60, total_secs % 60]
	var age_keys: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]

	var rival_ids: Array[int] = MatchConfig.get_rival_player_ids()
	var total_cols: int = 1 + rival_ids.size()   # player + rivals
	grid.columns = 1 + total_cols

	# Helper: get display name for a civ_id
	var _get_civ_display: Callable = func(civ_id: String) -> String:
		var res: CivilizationResource = load(
			"res://resources/civilizations/%s.tres" % civ_id) as CivilizationResource
		return res.display_name if res != null else civ_id

	# Column headers
	var _blank: Label = Label.new()
	grid.add_child(_blank)

	# Player column
	var player_col: VBoxContainer = VBoxContainer.new()
	player_col.add_theme_constant_override("separation", 1)
	var ph: Label = Label.new()
	ph.text = tr("GAMEOVER_PLAYER")
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ph.add_theme_font_size_override("font_size", 17)
	ph.add_theme_color_override("font_color", PlayerColors.get_color(local_player_id))
	player_col.add_child(ph)
	var pc: Label = Label.new()
	pc.text = _get_civ_display.call(MatchConfig.player_civ_id) as String
	pc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pc.add_theme_font_size_override("font_size", 15)
	pc.add_theme_color_override("font_color", PlayerColors.get_color(local_player_id).lightened(0.3))
	player_col.add_child(pc)
	grid.add_child(player_col)

	# Rival columns
	for ri: int in range(rival_ids.size()):
		var rid: int = rival_ids[ri]
		var rcol: VBoxContainer = VBoxContainer.new()
		rcol.add_theme_constant_override("separation", 1)
		var rh: Label = Label.new()
		var rival_label: String = tr("GAMEOVER_RIVAL") if rival_ids.size() == 1 \
			else tr("GAMEOVER_RIVAL") + " %d" % (ri + 1)
		rh.text = rival_label
		rh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rh.add_theme_font_size_override("font_size", 17)
		var rcol_color: Color = PlayerColors.get_color(rid)
		rh.add_theme_color_override("font_color", rcol_color)
		rcol.add_child(rh)
		var rcc: Label = Label.new()
		rcc.text = _get_civ_display.call(MatchConfig.get_rival_civ_id(rid)) as String
		rcc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rcc.add_theme_font_size_override("font_size", 15)
		rcc.add_theme_color_override("font_color", rcol_color.lightened(0.3))
		rcol.add_child(rcc)
		grid.add_child(rcol)

	# Helper: get rival stat value string
	var _rival_val: Callable = func(rid: int, key: String) -> String:
		if _rival_stats.has(rid):
			return str((_rival_stats[rid] as Dictionary).get(key, 0))
		# Fallback to legacy player_id 1 vars
		match key:
			"units_trained":   return str(_ai_stat_units_trained)
			"buildings_built": return str(_ai_stat_buildings_built)
			"units_lost":      return str(_ai_stat_units_lost)
		return "0"

	var _rival_res_val: Callable = func(rid: int, res: String) -> String:
		if _rival_stats.has(rid):
			var r: Dictionary = (_rival_stats[rid] as Dictionary).get("resources", {}) as Dictionary
			return str(r.get(res, 0))
		return str(_ai_stat_resources_gathered.get(res, 0))

	# Build stat rows — first element is label, then one value per column
	var stat_defs: Array = [
		{"label": tr("GAMEOVER_TIME"),
			"player": time_str,
			"rival_fn": func(_rid: int) -> String: return time_str},
		{"label": tr("GAMEOVER_AGE"),
			"player": tr(age_keys[clampi(AgeManager.get_age(local_player_id), 0, 3)]),
			"rival_fn": func(rid: int) -> String: return tr(age_keys[clampi(AgeManager.get_age(rid), 0, 3)])},
		{"label": tr("GAMEOVER_UNITS"),
			"player": str(_stat_units_trained),
			"rival_fn": func(rid: int) -> String: return _rival_val.call(rid, "units_trained") as String},
		{"label": tr("GAMEOVER_BUILDINGS"),
			"player": str(_stat_buildings_built),
			"rival_fn": func(rid: int) -> String: return _rival_val.call(rid, "buildings_built") as String},
		{"label": tr("GAMEOVER_KILLS"),
			"player": str(_stat_enemies_killed),
			"rival_fn": func(rid: int) -> String: return _rival_val.call(rid, "units_lost") as String},
		{"label": tr("GAMEOVER_FOOD"),
			"player": str(_stat_resources_gathered.get("food", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "food") as String},
		{"label": tr("GAMEOVER_WOOD"),
			"player": str(_stat_resources_gathered.get("wood", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "wood") as String},
		{"label": tr("GAMEOVER_GOLD"),
			"player": str(_stat_resources_gathered.get("gold", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "gold") as String},
		{"label": tr("GAMEOVER_STONE"),
			"player": str(_stat_resources_gathered.get("stone", 0)),
			"rival_fn": func(rid: int) -> String: return _rival_res_val.call(rid, "stone") as String},
	]

	for stat: Dictionary in stat_defs:
		var key_lbl: Label = Label.new()
		key_lbl.text = stat["label"] as String
		key_lbl.add_theme_font_size_override("font_size", 18)
		key_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
		grid.add_child(key_lbl)

		var player_val: Label = Label.new()
		player_val.text = stat["player"] as String
		player_val.add_theme_font_size_override("font_size", 18)
		player_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		player_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(player_val)

		for rid: int in rival_ids:
			var rival_val: Label = Label.new()
			rival_val.text = (stat["rival_fn"] as Callable).call(rid) as String
			rival_val.add_theme_font_size_override("font_size", 18)
			rival_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			rival_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(rival_val)

	# Separator
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	# Buttons row
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	# "Ver mapa" button — closes stats panel and adds a persistent corner exit button
	var hud_root: Node = root
	var map_btn: Button = Button.new()
	map_btn.text = tr("GAMEOVER_VIEW_MAP")
	map_btn.custom_minimum_size = Vector2(150.0, 36.0)
	map_btn.add_theme_font_size_override("font_size", 20)
	map_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.15, 0.30, 0.50, 0.95)))
	map_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.25, 0.45, 0.70, 0.95)))

	# The natural next click after a match: watch it back. Only when this
	# match actually recorded itself (never inside a replay of a replay) and
	# only once it is truly over — while spectating it is still recording.
	if final and not MatchConfig.is_replay() and not ReplayFile.last_recorded_path.is_empty():
		var replay_btn: Button = Button.new()
		replay_btn.text = tr("GAMEOVER_WATCH_REPLAY")
		replay_btn.custom_minimum_size = Vector2(180.0, 36.0)
		replay_btn.add_theme_font_size_override("font_size", 20)
		replay_btn.add_theme_stylebox_override("normal",
			HudStyle.panel(Color(0.45, 0.35, 0.10, 0.95)))
		replay_btn.add_theme_stylebox_override("hover",
			HudStyle.panel(Color(0.62, 0.49, 0.16, 0.95)))
		replay_btn.pressed.connect(func() -> void:
			get_tree().paused = false
			Engine.time_scale = 1.0
			ReplayFile.launch(ReplayFile.last_recorded_path, get_tree()))
		btn_row.add_child(replay_btn)

	var exit_btn: Button = Button.new()
	exit_btn.text = tr("GAMEOVER_EXIT")
	exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	exit_btn.offset_left   = -160.0
	exit_btn.offset_right  =    0.0
	exit_btn.offset_top    =    8.0
	exit_btn.offset_bottom =   40.0
	exit_btn.add_theme_font_size_override("font_size", 18)
	exit_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.15, 0.15, 0.15, 0.92)))
	exit_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.35, 0.15, 0.15, 0.92)))
	exit_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/game/main_menu.tscn")
	)
	_result_nodes.append(exit_btn)

	map_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		center.queue_free()
		hud_root.add_child(exit_btn)
		var world: Node = get_tree().get_nodes_in_group("world").front()
		if world == null:
			world = get_tree().current_scene
		for child: Node in world.get_children():
			if child is FogOfWar:
				(child as FogOfWar).reveal_all()
				break
	)
	btn_row.add_child(map_btn)

	# "Ver gráficas" button — opens timeline charts overlay
	var charts_btn: Button = Button.new()
	charts_btn.text = tr("GAMEOVER_CHARTS")
	charts_btn.custom_minimum_size = Vector2(150.0, 36.0)
	charts_btn.add_theme_font_size_override("font_size", 20)
	charts_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.22, 0.20, 0.38, 0.95)))
	charts_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.36, 0.32, 0.60, 0.95)))
	charts_btn.pressed.connect(func() -> void:
		_show_charts_panel(root)
	)
	btn_row.add_child(charts_btn)

	# "Volver al menú" button
	var menu_btn: Button = Button.new()
	menu_btn.text = tr("GAMEOVER_BACK_MENU")
	menu_btn.custom_minimum_size = Vector2(150.0, 36.0)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.15, 0.15, 0.15, 0.95)))
	menu_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.30, 0.30, 0.30, 0.95)))
	menu_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/game/main_menu.tscn")
	)
	btn_row.add_child(menu_btn)

# --- Match timeline charts ---

func _show_charts_panel(parent: Node) -> void:
	# Full-screen overlay
	var ov: ColorRect = ColorRect.new()
	ov.color = Color(0.0, 0.0, 0.0, 0.80)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(ov)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	ov.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.07, 0.07, 0.10, 0.98)))
	card.custom_minimum_size = Vector2(700.0, 0.0)
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Title
	var title_lbl: Label = Label.new()
	title_lbl.text = tr("GAMEOVER_CHARTS")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.90, 0.82, 0.52))
	vbox.add_child(title_lbl)

	var rival_ids: Array[int] = MatchConfig.get_rival_player_ids()

	# Legend row
	var legend: HBoxContainer = HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 24)
	vbox.add_child(legend)

	var legend_entries: Array = [[tr("GAMEOVER_PLAYER"), PlayerColors.get_color(local_player_id)]]
	for ri: int in range(rival_ids.size()):
		var label_text: String = tr("GAMEOVER_RIVAL") if rival_ids.size() == 1 \
			else tr("GAMEOVER_RIVAL") + " %d" % (ri + 1)
		legend_entries.append([label_text, PlayerColors.get_color(rival_ids[ri])])

	for ldata: Array in legend_entries:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		legend.add_child(row)
		var swatch: ColorRect = ColorRect.new()
		swatch.color = ldata[1] as Color
		swatch.custom_minimum_size = Vector2(18, 10)
		row.add_child(swatch)
		var ll: Label = Label.new()
		ll.text = ldata[0] as String
		ll.add_theme_font_size_override("font_size", 17)
		ll.add_theme_color_override("font_color", ldata[1] as Color)
		row.add_child(ll)

	vbox.add_child(HSeparator.new())

	# Build series_b (first rival) and extra_series (remaining rivals)
	var first_rid: int = rival_ids[0] if rival_ids.size() > 0 else 1
	var series_b_pop:    Array = _snap_pop_rivals.get(first_rid, []) as Array
	var series_b_res:    Array = _snap_res_rivals.get(first_rid, []) as Array
	var series_b_age:    Array = _snap_age_rivals.get(first_rid, []) as Array
	var series_b_kills:  Array = _snap_kills_rivals.get(first_rid, []) as Array
	var spikes_b_kills:  Array = _offense_snaps_rivals.get(first_rid, []) as Array

	var extra_pop:   Array = []
	var extra_res:   Array = []
	var extra_age:   Array = []
	var extra_kills: Array = []
	var extra_cols:  Array = []
	for ri: int in range(1, rival_ids.size()):
		var rid: int = rival_ids[ri]
		extra_pop.append(_snap_pop_rivals.get(rid, []))
		extra_res.append(_snap_res_rivals.get(rid, []))
		extra_age.append(_snap_age_rivals.get(rid, []))
		extra_kills.append(_snap_kills_rivals.get(rid, []))
		extra_cols.append(PlayerColors.get_color(rid))

	# Charts definition: [title, series_a, series_b, extra_series, extra_colors, spikes_a, spikes_b, mode]
	var chart_defs: Array = [
		[tr("CHART_POPULATION"), _snap_pop_a,   series_b_pop,   extra_pop,   extra_cols, [],              [],             MatchChart.Mode.LINES],
		[tr("CHART_RESOURCES"),  _snap_res_a,   series_b_res,   extra_res,   extra_cols, [],              [],             MatchChart.Mode.LINES],
		[tr("CHART_AGE"),        _snap_age_a,   series_b_age,   extra_age,   extra_cols, [],              [],             MatchChart.Mode.STEPS],
		[tr("CHART_OFFENSIVES"), _snap_kills_a, series_b_kills, extra_kills, extra_cols, _offense_snaps_a, spikes_b_kills, MatchChart.Mode.BARS],
	]

	for cdef: Array in chart_defs:
		var chart: MatchChart = MatchChart.new()
		chart.chart_title   = cdef[0] as String
		chart.series_a      = cdef[1] as Array
		chart.series_b      = cdef[2] as Array
		chart.extra_series  = cdef[3] as Array
		chart.extra_colors  = cdef[4] as Array
		chart.spikes_a      = cdef[5] as Array
		chart.spikes_b      = cdef[6] as Array
		chart.mode          = cdef[7] as int
		chart.total_time    = _elapsed_seconds
		chart.color_a       = PlayerColors.get_color(local_player_id)
		chart.color_b       = PlayerColors.get_color(first_rid)
		chart.custom_minimum_size = Vector2(0.0, 90.0)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(chart)

	vbox.add_child(HSeparator.new())

	# Close button
	var close_btn: Button = Button.new()
	close_btn.text = tr("GAMEOVER_CHARTS_CLOSE")
	close_btn.custom_minimum_size = Vector2(160.0, 36.0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.20, 0.20, 0.25, 0.95)))
	close_btn.add_theme_stylebox_override("hover",  HudStyle.panel(Color(0.35, 0.35, 0.42, 0.95)))
	close_btn.pressed.connect(func() -> void: ov.queue_free())
	vbox.add_child(close_btn)

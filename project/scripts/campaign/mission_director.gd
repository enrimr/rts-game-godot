class_name MissionDirector
extends Node

## Runs one campaign mission inside a live match: tracks the side objectives
## (EventBus-driven checkmarks in a HUD panel), spawns the scripted attack
## waves at the enemy base, drives the "survive" victory countdown, and
## reports mission completion to CampaignManager on victory. Mounted by
## GameWorld only when MatchConfig.campaign_mission >= 0 — skirmish and
## multiplayer never see this node.

const WAVE_SCENE_DIR: String = "res://scenes/units/"
const WAVE_SCENES: Dictionary = {
	"Militia": "militia.tscn", "ManAtArms": "man_at_arms.tscn",
	"LongSwordsman": "long_swordsman.tscn", "Pikeman": "pikeman.tscn",
	"Archer": "archer.tscn", "Scout": "scout.tscn",
	"HeavyScout": "heavy_scout.tscn", "Knight": "knight.tscn",
}

var _world = null   # GameWorld — untyped so dynamic access works
var _mission: Dictionary = {}
var _mission_index: int = -1
var _objectives: Array = []       # mutable copies with "done"/"progress"
var _pending_waves: Array = []
var _elapsed: float = 0.0
var _survive_left: float = -1.0
var _finished: bool = false

var _panel: VBoxContainer = null
var _objective_labels: Array = []
var _survive_label: Label = null

func setup(world) -> void:
	_world = world
	_mission_index = MatchConfig.campaign_mission
	_mission = CampaignData.mission(_mission_index)
	if _mission.is_empty():
		queue_free()
		return
	for obj: Variant in _mission.get("objectives", []) as Array:
		var copy: Dictionary = (obj as Dictionary).duplicate()
		copy["done"] = false
		copy["progress"] = 0
		_objectives.append(copy)
	_pending_waves = (_mission.get("waves", []) as Array).duplicate()
	if (_mission.get("victory", "") as String) == "survive":
		_survive_left = _mission.get("survive_sec", 600.0) as float
	_apply_restored_state(SaveManager.consume_campaign_state())
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.animal_herded.connect(_on_animal_herded)
	EventBus.building_construction_complete.connect(_on_building_complete)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	GameManager.game_over.connect(_on_game_over)
	if _mission.get("hold_offense", false):
		_hold_ai_offense()
	if _mission.get("ai_passive", false):
		_set_ai_flag("passive")
	if _mission.has("ai_military_cap"):
		_set_ai_value("military_cap", _mission.get("ai_military_cap") as int)
	if _mission.has("ai_tick_scale"):
		_set_ai_value("tick_interval_scale", _mission.get("ai_tick_scale") as float)
	_build_panel()

## Reload of a saved mission: rewind the clock and the checkmarks to where
## the save left them — waves already fired stay fired (their survivors were
## restored as regular units), pending ones keep their schedule.
func _apply_restored_state(restored: Dictionary) -> void:
	if restored.is_empty():
		return
	_elapsed = restored.get("elapsed", 0.0) as float
	if _survive_left > 0.0:
		_survive_left = restored.get("survive_left", _survive_left) as float
	var waves_left: Array = []
	for wave: Variant in _pending_waves:
		if ((wave as Dictionary)["at_sec"] as float) > _elapsed:
			waves_left.append(wave)
	_pending_waves = waves_left
	var saved_objectives: Array = restored.get("objectives", []) as Array
	for i: int in range(mini(saved_objectives.size(), _objectives.size())):
		var saved: Dictionary = saved_objectives[i] as Dictionary
		var obj: Dictionary = _objectives[i] as Dictionary
		obj["progress"] = saved.get("progress", 0) as int
		obj["done"] = saved.get("done", false) as bool

## Missions whose pressure is authored (scripted waves) muzzle the AI's own
## attack launcher — it still builds, defends and retaliates.
func _hold_ai_offense() -> void:
	_set_ai_flag("offense_held")

func _set_ai_flag(flag: String) -> void:
	_set_ai_value(flag, true)

func _set_ai_value(prop: String, value: Variant) -> void:
	for child: Node in (_world as Node).get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path.contains("ai_player"):
			child.set(prop, value)

func _process(delta: float) -> void:
	if _finished or GameManager.state != GameManager.GameState.PLAYING:
		return
	_elapsed += delta
	while not _pending_waves.is_empty() \
			and _elapsed >= ((_pending_waves[0] as Dictionary)["at_sec"] as float):
		_spawn_wave(_pending_waves.pop_front() as Dictionary)
	if _survive_left > 0.0:
		_survive_left -= delta
		if is_instance_valid(_survive_label):
			var secs: int = maxi(int(ceil(_survive_left)), 0)
			_survive_label.text = "%s  %02d:%02d" % [
				tr("CAMP_HUD_SURVIVE"), secs / 60, secs % 60]
		if _survive_left <= 0.0:
			_finished = true
			GameManager.declare_winner(0)

# ── Scripted waves ───────────────────────────────────────────────────────────

## Spawns at the FIRST rival TC (falls back to the map edge across from the
## player) and attack-moves the player's base — no AI brain required.
func _spawn_wave(wave: Dictionary) -> void:
	var target: Vector2 = Vector2.ZERO
	if is_instance_valid(_world.drop_off):
		target = (_world.drop_off as Node2D).global_position
	var origin: Vector2 = Vector2(600.0, 0.0)
	if target != Vector2.ZERO:
		origin = -target.normalized() * 400.0
	var tcs: Dictionary = _world.get("_ai_town_centers") as Dictionary
	for pid: Variant in tcs:
		if is_instance_valid(tcs[pid]):
			origin = (tcs[pid] as Node2D).global_position
			break
	var civ: String = MatchConfig.get_rival_civ_id(1)
	var spawned: int = 0
	var units: Dictionary = wave.get("units", {}) as Dictionary
	for unit_class: String in units:
		var scene: PackedScene = load(WAVE_SCENE_DIR + (WAVE_SCENES.get(unit_class, "militia.tscn") as String)) as PackedScene
		for _i: int in range(units[unit_class] as int):
			var unit: CharacterBody2D = scene.instantiate() as CharacterBody2D
			unit.set("player_id", 1)
			unit.set("civ_id", civ)
			(_world.get("units_layer") as Node).add_child(unit)
			var jitter: Vector2 = Vector2(MatchRng.randf_range(-70.0, 70.0),
				MatchRng.randf_range(-70.0, 70.0))
			unit.global_position = TerrainManager.nearest_passable(origin + jitter, civ)
			PopulationManager.add_unit(1)
			EventBus.unit_spawned.emit(unit, 1)
			if unit.has_method("order_attack_move"):
				unit.call("order_attack_move", target)
			spawned += 1
	if spawned > 0:
		_toast(tr("CAMP_HUD_WAVE"))

# ── Objectives ───────────────────────────────────────────────────────────────

func _on_unit_spawned(unit: Node, pid: int) -> void:
	if pid != 0:
		return
	_bump_objectives("train", _class_of(unit))

func _on_animal_herded(animal: Node, pid: int) -> void:
	if pid != 0:
		return
	_bump_objectives("herd", _class_of(animal))

func _on_building_complete(building: Node) -> void:
	var pid: Variant = building.get("player_id")
	if pid == null or (pid as int) != 0:
		return
	_bump_objectives("build", _class_of(building))

func _on_building_destroyed(building: Node, owner_id: int) -> void:
	if owner_id == 0:
		return
	_bump_objectives("destroy", _class_of(building))

func _bump_objectives(kind: String, cls: String) -> void:
	if cls.is_empty():
		return
	var changed: bool = false
	for obj: Variant in _objectives:
		var o: Dictionary = obj as Dictionary
		if o["done"] as bool or (o["type"] as String) != kind:
			continue
		var wanted: String = str(o.get("unit", o.get("building", "")))
		if wanted != cls:
			continue
		o["progress"] = (o["progress"] as int) + 1
		if (o["progress"] as int) >= (o.get("count", 1) as int):
			o["done"] = true
			_toast(tr("CAMP_HUD_OBJECTIVE_DONE"))
		changed = true
	if changed:
		_refresh_panel()

func _class_of(node: Node) -> String:
	var script: Script = node.get_script() as Script
	while script != null:
		var named: StringName = script.get_global_name()
		if named != &"":
			return String(named)
		script = script.get_base_script()
	return ""

# ── Completion ───────────────────────────────────────────────────────────────

func _on_game_over(winner_id: int) -> void:
	if winner_id == 0:
		CampaignManager.mark_completed(_mission_index)
		_show_outro()

## Victory epilogue: the mission's closing story beat, shown as a panel above
## the game-over overlay. Dismissing it reveals the normal end screen — the
## arc gets its connective tissue without touching the game-over flow.
func _show_outro() -> void:
	var key: String = _mission.get("outro_key", "") as String
	if key.is_empty() or _world == null:
		return
	var hud_root: Node = (_world.get("hud") as Node).get_node_or_null("HUDRoot")
	if hud_root == null:
		return
	var veil: Control = Control.new()
	veil.name = "MissionOutro"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.09, 0.10, 0.13, 0.96)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	veil.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = tr(_mission.get("title_key", "") as String)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", HudStyle.bold_font())
	title.add_theme_font_size_override("font_size", 20)
	HudStyle.add_text_outline(title)
	box.add_child(title)
	var body: Label = Label.new()
	body.text = tr(key)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(540, 0)
	HudStyle.add_text_outline(body)
	box.add_child(body)
	var btn: Button = Button.new()
	btn.text = tr("CAMP_CONTINUE")
	btn.custom_minimum_size = Vector2(160, 36)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(veil.queue_free)
	box.add_child(btn)
	hud_root.add_child(veil)
	# Centering must run after the panel measures its wrapped text.
	panel.reset_size.call_deferred()
	panel.set_anchors_preset.call_deferred(Control.PRESET_CENTER)

# ── HUD panel ────────────────────────────────────────────────────────────────

func _build_panel() -> void:
	var hud_root: Node = (_world.get("hud") as Node).get_node_or_null("HUDRoot")
	if hud_root == null:
		return
	_panel = VBoxContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 12.0
	_panel.offset_top = 64.0
	_panel.add_theme_constant_override("separation", 2)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_panel)
	var title: Label = _make_line(tr(_mission.get("title_key", "") as String))
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	title.add_theme_font_size_override("font_size", 17)
	if _survive_left > 0.0:
		_survive_label = _make_line("")
		_survive_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
	for obj: Variant in _objectives:
		_objective_labels.append(_make_line(""))
	_refresh_panel()

func _make_line(text: String) -> Label:
	var line: Label = Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", 14)
	line.add_theme_constant_override("outline_size", 4)
	line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(line)
	return line

func _refresh_panel() -> void:
	for i: int in range(_objectives.size()):
		if i >= _objective_labels.size() or not is_instance_valid(_objective_labels[i]):
			continue
		var o: Dictionary = _objectives[i] as Dictionary
		var count: int = o.get("count", 1) as int
		var progress: String = "" if count <= 1 else "  %d/%d" % [
			mini(o["progress"] as int, count), count]
		var done: bool = o["done"] as bool
		(_objective_labels[i] as Label).text = "%s %s%s" % [
			"☑" if done else "☐", tr(o["key"] as String), progress]
		(_objective_labels[i] as Label).add_theme_color_override("font_color",
			Color(0.55, 0.90, 0.55) if done else Color(0.85, 0.85, 0.88))

func _toast(text: String) -> void:
	if _world == null:
		return
	var hud_root: Node = (_world.get("hud") as Node).get_node_or_null("HUDRoot")
	if hud_root == null:
		return
	for child: Node in hud_root.get_children():
		if child is NotificationDisplay:
			(child as NotificationDisplay).push(text, Color(0.95, 0.85, 0.45))
			return

## Testing hooks.
func objectives() -> Array:
	return _objectives

func survive_left() -> float:
	return _survive_left

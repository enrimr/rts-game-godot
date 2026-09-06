extends CanvasLayer

## HUD coordinator: owns the selection info panel (name/HP/status/portraits/
## stat chips), the train-queue row, the detail-panel progress bars and the
## composition of every Hud* component. The command grid and all per-selection
## button layouts live in HudActionMenu; the tutorial in HudTutorial; action
## tables and cost resolution in HudActionDefs.

signal action_requested(action_id: String)
signal follow_requested()
## Emitted for actions that require a follow-up map click (move_to, attack_move).
signal pending_action_started(action_id: String)
signal pending_action_cancelled()

@export var local_player_id: int = 0

@onready var _food_display: ResourceDisplay = %FoodDisplay
@onready var _wood_display: ResourceDisplay = %WoodDisplay
@onready var _gold_display: ResourceDisplay = %GoldDisplay
@onready var _stone_display: ResourceDisplay = %StoneDisplay
@onready var _population_label: Label = %PopulationDisplay
@onready var _age_label: Label = %AgeDisplay
@onready var _clock_label: Label = %GameClock
@onready var _unit_portraits_grid: GridContainer = %UnitPortraitsGrid
@onready var _unit_name_label: Label = %UnitNameLabel
@onready var _unit_hp_bar: ProgressBar = %UnitHPBar
@onready var _unit_status_label: Label = %UnitStatusLabel
@onready var _action_grid: GridContainer = %ActionButtonsGrid
@onready var _train_queue_row: HBoxContainer = %TrainQueueRow
@onready var _pause_overlay: ColorRect = %PauseOverlay

var _selected_building: Node = null
var _selected_unit: Node = null   # tracked for transport garrison refresh
var _hp_bar_unit: Node = null     # unit/building whose HP drives the main HP bar
var _hp_bar_max: float = 100.0    # cached max HP for the current hp_bar_unit
var _hp_text: Label = null        # numeric "450 / 550" overlay on the HP bar
var _status_unit: Node = null
var _follow_btn: Button = null
var _following: bool = false
var _age_advance_bar: ProgressBar = null
var _hero_respawn_bar: ProgressBar = null
var _hero_respawn_label: Label = null
var _research_bar: ProgressBar = null
var _research_label: Label = null
var _menus: HudMenus = null
var _controls: HudControls = null
var _wonder_label: Label = null
var _hero_alert_overlay: ColorRect = null
var _weather: HudWeather = null
var _match_stats: HudMatchStats = null
var _resource_bar: HudResourceBar = null
var _hero_widget: HudHeroWidget = null
var _tutorial: HudTutorial = null
var _menu: HudActionMenu = null
var _detail_panel: VBoxContainer = null
var _stats_row: HBoxContainer = null    # compact stat chips for a single-selected unit
var _stats_unit: Node = null
var _stat_labels: Dictionary = {}       # stat id -> Label inside _stats_row
var _carry_chip: HBoxContainer = null
var _carry_icon: TextureRect = null
var _stats_timer: float = 0.0

const DETAIL_PANEL_PATH: String = "HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow/UnitDetailPanel"
const STATS_REFRESH_INTERVAL: float = 0.5

func _ready() -> void:
	local_player_id = NetworkSession.local_player_id
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.train_queue_changed.connect(_on_train_queue_changed)
	EventBus.resource_node_selected.connect(_on_resource_node_selected)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	EventBus.age_advance_started.connect(_on_age_advance_started)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_paused.connect(toggle_pause)
	EventBus.camera_follow_cancelled.connect(func() -> void: _set_follow_active(false))
	EventBus.hero_respawned.connect(_on_hero_respawned)
	EventBus.hero_low_hp.connect(_on_hero_low_hp)
	EventBus.garrison_changed.connect(_on_garrison_changed)
	EventBus.research_state_changed.connect(_on_research_state_changed)
	EventBus.building_construction_complete.connect(_on_building_construction_complete)
	_pause_overlay.visible = false
	_clock_label.text = "00:00"
	_unit_name_label.text = ""
	_unit_hp_bar.value = 0.0
	_resource_bar = HudResourceBar.new()
	_resource_bar.init(local_player_id, _food_display, _wood_display, _gold_display,
		_stone_display, _population_label, _age_label)
	add_child(_resource_bar)
	_controls = HudControls.new()
	_controls.init(local_player_id, get_node("HUDRoot"))
	add_child(_controls)
	_hero_widget = HudHeroWidget.new()
	_hero_widget.init(local_player_id, get_node("HUDRoot"))
	add_child(_hero_widget)
	var control_groups: HudControlGroups = HudControlGroups.new()
	control_groups.init(local_player_id, get_node("HUDRoot"))
	add_child(control_groups)
	_tutorial = HudTutorial.new()
	_tutorial.init(self)
	add_child(_tutorial)
	_menu = HudActionMenu.new()
	_menu.init(self, _tutorial, _action_grid, _train_queue_row,
		_unit_status_label, _unit_portraits_grid)
	add_child(_menu)
	_menus = HudMenus.new()
	_menus.init(
		_tutorial.start,
		_tutorial.overlay_active,
		func(visible: bool) -> void: _controls.set_dpad_visible(visible))
	add_child(_menus)
	_detail_panel = get_node_or_null(DETAIL_PANEL_PATH) as VBoxContainer
	_build_follow_button()
	_build_notifications()
	_build_pause_menu_button()
	_weather = HudWeather.new()
	add_child(_weather)
	_match_stats = HudMatchStats.new()
	_match_stats.init(local_player_id, _clock_label, get_node("HUDRoot"))
	add_child(_match_stats)
	var fps_counter: HudFpsCounter = HudFpsCounter.new()
	fps_counter.init(get_node("HUDRoot"))
	add_child(fps_counter)
	var minimap_node: Control = get_node_or_null("%Minimap") as Control
	if minimap_node != null:
		var players_panel: HudPlayersPanel = HudPlayersPanel.new()
		minimap_node.add_child(players_panel)
	if NetworkSession.is_online():
		var chat: HudChat = HudChat.new()
		chat.init(get_node("HUDRoot"))
		add_child(chat)
	_style_command_bar()

func _style_command_bar() -> void:
	var bottom_bar: PanelContainer = get_node_or_null("HUDRoot/BottomBar") as PanelContainer
	if bottom_bar != null:
		bottom_bar.add_theme_stylebox_override("panel", HudStyle.command_bar())
		HudStyle.add_top_sheen(bottom_bar)
	var selection_panel: Panel = get_node_or_null(
		"HUDRoot/BottomBar/BottomLayout/SelectionPanel") as Panel
	if selection_panel != null:
		selection_panel.add_theme_stylebox_override("panel", HudStyle.command_well())

func _process(delta: float) -> void:
	if is_instance_valid(_status_unit):
		_unit_status_label.text = _get_unit_status(_status_unit)
	_stats_timer += delta
	if _stats_timer >= STATS_REFRESH_INTERVAL:
		_stats_timer = 0.0
		_refresh_stats_row()
	_poll_hp_bars()
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.value = AgeManager.get_advance_progress(local_player_id) * 100.0
	_update_train_queue_progress()
	if is_instance_valid(_research_bar) and is_instance_valid(_selected_building):
		_research_bar.value = TechManager.get_research_progress(_selected_building) * 100.0
		if TechManager.get_researching_tech(_selected_building) == null:
			if is_instance_valid(_research_bar):
				_research_bar.queue_free()
				_research_bar = null
			if is_instance_valid(_research_label):
				_research_label.queue_free()
				_research_label = null
	if is_instance_valid(_hero_respawn_bar) and is_instance_valid(_selected_building):
		var tc: Variant = _selected_building
		if tc.has_method("get_hero_respawn_fraction"):
			_hero_respawn_bar.value = (tc.get_hero_respawn_fraction() as float) * 100.0
			var secs: int = tc.get_hero_respawn_remaining() as int
			if is_instance_valid(_hero_respawn_label):
				_hero_respawn_label.text = tr("UI_HERO_RESPAWNING") % secs if secs > 0 else tr("UI_HERO_READY")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		if _menus.is_pause_open():
			_menus.close_pause_menu()
		else:
			_menus.open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _menu.handle_hotkey(key):
		get_viewport().set_input_as_handled()

func update_resources(player_id: int, resources: Dictionary) -> void:
	_resource_bar.update_resources(player_id, resources)

## queue_free'd children still occupy container layout for the rest of the
## frame; detach first so stale rows can never inflate the band's minimum size.
func _free_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func update_selection(units: Array) -> void:
	cancel_pending()
	_free_children(_unit_portraits_grid)
	_menu.clear()
	_clear_stats_row()

	if units.is_empty():
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		_unit_status_label.text = ""
		_status_unit = null
		_hp_bar_unit = null
		return

	var capped: Array = units.slice(0, 40)
	var compact: bool = capped.size() > 10
	_unit_portraits_grid.columns = 20 if compact else 10
	for unit: Variant in capped:
		if not is_instance_valid(unit):
			continue
		var portrait: UnitPortrait = UnitPortrait.new()
		portrait.compact = compact
		_unit_portraits_grid.add_child(portrait)
		portrait.setup(unit)

	var first: Node = capped[0]
	if is_instance_valid(first):
		var display_name: String = tr("UI_UNIT")
		var unit_data: Variant = first.get("unit_data")
		if unit_data != null:
			var name_val: String = EntityNames.unit_name(unit_data as Resource)
			if not name_val.is_empty():
				display_name = name_val
		elif first is Animal:
			var aname: Variant = first.get("animal_name")
			display_name = aname as String if aname != null else tr("UI_ANIMAL")
		_unit_name_label.text = display_name

		var hp_variant: Variant = first.get("health")
		var hp: float = hp_variant as float if hp_variant != null else 100.0
		var max_hp: float = 100.0
		if unit_data != null:
			var max_hp_v: Variant = (unit_data as Resource).get("max_health")
			if max_hp_v != null:
				max_hp = max_hp_v as float
		elif first is Animal:
			var mhp: Variant = first.get("max_health")
			if mhp != null:
				max_hp = mhp as float
		if max_hp > 0.0:
			_unit_hp_bar.value = (hp / max_hp) * 100.0
			_hp_bar_unit = first
			_hp_bar_max = max_hp

		_status_unit = first if (first.has_method("order_gather") or first is FishingBoat) else null

		if first is Animal:
			var astate: Variant = first.get("current_state")
			var owned: bool = astate != null and (astate as int) == Animal.AnimalState.OWNED
			_unit_status_label.text = tr("UI_STATUS_YOURS") if owned else tr("UI_STATUS_WILD")
		_menu.populate_for_unit(first)

		if capped.size() == 1 and unit_data != null:
			_build_stats_row(first)

func update_age(age: int) -> void:
	_resource_bar.update_age(age)

func toggle_pause(is_paused: bool) -> void:
	_pause_overlay.visible = is_paused

func cancel_pending() -> void:
	_menu.cancel_pending()

## HudTutorial's step/finish hook — the menu repaints whatever panel is open.
func refresh_after_tutorial_change() -> void:
	_menu.refresh_after_tutorial_change()

func _on_game_started() -> void:
	IconBaker.clear_cache()   # civ picks can change between matches
	_controls.set_game_speed(1)
	update_age(AgeManager.get_age(local_player_id))
	var starting: Dictionary = ResourceManager.get_resources(local_player_id)
	update_resources(local_player_id, starting)
	if MatchConfig.launch_tutorial:
		MatchConfig.launch_tutorial = false
		_tutorial.start.call_deferred()

func _on_unit_selected(units: Array) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null
	_selected_unit = units[0] if units.size() == 1 else null
	_set_follow_active(false)
	update_selection(units)
	if is_instance_valid(_follow_btn):
		_follow_btn.visible = not units.is_empty()
	if not units.is_empty():
		var lead: Node = units[0] as Node
		var sound: String = "select_generic"
		if lead.has_method("get_selection_sound"):
			sound = lead.call("get_selection_sound") as String
		AudioManager.play_voice(sound, lead.get("is_female") == true,
			str(lead.get("civ_id")) if lead.get("civ_id") != null else "", -4.0)

func _on_building_selected(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = building
	if is_instance_valid(building) and building.has_method("set_selected"):
		building.set_selected(true)
	_set_follow_active(false)
	if is_instance_valid(_follow_btn):
		_follow_btn.visible = false
	_free_children(_unit_portraits_grid)
	_menu.clear()
	_clear_stats_row()

	_status_unit = null
	_hp_bar_unit = null
	if not is_instance_valid(building):
		_unit_name_label.text = ""
		_unit_hp_bar.value = 0.0
		_unit_status_label.text = ""
		return

	var display_name: String = tr("UI_BUILDING")
	var bdata: Variant = building.get("building_data")
	if bdata != null:
		var dname: String = EntityNames.building_name(bdata as Resource)
		if not dname.is_empty():
			display_name = dname
	_unit_name_label.text = display_name

	var hp_v: Variant = building.get("health")
	var hp: float = hp_v as float if hp_v != null else 0.0
	var max_hp: float = 0.0
	if bdata != null:
		var mhp_v: Variant = (bdata as Resource).get("max_health")
		if mhp_v != null:
			max_hp = mhp_v as float
	if max_hp <= 0.0:
		var mhp_direct: Variant = building.get("max_health")
		if mhp_direct != null:
			max_hp = mhp_direct as float
	if max_hp > 0.0:
		_unit_hp_bar.value = (hp / max_hp) * 100.0
		_hp_bar_unit = building
		_hp_bar_max = max_hp

	var bpid: Variant = building.get("player_id")
	if bpid != null and (bpid as int) != local_player_id:
		return

	var bstate: Variant = building.get("state")
	if bstate != null and (bstate as int) != BuildingBase.BuildingState.COMPLETE:
		_menu.populate([HudActionDefs.DESTROY_BUILDING_ACTION])
		return

	if building.has_method("is_respawning_hero") or building is TownCenterBuildable:
		_unit_name_label.text = tr("UI_TOWN_CENTER")
		var tc_hp: Variant = building.get("health")
		var tc_max: Variant = building.get("max_health")
		if tc_hp != null and tc_max != null and (tc_max as float) > 0.0:
			_unit_hp_bar.value = ((tc_hp as float) / (tc_max as float)) * 100.0
			_hp_bar_unit = building
			_hp_bar_max = tc_max as float

	_menu.populate_for_building(building)
	if building.has_method("get_queue"):
		_on_train_queue_changed(building, building.get_queue() as Array,
			building.get_max_queue() as int)
	_menu.append_garrison_ui(building)
	_refresh_research_slot()
	_append_group_count()

## "Cuartel  ×4" when a double click selected the whole building type: the
## panel shows the primary, the suffix says how many share the orders.
func _append_group_count() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var group: Variant = world.get("_selected_buildings")
	if group is Array and (group as Array).size() > 1:
		_unit_name_label.text += "  ×%d" % (group as Array).size()

func _on_population_changed(player_id: int, _current: int, _cap: int) -> void:
	# HudResourceBar updates the population label; the action menu refreshes the
	# train queue so the pop-blocked indicator updates when population frees up.
	if player_id != local_player_id:
		return
	if is_instance_valid(_selected_building) and _selected_building.has_method("get_queue"):
		_on_train_queue_changed(_selected_building,
			_selected_building.get_queue() as Array,
			_selected_building.get_max_queue() as int)

func _on_age_advance_started(player_id: int, _target_age: int) -> void:
	if player_id != local_player_id:
		return
	# If a building is selected, refresh so the advance button becomes the bar.
	_menu.repopulate_selected_building()

func _on_age_advance_complete(player_id: int, _new_age: int) -> void:
	# HudResourceBar updates the age label; HudActionMenu refreshes the newly
	# unlocked build/train options — here only the progress bar goes away.
	if player_id != local_player_id:
		return
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.queue_free()
		_age_advance_bar = null

func _on_garrison_changed(holder: Node, _current: int, _capacity: int) -> void:
	if is_instance_valid(_selected_unit) and _selected_unit == holder:
		_menu.populate_transport_buttons(holder as TransportShip)
	elif is_instance_valid(_selected_building) and _selected_building == holder:
		_on_building_selected(holder)

# ── Detail-panel progress bars (built on demand, freed on selection change) ──

func _clear_panel_bars() -> void:
	if is_instance_valid(_age_advance_bar):
		_age_advance_bar.queue_free()
		_age_advance_bar = null
	if is_instance_valid(_hero_respawn_bar):
		_hero_respawn_bar.queue_free()
		_hero_respawn_bar = null
	if is_instance_valid(_hero_respawn_label):
		_hero_respawn_label.queue_free()
		_hero_respawn_label = null
	if is_instance_valid(_research_bar):
		_research_bar.queue_free()
		_research_bar = null
	if is_instance_valid(_research_label):
		_research_label.queue_free()
		_research_label = null

func _build_age_advance_bar() -> void:
	if is_instance_valid(_age_advance_bar) or _detail_panel == null:
		return
	_age_advance_bar = ProgressBar.new()
	_age_advance_bar.min_value = 0.0
	_age_advance_bar.max_value = 100.0
	_age_advance_bar.value = 0.0
	_age_advance_bar.show_percentage = false
	_age_advance_bar.custom_minimum_size = Vector2(0, 12)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.70, 0.60, 0.15)
	_age_advance_bar.add_theme_stylebox_override("fill", fill)
	_detail_panel.add_child(_age_advance_bar)

func _build_hero_respawn_bar() -> void:
	if is_instance_valid(_hero_respawn_bar) or _detail_panel == null:
		return
	_hero_respawn_label = Label.new()
	_hero_respawn_label.add_theme_font_size_override("font_size", 15)
	_hero_respawn_label.add_theme_color_override("font_color", Color(0.90, 0.75, 0.25))
	_hero_respawn_label.text = ""
	_detail_panel.add_child(_hero_respawn_label)
	_hero_respawn_bar = ProgressBar.new()
	_hero_respawn_bar.min_value = 0.0
	_hero_respawn_bar.max_value = 100.0
	_hero_respawn_bar.value = 0.0
	_hero_respawn_bar.show_percentage = false
	_hero_respawn_bar.custom_minimum_size = Vector2(0, 12)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.55, 0.10)
	_hero_respawn_bar.add_theme_stylebox_override("fill", fill)
	_detail_panel.add_child(_hero_respawn_bar)

func _build_research_bar(building: Node) -> void:
	if not is_instance_valid(building) or _detail_panel == null:
		return
	var tech: TechnologyResource = TechManager.get_researching_tech(building)
	if tech == null:
		return
	if not is_instance_valid(_research_label):
		_research_label = Label.new()
		_research_label.add_theme_font_size_override("font_size", 15)
		_research_label.add_theme_color_override("font_color", Color(0.55, 0.80, 0.90))
		_detail_panel.add_child(_research_label)
	var research_name: String = EntityNames.tech_name(tech)
	_research_label.text = tr("UI_RESEARCHING") % research_name \
		if tr("UI_RESEARCHING") != "UI_RESEARCHING" else ("Researching: " + research_name)
	if not is_instance_valid(_research_bar):
		_research_bar = ProgressBar.new()
		_research_bar.min_value = 0.0
		_research_bar.max_value = 100.0
		_research_bar.value = 0.0
		_research_bar.show_percentage = false
		_research_bar.custom_minimum_size = Vector2(0, 12)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color(0.25, 0.55, 0.75)
		_research_bar.add_theme_stylebox_override("fill", fill)
		_detail_panel.add_child(_research_bar)

## Live refresh: starting/finishing/cancelling research rebuilds the selected
## building's panel — before this, the "Researching…" bar and the queue slot
## only appeared when the building was re-selected.
func _on_research_state_changed(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building == building:
		_on_building_selected(building)

# ── Train-queue row (unit slots + research slots) ─────────────────────────────

func _on_cancel_train_slot(index: int) -> void:
	if MatchConfig.is_replay():
		return   # recorded history — the queue is a mirror, nothing to cancel
	if not is_instance_valid(_selected_building):
		return
	if _selected_building.has_method("order_cancel_train"):
		CommandBus.submit(ProductionCommand.make(0, "cancel_train",
			EntityRegistry.id_of(_selected_building), "", index))

## How many entries of each unit_id a training queue holds — pure, tested.
static func queued_per_unit(queue: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Variant in queue:
		var uid: String = (entry as Dictionary).get("unit_id", "") as String
		counts[uid] = (counts.get(uid, 0) as int) + 1
	return counts

func _on_train_queue_changed(building: Node, queue: Array, max_queue: int) -> void:
	if building != _selected_building:
		return
	# Per-unit-type queue badge: a building that trains several unit types
	# (Barracks, Stable, Dock…) must show each button ITS OWN queued count —
	# the old total-size badge incremented every train button at once.
	var counts: Dictionary = queued_per_unit(queue)
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var aid: String = btn.action_id
		if not aid.begins_with("train:"):
			continue
		btn.set_train_queue_badge(
			counts.get(aid.trim_prefix("train:"), 0) as int, max_queue)
	_menu.refresh_button_states()
	# Rebuild the visual queue row
	for slot: Node in _train_queue_row.get_children():
		slot.queue_free()
	var pop_blocked: bool = not queue.is_empty() and PopulationManager.at_cap(local_player_id)
	for i: int in range(queue.size()):
		var entry: Dictionary = queue[i] as Dictionary
		var slot: TrainQueueSlot = TrainQueueSlot.new()
		_train_queue_row.add_child(slot)
		# Queue slots show the entity's baked icon (like the selection
		# portraits); entries without a scene fall back to the letter.
		var scene_path: String = entry.get("scene", "") as String
		var icon: Texture2D = IconBaker.get_icon(scene_path, local_player_id) \
			if not scene_path.is_empty() else null
		slot.setup(i, entry["label"] as String, entry["color"] as Color,
			i == 0, i == 0 and pop_blocked, icon)
		slot.cancel_requested.connect(_on_cancel_train_slot)
	_refresh_research_slot()

## Research shows in the SAME queue row as unit training, as a slot with a
## progress veil and a cancel button (full refund), so the building's "what is
## it making" reads identically for units and technologies.
func _refresh_research_slot() -> void:
	if not is_instance_valid(_train_queue_row):
		return
	for child: Node in _train_queue_row.get_children():
		if (child.name as String).begins_with("ResearchSlot"):
			child.name = String(child.name) + "Freeing"   # frees end-of-frame; keep names free
			child.queue_free()
	if not is_instance_valid(_selected_building):
		return
	var tech: TechnologyResource = TechManager.get_researching_tech(_selected_building)
	if tech == null:
		return
	var slot: TrainQueueSlot = _make_research_slot(tech, "ResearchSlot")
	slot.set_progress(TechManager.get_research_progress(_selected_building))
	slot.cancel_requested.connect(func(_idx: int) -> void:
		if not MatchConfig.is_replay() and is_instance_valid(_selected_building):
			CommandBus.submit(ProductionCommand.make(0, "cancel_research",
				EntityRegistry.id_of(_selected_building))))
	# Queued techs line up behind the active one, exactly like queued units:
	# each with its own cancel (full refund at the slot).
	var queue: Array = TechManager.get_research_queue(_selected_building)
	for qi: int in range(queue.size()):
		var queued: TechnologyResource = TechManager._all_techs.get(queue[qi]) as TechnologyResource
		if queued == null:
			continue
		var qslot: TrainQueueSlot = _make_research_slot(queued, "ResearchSlotQ%d" % qi)
		qslot.set_progress(0.0)
		var captured: int = qi
		qslot.cancel_requested.connect(func(_idx: int) -> void:
			if not MatchConfig.is_replay() and is_instance_valid(_selected_building):
				CommandBus.submit(ProductionCommand.make(0, "cancel_research_queued",
					EntityRegistry.id_of(_selected_building), "", captured)))

func _make_research_slot(tech: TechnologyResource, slot_name: String) -> TrainQueueSlot:
	var tech_name: String = EntityNames.tech_name(tech)
	var initials: String = ""
	for part: String in tech_name.split(" "):
		if not part.is_empty():
			initials += part[0]
	var slot: TrainQueueSlot = TrainQueueSlot.new()
	slot.name = slot_name
	_train_queue_row.add_child(slot)
	slot.setup(0, initials.left(2).to_upper(), Color(0.25, 0.55, 0.75), true, false,
		UiIcons.tech_glyph(tech.id))
	slot.tooltip_text = tech_name
	return slot

func _update_train_queue_progress() -> void:
	if not is_instance_valid(_selected_building):
		return
	var research_slot: Node = _train_queue_row.get_node_or_null("ResearchSlot")
	if research_slot is TrainQueueSlot:
		(research_slot as TrainQueueSlot).set_progress(
			TechManager.get_research_progress(_selected_building))
	if not _selected_building.has_method("get_train_progress"):
		return
	var p: float = _selected_building.get_train_progress() as float
	var first_slot: Node = _train_queue_row.get_child(0) if _train_queue_row.get_child_count() > 0 else null
	if first_slot is TrainQueueSlot and first_slot.name != &"ResearchSlot":
		(first_slot as TrainQueueSlot).set_progress(p)

# ── HP bar / unit status / stat chips ─────────────────────────────────────────

func _poll_hp_bars() -> void:
	if _hp_text == null:
		_hp_text = Label.new()
		_hp_text.add_theme_font_size_override("font_size", 10)
		_hp_text.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
		HudStyle.add_text_outline(_hp_text, 3)
		_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_unit_hp_bar.add_child(_hp_text)
		_hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid(_hp_bar_unit) and _hp_bar_max > 0.0:
		var hp_v: Variant = _hp_bar_unit.get("health")
		if hp_v != null:
			_unit_hp_bar.value = (hp_v as float) / _hp_bar_max * 100.0
			# Numbers, not just a bar: on a 1200 HP building a few sword hits
			# move the bar less than a pixel and damage LOOKED like it never
			# landed.
			_hp_text.text = "%d / %d" % [ceili(hp_v as float), roundi(_hp_bar_max)]
	# An empty detail panel otherwise renders a bare "0%" bar.
	_unit_hp_bar.visible = _unit_hp_bar.value > 0.0
	_hp_text.visible = _unit_hp_bar.visible and is_instance_valid(_hp_bar_unit)
	for child: Node in _unit_portraits_grid.get_children():
		if child is UnitPortrait:
			(child as UnitPortrait).refresh()

func _clear_stats_row() -> void:
	_stats_unit = null
	_stat_labels = {}
	_carry_chip = null
	_carry_icon = null
	if is_instance_valid(_stats_row):
		_stats_row.queue_free()
	_stats_row = null

## Compact stat chips (attack / armor m|p / range / speed) for a single-selected
## unit; villagers additionally get a carried-resource chip.
func _build_stats_row(unit: Node) -> void:
	_clear_stats_row()
	if _detail_panel == null or not is_instance_valid(unit):
		return
	var udata: UnitResource = unit.get("unit_data") as UnitResource
	if udata == null:
		return
	_stats_row = HBoxContainer.new()
	_stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_row.add_theme_constant_override("separation", 10)
	for stat: String in ["attack", "armor", "range", "speed"]:
		# Melee reach tops out at 1.5 tiles; only true ranged units get the chip.
		if stat == "range" and udata.attack_range <= 2.0:
			continue
		var chip: HBoxContainer = UiIcons.amount_chip("stat_" + stat, "")
		_stat_labels[stat] = chip.get_child(1) as Label
		_stats_row.add_child(chip)
	if unit.get("carried_resource") != null and unit.get("carried_amount") != null:
		_carry_chip = UiIcons.amount_chip("res_food", "")
		_carry_icon = _carry_chip.get_child(0) as TextureRect
		_stat_labels["carry"] = _carry_chip.get_child(1) as Label
		_carry_chip.visible = false
		_stats_row.add_child(_carry_chip)
	_detail_panel.add_child(_stats_row)
	# Sits right under the name / HP bar / status trio from the scene.
	_detail_panel.move_child(_stats_row, 3)
	_stats_unit = unit
	_refresh_stats_row()

func _refresh_stats_row() -> void:
	if not is_instance_valid(_stats_row) or not is_instance_valid(_stats_unit):
		return
	var udata: UnitResource = _stats_unit.get("unit_data") as UnitResource
	if udata == null:
		return
	var pid_v: Variant = _stats_unit.get("player_id")
	var pid: int = pid_v as int if pid_v != null else 0
	var uid: String = udata.id
	if _stat_labels.has("attack"):
		var atk: float = udata.attack * CivBonusManager.get_unit_attack_multiplier(pid, uid)
		(_stat_labels["attack"] as Label).text = str(int(roundf(atk)))
	if _stat_labels.has("armor"):
		var armor_m: float = udata.armor_melee + CivBonusManager.get_unit_armor_bonus(pid)
		var armor_p: float = udata.armor_pierce + CivBonusManager.get_archer_armor_pierce_bonus(pid)
		(_stat_labels["armor"] as Label).text = "%d/%d" % [int(armor_m), int(armor_p)]
	if _stat_labels.has("range"):
		var rng: float = udata.attack_range * CivBonusManager.get_archer_range_multiplier(pid) \
			+ CivBonusManager.get_archer_range_flat(pid)
		(_stat_labels["range"] as Label).text = str(int(roundf(rng)))
	if _stat_labels.has("speed"):
		var spd: float = udata.move_speed * CivBonusManager.get_unit_speed_multiplier(pid, uid) \
			* CivBonusManager.get_unit_move_speed_multiplier(pid)
		(_stat_labels["speed"] as Label).text = "%.0f" % spd
	if _stat_labels.has("carry") and is_instance_valid(_carry_chip):
		var res: String = _stats_unit.get("carried_resource") as String
		var amount: float = _stats_unit.get("carried_amount") as float
		if res.is_empty() or amount <= 0.0:
			_carry_chip.visible = false
		else:
			if UiIcons.has_glyph("res_" + res):
				_carry_icon.texture = UiIcons.get_icon("res_" + res)
			(_stat_labels["carry"] as Label).text = str(int(amount))
			_carry_chip.visible = true

func _get_unit_status(unit: Node) -> String:
	var state_v: Variant = unit.get("current_state")
	if state_v == null:
		return ""
	var state: int = state_v as int
	match state:
		1: # MOVING
			return tr("UI_STATUS_MOVING")
		2: # ATTACKING
			return tr("UI_STATUS_ATTACKING")
		3: # GATHERING
			if unit is FishingBoat:
				var fb: FishingBoat = unit as FishingBoat
				return tr("UI_STATUS_GATHERING_RES") % ["Fish", int(fb.carried_amount), int(FishingBoat.CARRY_CAPACITY)]
			var resource: Variant = unit.get("carried_resource")
			var amount: Variant = unit.get("carried_amount")
			if resource != null and amount != null:
				var r: String = resource as String
				var a: float = amount as float
				if r.is_empty():
					return tr("UI_STATUS_GATHERING")
				return tr("UI_STATUS_GATHERING_RES") % [r.capitalize(), int(a),
					int((unit.get("carry_capacity") as float) if unit.get("carry_capacity") != null else 10.0)]
			return tr("UI_STATUS_GATHERING")
		4: # RETURNING
			if unit is FishingBoat:
				var fb: FishingBoat = unit as FishingBoat
				return tr("UI_STATUS_RETURNING_RES") % ["Fish", int(fb.carried_amount)]
			var resource: Variant = unit.get("carried_resource")
			var amount: Variant = unit.get("carried_amount")
			if resource != null and amount != null:
				return tr("UI_STATUS_RETURNING_RES") % [(resource as String).capitalize(), int(amount as float)]
			return tr("UI_STATUS_RETURNING")
		5: # BUILDING
			return tr("UI_STATUS_BUILDING")
		6: # DEAD
			return tr("UI_STATUS_DEAD")
	return ""

# ── Hero alerts ───────────────────────────────────────────────────────────────

func _on_hero_low_hp(player_id: int) -> void:
	if player_id != local_player_id:
		return
	_flash_hero_alert()

func _flash_hero_alert() -> void:
	if not is_instance_valid(_hero_alert_overlay):
		_hero_alert_overlay = ColorRect.new()
		_hero_alert_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hero_alert_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hero_alert_overlay.color = Color(0.85, 0.0, 0.0, 0.0)
		_hero_alert_overlay.z_index = 100
		get_node("HUDRoot").add_child(_hero_alert_overlay)
	_hero_alert_overlay.color = Color(0.85, 0.0, 0.0, 0.55)
	var tw: Tween = create_tween()
	tw.tween_property(_hero_alert_overlay, "color:a", 0.0, 1.2)

func _on_hero_respawned(_respawn_player_id: int) -> void:
	if is_instance_valid(_hero_respawn_bar):
		_hero_respawn_bar.queue_free()
		_hero_respawn_bar = null
	if is_instance_valid(_hero_respawn_label):
		_hero_respawn_label.queue_free()
		_hero_respawn_label = null

# ── Other selections / lifecycle ─────────────────────────────────────────────

func _on_resource_node_selected(node: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.set_selected(false)
	_selected_building = null
	_status_unit = null
	_free_children(_unit_portraits_grid)
	_menu.clear()
	_clear_stats_row()
	_hp_bar_unit = null
	var rn: ResourceNode = node as ResourceNode
	var res_name: String = rn.get_resource_name().capitalize()
	_unit_name_label.text = res_name
	_unit_hp_bar.value = (rn.remaining_amount / rn.initial_amount) * 100.0
	_unit_status_label.text = "%d / %d" % [int(rn.remaining_amount), int(rn.initial_amount)]

func _on_building_destroyed(building: Node, _player_id: int) -> void:
	if building == _selected_building:
		if is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
			_selected_building.set_selected(false)
		_selected_building = null
		_on_building_selected(null)

func _on_unit_died(unit: Node, _player_id: int) -> void:
	_status_unit = null
	if unit == _hp_bar_unit or unit == _selected_unit:
		update_selection([])
		_selected_unit = null
		_hp_bar_unit = null
		return
	for child: Node in _unit_portraits_grid.get_children():
		if child is UnitPortrait and (child as UnitPortrait).unit_ref == unit:
			update_selection([])
			_selected_unit = null
			_hp_bar_unit = null
			return

func _on_building_construction_complete(building: Node) -> void:
	if is_instance_valid(_selected_building) and _selected_building == building:
		_on_building_selected(building)

func _build_notifications() -> void:
	var nd: NotificationDisplay = NotificationDisplay.new()
	get_node("HUDRoot").add_child(nd)

# ── Follow button ─────────────────────────────────────────────────────────────

func _build_follow_button() -> void:
	var top_row: Node = get_node_or_null("HUDRoot/BottomBar/BottomLayout/SelectionPanel/SelectionVBox/TopRow")
	if top_row == null:
		return
	# Square icon button: binoculars glyph, same command-button chrome as the
	# action grid. The lit frame marks camera-follow as engaged. Sits as its own
	# column right of the detail stack so it costs the band no vertical space.
	_follow_btn = Button.new()
	_follow_btn.focus_mode = Control.FOCUS_NONE
	_follow_btn.visible = false
	_follow_btn.custom_minimum_size = Vector2(38.0, 34.0)
	_follow_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_follow_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_follow_btn.add_child(UiIcons.icon_rect("follow", 4.0))
	_apply_follow_style(false)
	_follow_btn.pressed.connect(_on_follow_pressed)
	top_row.add_child(_follow_btn)

func _on_follow_pressed() -> void:
	_set_follow_active(not _following)
	follow_requested.emit()

func _set_follow_active(active: bool) -> void:
	_following = active
	if not is_instance_valid(_follow_btn):
		return
	_apply_follow_style(active)

func _apply_follow_style(active: bool) -> void:
	var accent: Color = HudStyle.ACCENT_UTILITY
	_follow_btn.add_theme_stylebox_override("normal",
		HudStyle.command_button(accent, "active" if active else "normal"))
	_follow_btn.add_theme_stylebox_override("hover",
		HudStyle.command_button(accent, "active" if active else "hover"))
	_follow_btn.add_theme_stylebox_override("pressed", HudStyle.command_button(accent, "pressed"))
	_follow_btn.tooltip_text = tr("UI_FOLLOWING") if active else tr("UI_FOLLOW_CAMERA")

# ── Corner menu button / wonder timer / weather forwarders ───────────────────

func _build_pause_menu_button() -> void:
	var hud_root: Control = get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(36, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = tr("UI_MENU")
	btn.add_child(UiIcons.icon_rect("menu", 5.0))
	# Anchor to top-right corner
	btn.anchor_left   = 1.0
	btn.anchor_top    = 0.0
	btn.anchor_right  = 1.0
	btn.anchor_bottom = 0.0
	btn.offset_left   = -69.0
	btn.offset_top    =  31.0
	btn.offset_right  = -31.0
	btn.offset_bottom =  67.0
	btn.add_theme_stylebox_override("normal",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "normal"))
	btn.add_theme_stylebox_override("hover",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "hover"))
	btn.add_theme_stylebox_override("pressed",
		HudStyle.command_button(HudStyle.ACCENT_UTILITY, "pressed"))
	btn.pressed.connect(_menus.open_pause_menu)
	hud_root.add_child(btn)

func show_wonder_timer(owner_pid: int) -> void:
	if not is_instance_valid(_wonder_label):
		_wonder_label = Label.new()
		_wonder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wonder_label.add_theme_font_size_override("font_size", 26)
		_wonder_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.20))
		_wonder_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_wonder_label.offset_top = 8.0
		_wonder_label.offset_bottom = 40.0
		add_child(_wonder_label)
	var who: String = tr("WONDER_TIMER_YOU") if GameManager.are_allied(owner_pid, local_player_id) else tr("WONDER_TIMER_ENEMY")
	_wonder_label.text = who + " — 4:00"

func hide_wonder_timer() -> void:
	if is_instance_valid(_wonder_label):
		_wonder_label.queue_free()
		_wonder_label = null

func update_wonder_timer(seconds_left: float) -> void:
	if not is_instance_valid(_wonder_label):
		return
	var mins: int = int(seconds_left) / 60
	var secs: int = int(seconds_left) % 60
	_wonder_label.text = _wonder_label.text.split(" — ")[0] + " — %d:%02d" % [mins, secs]

# Delegated to HudWeather (scripts/ui/hud/hud_weather.gd). Kept as thin
# forwarders for any external caller (game_world.gd) that still references them.

func show_weather(weather_id: String) -> void:
	if is_instance_valid(_weather):
		_weather.show_weather(weather_id)

func hide_weather() -> void:
	if is_instance_valid(_weather):
		_weather.hide_weather()

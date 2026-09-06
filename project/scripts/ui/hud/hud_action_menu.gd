class_name HudActionMenu
extends Node

## The command grid: renders action buttons (with paging), routes presses into
## the HUD's action signals, and owns every per-selection button layout —
## unit orders, the build menu, and one shared production panel for every
## train/research building (buttons read their costs from the .tres data the
## simulation actually charges; see HudActionDefs). The HUD manager keeps the
## selection info panel, queue row and detail-panel bars; this node reaches
## back through `_hud` the same way the world controllers reach GameWorld.

var _hud: CanvasLayer = null          # HudManager (hud.tscn root)
var _tutorial: HudTutorial = null
var _action_grid: GridContainer = null
var _train_queue_row: HBoxContainer = null
var _unit_status_label: Label = null
var _unit_portraits_grid: GridContainer = null

const ACTION_COLS: int = 5
const ACTION_ROWS: int = 2
const PAGE_SIZE: int = ACTION_COLS * ACTION_ROWS  # 10

var _active_actions: Array = []
var _action_page: int = 0
var _page_prev_btn: ActionButton = null
var _page_next_btn: ActionButton = null
var _in_build_menu: bool = false
var _pending_action: String = ""  # action waiting for a map click
var _mercenary_cooldown_refresh_timer: float = 0.0

func init(hud: CanvasLayer, tutorial: HudTutorial, action_grid: GridContainer,
		train_queue_row: HBoxContainer, unit_status_label: Label,
		unit_portraits_grid: GridContainer) -> void:
	_hud = hud
	_tutorial = tutorial
	_action_grid = action_grid
	_train_queue_row = train_queue_row
	_unit_status_label = unit_status_label
	_unit_portraits_grid = unit_portraits_grid
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.technology_researched.connect(_on_technology_researched)
	EventBus.age_advance_complete.connect(_on_age_advance_complete)
	EventBus.market_rate_changed.connect(_on_market_rate_changed)
	EventBus.mercenary_hired.connect(_on_mercenary_hired)

func _pid() -> int:
	return _hud.get("local_player_id") as int

func _selected_building() -> Node:
	return _hud.get("_selected_building") as Node

func _process(delta: float) -> void:
	var building: Node = _selected_building()
	if MatchConfig.player_civ_id == "fenicios" and is_instance_valid(building) \
			and building is Market:
		_mercenary_cooldown_refresh_timer += delta
		if _mercenary_cooldown_refresh_timer >= 1.0:
			_mercenary_cooldown_refresh_timer = 0.0
			populate_market_actions(building as Market)
	_refresh_hero_cooldown_badge()

func _refresh_hero_cooldown_badge() -> void:
	var unit: Node = _hud.get("_selected_unit") as Node
	if not (is_instance_valid(unit) and unit is HeroUnit):
		return
	var hero: HeroUnit = unit as HeroUnit
	var udata: UnitResource = hero.unit_data
	if udata == null or udata.hero_ability_id.is_empty():
		return
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id != "hero_ability":
			continue
		var cd_frac: float = hero.get_cooldown_fraction()
		if cd_frac <= 0.0:
			btn.set_badge("")
			btn.modulate = Color(1.0, 1.0, 1.0)
		else:
			var cd_secs: int = int(udata.hero_ability_cooldown * cd_frac)
			btn.set_badge("%ds" % cd_secs)
			btn.modulate = Color(0.65, 0.65, 0.65)

# ── Grid rendering ────────────────────────────────────────────────────────────

## queue_free'd children still occupy container layout for the rest of the
## frame; detach first so stale rows can never inflate the band's minimum size.
func _free_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func clear() -> void:
	_active_actions = []
	_action_page = 0
	_free_children(_action_grid)
	_free_children(_train_queue_row)
	if is_instance_valid(_page_prev_btn):
		_page_prev_btn.queue_free()
		_page_prev_btn = null
	if is_instance_valid(_page_next_btn):
		_page_next_btn.queue_free()
		_page_next_btn = null
	_hud.call("_clear_panel_bars")

func populate(actions: Array) -> void:
	clear()
	# A replay is recorded history: selection still shows the info panel, but
	# no command can exist — no buttons, no hotkeys (empty _active_actions).
	if MatchConfig.is_replay():
		return
	_active_actions = actions
	_action_grid.columns = ACTION_COLS
	_render_action_page()

func _render_action_page() -> void:
	_free_children(_action_grid)
	if is_instance_valid(_page_prev_btn):
		_page_prev_btn.queue_free()
		_page_prev_btn = null
	if is_instance_valid(_page_next_btn):
		_page_next_btn.queue_free()
		_page_next_btn = null

	var total: int = _active_actions.size()
	var needs_paging: bool = total > PAGE_SIZE
	# Reserve last 2 slots on the last row for pagination buttons when needed
	var slots: int = PAGE_SIZE - (2 if needs_paging else 0)
	var start: int = _action_page * slots
	var page_actions: Array = _active_actions.slice(start, start + slots)

	for entry: Variant in page_actions:
		var data: Dictionary = entry as Dictionary
		var btn: ActionButton = ActionButton.new()
		btn.action_id = data["id"] as String
		var key_int: int = data.get("key", -1) as int
		var key_hint: String = HudActionDefs.key_label(key_int) if key_int > 0 else ""
		var raw: bool = data.get("raw_label", false) as bool
		var translated_label: String = (data["label"] as String) if raw else tr(data["label"] as String)
		var lines: PackedStringArray = translated_label.split("\n")
		var title: String = lines[0].strip_edges()
		var extra: String = " ".join(lines.slice(1)).strip_edges() if lines.size() > 1 else ""
		var cost: Dictionary = data.get("cost", {}) as Dictionary
		btn.set_meta("cost", cost)
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(_pid(), cost)
		var locked: bool = (data.get("locked", false) as bool) \
			or (btn.action_id == "destroy" and _tutorial.gates_active)
		btn.set_meta("locked", locked)
		btn.set_hotkey(key_hint)
		btn.set_accent(HudActionDefs.accent_for_action(btn.action_id))
		# Icon-first button: full name, hotkey, costs and description live here.
		var tooltip: String = title if key_hint.is_empty() else "%s  [%s]" % [title, key_hint]
		# Raw "500F 175W" cost tokens are replaced by the hover cost strip plus a
		# readable plain-text line (accessibility fallback); other extras stay.
		if not extra.is_empty() and not HudActionDefs.is_cost_tokens(extra):
			tooltip += "\n" + extra
		var desc: String = data.get("description", "") as String
		if not desc.is_empty():
			tooltip += "\n" + tr(desc)
		btn.tooltip_text = tooltip
		# Costs render as a glyph row inside the button's own tooltip popup
		# (ActionButton._make_custom_tooltip).
		btn.action_costs = cost
		var icon_scene: String = HudActionDefs.action_icon_scene(btn.action_id)
		var glyph: String = data.get("glyph", HudActionDefs.ACTION_GLYPHS.get(btn.action_id, "")) as String
		if btn.action_id.begins_with("research:"):
			btn.set_glyph(UiIcons.tech_glyph(btn.action_id.trim_prefix("research:")))
		elif not icon_scene.is_empty():
			btn.set_entity_icon(IconBaker.get_icon(icon_scene, _pid()))
		elif not glyph.is_empty():
			btn.set_glyph(UiIcons.get_icon(glyph))
		else:
			btn.set_abbreviation(data.get("abbr", HudActionDefs.abbreviate(title)) as String)
		var badge: String = data.get("badge", "") as String
		if not badge.is_empty():
			btn.set_badge(badge)
		var is_upgrade: bool = data.get("is_upgrade", false) as bool
		btn.set_meta("is_upgrade", is_upgrade)
		btn.set_upgrade(is_upgrade)
		var toggled: bool = data.get("active", false) as bool
		btn.set_meta("toggled", toggled)
		btn.set_active(toggled)
		btn.set_enabled(can_pay and not locked)
		btn.action_pressed.connect(_on_action_button_pressed)
		_action_grid.add_child(btn)

	if needs_paging:
		# Pad so prev/next always land on the last two slots of the grid.
		var filled: int = page_actions.size()
		var spacers_needed: int = slots - filled
		for _i: int in range(maxi(0, spacers_needed)):
			var spacer: Control = Control.new()
			spacer.custom_minimum_size = ActionButton.BTN_SIZE
			_action_grid.add_child(spacer)

		var max_page: int = ceili(float(total) / float(slots)) - 1
		_page_prev_btn = _make_page_btn("page_prev")
		_page_prev_btn.set_enabled(_action_page > 0)
		_page_prev_btn.pressed.connect(func() -> void:
			_action_page = maxi(0, _action_page - 1)
			_render_action_page()
			refresh_button_states())
		_action_grid.add_child(_page_prev_btn)

		_page_next_btn = _make_page_btn("page_next")
		_page_next_btn.set_enabled(_action_page < max_page)
		_page_next_btn.pressed.connect(func() -> void:
			_action_page = mini(_action_page + 1, max_page)
			_render_action_page()
			refresh_button_states())
		_action_grid.add_child(_page_next_btn)
	_refresh_mode_highlights()

func _make_page_btn(glyph: String) -> ActionButton:
	var btn: ActionButton = ActionButton.new()
	btn.set_glyph(UiIcons.get_icon(glyph))
	btn.set_accent(HudStyle.ACCENT_UTILITY)
	btn.tooltip_text = tr("UI_PAGE_PREV") if glyph == "page_prev" else tr("UI_PAGE_NEXT")
	return btn

func _get_queue_size() -> int:
	var building: Node = _selected_building()
	if is_instance_valid(building) and building.has_method("get_queue"):
		return (building.get_queue() as Array).size()
	return 0

func _get_max_queue() -> int:
	var building: Node = _selected_building()
	if is_instance_valid(building) and building.has_method("get_max_queue"):
		return building.get_max_queue() as int
	return 0

func refresh_button_states() -> void:
	var queue_size: int = _get_queue_size()
	var max_queue: int = _get_max_queue()
	var queue_full: bool = max_queue > 0 and queue_size >= max_queue
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn == _page_prev_btn or btn == _page_next_btn:
			continue
		var cost: Dictionary = btn.get_meta("cost", {}) as Dictionary
		var is_train: bool = btn.action_id.begins_with("train:")
		var locked: bool = btn.get_meta("locked", false) as bool
		var can_pay: bool = cost.is_empty() or ResourceManager.can_afford(_pid(), cost)
		btn.set_enabled(can_pay and not locked and (not is_train or not queue_full))

# ── Press routing ─────────────────────────────────────────────────────────────

func _on_action_button_pressed(action_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if child is ActionButton and (child as ActionButton).action_id == action_id:
			var cost: Dictionary = (child as ActionButton).get_meta("cost", {}) as Dictionary
			if not cost.is_empty() and not ResourceManager.can_afford(_pid(), cost):
				AudioManager.play("ui_error")
				return
			break
	if action_id == "build_menu":
		AudioManager.play("ui_click")
		_in_build_menu = true
		populate(_filtered_build_actions())
		return
	if action_id == "back":
		AudioManager.play("ui_click")
		_in_build_menu = false
		populate_villager_actions()
		return
	# Actions that wait for a map click before executing
	if action_id == "move_to" or action_id == "attack_move" or action_id == "cover_fire" \
			or action_id == "garrison_into" or action_id == "patrol":
		AudioManager.play("ui_click")
		_set_pending_action(action_id)
		return
	if action_id.begins_with("train:"):
		AudioManager.play("train_queue")
	elif action_id == "advance_age":
		AudioManager.play("age_advance")
		_disable_action_button("advance_age")
	else:
		AudioManager.play("ui_click")
	_hud.emit_signal("action_requested", action_id)
	# The stance/formation state just changed synchronously during the emit;
	# re-light the toggle frames so the choice is visible immediately.
	if action_id.begins_with("stance:") or action_id.begins_with("formation:"):
		call_deferred("_refresh_mode_highlights")

## Hotkey dispatch from the HUD's _unhandled_input; true when consumed.
func handle_hotkey(key: InputEventKey) -> bool:
	if _active_actions.is_empty():
		return false
	for entry: Variant in _active_actions:
		var data: Dictionary = entry as Dictionary
		var mapped: int = data.get("key", -1) as int
		# macOS keyboards: the big "delete" key is BACKSPACE (KEY_DELETE is
		# fn+delete) — without the alias the destroy hotkey was dead on Mac.
		var is_match: bool = mapped == key.keycode or mapped == key.physical_keycode \
			or (mapped == KEY_DELETE and (key.keycode == KEY_BACKSPACE
				or key.physical_keycode == KEY_BACKSPACE))
		if is_match:
			_on_action_button_pressed(data["id"] as String)
			return true
	return false

func _set_pending_action(action_id: String) -> void:
	_pending_action = action_id
	_highlight_pending_button(action_id)
	_hud.emit_signal("pending_action_started", action_id)

func cancel_pending() -> void:
	if _pending_action.is_empty():
		return
	_pending_action = ""
	_highlight_pending_button("")
	_hud.emit_signal("pending_action_cancelled")

func _disable_action_button(target_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id == target_id:
			btn.set_meta("locked", true)
			btn.set_enabled(false)
			break

## Persistent feedback for the mode toggles: the current formation choice and
## the first selected unit's stance keep a lit frame on their button — before
## this, pressing Defensive or Box changed the simulation with zero visual echo.
func _refresh_mode_highlights() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var commands: Variant = world.get("_commands")
	var formation: String = ""
	if commands != null:
		formation = commands.get("_formation") as String
	var stance_id: String = _first_selected_stance(world)
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id.begins_with("formation:"):
			btn.set_active(btn.action_id.trim_prefix("formation:") == formation)
		elif btn.action_id.begins_with("stance:"):
			btn.set_active(btn.action_id.trim_prefix("stance:") == stance_id)

func _first_selected_stance(world: Node) -> String:
	var units: Variant = world.get("_selected_units")
	if units is Array and not (units as Array).is_empty():
		var unit: Variant = (units as Array)[0]
		if is_instance_valid(unit):
			var s: Variant = (unit as Node).get("stance")
			if s != null and (s as int) >= 0 and (s as int) < HudActionDefs.STANCE_NAMES.size():
				return HudActionDefs.STANCE_NAMES[s as int]
	return ""

func _highlight_pending_button(active_id: String) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		var is_pending: bool = btn.action_id == active_id and not active_id.is_empty()
		# Persistent toggles (e.g. scout auto-explore) keep their lit frame.
		btn.set_active(is_pending or (btn.get_meta("toggled", false) as bool))

# ── Per-selection layouts ─────────────────────────────────────────────────────

## Type dispatch for a unit selection (the info panel is already filled).
func populate_for_unit(first: Node) -> void:
	if first is Animal:
		var astate: Variant = first.get("current_state")
		var owned: bool = astate != null and (astate as int) == Animal.AnimalState.OWNED
		populate(HudActionDefs.ANIMAL_ACTIONS if owned else [])
	elif first is HeroUnit:
		_populate_hero_buttons(first as HeroUnit)
	elif first is TransportShip:
		populate_transport_buttons(first as TransportShip)
	elif first is Trebuchet:
		_populate_trebuchet_buttons(first as Trebuchet)
	elif first is Mangonel:
		populate(HudActionDefs.SIEGE_ACTIONS + HudActionDefs.COMBAT_MODE_ACTIONS)
	elif first is Archer or first is Longbowman:
		populate(HudActionDefs.RANGED_ACTIONS + HudActionDefs.COMBAT_MODE_ACTIONS)
	elif first is Scout:
		_populate_scout_buttons(first as Scout)
	elif first.has_method("order_gather"):
		populate_villager_actions()
	else:
		populate(HudActionDefs.UNIT_ACTIONS + HudActionDefs.COMBAT_MODE_ACTIONS)

## Type dispatch for a COMPLETE own building (info panel already filled).
func populate_for_building(building: Node) -> void:
	if building.has_method("is_respawning_hero") or building is TownCenterBuildable:
		populate_tc_actions()
	elif building is Market:
		populate_market_actions(building as Market)
	elif building is Gate:
		_populate_gate_actions(building as Gate)
	elif building is Blacksmith:
		_populate_production(building, TechnologyResource.ResearchBuilding.BLACKSMITH)
	elif building is University:
		_populate_production(building, TechnologyResource.ResearchBuilding.UNIVERSITY)
	elif building is Temple:
		_populate_production(building, TechnologyResource.ResearchBuilding.MONASTERY)
	elif building is Mill:
		_populate_production(building, TechnologyResource.ResearchBuilding.MILL)
	elif building is LumberCamp:
		_populate_production(building, TechnologyResource.ResearchBuilding.LUMBER_CAMP)
	elif building is MiningCamp:
		_populate_production(building, TechnologyResource.ResearchBuilding.MINING_CAMP)
	elif building is Barracks:
		_populate_production(building, TechnologyResource.ResearchBuilding.BARRACKS)
	elif building is Stable:
		_populate_production(building, TechnologyResource.ResearchBuilding.STABLE)
	elif building is ArcheryRange or building is SiegeWorkshop or building is Dock:
		_populate_production(building, -1)
	else:
		populate(HudActionDefs.BUILDING_ACTIONS)

## Repaints whatever the current selection shows (age-up, tech researched)
## without touching the info panel. Own COMPLETE buildings only — an enemy or
## under-construction selection must keep its buttonless/destroy-only panel.
func repopulate_selected_building() -> void:
	var building: Node = _selected_building()
	if not is_instance_valid(building):
		return
	var bpid: Variant = building.get("player_id")
	if bpid != null and (bpid as int) != _pid():
		return
	var bstate: Variant = building.get("state")
	if bstate != null and (bstate as int) != BuildingBase.BuildingState.COMPLETE:
		return
	populate_for_building(building)

func populate_villager_actions() -> void:
	populate(HudActionDefs.VILLAGER_ACTIONS)
	_apply_tutorial_villager_gates()

## ONE production panel for every train/research building: train buttons come
## from the building's own get_available_units() defs (costs from each unit's
## .tres), research buttons from TechManager. This replaced eight near-identical
## per-building populate functions.
func _populate_production(building: Node, research_type: int) -> void:
	var actions: Array = []
	if building.has_method("get_available_units"):
		for def: Dictionary in building.get_available_units():
			actions.append(HudActionDefs.train_action(def))
	if building is Dock:
		actions.append(_fish_trap_action())
	if research_type >= 0:
		var pending: Array = TechManager.pending_research_ids(building.get_instance_id())
		for tech: TechnologyResource in TechManager.get_available_techs(_pid(), research_type):
			actions.append(HudActionDefs.tech_action(tech, pending))
	actions.append(HudActionDefs.DESTROY_BUILDING_ACTION)
	populate(actions)
	_hud.call("_build_research_bar", building)

func _fish_trap_action() -> Dictionary:
	var costs: Dictionary = WorldPlacement.building_costs("fish_trap")
	return {
		"id": "build:fish_trap",
		"label": tr("ACTION_FISH_TRAP"),
		"color": Color(0.15, 0.40, 0.55),
		"cost": costs,
		"key": KEY_P,
		"raw_label": true,
	}

func populate_tc_actions() -> void:
	var actions: Array = [
		HudActionDefs.train_action({
			"id": "villager",
			"data": "res://resources/units/villager_data.tres",
			"color": Color(0.20, 0.45, 0.20),
			"description": "TOOLTIP_TRAIN_VILLAGER",
		}),
		HudActionDefs.TOWN_BELL_ACTION,
	]

	var current_age: int = AgeManager.get_age(_pid())
	if current_age < GameManager.Age.IMPERIAL:
		var advancing: bool = AgeManager.is_advancing(_pid())
		var next_age: int = current_age + 1
		var costs: Dictionary = AgeManager.ADVANCE_COSTS[next_age]
		var cost_str: String = ""
		for k: Variant in costs:
			cost_str += "\n%d%s" % [(costs[k] as int), (k as String).substr(0, 1).to_upper()]
		var advance_color: Color
		match next_age:
			1: advance_color = Color(0.65, 0.55, 0.20)
			2: advance_color = Color(0.25, 0.40, 0.65)
			_: advance_color = Color(0.55, 0.20, 0.55)
		const AGE_NAME_KEYS: Array[String] = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]
		actions.append({
			"id": "advance_age",
			"label": tr("UI_ADVANCE") + " " + tr(AGE_NAME_KEYS[next_age]) + "\n" + cost_str.strip_edges(),
			"color": advance_color,
			"cost": costs,
			"key": KEY_E,
			"raw_label": true,
			"locked": advancing or (_tutorial.gates_active and _tutorial.step < 7),
		})

	actions.append(HudActionDefs.DESTROY_BUILDING_ACTION)
	populate(actions)

	if AgeManager.is_advancing(_pid()):
		_hud.call("_build_age_advance_bar")

	var building: Node = _selected_building()
	if is_instance_valid(building) and building.has_method("is_respawning_hero"):
		if building.is_respawning_hero() as bool:
			_hud.call("_build_hero_respawn_bar")

func _populate_hero_buttons(hero: HeroUnit) -> void:
	var actions: Array = [
		{"id": "move_to",     "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
		{"id": "attack_move", "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
		{"id": "patrol",      "label": "ACTION_PATROL",      "color": Color(0.25, 0.35, 0.60), "cost": {}, "key": KEY_R, "description": "TOOLTIP_PATROL"},
		{"id": "stop",        "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
		HudActionDefs.DESTROY_ACTION,
	]
	var udata: UnitResource = hero.unit_data
	if udata != null and not udata.hero_ability_id.is_empty():
		var cd_frac: float = hero.get_cooldown_fraction()
		var cd_secs: int = int(udata.hero_ability_cooldown * cd_frac)
		var ability_name: String = tr("HERO_%s_ABILITY" % udata.hero_ability_id.to_upper())
		var status: String = tr("HERO_ABILITY_READY") if cd_frac <= 0.0 else tr("HERO_ABILITY_COOLDOWN") % cd_secs
		actions.insert(0, {
			"id": "hero_ability",
			"label": ability_name + "\n" + status,
			"color": Color(0.55, 0.20, 0.55) if cd_frac <= 0.0 else Color(0.25, 0.25, 0.30),
			"cost": {},
			"key": KEY_Q,
			"raw_label": true,
			"description": udata.hero_ability_description,
			# Tutorial: the ability unlocks at step 9 with the military lesson
			# — fired earlier it derails the guided steps (same gate the age
			# advance uses at step 7).
			"locked": _tutorial.gates_active and _tutorial.step < 9,
		})
	populate(actions)

func populate_transport_buttons(ship: TransportShip) -> void:
	var garrison: Array = ship.get_garrison()
	var cap: int = ship.get_capacity()

	# Fill portrait grid with garrisoned units; each portrait is clickable to unload that unit.
	_free_children(_unit_portraits_grid)
	for i: int in range(garrison.size()):
		var garrisoned: Node = garrison[i] as Node
		var portrait: UnitPortrait = UnitPortrait.new()
		_unit_portraits_grid.add_child(portrait)
		portrait.setup(garrisoned)
		var idx: int = i
		portrait.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_hud.emit_signal("action_requested", "unload_unit:%d" % idx)
		)

	var actions: Array = []
	if not garrison.is_empty():
		actions.append({
			"id": "unload",
			"label": tr("UI_UNLOAD") + " (%d/%d)" % [garrison.size(), cap],
			"cost": {},
			"key": KEY_U,
			"raw_label": true,
			"badge": str(garrison.size()),
		})
	actions.append({"id": "stop", "label": "ACTION_STOP", "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"})
	actions.append(HudActionDefs.DESTROY_ACTION)
	populate(actions)
	_unit_status_label.text = tr("UI_GARRISON_STATUS") % [garrison.size(), cap]

func _populate_trebuchet_buttons(treb: Trebuchet) -> void:
	var deploy_label: String = tr("ACTION_TREBUCHET_UNDEPLOY") if treb.is_deployed else tr("ACTION_TREBUCHET_DEPLOY")
	var deploy_color: Color = Color(0.20, 0.45, 0.20) if treb.is_deployed else Color(0.45, 0.35, 0.12)
	var actions: Array = [
		{"id": "move_to",     "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
		{"id": "attack_move", "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
		{"id": "stop",        "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
		{"id": "trebuchet_deploy", "label": deploy_label, "color": deploy_color, "cost": {}, "key": KEY_F, "raw_label": true},
		HudActionDefs.DESTROY_ACTION,
	]
	populate(actions)

func _populate_scout_buttons(scout: Scout) -> void:
	var actions: Array = [
		{"id": "move_to",     "label": "ACTION_MOVE_TO",     "color": Color(0.18, 0.38, 0.58), "cost": {}, "key": KEY_M, "description": "TOOLTIP_MOVE_TO"},
		{"id": "attack_move", "label": "ACTION_ATTACK_MOVE", "color": Color(0.60, 0.18, 0.10), "cost": {}, "key": KEY_Z, "description": "TOOLTIP_ATTACK_MOVE"},
		{"id": "patrol",      "label": "ACTION_PATROL",      "color": Color(0.25, 0.35, 0.60), "cost": {}, "key": KEY_R, "description": "TOOLTIP_PATROL"},
		{"id": "stop",        "label": "ACTION_STOP",        "color": Color(0.50, 0.10, 0.10), "cost": {}, "key": KEY_X, "description": "TOOLTIP_STOP"},
	]
	if scout.is_exploring():
		# Same looping-path glyph; the lit frame marks auto-explore as engaged.
		actions.append({"id": "scout_explore_stop", "label": "ACTION_SCOUT_EXPLORE_STOP", "cost": {}, "key": KEY_E, "description": "TOOLTIP_SCOUT_EXPLORE_STOP", "active": true})
	else:
		actions.append({"id": "scout_explore", "label": "ACTION_SCOUT_EXPLORE", "cost": {}, "key": KEY_E, "description": "TOOLTIP_SCOUT_EXPLORE"})
	actions.append(HudActionDefs.DESTROY_ACTION)
	populate(actions)

func _populate_gate_actions(gate: Gate) -> void:
	populate(HudActionDefs.GATE_ACTIONS)
	refresh_gate_toggle_label(gate)
	_unit_status_label.text = tr("UI_GATE_LOCKED") if gate.locked else (tr("UI_GATE_OPEN") if gate.is_open else tr("UI_GATE_CLOSED"))
	if not gate.gate_toggled.is_connected(_on_gate_toggled):
		gate.gate_toggled.connect(_on_gate_toggled)

func _on_gate_toggled(_is_open: bool) -> void:
	var building: Node = _selected_building()
	if is_instance_valid(building) and building is Gate:
		var gate: Gate = building as Gate
		refresh_gate_toggle_label(gate)
		_unit_status_label.text = tr("UI_GATE_LOCKED") if gate.locked else (tr("UI_GATE_OPEN") if gate.is_open else tr("UI_GATE_CLOSED"))

func refresh_gate_toggle_label(gate: Gate) -> void:
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id != "gate_lock":
			continue
		# The glyph shows the action to perform: closed padlock = lock it.
		btn.set_glyph(UiIcons.get_icon("gate_unlock" if gate.locked else "gate_lock"))
		btn.tooltip_text = "%s  [O]" % (tr("UI_GATE_UNLOCK") if gate.locked else tr("UI_GATE_LOCK"))

## Garrisonable buildings (TC, towers) get an eject button and an occupancy
## readout appended to whatever the type dispatch above built.
func append_garrison_ui(building: Node) -> void:
	if not building.has_method("garrison_capacity") \
			or (building.garrison_capacity() as int) <= 0:
		return
	var garrison: Array = building.get_garrison() as Array
	var cap: int = building.garrison_capacity() as int
	# "Garrisoned", not the ships' "crew" wording — a Town Center has no crew.
	_unit_status_label.text = tr("UI_GARRISONED") % [garrison.size(), cap]
	# The occupancy readout is fine in a replay; the eject button is not.
	if garrison.is_empty() or MatchConfig.is_replay():
		return
	_active_actions.append({
		"id": "ungarrison",
		"label": tr("UI_UNGARRISON") + " (%d/%d)" % [garrison.size(), cap],
		"cost": {},
		"key": KEY_U,
		"raw_label": true,
		"badge": str(garrison.size()),
		"description": "TOOLTIP_UNGARRISON",
	})
	_render_action_page()

func populate_market_actions(market: Market) -> void:
	var sr_f: int = market.get_sell_rate(_pid(), "food")
	var sr_w: int = market.get_sell_rate(_pid(), "wood")
	var sr_s: int = market.get_sell_rate(_pid(), "stone")
	var br_f: int = market.get_buy_rate(_pid(), "food")
	var br_w: int = market.get_buy_rate(_pid(), "wood")
	var br_s: int = market.get_buy_rate(_pid(), "stone")
	var actions: Array = [
		{"id": "market:sell:food",  "label": tr("MARKET_SELL_FMT") % [tr("ACTION_FOOD"), sr_f],  "abbr": "-F", "cost": {"food":  sr_f}, "key": KEY_NONE, "raw_label": true, "description": "TOOLTIP_MARKET_SELL"},
		{"id": "market:sell:wood",  "label": tr("MARKET_SELL_FMT") % [tr("ACTION_WOOD"), sr_w],  "abbr": "-W", "cost": {"wood":  sr_w}, "key": KEY_NONE, "raw_label": true, "description": "TOOLTIP_MARKET_SELL"},
		{"id": "market:sell:stone", "label": tr("MARKET_SELL_FMT") % [tr("ACTION_STONE"), sr_s], "abbr": "-S", "cost": {"stone": sr_s}, "key": KEY_NONE, "raw_label": true, "description": "TOOLTIP_MARKET_SELL"},
		{"id": "market:buy:food",   "label": tr("MARKET_BUY_FMT") % [tr("ACTION_FOOD"), br_f],   "abbr": "+F", "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true, "description": "TOOLTIP_MARKET_BUY"},
		{"id": "market:buy:wood",   "label": tr("MARKET_BUY_FMT") % [tr("ACTION_WOOD"), br_w],   "abbr": "+W", "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true, "description": "TOOLTIP_MARKET_BUY"},
		{"id": "market:buy:stone",  "label": tr("MARKET_BUY_FMT") % [tr("ACTION_STONE"), br_s],  "abbr": "+S", "cost": {"gold": 1},     "key": KEY_NONE, "raw_label": true, "description": "TOOLTIP_MARKET_BUY"},
	]
	# Mercenaries: every civ can hire (Fenicios pay less — the market is
	# their turf); gated by the LOCAL player's age, refreshed while open.
	var current_age: int = AgeManager.get_age(_pid())
	for def: Dictionary in HudActionDefs.MERCENARY_UNIT_DEFS:
		if (def["age"] as int) > current_age:
			continue
		var uid: String = def["id"] as String
		var scene_path: String = "res://scenes/units/%s.tscn" % uid
		if not ResourceLoader.exists(scene_path):
			continue
		var unit_res: Resource = load("res://resources/units/%s_data.tres" % uid) as Resource
		var display: String = EntityNames.unit_name(unit_res) if unit_res != null else (def["display"] as String)
		var gold_cost: int = market.get_mercenary_cost(uid)
		var cooldown_remaining: float = market.get_mercenary_cooldown_fraction(uid) * market.MERCENARY_COOLDOWN
		var on_cooldown: bool = cooldown_remaining > 0.0
		var label: String
		if on_cooldown:
			label = tr("MARKET_HIRE_CD_FMT") % [display, int(ceil(cooldown_remaining))]
		else:
			label = tr("MARKET_HIRE_FMT") % [display, gold_cost]
		actions.append({
			"id": "market:hire:%s" % uid,
			"label": label,
			"cost": {"gold": gold_cost},
			"key": KEY_NONE,
			"raw_label": true,
			"locked": on_cooldown,
			"badge": ("%ds" % int(ceil(cooldown_remaining))) if on_cooldown else "",
			"description": "TOOLTIP_MARKET_HIRE",
		})
	actions.append(HudActionDefs.DESTROY_BUILDING_ACTION)
	if MatchConfig.is_replay():
		return
	# Rate refreshes keep the page and the queue row: no full clear() here.
	_active_actions = actions
	_action_grid.columns = ACTION_COLS
	_render_action_page()

# ── Build menu / tutorial gates ───────────────────────────────────────────────

func _filtered_build_actions() -> Array:
	var current_age: int = AgeManager.get_age(_pid())
	var wonder_visible: bool = MatchConfig.victory_mode == MatchConfig.VictoryMode.WONDER \
		and current_age >= GameManager.Age.IMPERIAL
	var is_tutorial: bool = _tutorial.gates_active
	var unlocked: Array[String] = []
	if is_tutorial:
		unlocked = _tutorial.unlocked_build_ids()

	var result: Array = []
	for entry: Variant in HudActionDefs.BUILD_ACTIONS:
		var data: Dictionary = entry as Dictionary
		var bid: String = data.get("id", "") as String
		if bid == "back":
			result.append(data)
			continue
		# Wonder only shown in wonder-victory games at Imperial age
		if bid == "build:wonder" and not wonder_visible:
			continue
		# Hide buildings that require a higher age than the player currently
		# has (per-civ unlocks apply: Fenicios market in the Dark Age).
		var min_age: int = HudActionDefs.build_min_age(data, _pid())
		if current_age < min_age:
			continue
		# Costs come from the same .tres-backed table the placement charges,
		# filtered through the civ's discounts.
		data = HudActionDefs.build_action(data, _pid())
		# In tutorial, lock buildings not yet introduced
		if is_tutorial and _tutorial.step < 7 and bid not in unlocked:
			result.append(data.merged({"locked": true}, true))
		else:
			result.append(data)
	return result

func _apply_tutorial_villager_gates() -> void:
	if not _tutorial.gates_active:
		return
	for child: Node in _action_grid.get_children():
		if not (child is ActionButton):
			continue
		var btn: ActionButton = child as ActionButton
		if btn.action_id == "build_menu" and _tutorial.step < 3:
			btn.set_meta("locked", true)
			btn.set_enabled(false)

## Tutorial step changed or finished: repaint whichever panel is open so
## newly unlocked actions appear.
func refresh_after_tutorial_change() -> void:
	if _in_build_menu:
		populate(_filtered_build_actions())
		return
	var building: Node = _selected_building()
	if is_instance_valid(building):
		var scr: Script = building.get_script() as Script
		if scr != null and "town_center" in (scr.resource_path as String).to_lower():
			populate_tc_actions()
		return
	var unit: Node = _hud.get("_selected_unit") as Node
	if is_instance_valid(unit) and unit.has_method("order_gather"):
		populate_villager_actions()

# ── EventBus refreshes ────────────────────────────────────────────────────────

func _on_resource_changed(player_id: int, _resource: String, _amount: int) -> void:
	# HudResourceBar updates the counters; the action menu only needs an
	# affordability refresh when the local player's stockpile changes.
	if player_id != _pid():
		return
	refresh_button_states()

func _on_technology_researched(player_id: int, _tech_id: String) -> void:
	if player_id != _pid():
		return
	repopulate_selected_building()

func _on_age_advance_complete(player_id: int, _new_age: int) -> void:
	# The HUD frees the advance bar; newly unlocked build/train options appear.
	if player_id != _pid():
		return
	repopulate_selected_building()

func _on_market_rate_changed(pid: int, market: Market) -> void:
	if pid != _pid():
		return
	if is_instance_valid(_selected_building()) and _selected_building() == market:
		populate_market_actions(market)

func _on_mercenary_hired(_pid_unused: int, _unit_id: String, market: Market) -> void:
	if is_instance_valid(_selected_building()) and _selected_building() == market:
		populate_market_actions(market)

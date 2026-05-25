class_name AIDebugOverlay extends CanvasLayer

## Press F2 to toggle. Shows the last 40 AI decisions for every active AIPlayer.
## Attach this node to the game_world scene root (or add it from game_world._ready).

var _panel: PanelContainer
var _label: RichTextLabel
var _ai_players: Array[Node] = []

func _ready() -> void:
	layer = 128  # above HUD

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.set_position(Vector2(-420, 4))
	_panel.custom_minimum_size = Vector2(410, 0)
	_panel.visible = GameSettings.ai_debug
	add_child(_panel)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(410, 0)
	_label.add_theme_font_size_override("normal_font_size", 11)
	_panel.add_child(_label)

func register_ai(ai: Node) -> void:
	if not _ai_players.has(ai):
		_ai_players.append(ai)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_F2:
			GameSettings.ai_debug = not GameSettings.ai_debug
			_panel.visible = GameSettings.ai_debug

func _process(_delta: float) -> void:
	if not GameSettings.ai_debug or not _panel.visible:
		return
	var lines: PackedStringArray = PackedStringArray()
	for ai: Node in _ai_players:
		if not is_instance_valid(ai):
			continue
		var log: Array = ai.get_debug_log()
		var age_idx: int = AgeManager.get_age(ai.get("player_id") as int)
		var age_name: String = ["Dark", "Feudal", "Castle", "Imperial"][age_idx]
		var res: Dictionary = ResourceManager.get_resources(ai.get("player_id") as int)
		lines.append("[color=yellow]── P%d (%s) F:%d W:%d G:%d S:%d ──[/color]" % [
			ai.get("player_id") as int, age_name,
			res.get("food", 0) as int, res.get("wood", 0) as int,
			res.get("gold", 0) as int, res.get("stone", 0) as int,
		])
		var start: int = maxi(0, log.size() - 14)
		for i: int in range(start, log.size()):
			lines.append(log[i] as String)
	_label.text = "\n".join(lines)

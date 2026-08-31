class_name HudChat extends Node

## In-match multiplayer chat: Enter opens the input, Enter sends, Escape
## closes. Messages stack bottom-left above the command bar and fade out.
## While the input has focus it swallows every key, so the HUD hotkeys
## (which listen in _unhandled_input) cannot fire mid-sentence. Only built
## when NetworkSession.is_online().

const MAX_LINES: int = 6
const LINE_LIFETIME: float = 9.0
const FADE_TIME: float = 1.2

var _lines_box: VBoxContainer = null
var _input: LineEdit = null
var _hint: Label = null

func init(hud_root: Node) -> void:
	var anchor: Control = Control.new()
	anchor.name = "ChatAnchor"
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(anchor)

	_lines_box = VBoxContainer.new()
	_lines_box.add_theme_constant_override("separation", 2)
	_lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fixed box bottom-aligned above the input row: new lines push the stack
	# upward, never into the command bar.
	_lines_box.alignment = BoxContainer.ALIGNMENT_END
	_lines_box.position = Vector2(14.0, -472.0)
	_lines_box.size = Vector2(460.0, 168.0)
	anchor.add_child(_lines_box)

	_input = LineEdit.new()
	_input.custom_minimum_size = Vector2(360.0, 30.0)
	_input.position = Vector2(14.0, -298.0)
	_input.max_length = NetworkSession.CHAT_MAX_LEN
	_input.placeholder_text = tr("CHAT_PLACEHOLDER")
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_gui)
	anchor.add_child(_input)

	_hint = Label.new()
	_hint.text = tr("CHAT_HINT")
	_hint.position = Vector2(14.0, -294.0)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.5))
	anchor.add_child(_hint)

	NetworkSession.chat_received.connect(_on_chat)
	NetworkSession.system_chat_received.connect(_on_system)

func _exit_tree() -> void:
	if NetworkSession.chat_received.is_connected(_on_chat):
		NetworkSession.chat_received.disconnect(_on_chat)
	if NetworkSession.system_chat_received.is_connected(_on_system):
		NetworkSession.system_chat_received.disconnect(_on_system)

func _on_system(kind: String, display_name: String) -> void:
	_push_line(tr("CHAT_SYS_" + kind.to_upper()) % display_name,
		Color(0.72, 0.72, 0.72))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and not _input.visible:
		_open_input()
		get_viewport().set_input_as_handled()

func _open_input() -> void:
	_input.visible = true
	_hint.visible = false
	_input.grab_focus()

func _close_input() -> void:
	_input.text = ""
	_input.visible = false
	_hint.visible = true
	_input.release_focus()

func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_close_input()
		_input.accept_event()

func _on_submitted(text: String) -> void:
	NetworkSession.send_chat(text)
	_close_input()

func _on_chat(pid: int, text: String) -> void:
	_push_line("%s: %s" % [NetworkSession.display_name_of(pid), text],
		PlayerColors.get_color(pid).lightened(0.35))
	AudioManager.play("select_generic", -14.0)

func _push_line(text: String, color: Color) -> void:
	var line: Label = Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", 15)
	line.add_theme_color_override("font_color", color)
	line.add_theme_constant_override("outline_size", 5)
	line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_lines_box.add_child(line)
	while _lines_box.get_child_count() > MAX_LINES:
		_lines_box.get_child(0).free()
	var tween: Tween = line.create_tween()
	tween.tween_interval(LINE_LIFETIME)
	tween.tween_property(line, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(line.queue_free)

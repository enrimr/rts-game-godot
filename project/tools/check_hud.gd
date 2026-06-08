extends SceneTree

# Headless validation harness for the HUD refactor.
# Loads hud.tscn, instantiates it under the tree (so _ready runs and all
# %unique nodes + child controllers resolve), then quits. Any parse error,
# missing-node error, or _ready crash surfaces in stderr.
# Run: godot --headless -s tools/check_hud.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/ui/hud/hud.tscn") as PackedScene
	if packed == null:
		push_error("CHECK_HUD: failed to load hud.tscn")
		quit(1)
		return
	var hud: Node = packed.instantiate()
	if hud == null:
		push_error("CHECK_HUD: failed to instantiate hud.tscn")
		quit(1)
		return
	get_root().add_child(hud)
	print("CHECK_HUD: hud.tscn instantiated OK (%d direct children)" % hud.get_child_count())
	hud.queue_free()
	quit(0)

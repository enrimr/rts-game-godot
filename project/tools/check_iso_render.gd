extends Node2D

## Diagnostic: measures where billboarded visuals actually land on screen
## relative to their unit anchor under the isometric camera.
## Run: $GODOT --path project res://tools/check_iso_render.tscn

func _ready() -> void:
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	IsoProjection.apply_to_camera(cam, 1.0)
	cam.global_position = Vector2(1000.0, 1000.0)

	var unit: CharacterBody2D = (load("res://scenes/units/militia.tscn") as PackedScene).instantiate() as CharacterBody2D
	add_child(unit)
	unit.global_position = Vector2(1000.0, 1000.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var unit_canvas: Transform2D = unit.get_global_transform_with_canvas()
	print("UNIT canvas origin: ", unit_canvas.origin)

	var bar: ProgressBar = unit.get_node("HealthBar") as ProgressBar
	var bar_canvas: Transform2D = bar.get_global_transform_with_canvas()
	print("BAR canvas origin:  ", bar_canvas.origin)
	print("BAR delta:          ", bar_canvas.origin - unit_canvas.origin, "  (authored: -20, -36)")
	print("BAR basis x:        ", bar_canvas.x, "  (want ~(1,0))")
	print("BAR basis y:        ", bar_canvas.y, "  (want ~(0,1))")
	print("BAR node pos/rot/scale: ", bar.position, " ", bar.rotation, " ", bar.scale)

	var body: Node2D = unit.get_node("Body") as Node2D
	var body_canvas: Transform2D = body.get_global_transform_with_canvas()
	print("BODY delta:         ", body_canvas.origin - unit_canvas.origin, "  (authored: 0, 0)")
	print("BODY basis x:       ", body_canvas.x, "  (want ~(1,0))")
	print("BODY basis y:       ", body_canvas.y, "  (want ~(0,1))")

	var stripe: ColorRect = unit.get_node_or_null("PlayerColorStripe") as ColorRect
	if stripe != null:
		var sc: Transform2D = stripe.get_global_transform_with_canvas()
		print("STRIPE delta:       ", sc.origin - unit_canvas.origin)
		print("STRIPE basis x:     ", sc.x, "  basis y: ", sc.y)

	var tc: StaticBody2D = (load("res://scenes/buildings/town_center.tscn") as PackedScene).instantiate() as StaticBody2D
	add_child(tc)
	tc.global_position = Vector2(1100.0, 1000.0)
	if tc.has_method("force_complete"):
		tc.call("force_complete")

	var vil: CharacterBody2D = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate() as CharacterBody2D
	add_child(vil)
	vil.global_position = Vector2(1050.0, 1060.0)
	vil.set("carried_amount", 7.0)
	vil.set("carried_resource", "wood")

	for _i: int in range(8):
		await get_tree().process_frame
	if vil.has_method("_update_gather_indicator"):
		vil.call("_update_gather_indicator")
	for _i: int in range(4):
		await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/calima-iso/check_render.png")
	print("saved /tmp/calima-iso/check_render.png")
	get_tree().quit(0)

class_name IsoProjection
extends Object

## Camera-level isometric/axonometric projection:
##   screen = Scale(zoom, zoom * Y_SQUASH) x Rotate(WORLD_ROTATION) x world
## The whole game simulation stays cartesian; only the Camera2D view transform
## rotates and squashes. Physics bodies must NEVER sit under a non-uniformly
## scaled parent (it corrupts collision shapes), which is why the squash lives
## exclusively in Camera2D.zoom.

const WORLD_ROTATION: float = PI / 4.0
const Y_SQUASH: float = 0.5

## Godot's canvas transform applies Rotate(-camera.rotation), so a negative
## camera rotation renders the world rotated +WORLD_ROTATION on screen.
static func camera_rotation() -> float:
	return -WORLD_ROTATION

## Camera2D.zoom that composes the user zoom with the isometric Y squash.
static func camera_zoom(user_zoom: float) -> Vector2:
	return Vector2(user_zoom, user_zoom * Y_SQUASH)

## Recovers the user zoom factor from a composed Camera2D.zoom value.
static func user_zoom_from(zoom: Vector2) -> float:
	return zoom.x

static func apply_to_camera(camera: Camera2D, user_zoom: float) -> void:
	camera.ignore_rotation = false
	camera.rotation = camera_rotation()
	camera.zoom = camera_zoom(user_zoom)

## World position -> screen-space offset from the view centre (camera at origin).
static func world_to_screen(world: Vector2, user_zoom: float = 1.0) -> Vector2:
	var rotated: Vector2 = world.rotated(WORLD_ROTATION)
	return Vector2(rotated.x * user_zoom, rotated.y * Y_SQUASH * user_zoom)

## Inverse of world_to_screen.
static func screen_to_world(screen: Vector2, user_zoom: float = 1.0) -> Vector2:
	var unscaled: Vector2 = Vector2(screen.x / user_zoom, screen.y / (Y_SQUASH * user_zoom))
	return unscaled.rotated(-WORLD_ROTATION)

## Converts a screen-space pixel delta (e.g. mouse drag) into the world-space
## delta that keeps the content pinned under the cursor, given the camera zoom.
static func screen_delta_to_world(screen_delta: Vector2, zoom: Vector2) -> Vector2:
	return Vector2(screen_delta.x / zoom.x, screen_delta.y / zoom.y).rotated(-WORLD_ROTATION)

## Converts a screen-axis panning intent (keys, dpad, edge scroll) into a
## normalized world-space direction so camera movement follows screen axes.
static func screen_dir_to_world(screen_dir: Vector2) -> Vector2:
	if screen_dir == Vector2.ZERO:
		return Vector2.ZERO
	return screen_delta_to_world(screen_dir, camera_zoom(1.0)).normalized()

shader_type canvas_item;

// Full-screen vignette: subtly darkens the screen edges to focus the eye on
// the centre of the action and give the flat scene a touch of cinematic depth.
// Applied to a full-rect ColorRect on a CanvasLayer above the world.

uniform float intensity : hint_range(0.0, 1.0) = 0.35;
uniform float extent : hint_range(0.1, 1.5) = 0.75;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float dist = length(d) / 0.7071;          // 0 at centre, 1 at corners
	float v = smoothstep(extent, 1.0, dist) * intensity;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}

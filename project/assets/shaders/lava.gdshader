shader_type canvas_item;

// Pulsing ember glow for volcanic lava veins, caldera cracks and lava pools.
// Modulates the polygon/line's own colour so the orange "breathes" like cooling
// rock instead of sitting as a static fill. Sampled in world space so the
// flicker pattern varies along a vein rather than pulsing uniformly.

uniform float pulse_speed : hint_range(0.1, 4.0) = 1.4;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.55;
uniform float pulse_max : hint_range(1.0, 3.0) = 1.6;
uniform float flicker_scale : hint_range(0.001, 0.1) = 0.03;

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float t = TIME * pulse_speed;
	// Base sine breath plus a noise-driven flicker that travels along the vein.
	float breath = sin(t + world_pos.x * 0.05 + world_pos.y * 0.05) * 0.5 + 0.5;
	float flick = value_noise(world_pos * flicker_scale + vec2(t * 0.3, -t * 0.2));
	float glow = mix(pulse_min, pulse_max, clamp(breath * 0.7 + flick * 0.3, 0.0, 1.0));

	COLOR.rgb *= glow;
	// Lift alpha slightly at peak glow so hot spots read brighter.
	COLOR.a = clamp(COLOR.a * (0.85 + glow * 0.25), 0.0, 1.0);
}

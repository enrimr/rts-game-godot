shader_type canvas_item;

// Animated ocean: layered sine swell, value-noise ripples, and bright foam crests.
// Driven in world space (via VERTEX) so waves keep a consistent scale regardless
// of the ocean polygon's size or the camera zoom.

uniform vec4 water_deep : source_color = vec4(0.04, 0.16, 0.38, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.13, 0.40, 0.64, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.90, 0.96, 1.0);
uniform float wave_scale : hint_range(0.001, 0.05) = 0.010;
uniform float wave_speed : hint_range(0.05, 3.0) = 0.55;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.16;

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
	vec2 p = world_pos * wave_scale;
	float t = TIME * wave_speed;

	// Long directional swell built from a few sine bands.
	float swell = sin(p.x * 3.0 + t) * 0.5
				+ sin((p.x + p.y) * 2.1 - t * 1.3) * 0.30
				+ sin((p.x - p.y) * 4.3 + t * 0.7) * 0.20;

	// Higher-frequency drifting ripples from value noise.
	float ripple = value_noise(p * 6.0 + vec2(t * 0.6, -t * 0.4));

	float h = swell * 0.5 + 0.5;
	h = clamp(h * 0.7 + ripple * 0.3, 0.0, 1.0);

	vec3 col = mix(water_deep.rgb, water_shallow.rgb, h);

	// Foam: bright crests where swell+ripple peaks exceed a threshold.
	float crest = smoothstep(1.0 - foam_amount, 1.0, h + ripple * 0.25);
	col = mix(col, foam_color.rgb, crest * 0.6);

	// Preserve the polygon's own alpha so translucent sheets (shallow-water
	// shelves layered over the deep ocean) blend instead of cutting hard.
	COLOR = vec4(col, COLOR.a);
}

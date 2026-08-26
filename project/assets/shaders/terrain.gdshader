shader_type canvas_item;

// Adds organic tonal variation and fine grain to an otherwise flat-coloured
// terrain polygon. Sampled in world space so the pattern is stable as the
// camera pans and seamless across adjacent patches of the same terrain type.

uniform float detail_scale : hint_range(0.005, 0.1) = 0.022;
uniform float variation : hint_range(0.0, 0.5) = 0.16;
uniform float grain : hint_range(0.0, 0.3) = 0.06;

// Tile-scale mottling: the world plane is quantised into square cells that the
// isometric camera renders as ground diamonds, each cell shifted to one of a
// few discrete tones — the classic RTS tileset checker instead of one flat
// vector sheet. `dirt_amount` swaps a fraction of cells toward a dry dirt
// tint for extra patchiness.
uniform float tile_size : hint_range(8.0, 128.0) = 26.0;
uniform float mottle : hint_range(0.0, 0.5) = 0.14;
uniform float dirt_amount : hint_range(0.0, 0.5) = 0.12;
uniform vec3 dirt_tint : source_color = vec3(0.72, 0.62, 0.38);

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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += value_noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = world_pos * detail_scale;

	// Low-frequency patches lighten/darken broad areas.
	float patches = fbm(p) - 0.5;
	// High-frequency grain breaks up solid fills.
	float speckle = (hash(floor(world_pos * 0.5)) - 0.5);

	// Tile checker: each world cell picks one of 4 discrete tone steps.
	vec2 cell = floor(world_pos / tile_size);
	float tone = (floor(hash(cell) * 4.0) / 3.0 - 0.5) * 2.0 * mottle;

	float shade = 1.0 + patches * (variation * 2.0) + tone + speckle * grain;
	vec3 col = COLOR.rgb * shade;

	// Dry-dirt cells: a hashed fraction of tiles shifts toward the dirt tint,
	// keeping the tile's own tone step so dirt patches stay uneven.
	float dirt = step(hash(cell + vec2(7.31, 3.17)), dirt_amount);
	col = mix(col, dirt_tint * (1.0 + tone), dirt * 0.45);

	COLOR.rgb = col;
}

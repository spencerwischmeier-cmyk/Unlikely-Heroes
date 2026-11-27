// Grass tufts over the Roof Gardens lawns (scripts/level/gardens/gardens_look.gd). Each tuft is three
// crossed cards; the blades are cut out here (alpha scissor). Normals point up so the tufts light like the
// lawn under them; the colour runs from a dark root to a sunlit, slightly golden tip. Wind bends the tips.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 root_col : source_color = vec3(0.12, 0.26, 0.09);
uniform vec3 tip_col : source_color = vec3(0.55, 0.78, 0.3);
uniform vec3 dry_col : source_color = vec3(0.78, 0.74, 0.36);
uniform float wind = 0.09;

varying vec3 org;

float h1(float x) { return fract(sin(x * 91.3458) * 47453.5453); }

void vertex() {
	org = MODEL_MATRIX[3].xyz;
	float ph = org.x * 0.45 + org.z * 0.37;
	float k = UV.y * UV.y;
	float gust = sin(TIME * 1.6 + ph) * 0.7 + sin(TIME * 3.1 + ph * 2.1) * 0.3;
	VERTEX.x += gust * wind * k;
	VERTEX.z += cos(TIME * 1.3 + ph) * wind * 0.6 * k;
}

void fragment() {
	// 9 blades across the card, each with its own height, lean and width
	float x = UV.x * 9.0;
	float i = floor(x);
	float seed = i + floor(org.x * 13.0) + floor(org.z * 7.0) * 3.0;
	float hgt = 0.45 + 0.55 * h1(seed);
	float lean = (h1(seed + 3.1) - 0.5) * 0.7;
	float cx = 0.5 + lean * UV.y;
	float t = UV.y / hgt;
	float w = 0.42 * (1.0 - pow(clamp(t, 0.0, 1.0), 1.4));
	float m = step(abs(fract(x) - cx), w) * step(t, 1.0);
	ALPHA = m;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 tip = mix(tip_col, dry_col, step(0.82, h1(seed + 7.7)) * 0.7);
	vec3 c = mix(root_col, tip, smoothstep(0.0, 0.9, UV.y)) * (0.85 + 0.3 * h1(seed + 1.3));
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = c * vec3(1.0, 0.85, 0.45) * 0.5 * UV.y;
	AO = mix(0.45, 1.0, UV.y);
	AO_LIGHT_AFFECT = 0.4;
}

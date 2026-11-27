// Roof Gardens lawn (swapped in by scripts/level/gardens/gardens_look.gd for the kit's flat lawn): patchy
// greens with darker damp hollows and sun-dried tips, clover spots, faint mowing bands, blade-scale
// speckle and a bump so the low sun grazes it; soft, irregular edges blending into the paving.
shader_type spatial;
render_mode blend_mix, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_col : source_color = vec3(0.14, 0.28, 0.11);
uniform vec3 mid_col : source_color = vec3(0.3, 0.47, 0.2);
uniform vec3 sun_col : source_color = vec3(0.58, 0.65, 0.32);
varying vec3 wpos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { return 0.5 * n2(p) + 0.27 * n2(p * 2.1 + 3.1) + 0.15 * n2(p * 4.3 + 7.7) + 0.08 * n2(p * 9.1); }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.35);
	float mid = fbm(p * 1.4 + 5.0);
	float blade = h2(floor(p * 40.0)) * 0.6 + h2(floor(p * 90.0)) * 0.4;
	vec3 c = mix(deep_col, mid_col, smoothstep(0.25, 0.65, big));
	c = mix(c, sun_col, smoothstep(0.55, 0.8, mid) * 0.6);
	// clover spots
	float clover = smoothstep(0.78, 0.85, n2(p * 3.3 + 11.0));
	c = mix(c, vec3(0.2, 0.42, 0.16), clover * 0.6);
	// faint mowing bands
	c *= 1.0 + (step(0.5, fract(p.x * 0.45 + p.y * 0.12)) - 0.5) * 0.06;
	c *= 0.78 + 0.4 * blade;
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.05, min(e.x, e.y) + (mid - 0.5) * 0.05);
	ALBEDO = c;
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
	float hh = (blade * 0.4 + mid * 0.6) * 0.006;
	vec3 dpdx = dFdx(VERTEX); vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL); vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dFdx(hh) * r1 + dFdy(hh) * r2));
}

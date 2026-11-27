// Painted scrap metal for the Junkyard clutter (junk_kit.gd MultiMeshes on models/junkyard/scrap_hd.glb).
// Paint colour comes from the instance colour. UV2 carries baked wear from art/scrap_hd.py: x = convex edges,
// y = cavities. Edges chip to bare steel, rust blooms in world space (heavier in cavities), grime collects in
// cavities and on undersides, and the paint keeps a thin clearcoat where it is intact.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float chip = 0.85;
uniform float rust = 0.55;
uniform float grime = 0.6;
uniform float pit_depth = 0.5;
uniform sampler2D pit_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float pit_scale = 2.5;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 tint;

float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) { return 0.5 * noise(p) + 0.3 * noise(p * 2.03 + 1.7) + 0.2 * noise(p * 4.11 + 3.1); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR;
}

void fragment() {
	float edge = UV2.x;
	float cav = UV2.y;
	float n1 = fbm3(wpos * 1.9);
	float n2 = noise(wpos * 11.0);
	vec3 paint = tint.rgb * (0.82 + 0.3 * n1);
	// chipped edges: wear eats in from the baked edge mask, broken up by noise
	float chipm = smoothstep(0.42, 0.62, edge * chip + (n2 - 0.5) * 0.55 + (n1 - 0.5) * 0.35);
	// small scratches and chips anywhere
	chipm = max(chipm, smoothstep(0.9, 0.96, noise(wpos * vec3(23.0, 3.0, 23.0))) * 0.8);
	vec3 steel = vec3(0.52, 0.52, 0.54) * (0.75 + 0.35 * n2);
	// rust blooms (world space so neighbouring pieces differ), worse in cavities and around chips
	float rr = smoothstep(0.52, 0.72, fbm3(wpos * 0.9 + 7.0) + cav * 0.3 + chipm * 0.15) * rust;
	rr = clamp(rr + cav * rust * 0.35 * n1, 0.0, 1.0);
	vec3 rust_c = mix(vec3(0.16, 0.06, 0.025), vec3(0.52, 0.22, 0.08), noise(wpos * 5.0));
	vec3 c = mix(paint, steel, chipm);
	c = mix(c, rust_c, rr);
	// grime: cavities, undersides, and a soft dust film on top faces
	float down = clamp(-wnrm.y, 0.0, 1.0);
	float up = clamp(wnrm.y, 0.0, 1.0);
	c *= 1.0 - grime * clamp(cav * 0.75 + down * 0.3, 0.0, 0.85);
	c = mix(c, vec3(0.42, 0.36, 0.3), up * 0.18 * grime * n1);
	ALBEDO = c;
	METALLIC = mix(0.12, 0.92, chipm) * (1.0 - rr);
	ROUGHNESS = clamp(mix(0.38 + 0.2 * n1, 0.26, chipm) + rr * 0.5 + up * 0.1, 0.05, 1.0);
	CLEARCOAT = (1.0 - chipm) * (1.0 - rr) * 0.35;
	CLEARCOAT_ROUGHNESS = 0.35;
	NORMAL_MAP = texture(pit_nrm, UV * pit_scale).rgb;
	NORMAL_MAP_DEPTH = pit_depth * (0.3 + rr * 1.4 + chipm * 0.4);
}

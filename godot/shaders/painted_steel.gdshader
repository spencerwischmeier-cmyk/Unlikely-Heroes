// Weathered painted steel for the Crane Yard's structural pieces (girders, lattice towers, booths, plates).
// The kit builds these from box primitives, so each MeshInstance3D passes its box half-size as an instance
// uniform: the shader then knows how far every pixel is from the nearest box edge and
//   - rounds the edges with a fake bevel (the normal bends over the last few centimetres, so edges catch light)
//   - chips the paint back to bare steel along those edges, with rust blooming out of the chips
//   - runs rust streaks down vertical faces from the top edge, and collects grime toward the bottom.
// Pieces with box_half = 0 (cylinders, odd meshes) fall back to noise-only wear. Paint colour is a uniform,
// so there is one material per kit colour (yard_kit.gd keys), shared by every piece of that colour.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint : source_color = vec4(0.95, 0.68, 0.12, 1.0);
uniform float paint_metal = 0.1;
uniform float paint_rough = 0.45;
uniform float chip = 1.0;
uniform float rust = 0.6;
uniform float grime = 0.7;
uniform float streaks = 0.7;
uniform float bevel = 0.035;            // metres of rounded edge
uniform float hazard = 0.0;             // 1 = yellow/black diagonal stripes (world space)
uniform sampler2D pit_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float unit_half = 0.0;          // 0.5 for MultiMeshes of unit boxes scaled per instance (girders, towers)
instance uniform vec3 box_half = vec3(0.0);

varying vec3 half_s;

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) { return 0.5 * noise(p) + 0.3 * noise(p * 2.03 + 1.7) + 0.2 * noise(p * 4.11 + 3.1); }

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * sc;
	lnrm = NORMAL;
	half_s = (box_half.x > 0.0 ? box_half : vec3(unit_half)) * sc;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n1 = fbm3(wpos * 1.6);
	float n2 = noise(wpos * 9.0);
	float n3 = noise(wpos * 31.0);
	// ---- distance to the nearest box edge (object space), and the outward direction toward it
	float edge_d = 10.0;
	vec3 bend = vec3(0.0);
	float top_d = 10.0;                 // distance down from the top face (for streaks)
	float bot_d = 10.0;                 // distance up from the bottom (for grime)
	if (half_s.x > 0.0) {
		vec3 d = half_s - abs(lpos);
		vec3 an = abs(lnrm);
		// ignore the axis this face is on
		vec3 dd = d + an * 100.0;
		edge_d = min(min(dd.x, dd.y), dd.z);
		// bend the normal toward the edge(s) it is close to
		vec3 w = (1.0 - clamp(dd / bevel, 0.0, 1.0));
		bend = sign(lpos) * w * w * (1.0 - an);
		top_d = half_s.y - lpos.y;
		bot_d = half_s.y + lpos.y;
	}
	// ---- paint (optionally hazard stripes), with a little colour variation
	vec3 pc = paint.rgb;
	if (hazard > 0.5) {
		float s = fract((wpos.x + wpos.y + wpos.z) * 1.4);
		pc = mix(vec3(0.95, 0.68, 0.12), vec3(0.06, 0.06, 0.07), step(0.5, s));
	}
	pc *= 0.84 + 0.28 * n1;
	// ---- chips: eaten in from the edges, broken up by noise; plus small dings on faces
	float edge_w = 1.0 - smoothstep(0.0, 0.16, edge_d + (n2 - 0.5) * 0.12);
	float chipm = smoothstep(0.45, 0.62, edge_w * chip + (n2 - 0.5) * 0.5 + (n1 - 0.5) * 0.3);
	chipm = max(chipm, smoothstep(0.88, 0.95, noise(wpos * vec3(17.0, 4.0, 17.0) + 3.0)) * 0.85 * chip);
	vec3 steel = vec3(0.45, 0.45, 0.47) * (0.7 + 0.4 * n3);
	// ---- rust: blooms around chips, streaks running down from top edges on vertical faces
	float vert = 1.0 - abs(wnrm.y);
	float rr = smoothstep(0.55, 0.75, fbm3(wpos * 0.7 + 11.0) + chipm * 0.35) * rust;
	float streak = noise(vec3(wpos.x * 7.0 + wpos.z * 7.0, wpos.y * 0.35, 0.0)) * noise(vec3(wpos.x * 2.3 - wpos.z * 1.9, wpos.y * 0.2, 5.0));
	float run = exp(-top_d * 0.9) + 0.25 * smoothstep(0.6, 0.8, n1);
	rr = max(rr, smoothstep(0.18, 0.45, streak) * run * vert * streaks);
	rr = clamp(rr, 0.0, 1.0);
	vec3 rust_c = mix(vec3(0.17, 0.065, 0.03), vec3(0.5, 0.21, 0.07), noise(wpos * 4.0));
	vec3 c = mix(pc, steel, chipm);
	c = mix(c, rust_c, rr * 0.9);
	// ---- grime: near the bottom of each piece, on undersides, and dust on top faces
	float up = clamp(wnrm.y, 0.0, 1.0);
	float down = clamp(-wnrm.y, 0.0, 1.0);
	float g = clamp(exp(-bot_d * 1.2) * 0.7 + down * 0.35 + smoothstep(0.55, 0.85, n1) * 0.2, 0.0, 0.85) * grime;
	c *= 1.0 - g * 0.7;
	c = mix(c, vec3(0.36, 0.3, 0.25), up * 0.22 * grime * n1);
	ALBEDO = c;
	METALLIC = mix(paint_metal, 0.9, chipm) * (1.0 - rr);
	ROUGHNESS = clamp(mix(paint_rough + 0.2 * n1, 0.3, chipm) + rr * 0.45 + up * 0.08, 0.05, 1.0);
	// ---- the fake bevel and pitting
	vec3 nm = texture(pit_nrm, (wpos.xz + wpos.y) * 0.7).rgb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.25 + rr * 1.2 + chipm * 0.5;
	if (half_s.x > 0.0) {
		vec3 vb = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bend, 0.0)).xyz + vec3(1e-5));
		NORMAL = normalize(NORMAL + vb * length(bend) * 0.9);
	}
}

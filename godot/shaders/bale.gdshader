// Crushed-scrap bale (models/junkyard/scrap_hd.glb "scrap_bale", surface 0): sheets of painted metal squashed
// flat into thin wavy layers, each layer a run of different scrap (paint, bare steel, rust), with dark gaps
// between layers and bright crumpled edges. Instance colour tints it. Surface 1 (straps) uses scrap.gdshader.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 c0 : source_color = vec3(0.34, 0.36, 0.4);
uniform vec3 c1 : source_color = vec3(0.2, 0.32, 0.33);
uniform vec3 c2 : source_color = vec3(0.6, 0.56, 0.48);
uniform vec3 c3 : source_color = vec3(0.45, 0.2, 0.1);
uniform vec3 c4 : source_color = vec3(0.55, 0.45, 0.2);
uniform vec3 c5 : source_color = vec3(0.22, 0.22, 0.25);
uniform float layers = 9.0;      // layers per metre of height

varying vec3 lpos;
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 tint;

float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

vec3 pick(float id) {
	return id < 0.2 ? c0 : id < 0.36 ? c1 : id < 0.52 ? c2 : id < 0.7 ? c3 : id < 0.84 ? c4 : c5;
}

void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR;
}

void fragment() {
	// wavy squashed layers in world height, so stacked bales don't line up
	float along = wpos.x + wpos.z;
	float y = wpos.y + (noise(vec3(along * 1.7, 0.0, wpos.y)) - 0.5) * 0.18 + sin(along * 3.1 + wpos.y * 2.0) * 0.03;
	float ly = y * layers;
	float li = floor(ly);
	float lf = fract(ly);
	// each layer is broken into runs of different sheets along its length
	float seg = floor(along * (1.2 + hash(vec3(li, 1.0, 3.0)) * 1.6) + hash(vec3(li, 7.0, 1.0)) * 10.0);
	float id = hash(vec3(li, seg, 5.0));
	vec3 col = pick(id);
	col *= mix(vec3(1.0), tint.rgb * 1.4, 0.2);
	col *= 0.75 + 0.4 * noise(wpos * vec3(6.0, 30.0, 6.0));
	// dark gaps between layers, crumpled bright edge on top of each sheet
	float gap = smoothstep(0.16, 0.0, lf) + smoothstep(0.88, 1.0, lf) * 0.6;
	float lip = smoothstep(0.75, 0.86, lf) * (1.0 - smoothstep(0.9, 1.0, lf));
	// rust, more in the gaps
	float rr = smoothstep(0.5, 0.72, noise(wpos * 1.4 + 2.0) * 0.6 + noise(wpos * 5.0) * 0.4 + gap * 0.2);
	vec3 rust_c = mix(vec3(0.15, 0.06, 0.025), vec3(0.45, 0.19, 0.07), noise(wpos * 9.0));
	col = mix(col, rust_c, rr * 0.8);
	col = mix(col, vec3(0.62, 0.62, 0.64), lip * 0.35 * (1.0 - rr));
	col *= 1.0 - gap * 0.85;
	// the top face of a bale is crushed flat: show it as a crumpled lid
	float top = smoothstep(0.7, 0.95, wnrm.y);
	col = mix(col, pick(hash(floor(wpos * 1.6))) * (0.7 + 0.4 * noise(wpos * 8.0)), top * 0.7);
	ALBEDO = col;
	METALLIC = clamp(0.55 + lip * 0.3 - rr * 0.5, 0.0, 1.0);
	ROUGHNESS = clamp(0.42 + rr * 0.45 + gap * 0.3 - lip * 0.15, 0.08, 1.0);
	// layered relief from the gaps (screen-space derivative bump)
	float h = (1.0 - gap) * 0.6 + lip * 0.4;
	vec2 g = vec2(dFdx(h), dFdy(h)) / max(length(fwidth(wpos)), 1e-4);
	NORMAL = normalize(NORMAL + vec3(g, 0.0) * 0.02 * (1.0 - top));
	AO = 1.0 - gap * 0.7;
	AO_LIGHT_AFFECT = 0.5;
}

// Weathered garden surfaces for the Roof Gardens (scripts/level/gardens/gardens_look.gd):
//   kind 0  stained planter wood: grain along each plank's long axis, sun-bleached silver on top faces and
//           edges, damp dark wood and moss creeping up from the soil line
//   kind 1  garden stone: warm limestone with speckle, worn pale edges, moss in the low spots and on top
//   kind 2  bark: deep vertical furrows, moss on the shaded side
// Box pieces get rounded, light-catching edges (same trick as painted_steel.gdshader): MultiMeshes of unit
// boxes set unit_half = 0.5, single BoxMesh pieces pass their half size in the box_half instance uniform.
// Relief is bump-mapped from the procedural height (no textures).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int kind = 0;
uniform vec4 base_col : source_color = vec4(0.45, 0.28, 0.16, 1.0);
uniform vec4 moss_col : source_color = vec4(0.26, 0.38, 0.12, 1.0);
uniform float moss = 0.6;
uniform float weather = 0.7;
uniform float bump = 0.6;
uniform float bevel = 0.03;
uniform float unit_half = 0.0;
instance uniform vec3 box_half = vec3(0.0);

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 half_s;
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
	float n1 = fbm3(wpos * 1.3);
	float n2 = noise(wpos * 7.0);
	// ---- distance to the nearest box edge, and the bevel direction
	float edge_d = 10.0;
	vec3 bend = vec3(0.0);
	float bot_d = 10.0;
	vec3 an = abs(lnrm);
	if (half_s.x > 0.0) {
		vec3 d = half_s - abs(lpos);
		vec3 dd = d + an * 100.0;
		edge_d = min(min(dd.x, dd.y), dd.z);
		vec3 w = 1.0 - clamp(dd / bevel, 0.0, 1.0);
		bend = sign(lpos) * w * w * (1.0 - an);
		bot_d = half_s.y + lpos.y;
	}
	float up = clamp(wnrm.y, 0.0, 1.0);
	float edge_w = 1.0 - smoothstep(0.0, 0.07, edge_d + (n2 - 0.5) * 0.04);
	vec3 c;
	float h;
	float rough;
	float ridge = 0.0;
	if (kind == 0) {
		// grain runs along the plank's longest axis
		vec3 g = lpos;
		if (half_s.x > 0.0) {
			if (half_s.x >= half_s.y && half_s.x >= half_s.z) g = lpos.yxz;
			else if (half_s.z >= half_s.y) g = lpos.xzy;
		}
		float grain = noise(vec3(g.x * 26.0, g.y * 1.4, g.z * 26.0)) * 0.6 + noise(vec3(g.x * 70.0, g.y * 3.0, g.z * 70.0)) * 0.4;
		float rings = smoothstep(0.35, 0.6, fract(grain * 4.0 + n1));
		c = base_col.rgb * (0.78 + 0.32 * grain) * (0.92 + 0.12 * rings);
		// sun-bleached silver on top faces and worn edges
		float bleach = clamp(up * 0.55 + edge_w * 0.6, 0.0, 1.0) * weather * smoothstep(0.3, 0.7, n1 + 0.2);
		c = mix(c, vec3(0.6, 0.55, 0.48) * (0.85 + 0.3 * grain), bleach * 0.55);
		h = grain * 0.6 + rings * 0.3;
		rough = 0.72 + 0.15 * grain;
	} else if (kind == 1) {
		float speck = smoothstep(0.7, 0.9, noise(wpos * 23.0));
		c = base_col.rgb * (0.82 + 0.3 * n1) * (1.0 - speck * 0.25);
		c = mix(c, vec3(0.82, 0.78, 0.7), edge_w * 0.35 * weather);
		h = n1 * 0.7 + n2 * 0.3;
		rough = 0.85;
	} else {
		float fur = noise(vec3(wpos.x * 5.5, wpos.y * 0.55, wpos.z * 5.5));
		float fur2 = noise(vec3(wpos.x * 13.0, wpos.y * 1.6, wpos.z * 13.0));
		ridge = 1.0 - abs(fur * 2.0 - 1.0);
		c = base_col.rgb * (0.55 + 0.6 * ridge) * (0.9 + 0.2 * fur2);
		h = ridge * 0.8 + fur2 * 0.2;
		rough = 0.9;
	}
	// ---- damp and moss: up from the bottom of the piece, in low spots, on the shaded north side of bark
	float damp = exp(-bot_d * 3.0) * 0.8;
	float mm = smoothstep(0.5, 0.75, n1 + damp * 0.5 + up * 0.15 - h * 0.25) * moss;
	if (kind == 2) mm = smoothstep(0.45, 0.7, n1 + clamp(-wnrm.z, 0.0, 1.0) * 0.35 + (1.0 - abs(wnrm.y)) * 0.1 - ridge * 0.2) * moss;
	c *= 1.0 - damp * 0.45;
	c = mix(c, moss_col.rgb * (0.8 + 0.4 * n2), clamp(mm, 0.0, 0.9));
	ALBEDO = c;
	ROUGHNESS = clamp(rough - damp * 0.25, 0.3, 1.0);
	SPECULAR = 0.35;
	// ---- relief: bump from the height field, plus the bevel
	float hh = (h + mm * 0.4) * bump * 0.012;     // metres of relief
	vec3 dpdx = dFdx(VERTEX); vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(hh); float dhy = dFdy(hh);
	vec3 r1 = cross(dpdy, NORMAL); vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	if (half_s.x > 0.0) {
		vec3 vb = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bend, 0.0)).xyz + vec3(1e-5));
		NORMAL = normalize(NORMAL + vb * length(bend) * 0.9);
	}
}

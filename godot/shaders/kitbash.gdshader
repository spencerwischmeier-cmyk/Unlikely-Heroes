// Hand-finished look for the Junkyard's plain blocks and cylinders (areas/y_junk_retrofit.gd), so they match
// the bevelled HD scrap. The shape is known from instance uniforms (half extents in local space, cylinder
// flag), so edges and rims are found procedurally: paint chips to bare steel along edges, rust streaks run
// down from top edges, panel seams and rivet rows break up big faces, grime pools at the foot and dust
// settles on top. `wood` switches to planks (grain, dark seams, worn pale edges).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_col : source_color = vec3(0.6, 0.4, 0.25);
uniform float metal = 0.3;
uniform float wood = 0.0;
uniform float rust = 0.55;
uniform float chip = 0.8;
uniform float grime = 0.65;
uniform float panel = 1.6;           // metres between panel seams on big faces
uniform sampler2D pit_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

instance uniform vec3 half_ext = vec3(0.5);
instance uniform float is_cyl = 0.0;

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
	lpos = VERTEX;
	lnrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// distance (m) to the nearest edge, and to the top edge
float foot_r(float y, float n) { return (1.0 - smoothstep(0.0, 0.35 + 0.6 * n, y)) * 0.5; }

vec2 edge_dist() {
	vec3 h = max(half_ext, vec3(0.001));
	vec3 d = h - abs(lpos);               // distance to each face plane
	if (is_cyl > 0.5) {
		float r = length(lpos.xz);
		float rd = max(h.x - r, 0.0);
		float cap = d.y;
		// rims are where the side meets a cap
		float e = (abs(lnrm.y) > 0.5) ? rd : cap;
		return vec2(e, lpos.y > 0.0 ? cap : 99.0);
	}
	// on a face, the edges are the other two axes' planes
	vec3 an = abs(lnrm);
	float e;
	if (an.x > an.y && an.x > an.z) e = min(d.y, d.z);
	else if (an.y > an.z) e = min(d.x, d.z);
	else e = min(d.x, d.y);
	return vec2(e, d.y);
}

void fragment() {
	vec2 ed = edge_dist();
	float n1 = fbm3(wpos * 1.3);
	float n2 = noise(wpos * 9.0);
	float side = 1.0 - abs(wnrm.y);
	float up = clamp(wnrm.y, 0.0, 1.0);
	vec3 h = half_ext;
	// face coordinates for seams/rivets: local position along the face's two axes
	vec3 an = abs(lnrm);
	vec2 fc = (an.x > an.y && an.x > an.z) ? lpos.zy : (an.y > an.z ? lpos.xz : lpos.xy);
	if (is_cyl > 0.5 && an.y < 0.5) fc = vec2(atan(lpos.z, lpos.x) * h.x, lpos.y);
	vec3 c; float met; float rough; float cc = 0.0; float nd = 0.4;
	float edge = 1.0 - smoothstep(0.0, 0.09 + 0.05 * n1, ed.x);
	if (wood > 0.5) {
		// planks: grain along the long axis, dark seams every ~0.22 m, pale worn edges
		float across = (h.x > h.z) ? fc.y : fc.x;
		float along = (h.x > h.z) ? fc.x : fc.y;
		float plank = floor(across / 0.22);
		float seam = smoothstep(0.44, 0.49, abs(fract(across / 0.22) - 0.5));
		float grain = noise(vec3(along * 0.7, across * 26.0, plank * 3.1)) * 0.6 + noise(vec3(along * 3.0, across * 60.0, plank)) * 0.4;
		vec3 pc = base_col * (0.78 + 0.32 * hash(vec3(plank, 1.0, 2.0))) * (0.82 + 0.28 * grain);
		c = mix(pc, pc * 0.35, seam);
		c = mix(c, c * 1.35 + 0.05, edge * 0.7);
		met = 0.0; rough = 0.78 - 0.1 * edge; nd = 0.25 + seam;
	} else {
		vec3 paint = base_col * 0.78 * (0.8 + 0.32 * n1);
		// panel seams and rivet rows on faces big enough to carry them
		vec2 g = fc / panel;
		vec2 gf = abs(fract(g + 0.5) - 0.5) * panel;   // metres to nearest seam
		float big = step(panel * 0.9, max(abs(fc.x), abs(fc.y)) * 2.0);
		float seam = big * (1.0 - smoothstep(0.012, 0.03, min(gf.x, gf.y)));
		vec2 rv = abs(fract(fc / 0.16) - 0.5) * 0.16;
		float row = 1.0 - smoothstep(0.06, 0.075, min(gf.x, gf.y));
		float rivet = big * row * (1.0 - smoothstep(0.012, 0.02, length(rv)));
		// chipped edges (and the occasional scratch)
		float chipm = smoothstep(0.45, 0.62, edge * chip + (n2 - 0.5) * 0.6 + (n1 - 0.5) * 0.3);
		chipm = max(chipm, smoothstep(0.92, 0.97, noise(wpos * vec3(21.0, 2.5, 21.0))) * 0.7);
		vec3 steel = vec3(0.5, 0.5, 0.52) * (0.75 + 0.35 * n2);
		// rust: blooms, in seams, and streaks running down the sides from the top edge
		float streak = side * (1.0 - smoothstep(0.0, 0.9 + 1.2 * noise(vec3(wpos.x * 3.0, 0.0, wpos.z * 3.0)), ed.y))
			* smoothstep(0.45, 0.8, noise(vec3(wpos.x * 5.0 + wpos.z * 5.0, wpos.y * 0.4, 0.0)));
		float rr = smoothstep(0.46, 0.7, fbm3(wpos * 0.7 + 5.0)) + seam * 0.6 + streak * 0.9 + chipm * 0.3 + foot_r(lpos.y + half_ext.y, n1);
		rr = clamp(rr * rust, 0.0, 1.0);
		vec3 rust_c = mix(vec3(0.17, 0.065, 0.03), vec3(0.55, 0.24, 0.09), noise(wpos * 4.0));
		c = mix(paint, steel, chipm);
		c = mix(c, rust_c, rr);
		c *= 1.0 - seam * 0.55;
		c = mix(c, steel * 0.8, rivet);
		met = mix(0.15 + metal * 0.3, 0.9, max(chipm, rivet)) * (1.0 - rr);
		rough = clamp(mix(0.4 + 0.18 * n1, 0.28, chipm) + rr * 0.45, 0.08, 1.0);
		cc = (1.0 - chipm) * (1.0 - rr) * 0.3;
		nd = 0.35 + rr * 1.2 + seam;
	}
	// grime pools at the foot, darkens undersides; dust and oil film on top faces
	float foot = 1.0 - smoothstep(0.0, 0.5 + 0.5 * n1, lpos.y + h.y);
	c *= 1.0 - grime * clamp(foot * 0.55 + clamp(-wnrm.y, 0.0, 1.0) * 0.35, 0.0, 0.8);
	c = mix(c, vec3(0.4, 0.34, 0.28), up * 0.22 * grime * smoothstep(0.35, 0.7, n1));
	ALBEDO = c;
	METALLIC = met;
	ROUGHNESS = clamp(rough + up * 0.08, 0.05, 1.0);
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.35;
	vec3 an2 = abs(wnrm);
	vec2 tuv = (an2.x > an2.y && an2.x > an2.z) ? wpos.zy : (an2.y > an2.z ? wpos.xz : wpos.xy);
	NORMAL_MAP = texture(pit_nrm, tuv * 0.9).rgb;
	NORMAL_MAP_DEPTH = nd;
}

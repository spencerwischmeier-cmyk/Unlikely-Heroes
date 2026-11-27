// Leafy foliage for the Roof Gardens (scripts/level/gardens/gardens_look.gd builds the meshes).
// Every bush, hedge, tree crown and vine is a clump of small cards; each card is cut into a little spray of
// pointed leaves here (alpha scissor), so silhouettes are ragged and leafy instead of smooth balls.
//   - normals come from the clump's centre (baked into the mesh), so a clump shades as one soft volume
//   - UV2.x = how far out the card sits (0 core .. 1 outer): inner leaves darken (fake occlusion), outer
//     leaves sway more in the wind; UV2.y = a per-card random for hue and shape variation
//   - golden-hour translucency: leaves glow warm when the sun is behind them
// The clump's colour comes from the MultiMesh instance colour, as with the old blob foliage.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float sway = 0.07;
uniform float flutter = 0.025;
uniform float translucency = 0.55;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.86, 0.45);
uniform float leaf_width = 0.17;

varying vec3 tint;
varying vec2 info;
varying vec3 wpos;

void vertex() {
	tint = COLOR.rgb;
	info = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 org = MODEL_MATRIX[3].xyz;
	float ph = org.x * 0.31 + org.z * 0.23;
	float outer = info.x;
	// whole-clump sway plus a faster per-card flutter
	VERTEX.x += sin(TIME * 1.25 + ph) * sway * outer;
	VERTEX.z += cos(TIME * 1.05 + ph * 1.3) * sway * outer * 0.8;
	VERTEX += NORMAL * sin(TIME * 4.3 + info.y * 40.0 + ph) * flutter * outer;
}

// one pointed leaf growing from `base` along angle `a` (UV space)
float leaf(vec2 uv, vec2 base, float a, float len, float wid) {
	vec2 d = uv - base;
	vec2 r = vec2(d.x * cos(a) + d.y * sin(a), -d.x * sin(a) + d.y * cos(a));
	float t = r.x / len;
	if (t < 0.0 || t > 1.0) return 0.0;
	float w = wid * pow(sin(3.14159 * pow(t, 0.75)), 0.8);
	return 1.0 - smoothstep(w * 0.85, w, abs(r.y));
}

void fragment() {
	float rnd = info.y;
	vec2 uv = UV;
	if (rnd > 0.5) uv.x = 1.0 - uv.x;
	vec2 b = vec2(0.5, 0.04);
	float wid = leaf_width * (0.85 + 0.3 * fract(rnd * 7.3));
	float m = leaf(uv, b, 1.5708 + (rnd - 0.5) * 0.3, 0.92, wid);
	m = max(m, leaf(uv, b + vec2(0.0, 0.12), 0.85 + rnd * 0.25, 0.62, wid * 0.85));
	m = max(m, leaf(uv, b + vec2(0.0, 0.22), 2.3 - rnd * 0.25, 0.6, wid * 0.85));
	m = max(m, leaf(uv, b + vec2(0.0, 0.02), 0.35, 0.45, wid * 0.7) * step(0.35, rnd));
	// stem
	m = max(m, (1.0 - smoothstep(0.012, 0.02, abs(uv.x - 0.5))) * step(uv.y, 0.3));
	ALPHA = m;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// colour: instance tint, per-card hue jitter, darker toward the clump's core, sunlit tips warmer
	float ao = mix(0.38, 1.0, smoothstep(0.0, 1.0, info.x));
	vec3 c = tint * (0.82 + 0.36 * rnd);
	c = mix(c, c * vec3(1.12, 1.08, 0.72), fract(rnd * 13.7) * 0.35);
	// a lighter midrib
	float rib = 1.0 - smoothstep(0.0, 0.03, abs(uv.x - 0.5));
	c *= 1.0 + rib * 0.15;
	ALBEDO = c * ao;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	BACKLIGHT = c * sun_tint * translucency * ao;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	RIM = 0.25;
	RIM_TINT = 0.5;
}

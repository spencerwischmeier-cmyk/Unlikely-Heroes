// Skyharbor ground: one shader for every area's floor (see scripts/level/ground/ground.gd).
// Top faces sample the area's layer of the ground texture array in world XZ (with an anti-tiling second
// sample for organic surfaces), then add large-scale colour variation, grime that gathers toward the
// slab's edges, moss in the low spots, oil stains and glossy puddles. Side faces use a triplanar side
// layer (stone curbs, planks, steel...). Albedo A = roughness, normal A = height.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float layer = 0.0;
uniform float side_layer = 8.0;
uniform float tile_m = 6.0;
uniform float side_m = 3.0;
uniform float rot = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 side_tint : source_color = vec4(1.0);
uniform float organic = 0.0;
uniform float puddles = 0.0;
uniform float moss = 0.0;
uniform float oil = 0.0;
uniform float edge_grime = 0.5;
uniform vec3 grime_col : source_color = vec3(0.42, 0.36, 0.3);
uniform vec3 moss_col : source_color = vec3(0.33, 0.47, 0.17);
uniform float metal = 0.0;
uniform float rough_mul = 1.0;
uniform float nrm_depth = 1.0;
uniform float variation = 1.0;
instance uniform vec4 rect = vec4(-100000.0, -100000.0, 100000.0, 100000.0);
instance uniform float seed = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tnorm(vec4 n, float depth) {
	vec3 t = n.xyz * 2.0 - 1.0;
	t.xy *= depth;
	return normalize(t);
}

void fragment() {
	vec3 col; float rough; vec3 wn; float h = 0.5;
	float up = wnrm.y;
	if (up > 0.6) {
		// ---------------- top face
		float cr = cos(rot), sr = sin(rot);
		mat2 R = mat2(vec2(cr, sr), vec2(-sr, cr));
		vec2 uv = R * (wpos.xz / tile_m) + vec2(seed * 0.37, seed * 0.61);
		vec4 a = texture(alb, vec3(uv, layer));
		vec4 n = texture(nrm, vec3(uv, layer));
		vec4 mac = texture(macro, wpos.xz / 70.0 + seed * 0.13);
		vec4 mac2 = texture(macro, wpos.xz / 19.0 + vec2(0.31, 0.77));
		if (organic > 0.0) {
			vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.87 + vec2(0.43, 0.19);
			float b = smoothstep(0.42, 0.58, mac.g) * organic;
			if (b > 0.001) {
				a = mix(a, texture(alb, vec3(uv2, layer)), b);
				n = mix(n, texture(nrm, vec3(uv2, layer)), b);
			}
		}
		h = n.a;
		col = a.rgb * tint.rgb;
		rough = a.a * rough_mul;
		// large-scale colour drift so no two patches of floor look alike
		col *= mix(1.0, mix(0.8, 1.14, mac.r) * mix(0.93, 1.05, mac2.b), variation);
		col = mix(col, col * vec3(1.05, 1.0, 0.92), smoothstep(0.55, 0.8, mac.g) * 0.5 * variation);
		// grime and dust gathering toward the slab's edges
		float e = min(min(wpos.x - rect.x, rect.z - wpos.x), min(wpos.z - rect.y, rect.w - wpos.z));
		float eg = (1.0 - smoothstep(0.0, 1.8, e + (mac2.g - 0.5) * 1.6)) * edge_grime;
		col = mix(col, col * grime_col * 1.7, eg);
		// moss / weeds in the low spots
		float mo = smoothstep(0.5, 0.72, mac.g + (0.5 - h) * 0.7 + eg * 0.3) * moss * smoothstep(0.62, 0.32, h);
		col = mix(col, moss_col * (0.75 + 0.5 * mac2.b), mo);
		// oil stains
		float oi = smoothstep(0.68, 0.74, mac2.r * 0.75 + mac.b * 0.25) * oil;
		col *= 1.0 - oi * 0.55;
		// puddles: dark and glossy, flat
		float pw = smoothstep(0.69, 0.73, mac.b + (0.5 - h) * 0.3 + (1.0 - mac.r) * 0.08) * puddles;
		col *= 1.0 - pw * 0.4;
		rough = mix(rough, 0.04, pw);
		rough = mix(rough, 0.3, oi);
		rough = clamp(rough + mo * 0.2, 0.04, 1.0);
		vec3 t = tnorm(n, nrm_depth * (1.0 - pw));
		vec2 d = transpose(R) * vec2(t.x, -t.y);
		wn = normalize(vec3(d.x, t.z, d.y));
	} else {
		// ---------------- side faces: triplanar on X and Z
		vec3 w = pow(abs(wnrm), vec3(4.0));
		float wx = w.x / (w.x + w.z + 1e-4);
		vec2 ux = vec2(wpos.z * sign(wnrm.x), -wpos.y) / side_m + seed * 0.21;
		vec2 uz = vec2(-wpos.x * sign(wnrm.z), -wpos.y) / side_m + seed * 0.21;
		vec4 ax = texture(alb, vec3(ux, side_layer)), az = texture(alb, vec3(uz, side_layer));
		vec4 nx = texture(nrm, vec3(ux, side_layer)), nz = texture(nrm, vec3(uz, side_layer));
		vec4 a = mix(az, ax, wx);
		col = a.rgb * side_tint.rgb;
		rough = a.a;
		vec3 tx = tnorm(nx, nrm_depth), tz = tnorm(nz, nrm_depth);
		vec3 wnx = normalize(vec3(tx.z * sign(wnrm.x), tx.y, tx.x * sign(wnrm.x)));
		vec3 wnz = normalize(vec3(-tz.x * sign(wnrm.z), tz.y, tz.z * sign(wnrm.z)));
		wn = normalize(mix(wnz, wnx, wx));
		if (up < -0.6) wn = wnrm;
		// soot streaks running down
		vec4 mac = texture(macro, vec2(wpos.x + wpos.z, wpos.y * 0.25) / 23.0);
		col *= 1.0 - smoothstep(0.5, 0.85, mac.a) * 0.25 * variation;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

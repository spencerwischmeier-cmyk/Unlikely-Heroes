// Garden water for the Roof Gardens (swapped in by scripts/level/gardens/gardens_look.gd over the kit's flat
// water): clear water that shows its depth, with refraction, a Fresnel sky sheen, soft foam where it meets
// the stone and moving caustic glints on the bottom. Keeps the kit's `flow`, `deep` and `shallow` uniforms.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec2 flow = vec2(0.0, 0.0);
uniform vec3 deep : source_color = vec3(0.04, 0.22, 0.24);
uniform vec3 shallow : source_color = vec3(0.3, 0.62, 0.5);
uniform vec3 foam_col : source_color = vec3(0.92, 0.96, 0.95);
uniform float clarity = 0.9;          // metres of water before it turns fully deep-coloured
uniform float refract_amt = 0.035;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 wpos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
// ripple height: two layers of noise drifting against each other, plus the flow direction
float ripple(vec2 p) {
	vec2 f = flow * TIME * 1.4;
	return n2(p * 2.2 - f + TIME * vec2(0.13, 0.07)) * 0.55 + n2(p * 4.7 - f * 1.3 - TIME * vec2(0.09, 0.17) + 7.0) * 0.45;
}
// cheap caustic net: bright where two warped cell patterns meet
float caustic(vec2 p) {
	vec2 q = p * 1.6 + vec2(n2(p * 0.9 + TIME * 0.3), n2(p * 0.9 - TIME * 0.27 + 3.0)) * 1.4;
	float a = abs(sin(q.x * 3.1 + TIME * 0.8) + sin(q.y * 2.7 - TIME * 0.6));
	return pow(clamp(1.0 - a * 0.5, 0.0, 1.0), 6.0);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

float scene_depth(vec2 suv) {
	float d = textureLod(depth_tex, suv, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d, 1.0);
	return -vp.z / vp.w;
}

void fragment() {
	vec2 p = wpos.xz;
	float e = 0.06;
	float h0 = ripple(p);
	vec2 g = vec2(ripple(p + vec2(e, 0.0)) - h0, ripple(p + vec2(0.0, e)) - h0) / e;
	vec3 wn = normalize(vec3(-g.x * 0.12, 1.0, -g.y * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float surf = -VERTEX.z;
	// how much water lies between the surface and whatever is behind it
	float thick0 = max(scene_depth(SCREEN_UV) - surf, 0.0);
	vec2 off = g * refract_amt * clamp(thick0 * 2.0, 0.0, 1.0);
	vec2 ruv = SCREEN_UV + off;
	float thick = scene_depth(ruv) - surf;
	if (thick < 0.0) { ruv = SCREEN_UV; thick = thick0; }   // don't refract things in front of the water
	float k = 1.0 - exp(-thick / clarity);
	vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;
	// caustics dance on the bottom where the water is shallow
	behind *= 1.0 + caustic(p + g * 0.3) * 0.9 * (1.0 - k) * clamp(thick * 4.0, 0.0, 1.0);
	vec3 body = mix(shallow, deep, smoothstep(0.0, 1.0, k));
	vec3 col = mix(behind * mix(vec3(1.0), shallow * 1.6, 0.5), body, clamp(k * 0.92, 0.0, 0.92));
	// foam lines where the water meets stone, broken up by noise
	float fn = n2(p * 6.0 - flow * TIME * 2.0 + TIME * 0.2);
	float foam = (1.0 - smoothstep(0.0, 0.18 + fn * 0.12, thick0)) * smoothstep(0.25, 0.6, fn + 0.25);
	foam = max(foam, smoothstep(0.78, 0.92, h0) * length(flow) * 0.6);
	col = mix(col, foam_col, clamp(foam, 0.0, 1.0) * 0.8);
	// the colour arrives through EMISSION so the refracted scene isn't lit twice; ALBEDO stays dark
	// and the specular/Fresnel sky sheen comes from the lighting and reflections
	ALBEDO = foam_col * foam * 0.4;
	EMISSION = col * (1.0 - foam * 0.6);
	ROUGHNESS = mix(0.04, 0.5, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	ALPHA = 1.0;
}

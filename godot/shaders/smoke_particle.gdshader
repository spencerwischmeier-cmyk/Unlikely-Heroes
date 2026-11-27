// Lit, billowing smoke puffs for chaos.gd: billboarded and spun particles with a noisy cauliflower edge, lit
// by the sun (with some light coming through), glowing ember-orange while young, soft against geometry.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

uniform float ember = 0.0;
uniform vec3 ember_col : source_color = vec3(1.0, 0.42, 0.12);
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec4 pc;
varying float age;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return 0.5 * noise(p) + 0.27 * noise(p * 2.1 + 3.7) + 0.15 * noise(p * 4.3 + 1.3) + 0.08 * noise(p * 8.9); }

void vertex() {
	float a = INSTANCE_CUSTOM.x;
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	w = w * mat4(vec4(cos(a), -sin(a), 0, 0), vec4(sin(a), cos(a), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	pc = COLOR;
	age = INSTANCE_CUSTOM.y;
	seed = float(INSTANCE_ID) * 3.17;
}

void fragment() {
	vec2 q = UV - 0.5;
	float n = fbm(UV * 3.2 + seed + vec2(0.0, TIME * 0.05));
	float r = length(q) * 2.0 + (n - 0.5) * 0.9;
	float a = smoothstep(1.0, 0.45, r);
	// fake rounded normal so the puffs shade like volumes
	vec3 nrm = normalize(vec3(q * 1.6 + (vec2(n) - 0.5) * 0.6, 0.6));
	NORMAL = nrm;
	float d = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0); vp.xyz /= vp.w;
	float soft = clamp((VERTEX.z - vp.z) / 1.2, 0.0, 1.0);
	ALBEDO = pc.rgb * (0.75 + 0.5 * n);
	ALPHA = clamp(a * pc.a * soft * (0.7 + 0.6 * n), 0.0, 1.0);
	BACKLIGHT = vec3(0.35, 0.3, 0.26);
	EMISSION = ember_col * ember * pow(clamp(1.0 - age * 3.0, 0.0, 1.0), 2.0) * a;
}

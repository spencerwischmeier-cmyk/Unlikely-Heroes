// Flame tongues for chaos.gd fires: billboarded GPU particles, each a noisy teardrop that licks upward.
// Colour and fade come from the particle colour ramp; additive and unshaded so it glows into the bloom.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 2.6;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec4 pc;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return 0.5 * noise(p) + 0.3 * noise(p * 2.1 + 3.7) + 0.2 * noise(p * 4.3 + 1.3); }

void vertex() {
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	pc = COLOR;
	seed = float(INSTANCE_ID) * 7.31;
}

void fragment() {
	vec2 uv = UV;
	float up = 1.0 - uv.y;                       // 0 at the base, 1 at the tip
	float n = fbm(vec2(uv.x * 3.0 + seed, uv.y * 2.4 + TIME * 2.6 + seed));
	vec2 q = uv - vec2(0.5, 0.68);
	q.x += (n - 0.5) * 0.45 * up;                // the tongue wavers more near the tip
	q.x *= 2.0 / (0.35 + 0.9 * (1.0 - up));      // narrower as it rises
	q.y *= 1.35;
	float shape = 1.0 - length(q) - (n - 0.5) * 0.5;
	float a = smoothstep(0.2, 0.55, shape);
	float core = smoothstep(0.45, 0.8, shape);
	vec3 col = mix(pc.rgb, vec3(1.0, 0.92, 0.7), core * 0.6);
	// soft where it meets geometry
	float d = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0); vp.xyz /= vp.w;
	float soft = clamp((VERTEX.z - vp.z) / 0.4, 0.0, 1.0);
	ALBEDO = col * intensity * a * pc.a * soft;
}

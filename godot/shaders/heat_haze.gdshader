// Heat shimmer above fires: a camera-facing quad that wobbles what's behind it (screen texture), strongest
// low and in the middle, fading out at the edges and the top.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.012;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 q = UV - 0.5;
	float mask = (1.0 - smoothstep(0.2, 0.5, abs(q.x))) * smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	vec2 n = vec2(noise(UV * vec2(6.0, 4.0) + vec2(0.0, TIME * 3.0)), noise(UV * vec2(5.0, 3.0) + vec2(7.0, TIME * 2.4))) - 0.5;
	vec2 suv = SCREEN_UV + n * strength * mask;
	ALBEDO = textureLod(screen_tex, suv, 0.0).rgb;
	ALPHA = mask;
}

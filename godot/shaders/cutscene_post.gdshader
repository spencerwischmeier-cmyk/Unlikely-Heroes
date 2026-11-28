// Cutscene camera post: camera motion blur (reprojects the depth buffer with last frame's camera),
// fine film grain and a touch of lens chromatic aberration at the edges. Drawn on a full-screen quad
// that cutscenes.gd parents to the cutscene camera.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform mat4 prev_view = mat4(1.0);   // last frame's world -> view
uniform float blur = 0.0;             // shutter (0 off .. 1 = full frame of motion)
uniform float grain = 0.025;
uniform float aberration = 0.0012;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col;
	vec2 vel = vec2(0.0);
	if (blur > 0.001) {
		float d = max(texture(depth_tex, uv).r, 0.00001);
		vec4 v = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
		v.xyz /= v.w;
		vec3 wp = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;
		vec4 pc = PROJECTION_MATRIX * (prev_view * vec4(wp, 1.0));
		vec2 puv = pc.xy / pc.w * 0.5 + 0.5;
		vel = (uv - puv) * blur;
		float l = length(vel);
		if (l > 0.035) vel *= 0.035 / l;
		if (l < 0.0007) vel = vec2(0.0);
	}
	vec2 dir = uv - 0.5;
	float ab = aberration * dot(dir, dir) * 4.0;
	col = vec3(0.0);
	const int N = 9;
	for (int i = 0; i < N; i++) {
		vec2 o = vel * (float(i) / float(N - 1) - 0.5);
		col.r += texture(screen_tex, uv + o + dir * ab).r;
		col.g += texture(screen_tex, uv + o).g;
		col.b += texture(screen_tex, uv + o - dir * ab).b;
	}
	col /= float(N);
	float g = hash(uv * vec2(1920.0, 1080.0) + fract(TIME * 13.7) * 91.0) - 0.5;
	col += g * grain * (0.35 + 0.65 * (1.0 - dot(col, vec3(0.333))));
	ALBEDO = col;
}

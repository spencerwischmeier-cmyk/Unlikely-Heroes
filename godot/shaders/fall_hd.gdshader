// Waterfall sheets for the Roof Gardens (swapped in by scripts/level/gardens/gardens_look.gd over the kit's
// flat falls): a glassy blue-green body that refracts what is behind it near the lip, breaking into white
// streaks and ragged edges as it falls, with a sun-caught sheen. Uses the kit's QuadMesh UVs
// (x across the sheet, y down it).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx, shadows_disabled;

uniform vec3 body_col : source_color = vec3(0.22, 0.55, 0.55);
uniform vec3 white_col : source_color = vec3(0.95, 0.98, 1.0);
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// streaks stretch as the water speeds up further down
	float sp = 1.0 + uv.y * 2.0;
	float s1 = n2(vec2(uv.x * 16.0, uv.y * 2.5 - t * 2.2 * sp));
	float s2 = n2(vec2(uv.x * 38.0 + 3.0, uv.y * 6.0 - t * 3.4 * sp));
	float s3 = n2(vec2(uv.x * 80.0 + 9.0, uv.y * 12.0 - t * 5.0 * sp));
	float streak = s1 * 0.5 + s2 * 0.32 + s3 * 0.18;
	// ragged sides that wobble, and the sheet thinning into spray toward the bottom
	float wob = (n2(vec2(uv.y * 8.0 - t * 3.0, 1.0)) - 0.5) * 0.12;
	float side = smoothstep(0.0, 0.14, uv.x + wob) * smoothstep(1.0, 0.86, uv.x - wob);
	float fade = smoothstep(1.0, 0.45, uv.y);
	float whiteness = smoothstep(0.42, 0.75, streak + uv.y * 0.35);
	float a = side * fade * mix(0.55, 0.95, whiteness);
	a *= smoothstep(0.1, 0.35, streak + 0.25 - uv.y * 0.15);
	// refract the scene behind the glassy upper part
	vec2 off = vec2((s1 - 0.5) * 0.02, (s2 - 0.5) * 0.01);
	vec3 behind = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	vec3 glass = mix(behind, body_col, 0.55);
	vec3 col = mix(glass, white_col, whiteness);
	// bumpy surface so the sun catches the streaks
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4((s2 - 0.5) * 0.6, 0.0, (s1 - 0.5) * 0.6, 0.0)).xyz);
	ALBEDO = white_col * whiteness * 0.6;
	EMISSION = col * mix(0.85, 0.45, whiteness);
	ROUGHNESS = mix(0.1, 0.55, whiteness);
	SPECULAR = 0.55;
	BACKLIGHT = vec3(0.4);
	ALPHA = clamp(a, 0.0, 1.0);
}

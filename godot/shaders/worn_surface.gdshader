// Weathered version of a tileable texture set (world triplanar): large-scale grime, rust blooms,
// moss and oil stains on upward faces, and wet patches with lower roughness. Used to age the docks.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tex_scale = 0.14;
uniform float metallic_v = 0.4;
uniform float rough_v = 0.6;
uniform float grime = 0.7;
uniform float rust = 0.6;
uniform float moss = 0.5;
uniform vec3 grime_col : source_color = vec3(0.32, 0.27, 0.22);
uniform vec3 rust_col : source_color = vec3(0.55, 0.26, 0.11);
uniform vec3 moss_col : source_color = vec3(0.33, 0.45, 0.18);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; } return v; }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0)); w /= (w.x + w.y + w.z);
	vec3 p = wpos * tex_scale;
	vec3 base = tri(albedo_tex, p, w).rgb * tint.rgb;
	float r = tri(rough_tex, p, w).r;
	vec3 nm = tri(normal_tex, p, w).rgb;
	float up = clamp(wnrm.y, 0.0, 1.0);
	float side = 1.0 - up;
	// big soft grime patches + streaks running down vertical faces
	float g = smoothstep(0.38, 0.68, fbm(wpos * 0.22 + 3.1)) * grime;
	float streak = smoothstep(0.55, 0.85, fbm(vec3(wpos.x * 1.6, wpos.y * 0.18, wpos.z * 1.6))) * side * grime;
	base = mix(base, base * grime_col * 1.5, clamp(g * 0.85 + streak * 0.6, 0.0, 1.0));
	base *= 0.9 + 0.2 * noise(wpos * 1.3);
	// rust blooms
	float rr = smoothstep(0.56, 0.76, fbm(wpos * 0.6 + 11.0)) * rust;
	float rspeck = smoothstep(0.7, 0.9, noise(wpos * 6.0)) * rr;
	base = mix(base, rust_col * (0.7 + 0.5 * noise(wpos * 3.0)), clamp(rr * 0.65 + rspeck * 0.5, 0.0, 1.0));
	// moss in patches on upward faces, hugging seams (dark texels)
	float lum = dot(tri(albedo_tex, p, w).rgb, vec3(0.333));
	float m = smoothstep(0.5, 0.72, fbm(wpos * 0.35 + 7.0)) * up * moss;
	m *= 0.45 + 0.55 * smoothstep(0.55, 0.35, lum);
	base = mix(base, moss_col * (0.75 + 0.5 * noise(wpos * 4.0)), clamp(m, 0.0, 1.0));
	// oil / wet patches: darker and glossy on the floor
	float wet = smoothstep(0.68, 0.74, fbm(wpos * 0.15 + 21.0)) * up;
	base *= 1.0 - wet * 0.35;
	ALBEDO = base;
	METALLIC = metallic_v * (1.0 - rr) * (1.0 - m);
	ROUGHNESS = clamp(mix(r * rough_v * 1.6, 0.12, wet) + rr * 0.3 + m * 0.3, 0.05, 1.0);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
}

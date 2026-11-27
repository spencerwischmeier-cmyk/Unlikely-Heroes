// Soft cumulus bank (FogVolume ellipsoid) below the islands: bright, slowly churning, thin at the edges.
shader_type fog;

uniform float density = 0.05;
uniform vec3 albedo : source_color = vec3(1.0, 0.95, 0.9);
uniform sampler3D noise_tex : repeat_enable;

void fog() {
	float edge = 1.0 - clamp(length(UVW - 0.5) * 2.0, 0.0, 1.0);
	float n = texture(noise_tex, WORLD_POSITION * 0.025 + vec3(TIME * 0.004, 0.0, TIME * 0.002)).r;
	float n2 = texture(noise_tex, WORLD_POSITION * 0.07 + vec3(0.0, TIME * 0.006, 0.0)).r;
	DENSITY = density * smoothstep(0.15, 0.6, edge * 0.8 + n * 0.5 + n2 * 0.25 - 0.35);
	ALBEDO = albedo;
}

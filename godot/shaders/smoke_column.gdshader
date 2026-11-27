// Volumetric smoke column (a FogVolume box, chaos.gd column()): a plume that widens and leans as it rises,
// churned by scrolling 3D noise, with an ember glow at its foot. Needs volumetric fog on (main.gd).
shader_type fog;

uniform float density = 1.6;
uniform vec3 albedo : source_color = vec3(0.035, 0.034, 0.033);
uniform vec3 emit : source_color = vec3(1.0, 0.38, 0.1);
uniform float emit_strength = 0.12;
uniform float lean = 0.18;
uniform sampler3D noise_tex : repeat_enable;

void fog() {
	vec3 p = UVW;                              // 0..1 inside the box
	float h = p.y;
	vec2 c = p.xz - vec2(0.5 + lean * h * h, 0.5);
	float r = length(c) / mix(0.12, 0.48, sqrt(h));
	float n = texture(noise_tex, WORLD_POSITION * 0.09 + vec3(0.0, -TIME * 0.12, TIME * 0.03)).r;
	float n2 = texture(noise_tex, WORLD_POSITION * 0.23 + vec3(TIME * 0.02, -TIME * 0.3, 0.0)).r;
	float d = smoothstep(1.0, 0.35, r + (n - 0.5) * 1.1 + (n2 - 0.5) * 0.5);
	d *= smoothstep(0.0, 0.06, h) * smoothstep(1.0, 0.65, h);
	DENSITY = density * d;
	ALBEDO = albedo;
	EMISSION = emit * emit_strength * smoothstep(0.12, 0.0, h) * d;
}

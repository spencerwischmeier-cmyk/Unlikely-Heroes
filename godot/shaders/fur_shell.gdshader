// One shell of Vesk's fur (shell texturing): the mesh pushed out along its normals, with strands cut
// out by a hashed grid in UV space. vesk_actor.gd chains ~10 of these as next passes, shell 0..1.
// The mask (textures/vesk_fur_mask.png, from art/face/fur_mask.py) keeps fur off armour, straps and the muzzle.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_enable;
uniform float shell = 0.5;
uniform float fur_len = 0.011;
uniform float density = 1500.0;
uniform float droop = 0.35;

varying float vmask;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	vmask = texture(mask_tex, UV).r;
	float h = fur_len * shell * vmask;
	VERTEX += NORMAL * h;
	vec3 down = normalize((inverse(MODEL_MATRIX) * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
	VERTEX += down * h * droop * shell;
}

void fragment() {
	if (vmask < 0.35) discard;
	vec2 cell = UV * density;
	vec2 id = floor(cell);
	float n = hash(id);
	vec2 f = fract(cell) - 0.5;
	f += (vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5) * 0.3;
	// each strand has its own height; it tapers toward the tip
	float tall = 0.35 + 0.65 * n;
	if (shell > tall * vmask) discard;
	float r = length(f) * 2.0;
	if (r > (1.0 - shell / tall) * 1.05) discard;
	vec3 base = texture(albedo_tex, UV).rgb;
	float ao = mix(0.5, 1.12, shell);
	ALBEDO = base * ao * (0.9 + 0.2 * n);
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = base * 0.35;
	RIM = 0.35;
	RIM_TINT = 0.6;
}

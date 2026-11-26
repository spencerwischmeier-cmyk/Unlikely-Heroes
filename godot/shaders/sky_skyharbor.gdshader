// Skyharbor sky: golden-hour gradient, sun halo, painterly cloud banks, a sea of clouds below the
// horizon, and a big ringed gas giant plus a small moon hanging in the sky. No TIME, so the radiance
// map is only rebuilt when the sun moves (cheap).
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.16, 0.38, 0.72);
uniform vec3 mid : source_color = vec3(0.45, 0.66, 0.86);
uniform vec3 horizon : source_color = vec3(0.98, 0.84, 0.62);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.9, 0.76);
uniform vec3 cloud_shade : source_color = vec3(0.56, 0.6, 0.76);
uniform vec3 sea_top : source_color = vec3(0.96, 0.88, 0.8);
uniform vec3 sea_deep : source_color = vec3(0.52, 0.6, 0.78);
uniform vec3 planet_dir = vec3(-0.6, 0.2, -0.77);
uniform float planet_size = 0.17;
uniform vec3 planet_a : source_color = vec3(0.93, 0.64, 0.46);
uniform vec3 planet_b : source_color = vec3(0.62, 0.42, 0.5);
uniform vec3 moon_dir = vec3(0.62, 0.42, -0.66);
uniform float energy = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

// a body in the sky: returns coverage in .a and its colour in .rgb
vec4 body(vec3 d, vec3 dir, float size, vec3 sun, bool banded, vec3 ca, vec3 cb) {
	dir = normalize(dir);
	vec3 right = normalize(cross(dir, vec3(0, 1, 0)));
	vec3 up = cross(right, dir);
	float fwd = dot(d, dir);
	if (fwd <= 0.0) return vec4(0.0);
	vec2 uv = vec2(dot(d, right), dot(d, up)) / (fwd * size);
	float r = length(uv);
	vec4 o = vec4(0.0);
	if (r < 1.0) {
		vec3 n = normalize(right * uv.x + up * uv.y - dir * sqrt(1.0 - r * r));
		float lit = clamp(dot(-n, -sun) * 0.5 + 0.5, 0.0, 1.0);
		lit = smoothstep(0.15, 0.9, lit);
		vec3 c;
		if (banded) {
			float band = uv.y * 7.0 + fbm(uv * vec2(1.5, 9.0)) * 1.6;
			c = mix(ca, cb, 0.5 + 0.5 * sin(band * 3.1));
			c = mix(c, ca * 1.15, smoothstep(0.55, 0.9, fbm(uv * 4.0 + 3.0)) * 0.5);
		} else {
			c = mix(ca, cb, fbm(uv * 3.5));
		}
		c *= mix(0.22, 1.15, lit);
		c += vec3(1.0, 0.8, 0.6) * pow(r, 6.0) * 0.35;   // rim scatter
		o = vec4(c, (1.0 - smoothstep(0.985, 1.0, r)));
	}
	if (banded) {
		// tilted ring: an ellipse in the planet's screen plane, hidden behind the planet's top half
		vec2 ru = vec2(uv.x * 0.94 + uv.y * 0.34, (uv.y * 0.94 - uv.x * 0.34) * 4.2);
		float rr = length(ru);
		float ring = smoothstep(1.35, 1.42, rr) * (1.0 - smoothstep(2.12, 2.25, rr));
		ring *= 0.6 + 0.4 * (0.5 + 0.5 * sin(rr * 38.0));
		bool behind = r < 1.0 && ru.y > 0.0;
		if (!behind && ring > 0.0) {
			vec3 rc = mix(vec3(0.95, 0.85, 0.72), vec3(0.75, 0.6, 0.55), fract(rr * 3.0)) * 0.95;
			o.rgb = mix(o.rgb, rc, ring * 0.85);
			o.a = max(o.a, ring * 0.85);
		}
	}
	return o;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = normalize(LIGHT0_DIRECTION);
	float h = d.y;
	float sun_d = max(dot(d, sun), 0.0);
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon, mid, smoothstep(0.0, 0.22, h));
		col = mix(col, zenith, smoothstep(0.2, 0.85, h));
		col += sun_glow * pow(sun_d, 6.0) * 0.55 * (1.0 - smoothstep(0.0, 0.6, h) * 0.5);
	} else {
		col = horizon;
	}
	if (!AT_CUBEMAP_PASS) {
		// big things in the sky (skipped in the radiance pass so they don't tint the ambient light)
		vec4 pl = body(d, planet_dir, planet_size, sun, true, planet_a, planet_b);
		col = mix(col, pl.rgb, pl.a * 0.92);
		vec4 mo = body(d, moon_dir, 0.045, sun, false, vec3(0.92, 0.9, 0.95), vec3(0.62, 0.62, 0.72));
		col = mix(col, mo.rgb, mo.a * 0.85);
	}
	// sun disk and halo
	col += vec3(1.0, 0.9, 0.7) * smoothstep(0.9993, 0.9997, sun_d) * 18.0;
	col += sun_glow * pow(sun_d, 120.0) * 2.0;
	// cloud banks above the horizon: fbm on a flattened dome
	if (h > -0.02) {
		vec2 cp = d.xz / (h + 0.18) * 1.4;
		float n = fbm(cp + vec2(3.0, 1.0));
		float wisps = fbm(cp * vec2(0.6, 2.4) + 7.0);
		float cov = smoothstep(0.52, 0.78, n * 0.7 + wisps * 0.45) * (1.0 - smoothstep(0.05, 0.55, h));
		float lit = 0.55 + 0.45 * fbm(cp * 2.0 + sun.xz * 2.0) + pow(sun_d, 4.0) * 0.6;
		vec3 cc = mix(cloud_shade, cloud_lit, clamp(lit, 0.0, 1.0));
		col = mix(col, cc, cov * 0.88);
	}
	// sea of clouds under the city
	if (h < 0.02) {
		vec2 sp = d.xz / max(-h + 0.04, 0.04) * 0.55;
		float billow = fbm(sp + 11.0);
		float top = smoothstep(0.35, 0.75, billow);
		vec3 sea = mix(sea_deep, sea_top, top);
		sea += sun_glow * pow(sun_d, 8.0) * 0.45 * top;
		float fade = (1.0 - smoothstep(-0.06, 0.02, h));
		col = mix(col, sea, fade);
		col = mix(col, horizon, smoothstep(-0.12, 0.0, h) * 0.55);
	}
	COLOR = col * energy;
}

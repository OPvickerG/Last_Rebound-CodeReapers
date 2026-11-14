// LAST REBOUND: storm sky with drifting clouds, lightning flashes and a dawn ending.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.04, 0.045, 0.065);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.17, 0.21);
uniform vec3 cloud_color : source_color = vec3(0.11, 0.12, 0.15);
uniform vec3 flash_color : source_color = vec3(0.75, 0.8, 1.0);
uniform float flash : hint_range(0.0, 2.0) = 0.0;
uniform float dawn : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dawn_top : source_color = vec3(0.22, 0.32, 0.5);
uniform vec3 dawn_horizon : source_color = vec3(1.0, 0.6, 0.32);
uniform vec3 sun_dir = vec3(0.3, 0.12, -1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 base = mix(horizon_color, top_color, smoothstep(0.0, 0.65, h));

	// Clouds projected onto a high plane, so they converge toward the horizon.
	vec2 uv = d.xz / (abs(h) + 0.18);
	float c1 = fbm(uv * 0.55 + vec2(TIME * 0.018, TIME * 0.008));
	float c2 = fbm(uv * 1.4 - vec2(TIME * 0.04, -TIME * 0.01));
	float clouds = smoothstep(0.38, 0.85, c1 * 0.75 + c2 * 0.4);
	float bright_edges = smoothstep(0.55, 0.9, c2) * clouds;

	vec3 col = mix(base, cloud_color, clouds * 0.9);
	// Lightning lights the clouds from inside.
	col += flash_color * flash * (0.18 + clouds * 0.9 + bright_edges * 0.6);
	// Below the horizon: the abyss.
	col = mix(col, horizon_color * 0.35, smoothstep(0.0, -0.35, h));

	// Dawn: the storm breaks.
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	vec3 dawn_col = mix(dawn_horizon, dawn_top, smoothstep(-0.05, 0.55, h));
	dawn_col += vec3(1.0, 0.8, 0.55) * (pow(s, 400.0) * 6.0 + pow(s, 12.0) * 0.6);
	dawn_col = mix(dawn_col, dawn_col * 0.7 + vec3(1.0, 0.68, 0.48) * 0.3, clouds * 0.7);
	dawn_col = mix(dawn_col, dawn_horizon * 0.3, smoothstep(0.0, -0.4, h));

	COLOR = mix(col, dawn_col, dawn);
}

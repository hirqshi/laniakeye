shader_type spatial;
render_mode cull_front, blend_add, depth_draw_never, unshaded, shadows_disabled;

// volumetric atmosphere shell, view-ray integral solved analytically
// (no raymarch loop -> no banding regardless of viewing angle, even
// standing on the surface looking at a near-tangent sky).
//
// COLOR: the pure per-channel-transmittance approach (rayleigh
// scattering blue more than red) technically produces a warmer tint on
// long grazing paths, but the effect is too subtle to read as a sunset
// once glow intensity is in a normal range - transmittance saturates
// toward the same near-zero value on all channels for long paths, so
// the color difference gets visually swamped. bringing back an
// explicit art-directed day/sunset color mix (same terminator_mask
// logic as the older fresnel-only shader) on top of the physically-
// shaped glow gives both: correct soft falloff/no banding from the
// analytic integral, and a visible warm terminator color.

uniform float planet_radius_m = 10.0;
uniform float outer_shell_height_m = 1.0;
uniform float inner_haze_height_m = 0.3;
uniform vec3 planet_center_world = vec3(0.0);

uniform vec3 rayleigh_coefficient: source_color = vec3(0.29, 0.53, 1.0);
uniform vec3 mie_coefficient: source_color = vec3(0.6, 0.6, 0.6);
uniform float mie_anisotropy: hint_range(0.0, 0.99) = 0.76;

uniform float atmosphere_density: hint_range(0.0, 5.0) = 1.0;
uniform float intensity: hint_range(0.0, 20.0) = 6.0;

uniform float outer_edge_softness: hint_range(0.0, 1.0) = 0.4;

// art-directed terminator color, mixed in on top of the physical glow.
uniform vec3 day_color: source_color = vec3(0.4, 0.7, 1.0);
uniform vec3 sunset_color: source_color = vec3(1.0, 0.5, 0.2);
uniform float terminator_width: hint_range(0.05, 1.0) = 0.3;
uniform float sunset_strength: hint_range(0.0, 3.0) = 1.5;

uniform vec3 light_direction = vec3(1.0, 0.0, 0.0);
uniform vec3 light_color: source_color = vec3(1.0, 0.95, 0.9);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ray_sphere_intersect(vec3 ray_origin, vec3 ray_dir, vec3 sphere_center, float radius) {
	vec3 offset = ray_origin - sphere_center;
	float a = dot(ray_dir, ray_dir);
	float b = 2.0 * dot(offset, ray_dir);
	float c = dot(offset, offset) - radius * radius;
	float discriminant = b * b - 4.0 * a * c;
	if (discriminant < 0.0) {
		return vec2(1.0, -1.0);
	}
	float sqrt_disc = sqrt(discriminant);
	return vec2((-b - sqrt_disc) / (2.0 * a), (-b + sqrt_disc) / (2.0 * a));
}

float phase_rayleigh(float cos_angle) {
	return 3.0 / (16.0 * PI) * (1.0 + cos_angle * cos_angle);
}

float phase_mie(float cos_angle, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_angle, 0.0001), 1.5));
}

// closed-form integral of exp(-height(s)/H) ds from s=0 to s=path_length,
// flat-atmosphere approximation (valid since inner_haze_height_m is tiny
// compared to planet_radius_m).
float analytic_optical_depth(float h0, float cos_angle, float path_length, float scale_height) {
	float safe_scale = max(scale_height, 0.0001);
	if (abs(cos_angle) < 0.001) {
		return exp(-h0 / safe_scale) * path_length;
	}
	float h_end = h0 + path_length * cos_angle;
	return (safe_scale / cos_angle) * (exp(-h0 / safe_scale) - exp(-h_end / safe_scale));
}

void fragment() {
	vec3 camera_pos = CAMERA_POSITION_WORLD;
	vec3 ray_dir = normalize(world_position - camera_pos);
	vec3 light_dir = normalize(light_direction);

	float outer_radius = planet_radius_m + outer_shell_height_m;
	vec2 outer_hit = ray_sphere_intersect(camera_pos, ray_dir, planet_center_world, outer_radius);

	float march_start = max(outer_hit.x, 0.0);
	float march_end = outer_hit.y;
	float path_length = march_end - march_start;

	vec3 final_albedo = vec3(0.0);
	float final_alpha = 0.0;

	if (path_length > 0.0) {
		vec3 path_origin = camera_pos + ray_dir * march_start;
		vec3 origin_up = normalize(path_origin - planet_center_world);
		float h0 = distance(path_origin, planet_center_world) - planet_radius_m;
		float cos_angle = dot(ray_dir, origin_up);

		float optical_depth = analytic_optical_depth(h0, cos_angle, path_length, inner_haze_height_m) * atmosphere_density;

		vec3 mid_point = camera_pos + ray_dir * (march_start + path_length * 0.5);
		vec3 mid_up = normalize(mid_point - planet_center_world);
		float signed_light_term = dot(mid_up, light_dir);
		float light_term = max(signed_light_term, 0.0);

		float cos_view_light = dot(ray_dir, light_dir);
		float phase_r = phase_rayleigh(cos_view_light);
		float phase_m = phase_mie(cos_view_light, mie_anisotropy);

		vec3 transmittance = exp(-(rayleigh_coefficient + mie_coefficient) * optical_depth);
		vec3 scattered = (vec3(1.0) - transmittance) * light_term;

		vec3 physical_color = (scattered * rayleigh_coefficient * phase_r + scattered * mie_coefficient * phase_m) * light_color * intensity;
		float glow_brightness = max(physical_color.r, max(physical_color.g, physical_color.b));

		// art-directed terminator tint: peaks where signed_light_term is
		// near zero (the day/night boundary), fades out toward both
		// full day and full night, matching the geometric terminator.
		float terminator_mask = 1.0 - smoothstep(0.0, terminator_width, abs(signed_light_term));

		vec3 tint = mix(day_color, sunset_color, terminator_mask);
		vec3 color = mix(physical_color, tint * glow_brightness * sunset_strength, terminator_mask);

		float shell_diameter_estimate = 2.0 * sqrt(max(outer_radius * outer_radius - planet_radius_m * planet_radius_m, 0.0001));
		float edge_fade = smoothstep(0.0, max(outer_edge_softness * shell_diameter_estimate, 0.0001), path_length);

		final_albedo = color * edge_fade;
		final_alpha = clamp(max(final_albedo.r, max(final_albedo.g, final_albedo.b)), 0.0, 1.0);
	}

	ALBEDO = final_albedo;
	ALPHA = final_alpha;
}
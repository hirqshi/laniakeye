shader_type spatial;
render_mode skip_vertex_transform, diffuse_burley, specular_schlick_ggx, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

#include "res://game/world/rendering/lk_far_system_common.gdshaderinc"

uniform vec3 active_ambient_linear = vec3(0.38, 0.45, 0.60);
uniform float active_day_ambient = 0.18;
uniform float active_night_ambient = 0.035;
uniform float active_horizon_fade_sine = 0.02;

uniform bool active_shell_valid = false;
uniform bool active_shell_stable = false;
uniform float active_shell_c = 0.0;

void fragment() {
	if (texture(scene_depth, SCREEN_UV).r > 0.0) { discard; }
	vec3 view_ray = normalize(VERTEX);
	vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * view_ray);
	float nearest = 1e30;
	float nearest_relative = 0.0;
	int winner = -1;
	for (int i = 0; i < 64; i++) {
		if (i >= body_count) { break; }
		vec3 center = body_spheres[i].xyz;
		float radius = body_spheres[i].w;
		float along = dot(center, ray);
		float hit = -1.0;
		if (i == 0) {
			// Only the OUTSIDE entry of active nominal sphere can be a fallback.
			// Never take the far exit through the planet and fill an open pit's sky.
			if (!active_shell_valid || along <= 0.0) { continue; }
			if (active_shell_stable) {
				float disc = along * along - active_shell_c;
				if (disc < 0.0) { continue; }
				float denominator = along + sqrt(max(disc, 0.0));
				if (denominator <= 0.0) { continue; }
				hit = active_shell_c / denominator;
			} else {
				vec3 perpendicular = center - along * ray;
				float disc = radius * radius - dot(perpendicular, perpendicular);
				if (disc < 0.0) { continue; }
				hit = along - sqrt(max(disc, 0.0));
			}
		} else {
			vec3 perpendicular = center - along * ray;
			float disc = radius * radius - dot(perpendicular, perpendicular);
			if (disc < 0.0) { continue; }
			float root = sqrt(max(disc, 0.0));
			hit = along - root;
			if (hit <= 0.0) { hit = along + root; }
		}
		if (hit <= 0.0) { continue; }
		float meters = hit * body_scales[i];
		if (meters < nearest) {
			nearest = meters;
			nearest_relative = hit;
			winner = i;
		}
	}
	if (winner < 0) { discard; }
	// NORMALIZE_GUARD_SURFACE_V1: cancellation can erase a tiny disc normal.
	// Do not use an arbitrary epsilon that would remove valid small discs.
	vec3 normal_delta = ray * nearest_relative - body_spheres[winner].xyz;
	if (!(dot(normal_delta, normal_delta) > 0.0)) { discard; }
	vec3 normal_system = normalize(normal_delta);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal_system);
	ALBEDO = vec3(0.0);
	EMISSION = vec3(0.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	IRRADIANCE = vec4(0.0, 0.0, 0.0, 1.0);
	RADIANCE = vec4(0.0, 0.0, 0.0, 1.0);
	if (winner == 0 && !debug_active_albedo) {
		ALBEDO = body_colors[0].rgb;
		ROUGHNESS = surface_roughness;
		METALLIC = surface_metallic;
		SPECULAR = surface_specular;
		// Missing sun direction is not an arbitrary horizon/daylight direction.
		float solar_altitude = -1.0;
		if (dot(body_suns[0], body_suns[0]) > 0.0) {
			solar_altitude = dot(normal_system, normalize(body_suns[0]));
		}
		float visibility = smoothstep(0.0, max(active_horizon_fade_sine, 0.00001), solar_altitude);
		float ambient_energy = mix(active_night_ambient, active_day_ambient, visibility);
		IRRADIANCE = vec4(active_ambient_linear * ambient_energy, 1.0);
		LIGHT_VERTEX = view_ray * nearest;
	} else if (winner == 0 || body_colors[winner].a > 0.5) {
		EMISSION = body_colors[winner].rgb;
	} else {
		float diffuse = 0.0;
		if (dot(body_suns[winner], body_suns[winner]) > 0.0) {
			diffuse = max(dot(normal_system, normalize(body_suns[winner])), 0.0);
		}
		EMISSION = body_colors[winner].rgb * (vec3(distant_ambient) + vec3(sun_energy * diffuse));
	}
	ALPHA = 1.0;
}

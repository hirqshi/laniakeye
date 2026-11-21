shader_type spatial;
// Match the flat StandardMaterial3D used by the integration terrain.
// No unshaded render mode: active surface uses Godot's normal lighting path.
render_mode skip_vertex_transform, diffuse_burley, specular_schlick_ggx, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

#include "res://world/rendering/lk_far_system_common.gdshaderinc"

void fragment() {
	if (texture(scene_depth, SCREEN_UV).r > 0.0 || active_inside) { discard; }
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
		vec3 perpendicular = center - along * ray;
		float disc = radius * radius - dot(perpendicular, perpendicular);
		if (disc < 0.0) { continue; }
		float root = sqrt(max(disc, 0.0));
		float hit = along - root;
		if (hit <= 0.0) { hit = along + root; }
		if (hit <= 0.0) { continue; }
		float meters = hit * body_scales[i];
		if (meters < nearest) {
			nearest = meters;
			nearest_relative = hit;
			winner = i;
		}
	}
	if (winner < 0) { discard; }
	float opacity = 1.0;
	if (winner == 0) {
		if (nearest <= active_cutoff_m) { discard; }
		opacity = smoothstep(active_cutoff_m, active_cutoff_m + max(active_fade_m, 1.0), nearest);
	}
	// Float32 cancellation can erase the hit normal of a tiny disc.
	// Reject only a non-positive squared length, not an arbitrary epsilon.
	vec3 normal_delta = ray * nearest_relative - body_spheres[winner].xyz;
	if (!(dot(normal_delta, normal_delta) > 0.0)) { discard; }
	vec3 normal_system = normalize(normal_delta);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal_system);
	// Default all branches to emission-only. Remote bodies must not be lit
	// by the observer's horizon-masked DirectionalLight3D.
	ALBEDO = vec3(0.0);
	EMISSION = vec3(0.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	if (winner == 0 && !debug_active_albedo) {
		ALBEDO = body_colors[0].rgb;
		ROUGHNESS = surface_roughness;
		METALLIC = surface_metallic;
		SPECULAR = surface_specular;
		// Actual analytic hit, in VIEW space, for lighting and shadow lookup.
		// This does not move the fullscreen geometry or write fake scene depth.
		LIGHT_VERTEX = view_ray * nearest;
	} else if (winner == 0 || body_colors[winner].a > 0.5) {
		EMISSION = body_colors[winner].rgb;
	} else {
		float diffuse = max(dot(normal_system, normalize(body_suns[winner])), 0.0);
		EMISSION = body_colors[winner].rgb * (vec3(distant_ambient) + vec3(sun_energy * diffuse));
	}
	ALPHA = opacity;
}

shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 center_relative = vec3(0.0, -1.0, 0.0);
uniform float radius_relative = 0.99;
uniform vec3 surface_color : source_color = vec3(0.35, 0.45, 0.3);
uniform vec3 direction_to_sun = vec3(0.35, 0.8, 0.4);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float opaque_depth = texture(scene_depth, SCREEN_UV).r;
	// Preserve every opaque near object; this pass only fills the background.
	if (opaque_depth > 0.0) {
		discard;
	}
	vec2 ndc_xy = SCREEN_UV * 2.0 - 1.0;
	vec4 view_point = INV_PROJECTION_MATRIX * vec4(ndc_xy, 1.0, 1.0);
	vec3 view_ray = normalize(view_point.xyz / view_point.w);
	vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * view_ray);
	float along_ray = dot(ray, center_relative);
	vec3 perpendicular = center_relative - along_ray * ray;
	float discriminant = radius_relative * radius_relative - dot(perpendicular, perpendicular);
	if (discriminant < 0.0 || along_ray <= 0.0) {
		discard;
	}
	float entry = along_ray - sqrt(max(discriminant, 0.0));
	if (entry <= 0.0) {
		discard;
	}
	vec3 normal = normalize(entry * ray - center_relative);
	float diffuse = max(dot(normal, normalize(direction_to_sun)), 0.0);
	ALBEDO = surface_color * (0.22 + 0.78 * diffuse);
	ALPHA = 1.0;
}

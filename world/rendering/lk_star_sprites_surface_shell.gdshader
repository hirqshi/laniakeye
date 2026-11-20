shader_type spatial;
render_mode unshaded, blend_add, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform int occluder_count = 0;
uniform vec4 occluder_spheres[64];
uniform bool observer_inside = false; // compatibility, not global sky suppression
uniform vec2 viewport_pixels = vec2(1280.0, 720.0);
uniform float star_gain = 0.8;

uniform bool active_shell_valid = false;
uniform bool active_shell_stable = false;
uniform float active_shell_c = 0.0;

varying vec3 star_linear_color;
varying float star_amplitude;

void vertex() {
	vec3 view_direction = mat3(VIEW_MATRIX) * INSTANCE_CUSTOM.xyz;
	float flux = max(INSTANCE_CUSTOM.w, 0.0);
	float radius_px = clamp(1.15 + 0.28 * log2(1.0 + flux), 1.15, 4.0);
	star_amplitude = min(16.0, 0.22 * pow(flux, 0.60)) * star_gain;
	star_linear_color = COLOR.rgb;
	if (view_direction.z >= -0.00001) {
		POSITION = vec4(2.0, 2.0, 0.0, 1.0);
	} else {
		vec4 clip = PROJECTION_MATRIX * vec4(view_direction, 1.0);
		clip.xy += VERTEX.xy * (2.0 * radius_px / max(viewport_pixels, vec2(1.0))) * clip.w;
		clip.z = 0.0;
		POSITION = clip;
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float radius = length(q);
	if (radius >= 1.0) { discard; }
	if (texture(scene_depth, SCREEN_UV).r > 0.0) { discard; }
	vec4 near_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * normalize(near_view.xyz / near_view.w));
	for (int i = 0; i < 64; i++) {
		if (i >= occluder_count) { break; }
		vec3 center = occluder_spheres[i].xyz;
		float along = dot(center, ray);
		if (i == 0) {
			if (!active_shell_valid || along <= 0.0) { continue; }
			if (active_shell_stable) {
				float disc = along * along - active_shell_c;
				if (disc < 0.0) { continue; }
				float denominator = along + sqrt(max(disc, 0.0));
				if (denominator > 0.0 && active_shell_c / denominator > 0.0) { discard; }
				continue;
			}
		}
		vec3 perpendicular = center - along * ray;
		float disc = occluder_spheres[i].w * occluder_spheres[i].w - dot(perpendicular, perpendicular);
		if (disc >= 0.0 && along + sqrt(max(disc, 0.0)) > 0.0) { discard; }
	}
	float psf = exp(-4.0 * radius * radius) * (1.0 - smoothstep(0.70, 1.0, radius));
	ALBEDO = star_linear_color * star_amplitude;
	ALPHA = psf;
}

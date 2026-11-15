shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D height_map : repeat_enable, filter_linear;
uniform vec3 center_relative = vec3(0.0, -1.0, 0.0);
uniform float radius_relative = 1.0;
uniform float height_limit_relative = 0.001;
uniform float meters_to_relative = 0.000001;
uniform float pixel_angle = 0.001;
uniform vec3 surface_color : source_color = vec3(0.35, 0.45, 0.3);
uniform vec3 direction_to_sun = vec3(0.353553, 0.707107, 0.612372);
uniform vec3 sunlight : source_color = vec3(1.2);
uniform vec3 ambient_light : source_color = vec3(0.09, 0.105, 0.135);
uniform float agreement_tolerance_m = 250.0;
uniform float agreement_fraction = 0.15;
uniform float far_min_distance_m : hint_range(0.0, 100000.0, 100.0) = 5000.0;
uniform float far_fade_width_m : hint_range(1.0, 100000.0, 100.0) = 3000.0;
// 0: color; 1: log distance; 2: red sphere fallback; 3: overlay agreement.
uniform int debug_view : hint_range(0, 3) = 0;

float field(vec3 p) {
	float radial = max(length(p), 1e-12);
	vec3 n = p / radial;
	vec2 tex_size = vec2(textureSize(height_map, 0));
	vec2 uv = vec2(atan(n.z, n.x) / 6.28318530718, acos(clamp(n.y, -1.0, 1.0)) / 3.14159265359);
	uv.x = fract(uv.x);
	uv.y = clamp(uv.y, 0.5 / tex_size.y, 1.0 - 0.5 / tex_size.y);
	return radial - radius_relative - textureLod(height_map, uv, 0.0).r * meters_to_relative;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Shared hard exclusion, including the generated terrain overlay.
	float exclusion_depth = texture(scene_depth, SCREEN_UV).r;
	float exclusion_near_m = 1e30;
	if (exclusion_depth > 0.0) {
		vec4 exclusion_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, exclusion_depth, 1.0);
		exclusion_near_m = length(exclusion_point.xyz / exclusion_point.w);
		if (exclusion_near_m <= far_min_distance_m) { discard; }
	}
	// This exact guard is replaced by PlanetFarMesh for the terrain overlay.
	if (texture(scene_depth, SCREEN_UV).r > 0.0) { discard; }
	vec4 view_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * normalize(view_point.xyz / view_point.w));
	float outer = radius_relative + height_limit_relative + 2.0 * meters_to_relative;
	float along_ray = dot(ray, center_relative);
	vec3 perpendicular = center_relative - along_ray * ray;
	float disc = outer * outer - dot(perpendicular, perpendicular);
	if (disc < 0.0) { discard; }
	float root = sqrt(max(disc, 0.0));
	float start = max(along_ray - root, 0.0);
	float finish = along_ray + root;
	if (finish <= start) { discard; }
	// A camera below the sampled heightfield must not become a t=0 hit.
	if (start == 0.0 && field(-center_relative) <= 0.5 * meters_to_relative) { discard; }
	float t = start;
	float previous_t = start;
	bool hit = false;
	for (int i = 0; i < 512; i++) {
		float value = field(ray * t - center_relative);
		float tolerance = max(0.5 * meters_to_relative, t * pixel_angle * 0.25);
		if (value <= tolerance) {
			if (value < 0.0 && t > previous_t) {
				float lo = previous_t;
				float hi = t;
				for (int j = 0; j < 10; j++) {
					float mid = (lo + hi) * 0.5;
					if (field(ray * mid - center_relative) > 0.0) { lo = mid; } else { hi = mid; }
				}
				t = (lo + hi) * 0.5;
			}
			hit = true;
			break;
		}
		previous_t = t;
		t += max(value * 0.5, t * pixel_angle);
		if (t > finish) { break; }
	}
	if (!hit) {
		float inner = max(radius_relative - height_limit_relative, 1e-8);
		float inner_disc = inner * inner - dot(perpendicular, perpendicular);
		if (inner_disc < 0.0) { discard; }
		t = along_ray - sqrt(inner_disc);
		if (t <= 0.0) { discard; }
	}
	if (t <= 0.5 * meters_to_relative) { discard; }
	float far_distance_m = t / max(meters_to_relative, 1e-30);
	float visible_distance_m = min(far_distance_m, exclusion_near_m);
	if (visible_distance_m <= far_min_distance_m) { discard; }
	float distance_alpha = clamp((visible_distance_m - far_min_distance_m) / max(far_fade_width_m, 1.0), 0.0, 1.0);
	distance_alpha = distance_alpha * distance_alpha * distance_alpha * (distance_alpha * (distance_alpha * 6.0 - 15.0) + 10.0);
	vec3 p = ray * t - center_relative;
	vec3 normal = normalize(p);
	if (hit) {
		float e = max(2.0 * meters_to_relative, max(radius_relative * 0.00005, t * pixel_angle));
		vec3 gradient = vec3(
			field(p + vec3(e, 0.0, 0.0)) - field(p - vec3(e, 0.0, 0.0)),
			field(p + vec3(0.0, e, 0.0)) - field(p - vec3(0.0, e, 0.0)),
			field(p + vec3(0.0, 0.0, e)) - field(p - vec3(0.0, 0.0, e))
		);
		if (dot(gradient, gradient) > 1e-20) { normal = normalize(gradient); }
	}
	float agreement = 1.0;
	float opaque_depth = texture(scene_depth, SCREEN_UV).r;
	if (opaque_depth > 0.0) {
		vec4 opaque_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, opaque_depth, 1.0);
		float near_distance_m = length(opaque_point.xyz / opaque_point.w);
		float allowed_error = max(agreement_tolerance_m, near_distance_m * agreement_fraction);
		float mismatch = abs(far_distance_m - near_distance_m);
		agreement = 1.0 - smoothstep(allowed_error, allowed_error * 2.0, mismatch);
		if (!hit) { agreement = 0.0; }
	}
	vec3 color = surface_color * (ambient_light + sunlight * max(dot(normal, normalize(direction_to_sun)), 0.0));
	if (debug_view == 1) {
		float d = clamp(log2(1.0 + far_distance_m) / 24.0, 0.0, 1.0);
		color = vec3(d);
	} else if (debug_view == 2) {
		color = hit ? vec3(0.1, 0.65, 0.15) : vec3(1.0, 0.0, 0.0);
	} else if (debug_view == 3) {
		color = vec3(1.0 - agreement, agreement, 0.0);
	}
	ALBEDO = color;
	// Keep this assignment: overlay variant replaces it with ALPHA = weight.
	ALPHA = 1.0;
	ALPHA *= distance_alpha;
}

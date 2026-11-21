// LK_FAR_SYSTEM_COMMON_V1
// Shared declarations and vertex stage for the far-system fallback shaders.
// Fragment behavior deliberately remains shader-specific.
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform int body_count = 0;
uniform vec4 body_spheres[64];
uniform float body_scales[64];
// RGB is explicitly LINEAR, converted once in GDScript. Alpha is a flag.
uniform vec4 body_colors[64];
uniform vec3 body_suns[64];
uniform bool active_inside = false;
uniform float active_cutoff_m = 128.0;
uniform float active_fade_m = 32.0;
uniform float distant_ambient = 0.025;
uniform float sun_energy = 1.0;
uniform float surface_roughness = 1.0;
uniform float surface_metallic = 0.0;
uniform float surface_specular = 0.5;
uniform bool debug_active_albedo = false;

void vertex() {
	vec4 clip = vec4(VERTEX.xy, 1.0, 1.0);
	vec4 near_view = INV_PROJECTION_MATRIX * clip;
	// With skip_vertex_transform this is already in VIEW space. Preserve a
	// correct per-pixel VIEW direction, instead of lighting a 2m camera quad.
	VERTEX = near_view.xyz / near_view.w;
	POSITION = clip;
}

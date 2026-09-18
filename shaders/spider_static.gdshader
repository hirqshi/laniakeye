shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform sampler2D normal_texture : hint_normal, filter_nearest;
uniform sampler2D roughness_texture : hint_default_white, filter_nearest;

uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_multiplier : hint_range(0.0, 2.0) = 1.0;

uniform vec4 albedo_tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = texture(roughness_texture, UV).r * roughness_multiplier;
}
shader_type spatial;

render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_disable;
uniform sampler2D roughness_texture : hint_roughness_r, filter_nearest, repeat_disable;

uniform vec4 foliage_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.5) = 0.5;
uniform float normal_strength : hint_range(0.0, 2.0, 1.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0, 0.86) = 0.86;
uniform float roughness_multiplier : hint_range(0.0, 2.0, 1.0) = 1.0;

void fragment() {
	vec4 albedo_sample = texture(albedo_texture, UV);

	if (albedo_sample.a < alpha_cutoff) {
		discard;
	}

	float roughness_sample = texture(roughness_texture, UV).r;

	ALBEDO = albedo_sample.rgb * foliage_tint.rgb * COLOR.rgb;
	ROUGHNESS = clamp(
		roughness_value * roughness_sample * roughness_multiplier,
		0.0,
		1.0
	);

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	if (normal_strength > 0.0) {
		vec3 sampled_normal = texture(normal_texture, UV).rgb * 2.0 - 1.0;
		sampled_normal.xy *= normal_strength;
		NORMAL_MAP = normalize(sampled_normal);
	}
}
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform sampler2D normal_texture : hint_normal, filter_nearest;
uniform sampler2D roughness_texture : hint_default_white, filter_nearest;

uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_multiplier : hint_range(0.0, 2.0) = 1.0;

uniform float body_wiggle_multiplier : hint_range(0.0, 1.0) = 0.12;

uniform float body_wave_frequency : hint_range(0.0, 10.0) = 2.0;
uniform float body_wave_speed : hint_range(-10.0, 10.0) = 3.5;
uniform float body_wave_amplitude_ratio : hint_range(0.0, 10.0) = 1.0;
uniform float body_radius_m : hint_range(0.01, 500.0) = 0.2;

uniform float tentacle_wave_frequency : hint_range(0.0, 10.0) = 1.4;
uniform float tentacle_wave_speed : hint_range(-10.0, 10.0) = 2.0;
uniform float tentacle_wave_amplitude_ratio : hint_range(0.0, 10.0) = 1.2;
uniform float tentacle_radius_m : hint_range(0.01, 500.0) = 0.1;

uniform vec3 tentacle_lag_offset_local = vec3(0.0);

uniform float tentacle_lag_strength : hint_range(0.0, 10.0) = 1.8;
uniform float tentacle_lag_wave_count : hint_range(0.1, 8.0) = 1.4;
uniform float tentacle_lag_wave_speed : hint_range(0.0, 20.0) = 6.0;
uniform float tentacle_lag_wave_sharpness : hint_range(0.1, 6.0) = 1.7;

uniform float surface_mode : hint_range(0.0, 1.0) = 0.0;

uniform vec4 emission_color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float emission_energy_multiplier : hint_range(0.0, 20.0) = 0.0;
uniform float emission_band_count : hint_range(0.1, 20.0) = 6.0;
uniform float emission_pulse_speed : hint_range(0.0, 20.0) = 1.5;
uniform float emission_band_sharpness : hint_range(0.1, 8.0) = 3.0;

void vertex() {
	if (surface_mode < 0.5) {
		float body_phase = (
			UV.y * body_wave_frequency * 6.2831853
			- TIME * body_wave_speed
		);
		float body_weight = UV.y * body_wiggle_multiplier;

		VERTEX.x += (
			sin(body_phase)
			* body_wave_amplitude_ratio
			* body_radius_m
			* body_weight
		);
	} else {
		float tentacle_phase = COLOR.a * 6.2831853;
		float wave_phase = (
			UV.y * tentacle_wave_frequency * 6.2831853
			- TIME * tentacle_wave_speed
			+ tentacle_phase
		);

		float tip_weight = UV.y * UV.y;

		float lateral_wave = sin(wave_phase);
		float vertical_wave = cos(
			wave_phase * 0.73 + tentacle_phase
		);

		VERTEX.x += (
			lateral_wave
			* tentacle_wave_amplitude_ratio
			* tentacle_radius_m
			* tip_weight
		);

		VERTEX.y += (
			vertical_wave
			* tentacle_wave_amplitude_ratio
			* tentacle_radius_m
			* tip_weight
		);
		float lag_phase = (
			UV.y * tentacle_lag_wave_count * 6.2831853
			- TIME * tentacle_lag_wave_speed
			+ tentacle_phase
		);

		float lag_wave = sin(lag_phase) * 0.5 + 0.5;
		lag_wave = pow(lag_wave, tentacle_lag_wave_sharpness);

		float lag_weight = UV.y * lag_wave * tentacle_lag_strength;

		VERTEX += tentacle_lag_offset_local * lag_weight;
	}
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * COLOR.rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = texture(roughness_texture, UV).r * roughness_multiplier;

	if (emission_energy_multiplier > 0.0) {
		float band_phase = UV.y * emission_band_count * 6.2831853 - TIME * emission_pulse_speed;
		float band_wave = sin(band_phase) * 0.5 + 0.5;
		band_wave = pow(band_wave, emission_band_sharpness);

		EMISSION = emission_color.rgb * band_wave * emission_energy_multiplier;
	}
}
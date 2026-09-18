class_name CreatureMaterialFactory
extends RefCounted

const WORM_SHADER: Shader = preload(
	"res://shaders/worm_wiggle.gdshader"
)

const SQUID_SHADER: Shader = preload(
	"res://shaders/squid_wiggle.gdshader"
)

static func create_worm_material(
	profile: CreatureProfile,
	emission_color: Color = Color.BLACK,
	emission_energy_multiplier: float = 0.0
) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WORM_SHADER

	_apply_shared_texture_parameters(material, profile)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = profile.preview_seed

	profile.get_length_m(rng)

	var body_radius_m: float = profile.get_worm_radius_m(rng)

	material.set_shader_parameter(
		"wave_amplitude_ratio",
		profile.wave_amplitude_ratio
	)
	material.set_shader_parameter(
		"wave_frequency",
		profile.wave_frequency
	)
	material.set_shader_parameter(
		"wave_speed",
		profile.wave_speed
	)
	material.set_shader_parameter("body_radius_m", body_radius_m)
	material.set_shader_parameter("wiggle_multiplier", 1.0)
	material.set_shader_parameter("emission_color", emission_color)
	material.set_shader_parameter("emission_energy_multiplier", emission_energy_multiplier)

	return material

static func create_squid_material(
	profile: CreatureProfile,
	is_tentacle_surface: bool,
	body_wiggle_multiplier: float,
	emission_color: Color = Color.BLACK,
	emission_energy_multiplier: float = 0.0
) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SQUID_SHADER

	_apply_shared_texture_parameters(material, profile)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = profile.preview_seed

	var creature_length_m: float = profile.get_length_m(rng)
	var body_radius_m: float = (
		creature_length_m * profile.squid_body_radius_ratio
	)

	material.set_shader_parameter(
		"body_wiggle_multiplier",
		body_wiggle_multiplier
	)
	material.set_shader_parameter(
		"body_wave_frequency",
		profile.wave_frequency
	)
	material.set_shader_parameter(
		"body_wave_speed",
		profile.wave_speed
	)
	material.set_shader_parameter(
		"body_wave_amplitude_ratio",
		profile.wave_amplitude_ratio
	)
	material.set_shader_parameter("body_radius_m", body_radius_m)

	material.set_shader_parameter(
		"tentacle_wave_frequency",
		profile.tentacle_wave_frequency
	)
	material.set_shader_parameter(
		"tentacle_wave_speed",
		profile.tentacle_wave_speed
	)
	material.set_shader_parameter(
		"tentacle_wave_amplitude_ratio",
		profile.tentacle_wave_amplitude_ratio
	)
	material.set_shader_parameter(
		"tentacle_radius_m",
		body_radius_m * profile.tentacle_radius_ratio
	)
	material.set_shader_parameter(
		"surface_mode",
		1.0 if is_tentacle_surface else 0.0
	)
	material.set_shader_parameter("emission_color", emission_color)
	material.set_shader_parameter("emission_energy_multiplier", emission_energy_multiplier)

	return material

static func _apply_shared_texture_parameters(
	material: ShaderMaterial,
	profile: CreatureProfile
) -> void:
	material.set_shader_parameter(
		"albedo_texture",
		profile.albedo_texture
	)
	material.set_shader_parameter(
		"normal_texture",
		profile.normal_texture
	)
	material.set_shader_parameter(
		"roughness_texture",
		profile.roughness_texture
	)
	material.set_shader_parameter("normal_strength", 1.0)
	material.set_shader_parameter("roughness_multiplier", 1.0)

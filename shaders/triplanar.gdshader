shader_type spatial;

// VERTEX/NORMAL remain in object space.
// Projection stays glued to the planet while it rotates or orbits.
//
// NORMAL MAP FIX: NORMAL in fragment() is in VIEW space (see Godot docs),
// not object/local space. The old code wrote a blended object-space
// normal directly into NORMAL, which made lighting depend on view angle
// instead of light angle (surface went dark when looking toward the
// light). Fixed by writing the triplanar-blended normal into NORMAL_MAP
// instead - Godot handles the tangent-space -> correct space conversion
// itself using the mesh's generated TANGENT/BITANGENT.
//
// ATMOSPHERE SURFACE TINT: optional rim-based color bleed from the
// planet's atmosphere onto its own surface, driven by the same
// rayleigh color/light direction as atmosphere.gdshader so the ground
// near the limb reads as lit through a colored haze instead of the
// atmosphere being a completely separate, disconnected glow shell.

uniform sampler2D albedo_linear : source_color, repeat_enable, filter_linear;
uniform sampler2D albedo_linear_mipmap : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D albedo_nearest : source_color, repeat_enable, filter_nearest;
uniform sampler2D albedo_nearest_mipmap : source_color, repeat_enable, filter_nearest_mipmap;

uniform sampler2D normal_linear : hint_normal, repeat_enable, filter_linear;
uniform sampler2D normal_linear_mipmap : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_nearest : hint_normal, repeat_enable, filter_nearest;
uniform sampler2D normal_nearest_mipmap : hint_normal, repeat_enable, filter_nearest_mipmap;

uniform sampler2D roughness_linear : repeat_enable, filter_linear;
uniform sampler2D roughness_linear_mipmap : repeat_enable, filter_linear_mipmap;
uniform sampler2D roughness_nearest : repeat_enable, filter_nearest;
uniform sampler2D roughness_nearest_mipmap : repeat_enable, filter_nearest_mipmap;

uniform sampler2D metallic_linear : repeat_enable, filter_linear;
uniform sampler2D metallic_linear_mipmap : repeat_enable, filter_linear_mipmap;
uniform sampler2D metallic_nearest : repeat_enable, filter_nearest;
uniform sampler2D metallic_nearest_mipmap : repeat_enable, filter_nearest_mipmap;

uniform sampler2D ao_linear : repeat_enable, filter_linear;
uniform sampler2D ao_linear_mipmap : repeat_enable, filter_linear_mipmap;
uniform sampler2D ao_nearest : repeat_enable, filter_nearest;
uniform sampler2D ao_nearest_mipmap : repeat_enable, filter_nearest_mipmap;

uniform sampler2D emission_linear : source_color, repeat_enable, filter_linear;
uniform sampler2D emission_linear_mipmap : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D emission_nearest : source_color, repeat_enable, filter_nearest;
uniform sampler2D emission_nearest_mipmap : source_color, repeat_enable, filter_nearest_mipmap;

uniform bool use_albedo_texture = true;
uniform bool use_normal_map = false;
uniform bool use_roughness_texture = false;
uniform bool use_metallic_texture = false;
uniform bool use_ao_texture = false;
uniform bool use_emission_texture = false;
uniform bool invert_normal_green_channel = false;

// 0 linear, 1 linear+mipmap, 2 nearest, 3 nearest+mipmap.
uniform int texture_filter_mode = 1;

uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float triplanar_scale : hint_range(0.001, 10.0) = 0.25;
uniform float blend_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform vec3 triplanar_offset = vec3(0.0);

uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_multiplier : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_multiplier : hint_range(0.0, 2.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;

group_uniforms atmosphere_tint;
uniform bool has_atmosphere_tint = false;
uniform vec3 atmosphere_tint_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float atmosphere_tint_strength : hint_range(0.0, 2.0) = 0.3;
uniform float atmosphere_tint_rim_power : hint_range(0.5, 8.0) = 2.0;
uniform vec3 atmosphere_light_direction = vec3(1.0, 0.0, 0.0);

varying vec3 object_position;
varying vec3 object_normal;
varying vec3 world_normal_for_tint;

vec3 triplanar_blend(vec3 normal_in) {
	vec3 blend = abs(normalize(normal_in));
	blend = pow(blend, vec3(blend_sharpness));
	return blend / max(blend.x + blend.y + blend.z, 0.0001);
}

vec4 sample_color_by_filter(
	sampler2D linear_texture,
	sampler2D linear_mipmap_texture,
	sampler2D nearest_texture,
	sampler2D nearest_mipmap_texture,
	vec2 uv
) {
	if (texture_filter_mode == 0) {
		return texture(linear_texture, uv);
	}

	if (texture_filter_mode == 1) {
		return texture(linear_mipmap_texture, uv);
	}

	if (texture_filter_mode == 2) {
		return texture(nearest_texture, uv);
	}

	return texture(nearest_mipmap_texture, uv);
}

float sample_gray_by_filter(
	sampler2D linear_texture,
	sampler2D linear_mipmap_texture,
	sampler2D nearest_texture,
	sampler2D nearest_mipmap_texture,
	vec2 uv
) {
	return sample_color_by_filter(
		linear_texture,
		linear_mipmap_texture,
		nearest_texture,
		nearest_mipmap_texture,
		uv
	).r;
}

vec3 triplanar_albedo(vec3 scaled_position, vec3 blend) {
	vec3 x_sample = sample_color_by_filter(
		albedo_linear,
		albedo_linear_mipmap,
		albedo_nearest,
		albedo_nearest_mipmap,
		scaled_position.zy
	).rgb;

	vec3 y_sample = sample_color_by_filter(
		albedo_linear,
		albedo_linear_mipmap,
		albedo_nearest,
		albedo_nearest_mipmap,
		scaled_position.xz
	).rgb;

	vec3 z_sample = sample_color_by_filter(
		albedo_linear,
		albedo_linear_mipmap,
		albedo_nearest,
		albedo_nearest_mipmap,
		scaled_position.xy
	).rgb;

	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

// Triplanar normal mapping, kept in tangent space and written to
// NORMAL_MAP (not NORMAL). Each of the three projections samples its own
// tangent-space normal; blending them directly in tangent space and
// letting Godot's own TBN transform handle the rest is the standard,
// community-verified way to do this without breaking lighting.
vec3 triplanar_normal_map(vec3 scaled_position, vec3 blend) {
	vec3 x_normal = sample_color_by_filter(
		normal_linear,
		normal_linear_mipmap,
		normal_nearest,
		normal_nearest_mipmap,
		scaled_position.zy
	).rgb;

	vec3 y_normal = sample_color_by_filter(
		normal_linear,
		normal_linear_mipmap,
		normal_nearest,
		normal_nearest_mipmap,
		scaled_position.xz
	).rgb;

	vec3 z_normal = sample_color_by_filter(
		normal_linear,
		normal_linear_mipmap,
		normal_nearest,
		normal_nearest_mipmap,
		scaled_position.xy
	).rgb;

	if (invert_normal_green_channel) {
		x_normal.g = 1.0 - x_normal.g;
		y_normal.g = 1.0 - y_normal.g;
		z_normal.g = 1.0 - z_normal.g;
	}

	vec3 blended_normal = normalize(
		x_normal * blend.x
		+ y_normal * blend.y
		+ z_normal * blend.z
	);

	// blended_normal is still packed (0..1); NORMAL_MAP expects the same
	// packed format a regular texture(normal_texture, UV).rgb would give,
	// so we return it packed and let normal_strength blend toward the
	// neutral packed normal (0.5, 0.5, 1.0) instead of unpacking here.
	return mix(vec3(0.5, 0.5, 1.0), blended_normal, normal_strength);
}

float triplanar_roughness(vec3 scaled_position, vec3 blend) {
	float x_sample = sample_gray_by_filter(
		roughness_linear,
		roughness_linear_mipmap,
		roughness_nearest,
		roughness_nearest_mipmap,
		scaled_position.zy
	);

	float y_sample = sample_gray_by_filter(
		roughness_linear,
		roughness_linear_mipmap,
		roughness_nearest,
		roughness_nearest_mipmap,
		scaled_position.xz
	);

	float z_sample = sample_gray_by_filter(
		roughness_linear,
		roughness_linear_mipmap,
		roughness_nearest,
		roughness_nearest_mipmap,
		scaled_position.xy
	);

	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

float triplanar_metallic(vec3 scaled_position, vec3 blend) {
	float x_sample = sample_gray_by_filter(
		metallic_linear,
		metallic_linear_mipmap,
		metallic_nearest,
		metallic_nearest_mipmap,
		scaled_position.zy
	);

	float y_sample = sample_gray_by_filter(
		metallic_linear,
		metallic_linear_mipmap,
		metallic_nearest,
		metallic_nearest_mipmap,
		scaled_position.xz
	);

	float z_sample = sample_gray_by_filter(
		metallic_linear,
		metallic_linear_mipmap,
		metallic_nearest,
		metallic_nearest_mipmap,
		scaled_position.xy
	);

	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

float triplanar_ao(vec3 scaled_position, vec3 blend) {
	float x_sample = sample_gray_by_filter(
		ao_linear,
		ao_linear_mipmap,
		ao_nearest,
		ao_nearest_mipmap,
		scaled_position.zy
	);

	float y_sample = sample_gray_by_filter(
		ao_linear,
		ao_linear_mipmap,
		ao_nearest,
		ao_nearest_mipmap,
		scaled_position.xz
	);

	float z_sample = sample_gray_by_filter(
		ao_linear,
		ao_linear_mipmap,
		ao_nearest,
		ao_nearest_mipmap,
		scaled_position.xy
	);

	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

vec3 triplanar_emission(vec3 scaled_position, vec3 blend) {
	vec3 x_sample = sample_color_by_filter(
		emission_linear,
		emission_linear_mipmap,
		emission_nearest,
		emission_nearest_mipmap,
		scaled_position.zy
	).rgb;

	vec3 y_sample = sample_color_by_filter(
		emission_linear,
		emission_linear_mipmap,
		emission_nearest,
		emission_nearest_mipmap,
		scaled_position.xz
	).rgb;

	vec3 z_sample = sample_color_by_filter(
		emission_linear,
		emission_linear_mipmap,
		emission_nearest,
		emission_nearest_mipmap,
		scaled_position.xy
	).rgb;

	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

void vertex() {
	object_position = VERTEX;
	object_normal = NORMAL;
	world_normal_for_tint = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 blend = triplanar_blend(object_normal);
	vec3 scaled_position = (object_position + triplanar_offset) * triplanar_scale;

	vec3 albedo = albedo_tint.rgb;

	if (use_albedo_texture) {
		albedo *= triplanar_albedo(scaled_position, blend);
	}

	if (use_normal_map) {
		NORMAL_MAP = triplanar_normal_map(scaled_position, blend);
	}

	float roughness = roughness_value;

	if (use_roughness_texture) {
		roughness *= triplanar_roughness(scaled_position, blend);
	}

	ROUGHNESS = clamp(
		roughness * roughness_multiplier,
		0.0,
		1.0
	);

	float metallic = metallic_value;

	if (use_metallic_texture) {
		metallic *= triplanar_metallic(scaled_position, blend);
	}

	METALLIC = clamp(
		metallic * metallic_multiplier,
		0.0,
		1.0
	);

	if (use_ao_texture) {
		float ao = triplanar_ao(scaled_position, blend);
		AO = mix(1.0, ao, ao_strength);
	}

	if (use_emission_texture && emission_energy > 0.0) {
		EMISSION = triplanar_emission(
			scaled_position,
			blend
		) * emission_color.rgb * emission_energy;
	}

	if (has_atmosphere_tint) {
		float light_term = max(dot(world_normal_for_tint, normalize(atmosphere_light_direction)), 0.0);
		float rim = pow(1.0 - clamp(dot(world_normal_for_tint, VIEW), 0.0, 1.0), atmosphere_tint_rim_power);
		albedo = mix(albedo, atmosphere_tint_color, rim * light_term * atmosphere_tint_strength);
	}

	ALBEDO = albedo;
}
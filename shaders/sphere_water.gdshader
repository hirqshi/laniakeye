/*
Sphere Water Shader - adapted from Pixel Water Shader by Taillight Games
Original: https://github.com/taillight-games/godot-4-pixelated-water-shader
MIT License

The water is a plain solid sphere sitting at sea_level_radius_m - it does
NOT mask/cutout land vs. ocean itself. Ocean basin shape is carved
directly into the planet's terrain GEOMETRY by PlanetMeshGenerator
(a large-scale noise pass that pushes vertices below sea level wherever
a basin should exist). Land simply pokes up through this sphere
geometrically wherever the terrain wasn't carved deep enough, the same
way real land sits above real sea level - no shader-side basin mask
needed or wanted here.

PORT NOTES (plane -> sphere):
- the original sampled vertex_noise_big/big2 and normal_noise using
  VERTEX.xz as flat plane-space coordinates. on a sphere that breaks
  down completely, so every place that used to read VERTEX.xz now uses
  a TRIPLANAR sample instead - same technique as triplanar.gdshader.
- foam has been stripped entirely.
*/

shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_always, ambient_light_disabled, diffuse_burley, blend_mix;

varying vec3 triplanar_pos;
varying vec3 object_normal_v;
varying vec3 world_normal;

group_uniforms waves;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.15;
uniform float height_scale : hint_range(0.0, 20.0) = 3.0;
uniform float amplitude1 : hint_range(0.0, 5.0) = 2.0;
uniform float amplitude2 : hint_range(0.0, 5.0) = 0.5;
uniform float v_normal_scale : hint_range(0.0, 5.0) = 1.0;

group_uniforms wave_textures;
uniform sampler2D vertex_noise_big : repeat_enable;
uniform sampler2D vertex_noise_big2 : repeat_enable;
uniform float triplanar_scale : hint_range(0.001, 10.0) = 0.05;
uniform float triplanar_blend_sharpness : hint_range(1.0, 16.0) = 4.0;

group_uniforms normal_ripples;
uniform sampler2D normal_noise : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_noise2 : hint_normal, filter_linear_mipmap;
uniform float normal_noise_speed : hint_range(0.0, 2.0) = 0.15;

group_uniforms refraction;
uniform float caustic_speed = 0.01;
uniform float wobble_power = 0.01;
uniform sampler2D under_wobble_noise;

group_uniforms depth_and_color;
uniform float edge_fade_power = 2.0;
uniform float transmittence : hint_range(0.0, 1.0) = 0.04;
uniform float h_dist_trans_weight = 3.0;
uniform vec3 transmit_color : source_color;

// set this from script as a value proportional to the ocean's own
// radius (e.g. sea_level_radius_m * 0.4), not a small fixed constant -
// keeps the same visual depth gradient regardless of planet size.
uniform float depth_fade : hint_range(0.0, 0.5, 0.01) = 0.3;
uniform float depth_fade_distance : hint_range(0.0, 500.0, 0.1) = 40.0;

uniform vec3 surface_albedo : source_color;
uniform vec4 surface_bottom : source_color;

uniform float opacity : hint_range(0.0, 5.0, 0.01) = 0.4;
uniform float opacity_floor = 0.1;
uniform float opacity_ceiling = 0.8;

uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.4;

uniform vec3 sky_color : source_color;
varying vec4 v_color;

group_uniforms wave_color_tint;
uniform vec3 high_color : source_color;
uniform vec3 low_color : source_color;
varying vec3 wave_color;
uniform float wave_color_range = 2.0;

uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D depth_texture : hint_depth_texture;

float remap(float in_low, float in_high, float out_low, float out_high, float value) {
	return out_low + (value - in_low) * (out_high - out_low) / (in_high - in_low);
}

vec3 triplanar_blend(vec3 normal_in) {
	vec3 blend = abs(normalize(normal_in));
	blend = pow(blend, vec3(triplanar_blend_sharpness));
	return blend / max(blend.x + blend.y + blend.z, 0.0001);
}

float sample_wave_noise(sampler2D tex, vec2 uv, float speed, bool flipped) {
	vec2 scrolled = uv;
	float t = TIME * speed;
	if (!flipped) {
		scrolled += vec2(t, t);
	} else {
		scrolled.x -= t;
	}
	return texture(tex, scrolled).r;
}

float triplanar_wave_sample(sampler2D tex, vec3 pos, vec3 blend, float speed, bool flipped) {
	float x_sample = sample_wave_noise(tex, pos.zy, speed, flipped);
	float y_sample = sample_wave_noise(tex, pos.xz, speed, flipped);
	float z_sample = sample_wave_noise(tex, pos.xy, speed, flipped);
	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

float wave(vec3 world_pos, vec3 normal_dir) {
	vec3 blend = triplanar_blend(normal_dir);
	vec3 scaled_pos = world_pos * triplanar_scale;

	float s = 0.0;
	s += triplanar_wave_sample(vertex_noise_big, scaled_pos, blend, wave_speed, false) * amplitude1;
	s += triplanar_wave_sample(vertex_noise_big2, scaled_pos + vec3(0.3, 0.476, 0.0), blend, wave_speed, true) * amplitude2;
	s -= (amplitude1 + amplitude2) * 0.5;

	return s;
}

varying mat4 camera_mix;

void vertex() {
	object_normal_v = NORMAL;

	float _height = wave(VERTEX, NORMAL) * height_scale;
	VERTEX += NORMAL * _height;

	float wave_color_mix = clamp(remap(-wave_color_range, wave_color_range, 0.0, 1.0, _height), 0.0, 1.0);
	wave_color = mix(low_color, high_color, wave_color_mix);

	vec3 up = abs(NORMAL.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(up, NORMAL));
	vec3 bitangent = normalize(cross(NORMAL, tangent));
	float e = 0.1;
	float v_scale = height_scale * v_normal_scale;

	float h_center = wave(VERTEX, NORMAL) * v_scale;
	float h_tangent = wave(VERTEX + tangent * e, NORMAL) * v_scale;
	float h_bitangent = wave(VERTEX + bitangent * e, NORMAL) * v_scale;

	vec3 normal = normalize(NORMAL - tangent * (h_tangent - h_center) / e - bitangent * (h_bitangent - h_center) / e);
	NORMAL = normal;

	triplanar_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	v_color = COLOR.rgba;
	camera_mix = INV_VIEW_MATRIX;
}

void fragment() {
	ROUGHNESS = roughness;
	vec3 _albedo;
	vec3 deep;

	vec2 wobble_uv = (texture(under_wobble_noise, SCREEN_UV * 10.0 + TIME * caustic_speed).xy * wobble_power);
	wobble_uv -= wobble_power * 0.86;

	vec3 under = texture(screen_texture, SCREEN_UV + wobble_uv).rgb;

	float depth3 = texture(depth_texture, SCREEN_UV + wobble_uv).x;
	vec3 ndc3 = vec3(SCREEN_UV + wobble_uv, depth3) * 2.0 - 1.0;
	vec4 world3 = camera_mix * INV_PROJECTION_MATRIX * vec4(ndc3, 1.0);
	vec3 world_position = world3.xyz / world3.w;

	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;

	float _dist = distance(world_position.y, vertex_y);
	float _h_dist = distance(triplanar_pos, world_position);

	_dist += _h_dist * h_dist_trans_weight;

	float depth_fade_blend = clamp(exp(-_dist / max(depth_fade_distance, 0.001)), 0.0, 1.0);

	float alpha_blend = -_dist * transmittence;
	alpha_blend = clamp(1.0 - exp(alpha_blend), 0.7, 1.0);

	deep = mix(wave_color, surface_albedo, depth_fade_blend);

	vec3 blend = triplanar_blend(object_normal_v);
	vec3 scaled_pos = triplanar_pos * triplanar_scale;

	vec3 n_map1_x = texture(normal_noise, scaled_pos.zy + TIME * normal_noise_speed).xyz;
	vec3 n_map1_y = texture(normal_noise, scaled_pos.xz + TIME * normal_noise_speed).xyz;
	vec3 n_map1_z = texture(normal_noise, scaled_pos.xy + TIME * normal_noise_speed).xyz;
	vec3 n_map1 = n_map1_x * blend.x + n_map1_y * blend.y + n_map1_z * blend.z;

	vec3 n_map2_x = texture(normal_noise2, scaled_pos.zy - TIME * normal_noise_speed).xyz;
	vec3 n_map2_y = texture(normal_noise2, scaled_pos.xz - TIME * normal_noise_speed).xyz;
	vec3 n_map2_z = texture(normal_noise2, scaled_pos.xy - TIME * normal_noise_speed).xyz;
	vec3 n_map2 = n_map2_x * blend.x + n_map2_y * blend.y + n_map2_z * blend.z;

	NORMAL_MAP = mix(n_map1, n_map2, 0.5);

	if (FRONT_FACING) {
		_albedo = mix(under, deep, alpha_blend);
		float _ALPHA = remap(0.0, opacity, opacity_floor, opacity_ceiling, pow(alpha_blend, edge_fade_power));
		_albedo = mix(under + transmit_color, _albedo, _ALPHA);
		ALPHA = _ALPHA;
	} else {
		NORMAL = -NORMAL;
		NORMAL_MAP = mix(vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), NORMAL_MAP);
		vec3 over = texture(screen_texture, SCREEN_UV + wobble_uv).rgb;
		_albedo = mix(over, surface_bottom.rgb, surface_bottom.a);
		ALPHA = surface_bottom.a;
	}

	ALBEDO = _albedo;
	ALBEDO = mix(sky_color, ALBEDO, v_color.a);
}


group_uniforms lighting;

uniform bool enable_fake_lighting = false;

uniform float shine_strength : hint_range(0.0, 1.0) = 0.17;
uniform float shine_shininess : hint_range(0.0, 32.0) = 18.0;

uniform float shadow : hint_range(0.0, 1.0) = 0.72;
uniform float shadow_width : hint_range(0.001, 0.5) = 0.18;
uniform vec4 shadow_color: source_color = vec4(0.705);

uniform float _specular_smoothness : hint_range(0.0, 0.5) = 0.199;
uniform float _specular_strength : hint_range(0.0, 9.25) = 0.075;
uniform float _glossiness : hint_range(0.0, 0.5) = 0.067;

void light() {
	vec3 H;

	if (enable_fake_lighting) {
		H = normalize(LIGHT);
	} else {
		H = normalize(VIEW + LIGHT);
	}
	float NdotH = dot(NORMAL, H);
	float specular_amount = max(pow(NdotH, shine_shininess * shine_shininess), 0.0) * ATTENUATION;
	SPECULAR_LIGHT += shine_strength * specular_amount * LIGHT_COLOR;

	float NdotL = dot(NORMAL, LIGHT) * ATTENUATION;
	NdotL = smoothstep(shadow - shadow_width, shadow + shadow_width, NdotL);

	float specular_intensity = pow(NdotH, 1.0 / _glossiness);
	vec3 specular = vec3(smoothstep(0.5 - _specular_smoothness, 0.5 + _specular_smoothness, specular_intensity));

	vec3 rim = vec3(1.0);

	DIFFUSE_LIGHT += ATTENUATION * mix(ALBEDO * shadow_color.rgb, (ALBEDO + (rim + specular) * _specular_strength) * LIGHT_COLOR.rgb * 0.33, NdotL + 0.33);
	DIFFUSE_LIGHT = mix(sky_color, DIFFUSE_LIGHT, v_color.r);
	SPECULAR_LIGHT = mix(vec3(0.0), SPECULAR_LIGHT, v_color.r);
}
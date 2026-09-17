shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, diffuse_lambert, specular_disabled;

// base color/alpha across the radial band, baked from a Gradient resource.
uniform sampler2D ring_gradient_texture: source_color, filter_linear;

// second, smaller-scale noise-ish texture (any tileable grayscale noise
// works - e.g. a NoiseTexture2D) sampled along U only, to fake the
// countless thin density bands real rings have (like Saturn's gaps).
uniform sampler2D band_noise_texture: source_color, filter_nearest, repeat_enable;
uniform float band_noise_scale: hint_range(1.0, 64.0) = 24.0;
uniform float band_noise_strength: hint_range(0.0, 1.0) = 0.5;

uniform float alpha_multiplier: hint_range(0.0, 1.0) = 0.85;

// soft fade-in/out at the inner/outer edges so the ring doesn't look
// like it was cut with scissors.
uniform float edge_fade_width: hint_range(0.0, 0.3) = 0.06;

// planet-shadow fake: the ring darkens on the side that's behind the
// planet relative to the main light direction.
uniform vec3 planet_world_position;
uniform float planet_radius_m;
uniform vec3 light_direction = vec3(1.0, 0.0, 0.0);
uniform float shadow_strength: hint_range(0.0, 1.0) = 0.75;

varying vec3 world_vertex_position;

void vertex() {
	world_vertex_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 base_color = texture(ring_gradient_texture, vec2(UV.x, 0.5));

	float band = texture(band_noise_texture, vec2(UV.x * band_noise_scale, 0.0)).r;
	float band_mix = mix(1.0, band, band_noise_strength);

	float edge_fade = smoothstep(0.0, edge_fade_width, UV.x)
		* smoothstep(1.0, 1.0 - edge_fade_width, UV.x);

	// fake planet shadow: does this ring point sit roughly opposite the
	// light, at a radius still inside the planet's silhouette?
	vec3 to_fragment = world_vertex_position - planet_world_position;
	float along_light = dot(normalize(to_fragment), normalize(-light_direction));
	float lateral_distance = length(to_fragment - dot(to_fragment, normalize(light_direction)) * normalize(light_direction));
	float in_shadow_cone = step(0.0, along_light) * (1.0 - smoothstep(planet_radius_m * 0.9, planet_radius_m * 1.1, lateral_distance));
	float shadow_factor = 1.0 - in_shadow_cone * shadow_strength;

	ALBEDO = base_color.rgb * band_mix * shadow_factor;
	ALPHA = base_color.a * band_mix * edge_fade * alpha_multiplier;

	// keep a whisper of normal-based shading so it isn't a flat cutout,
	// without going full diffuse (rings read as thin/backlit, not solid).
	NORMAL = vec3(0.0, sign(dot(VIEW, NORMAL)), 0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
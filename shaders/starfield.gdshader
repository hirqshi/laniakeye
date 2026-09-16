shader_type sky;

// Pure procedural starfield: black background with pinpoint stars
// scattered by direction (EYEDIR), no textures involved.
//
// FIX (stars reshuffling every frame while rotating the camera): the
// previous version picked one of 6 cube faces via abs(direction).x/y/z
// comparisons, then hashed (cell_index, face_id). Near any face boundary
// (any diagonal-ish direction - which is constantly crossed during
// normal camera rotation, not a rare edge case) a tiny direction change
// flips which face wins the comparison, changing face_id and therefore
// completely changing the hash seed for that whole region - the star
// pattern there instantly reshuffled every time a boundary was crossed.
//
// Fixed by dropping the cube-face split entirely. Instead we snap the
// continuous unit direction vector to a 3D grid of cells directly (a
// "3D cell noise" over the sphere of directions) - there is no
// discontinuous face selection anywhere, so the hash seed only changes
// when the direction actually crosses into a neighboring 3D cell, which
// happens smoothly and consistently regardless of rotation axis.

uniform float star_density : hint_range(0.0, 1.0) = 0.985;
uniform float star_cell_scale : hint_range(1.0, 200.0) = 40.0;
uniform float star_size : hint_range(0.0001, 0.02) = 0.003;
uniform float star_brightness_min : hint_range(0.0, 4.0) = 0.4;
uniform float star_brightness_max : hint_range(0.0, 8.0) = 2.2;
uniform vec4 star_color_a : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 star_color_b : source_color = vec4(0.7, 0.8, 1.0, 1.0);
uniform vec4 sky_background_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float twinkle_speed : hint_range(0.0, 10.0) = 1.5;
uniform float twinkle_amount : hint_range(0.0, 1.0) = 0.3;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453123);
}

// Evaluates star presence/appearance for a single 3D cell, given the
// direction's fractional position within that cell (used both for the
// cell the direction is currently in and its neighbors, so a star whose
// random offset pushes it across a cell boundary still renders smoothly
// instead of popping at the edge).
vec4 evaluate_star_cell(vec3 cell_index, vec3 local_pos, float time) {
	vec3 random_values = hash33(cell_index);

	float presence = step(star_density, random_values.x);
	if (presence < 0.5) {
		return vec4(0.0);
	}

	vec3 star_offset = (random_values - 0.5) * (1.0 - star_size * 20.0);
	float distance_to_star = length(local_pos - star_offset);

	float star_shape = smoothstep(star_size, 0.0, distance_to_star);
	if (star_shape <= 0.0) {
		return vec4(0.0);
	}

	float brightness_seed = hash13(cell_index + vec3(7.0, 13.0, 19.0));
	float brightness = mix(star_brightness_min, star_brightness_max, brightness_seed);

	float twinkle_seed = hash13(cell_index + vec3(31.0, 17.0, 5.0));
	float twinkle = 1.0 + sin(time * twinkle_speed + twinkle_seed * TAU) * twinkle_amount;
	brightness *= max(twinkle, 0.0);

	float color_mix = hash13(cell_index + vec3(41.0, 3.0, 27.0));
	vec3 star_color = mix(star_color_a.rgb, star_color_b.rgb, color_mix);

	return vec4(star_color * brightness * star_shape, star_shape);
}

vec3 compute_starfield(vec3 direction, float time) {
	vec3 scaled_pos = direction * star_cell_scale;
	vec3 base_cell = floor(scaled_pos);
	vec3 local_pos = fract(scaled_pos) - 0.5;

	vec3 accumulated_color = vec3(0.0);
	float accumulated_alpha = 0.0;

	// check the current cell plus its 26 neighbors so a star near a cell
	// edge is still found and drawn without popping - direction-based
	// cell noise has no discontinuous face boundaries like the old cube
	// projection did, but individual cell EDGES still need this to avoid
	// stars getting clipped exactly at their own cell's border.
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 neighbor_offset = vec3(float(x), float(y), float(z));
				vec3 neighbor_cell = base_cell + neighbor_offset;
				vec3 neighbor_local_pos = local_pos - neighbor_offset;

				vec4 star_result = evaluate_star_cell(neighbor_cell, neighbor_local_pos, time);
				accumulated_color += star_result.rgb;
				accumulated_alpha = max(accumulated_alpha, star_result.a);
			}
		}
	}

	return accumulated_color;
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	vec3 stars = compute_starfield(direction, TIME);

	COLOR = sky_background_color.rgb + stars;
}
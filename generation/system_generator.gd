class_name SystemGenerator
extends RefCounted

## Pure generation logic, no nodes involved. Fully testable in isolation.
## All tunable numbers come from a GenerationSettings resource, editable
## in the inspector - no constants hardcoded in this file anymore.
##
## FIX (planets/moons overlapping): the previous version advanced orbit
## distance by a FIXED step (orbit_distance_step_m +/- jitter) that never
## accounted for the ACTUAL radius_m of either body, since radius_m was
## randomized INSIDE _generate_body(), one level below where the orbit
## distance was already decided. Two consecutive large-radius rolls (or
## unlucky negative jitter) could easily overlap. Moons had the same bug:
## a moon's own orbit distance was chosen BEFORE its own radius_m was
## rolled, so the first moon could spawn inside its parent planet.
##
## Fix: generate EACH body's full data (including radius_m) FIRST, then
## place it using the actual radius of the body immediately before it,
## guaranteeing orbit_surface_gap_m / moon_surface_gap_m of empty space
## between any two consecutive bodies' SURFACES, not just their orbit
## centers.
##
## Moons also now use their own noise scale range
## (moon_terrain_noise_scale_min/max) instead of reusing the planet-scale
## terrain_noise_scale_min/max - moons are much smaller, so they need a
## proportionally different noise frequency to avoid a single "hill"
## covering half the moon.

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var surface_profile_set: SurfaceProfileSet
var settings: GenerationSettings

func _init(profile_set: SurfaceProfileSet, generation_settings: GenerationSettings) -> void:
	surface_profile_set = profile_set
	settings = generation_settings

func generate(system_seed: int) -> SystemData:
	rng.seed = system_seed

	var system_data: SystemData = SystemData.new()
	system_data.system_seed = system_seed

	var planet_count: int = rng.randi_range(settings.min_planets, settings.max_planets)
	var distributed_profiles: Array[SurfaceProfile] = surface_profile_set.get_distributed_profiles(rng, planet_count)

	var previous_orbit_distance_m: float = 0.0
	var previous_radius_m: float = 0.0

	for i in range(planet_count):
		var planet: PlanetData = _generate_body_data(false, false, distributed_profiles[i])

		var base_radius_m: float = settings.star_radius_m if i == 0 else previous_radius_m
		var base_gap_m: float = settings.star_surface_gap_m if i == 0 else settings.orbit_surface_gap_m

		var min_center_distance: float = (
			previous_orbit_distance_m
			+ base_radius_m
			+ base_gap_m
			+ planet.radius_m
		)

		var desired_step: float = settings.orbit_distance_step_m + rng.randf_range(
			-settings.orbit_distance_jitter_m,
			settings.orbit_distance_jitter_m
		)

		var candidate_distance: float = previous_orbit_distance_m + desired_step
		var orbit_distance_m: float = max(candidate_distance, min_center_distance)

		planet.orbit_distance_m = orbit_distance_m
		planet.display_name = CelestialNameGenerator.generate_planet_name(planet.planet_seed)
		planet.moons = _generate_moons(planet.radius_m, orbit_distance_m)

		for moon_index in range(planet.moons.size()):
			planet.moons[moon_index].display_name = CelestialNameGenerator.generate_moon_name(planet.display_name, moon_index)

		system_data.planets.append(planet)

		previous_orbit_distance_m = orbit_distance_m
		previous_radius_m = planet.radius_m

	return system_data

## Generates all of a body's data EXCEPT orbit_distance_m, which the
## caller assigns afterward once it knows the body's actual radius_m -
## this ordering is what makes correct spacing possible in the first place.
func _generate_body_data(unused_allow_moons: bool, is_moon: bool, forced_profile: SurfaceProfile = null) -> PlanetData:
	var body: PlanetData = PlanetData.new()
	body.planet_seed = rng.randi()
	body.radius_m = rng.randf_range(settings.planet_radius_min_m, settings.planet_radius_max_m)
	body.gravity_strength = rng.randf_range(settings.planet_gravity_min, settings.planet_gravity_max)
	body.orbit_angle_rad = rng.randf_range(0.0, TAU)
	body.orbit_speed_rad_s = rng.randf_range(settings.orbit_speed_min, settings.orbit_speed_max) * (1.0 if rng.randf() > 0.5 else -1.0)
	body.axial_tilt_rad = rng.randf_range(-settings.axial_tilt_max_rad, settings.axial_tilt_max_rad)
	body.rotation_speed_rad_s = rng.randf_range(settings.rotation_speed_min, settings.rotation_speed_max)

	var profile: SurfaceProfile = forced_profile if forced_profile else surface_profile_set.get_random_profile(rng)
	body.surface_profile = profile
	body.albedo_color = profile.get_random_color(rng) if profile else Color.WHITE
	body.vegetation_density = profile.get_random_vegetation_density(rng) if profile else 0.0
	body.has_vegetation = body.vegetation_density > 0.0

	if is_moon:
		body.terrain_noise_scale = rng.randf_range(settings.moon_terrain_noise_scale_min, settings.moon_terrain_noise_scale_max)
	else:
		body.terrain_noise_scale = rng.randf_range(settings.terrain_noise_scale_min, settings.terrain_noise_scale_max)

	body.terrain_height_m = profile.get_random_terrain_height(rng) if profile else rng.randf_range(2.0, 12.0)

	return body

func _generate_moons(planet_radius_m: float, planet_orbit_distance_m: float) -> Array[PlanetData]:
	var moons: Array[PlanetData] = []
	if rng.randf() > settings.moon_chance:
		return moons

	var moon_count: int = rng.randi_range(1, settings.max_moons_per_planet)
	var previous_orbit_distance_m: float = 0.0
	var previous_radius_m: float = 0.0

	# hard ceiling: even a moon sitting exactly between the planet and the
	# star must not cross into the star's surface + gap.
	var max_moon_orbit_distance_m: float = max(
		0.0,
		planet_orbit_distance_m - settings.star_radius_m - settings.star_surface_gap_m
	)

	for i in range(moon_count):
		var moon: PlanetData = _generate_body_data(false, true)
		moon.radius_m = rng.randf_range(5.0, planet_radius_m * settings.moon_radius_ratio_max)
		moon.gravity_strength = rng.randf_range(settings.moon_gravity_min, settings.moon_gravity_max)
		moon.orbit_speed_rad_s = rng.randf_range(settings.moon_orbit_speed_min, settings.moon_orbit_speed_max) * (1.0 if rng.randf() > 0.5 else -1.0)
		moon.rotation_speed_rad_s = rng.randf_range(settings.moon_rotation_speed_min, settings.moon_rotation_speed_max)

		var base_radius_m: float = planet_radius_m if i == 0 else previous_radius_m
		var base_distance_m: float = 0.0 if i == 0 else previous_orbit_distance_m

		var min_center_distance: float = (
			base_distance_m
			+ base_radius_m
			+ settings.moon_surface_gap_m
			+ moon.radius_m
		)

		var desired_step: float = moon.radius_m * settings.moon_orbit_step_radius_multiplier + rng.randf_range(
			settings.moon_orbit_jitter_min_m,
			settings.moon_orbit_jitter_max_m
		)

		var candidate_distance: float = base_distance_m + base_radius_m + desired_step
		var orbit_distance_m: float = max(candidate_distance, min_center_distance)

		# clamp to the star-safety ceiling - if min_center_distance itself
		# already exceeds the ceiling, this moon (and all further ones,
		# since distances only grow) simply can't fit safely; stop here
		# instead of forcing an unsafe orbit.
		if min_center_distance > max_moon_orbit_distance_m:
			break

		orbit_distance_m = min(orbit_distance_m, max_moon_orbit_distance_m)

		moon.orbit_distance_m = orbit_distance_m
		moons.append(moon)

		previous_orbit_distance_m = orbit_distance_m
		previous_radius_m = moon.radius_m

	return moons

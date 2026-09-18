class_name PlanetSurfaceSampler
extends RefCounted

const CRATER_RIM_POSITION: float = 0.85
const CRATER_RIM_WIDTH: float = 0.08
const DEFAULT_BASIN_SEED_OFFSET: int = 900_001

var _radius_m: float = 0.0
var _terrain_height_m: float = 0.0
var _terrain_noise: FastNoiseLite
var _surface_profile: Resource

var _craters: Array[Dictionary] = []

var _has_ocean: bool = false
var _sea_level_radius_m: float = 0.0
var _basin_noise: FastNoiseLite

func setup(
	radius_m: float,
	planet_seed: int,
	terrain_noise_scale: float,
	terrain_height_m: float,
	terrain_noise_type: int,
	surface_profile: Resource
) -> void:
	_radius_m = radius_m
	_terrain_height_m = terrain_height_m
	_surface_profile = surface_profile

	_setup_terrain_noise(
		planet_seed,
		terrain_noise_scale,
		terrain_noise_type
	)

	_craters = _generate_craters(planet_seed)

	_has_ocean = _get_profile_bool("has_ocean", false)
	_sea_level_radius_m = 0.0
	_basin_noise = null

	if _has_ocean:
		_sea_level_radius_m = _radius_m * _get_profile_float(
			"sea_level_radius_ratio",
			1.0
		)
		_basin_noise = _build_basin_noise(planet_seed)

func get_surface_radius_m(direction: Vector3) -> float:
	var normalized_direction: Vector3 = direction.normalized()
	var terrain_noise_value: float = _terrain_noise.get_noise_3dv(
		normalized_direction * 100.0
	)

	var surface_radius_m: float = (
		_radius_m
		+ terrain_noise_value * _terrain_height_m
	)

	if not _craters.is_empty():
		surface_radius_m += _sample_craters(normalized_direction)

	if _has_ocean and _basin_noise != null:
		surface_radius_m -= _sample_basin_depth(normalized_direction)

	return surface_radius_m

func get_surface_position(direction: Vector3) -> Vector3:
	var normalized_direction: Vector3 = direction.normalized()
	var surface_radius_m: float = get_surface_radius_m(normalized_direction)

	return normalized_direction * surface_radius_m

func get_surface_normal(direction: Vector3) -> Vector3:
	var center_direction: Vector3 = direction.normalized()

	var tangent_a: Vector3 = center_direction.cross(Vector3.UP)
	if tangent_a.length_squared() < 0.0001:
		tangent_a = center_direction.cross(Vector3.RIGHT)

	tangent_a = tangent_a.normalized()

	var tangent_b: Vector3 = center_direction.cross(tangent_a).normalized()

	# Angular step, not a world-unit step. It stays stable on both
	# a 15m moon and a 300m planet.
	var sample_angle_rad: float = 0.003

	var center_position: Vector3 = get_surface_position(center_direction)
	var sample_a_position: Vector3 = get_surface_position(
		(center_direction + tangent_a * sample_angle_rad).normalized()
	)
	var sample_b_position: Vector3 = get_surface_position(
		(center_direction + tangent_b * sample_angle_rad).normalized()
	)

	var normal: Vector3 = (
		sample_a_position - center_position
	).cross(
		sample_b_position - center_position
	).normalized()

	if normal.dot(center_direction) < 0.0:
		normal = -normal

	return normal

func is_surface_above_water(
	direction: Vector3,
	clearance_m: float = 0.05
) -> bool:
	if not _has_ocean:
		return true

	var normalized_direction: Vector3 = direction.normalized()
	var surface_radius_m: float = get_surface_radius_m(normalized_direction)

	return surface_radius_m > _sea_level_radius_m + clearance_m

func is_underwater(direction: Vector3) -> bool:
	return not is_surface_above_water(direction, 0.0)

func get_sea_level_radius_m() -> float:
	return _sea_level_radius_m

func _setup_terrain_noise(
	planet_seed: int,
	terrain_noise_scale: float,
	terrain_noise_type: int
) -> void:
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = planet_seed
	_terrain_noise.frequency = 0.01 * terrain_noise_scale
	_terrain_noise.fractal_octaves = 4
	_terrain_noise.fractal_gain = 0.5
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	if terrain_noise_type == 1:
		_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	else:
		_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM

func _generate_craters(planet_seed: int) -> Array[Dictionary]:
	var craters: Array[Dictionary] = []

	if not _get_profile_bool("allow_craters", false):
		return craters

	if _surface_profile == null:
		return craters

	if not _surface_profile.has_method("get_random_crater_count"):
		return craters

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = planet_seed + 987_654

	var crater_count: int = int(
		_surface_profile.call("get_random_crater_count", rng)
	)

	var radius_min_ratio: float = _get_profile_float(
		"crater_radius_min_ratio",
		0.04
	)
	var radius_max_ratio: float = _get_profile_float(
		"crater_radius_max_ratio",
		0.18
	)
	var crater_depth_m: float = _get_profile_float(
		"crater_depth_m",
		1.5
	)
	var crater_rim_height_m: float = _get_profile_float(
		"crater_rim_height_m",
		0.6
	)

	for crater_index: int in range(crater_count):
		var center: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)

		if center.length_squared() < 0.0001:
			center = Vector3.UP
		else:
			center = center.normalized()

		var radius_ratio: float = rng.randf_range(
			radius_min_ratio,
			radius_max_ratio
		)
		var crater_radius_m: float = _radius_m * radius_ratio
		var angular_radius_rad: float = crater_radius_m / maxf(
			_radius_m,
			0.001
		)

		craters.append({
			"center": center,
			"angular_radius_rad": angular_radius_rad,
			"depth_m": crater_depth_m,
			"rim_height_m": crater_rim_height_m
		})

	return craters

func _sample_craters(direction: Vector3) -> float:
	var best_offset_m: float = 0.0
	var best_angular_distance_rad: float = INF

	for crater: Dictionary in _craters:
		var crater_center: Vector3 = crater["center"] as Vector3
		var angular_radius_rad: float = float(
			crater["angular_radius_rad"]
		)

		var cosine_angle: float = clampf(
			direction.dot(crater_center),
			-1.0,
			1.0
		)
		var angular_distance_rad: float = acos(cosine_angle)

		if angular_distance_rad >= best_angular_distance_rad:
			continue

		if angular_distance_rad > angular_radius_rad:
			continue

		best_angular_distance_rad = angular_distance_rad
		best_offset_m = _get_crater_bowl_offset(
			angular_distance_rad,
			crater
		)

	return best_offset_m

func _get_crater_bowl_offset(
	angular_distance_rad: float,
	crater: Dictionary
) -> float:
	var angular_radius_rad: float = float(
		crater["angular_radius_rad"]
	)
	var crater_depth_m: float = float(crater["depth_m"])
	var rim_height_m: float = float(crater["rim_height_m"])

	var t: float = angular_distance_rad / maxf(
		angular_radius_rad,
		0.0001
	)

	var bowl: float = (t * t - 1.0) * crater_depth_m

	var rim: float = exp(
		-pow(
			t - CRATER_RIM_POSITION,
			2.0
		) / (
			2.0
			* CRATER_RIM_WIDTH
			* CRATER_RIM_WIDTH
		)
	) * rim_height_m

	return bowl + rim

func _build_basin_noise(planet_seed: int) -> FastNoiseLite:
	var basin_noise: FastNoiseLite = FastNoiseLite.new()

	var seed_offset: int = int(
		_get_profile_float(
			"ocean_basin_seed_offset",
			DEFAULT_BASIN_SEED_OFFSET
		)
	)

	var scale: float = maxf(
		_get_profile_float("ocean_basin_noise_scale", 1.0),
		0.001
	)

	basin_noise.seed = planet_seed + seed_offset
	basin_noise.frequency = 0.01 / scale
	basin_noise.fractal_octaves = 3
	basin_noise.fractal_gain = 0.5
	basin_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	basin_noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	return basin_noise

func _sample_basin_depth(direction: Vector3) -> float:
	if _basin_noise == null:
		return 0.0

	var raw_value: float = _basin_noise.get_noise_3dv(direction * 100.0)
	var normalized_value: float = (raw_value + 1.0) * 0.5

	var threshold: float = _get_profile_float(
		"ocean_basin_threshold",
		0.5
	)
	var edge_softness: float = maxf(
		_get_profile_float(
			"ocean_basin_edge_softness",
			0.1
		),
		0.001
	)
	var depth_m: float = _get_profile_float(
		"ocean_basin_depth_m",
		0.0
	)

	var basin_amount: float = smoothstep(
		threshold + edge_softness,
		threshold - edge_softness,
		normalized_value
	)

	return basin_amount * depth_m

func _get_profile_bool(
	property_name: StringName,
	default_value: bool
) -> bool:
	if _surface_profile == null:
		return default_value

	var value: Variant = _surface_profile.get(property_name)
	if value == null:
		return default_value

	return bool(value)

func _get_profile_float(
	property_name: StringName,
	default_value: float
) -> float:
	if _surface_profile == null:
		return default_value

	var value: Variant = _surface_profile.get(property_name)
	if value == null:
		return default_value

	if value is float:
		return value

	if value is int:
		return float(value)

	return default_value

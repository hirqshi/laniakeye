class_name LeviathanSpawner
extends Node3D

@export var leviathan_profiles: Array[LeviathanProfile] = []
@export_range(0, 16, 1) var max_leviathans: int = 3

var _star_system: Node3D
var _star_radius_m: float = 300.0
var _spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(star_system: Node3D, system_seed: int, star_radius_m: float) -> void:
	_star_system = star_system
	_star_radius_m = star_radius_m
	_spawn_rng.seed = system_seed ^ 0x1EA1A7A5

	_clear_spawned()

	if leviathan_profiles.is_empty():
		return

	var system_data: SystemData = _star_system.get("system_data")
	var outer_bound_m: float = _estimate_outer_bound_m(system_data)

	var spawn_count: int = _spawn_rng.randi_range(1, max_leviathans)

	for _spawn_index: int in spawn_count:
		_spawn_one_leviathan(outer_bound_m)

func get_active_leviathans() -> Array[LeviathanBody]:
	var result: Array[LeviathanBody] = []

	for child: Node in get_children():
		var leviathan: LeviathanBody = child as LeviathanBody

		if leviathan == null:
			continue

		if not is_instance_valid(leviathan):
			continue

		result.append(leviathan)

	return result

func get_obstacle_list() -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = []

	if _star_system == null:
		return obstacles

	var system_data: SystemData = _star_system.get("system_data")

	if system_data == null:
		return obstacles

	var star_center: Vector3 = _star_system.global_position

	obstacles.append({"center": star_center, "radius_m": _star_radius_m})

	for planet_data: PlanetData in system_data.planets:
		var planet_position: Vector3 = planet_data.get_orbit_position(
			star_center
		)

		obstacles.append({
			"center": planet_position,
			"radius_m": planet_data.radius_m
		})

		for moon_data: PlanetData in planet_data.moons:
			var moon_position: Vector3 = moon_data.get_orbit_position(
				planet_position
			)

			obstacles.append({
				"center": moon_position,
				"radius_m": moon_data.radius_m
			})

	return obstacles


func _spawn_one_leviathan(outer_bound_m: float) -> void:
	var profile: LeviathanProfile = leviathan_profiles[
		_spawn_rng.randi_range(0, leviathan_profiles.size() - 1)
	]

	if profile.creature_scene == null:
		push_warning(
			"LeviathanSpawner: profile '%s' has no creature_scene"
			% profile.display_name
		)
		return

	var instance: Node = profile.creature_scene.instantiate()
	var leviathan: LeviathanBody = instance as LeviathanBody

	if leviathan == null:
		push_error(
			"LeviathanSpawner: scene root for '%s' is not LeviathanBody"
			% profile.display_name
		)
		instance.queue_free()
		return

	add_child(leviathan)

	var spawn_direction: Vector3 = Vector3(
		_spawn_rng.randf_range(-1.0, 1.0),
		_spawn_rng.randf_range(-1.0, 1.0),
		_spawn_rng.randf_range(-1.0, 1.0)
	)

	if spawn_direction.length_squared() < 0.0001:
		spawn_direction = Vector3.UP
	else:
		spawn_direction = spawn_direction.normalized()

	var spawn_distance_m: float = _spawn_rng.randf_range(
		outer_bound_m * 0.5,
		outer_bound_m
	)

	var spawn_position: Vector3 = (
		_star_system.global_position + spawn_direction * spawn_distance_m
	)

	leviathan.setup(profile, spawn_position, get_obstacle_list)


func _estimate_outer_bound_m(system_data: SystemData) -> float:
	var outer_bound_m: float = _star_radius_m

	if system_data == null:
		return outer_bound_m

	for planet_data: PlanetData in system_data.planets:
		var planet_outer_m: float = (
			planet_data.orbit_distance_m + planet_data.radius_m
		)
		outer_bound_m = maxf(outer_bound_m, planet_outer_m)

	return outer_bound_m


func _clear_spawned() -> void:
	for child: Node in get_children():
		if child is LeviathanBody:
			child.queue_free()

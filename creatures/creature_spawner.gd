class_name CreatureSpawner
extends Node3D

const SPAWN_ANCHOR_GROUP: StringName = &"creature_spawn_anchor"

@export_category("Streaming")

@export_range(0, 64, 1)
var max_active_creatures: int = 8

@export_range(1.0, 500.0, 1.0, "suffix:m")
var spawn_min_distance_m: float = 25.0

@export_range(1.0, 500.0, 1.0, "suffix:m")
var spawn_max_distance_m: float = 60.0

@export_range(1.0, 1000.0, 1.0, "suffix:m")
var despawn_distance_m: float = 90.0

@export_range(0.1, 10.0, 0.1, "suffix:s")
var refresh_interval_s: float = 0.75

@export_range(-1.0, 1.0, 0.01)
var min_slope_dot: float = 0.25

@export_range(1, 128, 1)
var spawn_attempts_per_refresh: int = 12

@export_range(0.0, 10.0, 0.01, "suffix:m")
var land_surface_offset_m: float = 0.15

@export_category("Debug")

@export var debug_logging: bool = false

var _planet_data: PlanetData
var _surface_sampler: PlanetSurfaceSampler = PlanetSurfaceSampler.new()
var _spawn_anchor: Node3D
var _refresh_timer_s: float = 0.0
var _spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_instance_seed: int = 0

## Which creatures this planet's SurfaceProfile allows, sourced from
## CreaturePlanetProfile.spawn_entries - not authored on the spawner
## itself, so the same scene works for every planet type.
var _active_entries: Array[CreatureSpawnEntry] = []

## Per-species concurrent cap for this planet instance, rolled once at
## setup() via CreatureSpawnEntry.get_spawn_count() so it stays fixed
## for the planet's lifetime instead of re-rolling every refresh.
var _entry_target_counts: Dictionary = {}


func setup(data: PlanetData) -> void:
	_planet_data = data
	_spawn_anchor = null
	_refresh_timer_s = 0.0
	_next_instance_seed = 0
	_active_entries.clear()
	_entry_target_counts.clear()

	_clear_spawned()

	if _planet_data == null:
		return

	_spawn_rng.seed = _planet_data.planet_seed ^ 0x4F1BBCDC

	var surface_profile: Resource = _planet_data.surface_profile
	var noise_type: int = 0

	if surface_profile != null:
		var raw_noise_type: Variant = surface_profile.get(
			"terrain_noise_type"
		)

		if raw_noise_type != null:
			noise_type = int(raw_noise_type)

		var raw_creature_profile: Variant = surface_profile.get(
			"creature_profile"
		)

		if raw_creature_profile is CreaturePlanetProfile:
			_active_entries = raw_creature_profile.get_active_entries()

			for entry: CreatureSpawnEntry in _active_entries:
				if entry.creature_profile == null:
					continue

				_entry_target_counts[entry.creature_profile] = (
					entry.get_spawn_count(_spawn_rng)
				)

	_surface_sampler.setup(
		_planet_data.radius_m,
		_planet_data.planet_seed,
		_planet_data.terrain_noise_scale,
		_planet_data.terrain_height_m,
		noise_type,
		surface_profile
	)


func _physics_process(delta: float) -> void:
	if _planet_data == null:
		return

	if not _ensure_spawn_anchor():
		return

	_refresh_timer_s -= delta

	if _refresh_timer_s > 0.0:
		return

	_refresh_timer_s = refresh_interval_s

	_despawn_distant_creatures()
	_fill_active_creatures()


func _ensure_spawn_anchor() -> bool:
	if _spawn_anchor != null:
		if is_instance_valid(_spawn_anchor):
			if _spawn_anchor.is_in_group(SPAWN_ANCHOR_GROUP):
				return true

	_spawn_anchor = get_tree().get_first_node_in_group(
		SPAWN_ANCHOR_GROUP
	) as Node3D

	if _spawn_anchor == null:
		if debug_logging:
			push_warning(
				"CreatureSpawner: no Node3D in group "
				+ "'creature_spawn_anchor'"
			)
		return false

	return true


func _despawn_distant_creatures() -> void:
	if _spawn_anchor == null:
		return

	var anchor_local_position: Vector3 = to_local(
		_spawn_anchor.global_position
	)

	for child: Node in get_children():
		var creature: CreatureBody = child as CreatureBody

		if creature == null:
			continue

		var distance_m: float = creature.position.distance_to(
			anchor_local_position
		)

		if distance_m > despawn_distance_m:
			if debug_logging:
				print(
					"CreatureSpawner: despawned ",
					creature.creature_profile.display_name
				)

			creature.queue_free()


func _fill_active_creatures() -> void:
	var active_count: int = _get_active_creature_count()

	if active_count >= max_active_creatures:
		return

	var missing_count: int = (
		max_active_creatures - active_count
	)

	var pending_entries: Array[CreatureSpawnEntry] = (
		_get_pending_entries()
	)

	if pending_entries.is_empty():
		return

	## Round-robin across every species that still needs individuals,
	## instead of one shared random pool - guarantees every underfilled
	## species gets real attempts every refresh, regardless of how many
	## other species are competing for the same random rolls.
	var attempts_per_entry: int = maxi(
		spawn_attempts_per_refresh / pending_entries.size(),
		1
	)

	for entry: CreatureSpawnEntry in pending_entries:
		if missing_count <= 0:
			return

		var target_count: int = _entry_target_counts.get(
			entry.creature_profile,
			0
		)

		for _attempt_index: int in attempts_per_entry:
			if missing_count <= 0:
				return

			var alive_count: int = _get_alive_count_for_profile(
				entry.creature_profile
			)

			if alive_count >= target_count:
				break

			if _try_spawn_entry(entry):
				missing_count -= 1


func _get_pending_entries() -> Array[CreatureSpawnEntry]:
	var pending: Array[CreatureSpawnEntry] = []

	for entry: CreatureSpawnEntry in _active_entries:
		if entry.creature_profile == null:
			continue

		var target_count: int = _entry_target_counts.get(
			entry.creature_profile,
			0
		)

		if target_count <= 0:
			continue

		var alive_count: int = _get_alive_count_for_profile(
			entry.creature_profile
		)

		if alive_count >= target_count:
			continue

		pending.append(entry)

	return pending


func _try_spawn_entry(entry: CreatureSpawnEntry) -> bool:
	var profile: CreatureProfile = entry.creature_profile

	match profile.locomotion_mode:
		CreatureProfile.LocomotionMode.SURFACE_CLING, CreatureProfile.LocomotionMode.SURFACE_HOP:
			return _try_spawn_surface_creature(profile)
		CreatureProfile.LocomotionMode.FLYING:
			return _try_spawn_flying_creature(profile)
		CreatureProfile.LocomotionMode.SWIMMING:
			return _try_spawn_swimming_creature(profile)

	return false


func _try_spawn_surface_creature(profile: CreatureProfile) -> bool:
	if _spawn_anchor == null:
		return false

	var anchor_local_position: Vector3 = to_local(
		_spawn_anchor.global_position
	)

	var anchor_direction: Vector3 = (
		anchor_local_position.normalized()
	)

	if anchor_direction.length_squared() < 0.0001:
		return false

	var tangent_a: Vector3 = anchor_direction.cross(
		Vector3.UP
	)

	if tangent_a.length_squared() < 0.0001:
		tangent_a = anchor_direction.cross(Vector3.RIGHT)

	tangent_a = tangent_a.normalized()

	var tangent_b: Vector3 = anchor_direction.cross(
		tangent_a
	).normalized()

	var bearing_rad: float = _spawn_rng.randf_range(0.0, TAU)

	var surface_distance_m: float = _spawn_rng.randf_range(
		spawn_min_distance_m,
		spawn_max_distance_m
	)

	var angular_distance_rad: float = (
		surface_distance_m
		/ maxf(_planet_data.radius_m, 0.001)
	)

	var tangent_direction: Vector3 = (
		tangent_a * cos(bearing_rad)
		+ tangent_b * sin(bearing_rad)
	).normalized()

	var candidate_direction: Vector3 = (
		anchor_direction * cos(angular_distance_rad)
		+ tangent_direction * sin(angular_distance_rad)
	).normalized()

	var candidate_normal: Vector3 = (
		_surface_sampler.get_surface_normal(
			candidate_direction
		).normalized()
	)

	if candidate_normal.dot(candidate_direction) < min_slope_dot:
		return false

	if not _surface_sampler.is_surface_above_water(
		candidate_direction,
		0.0
	):
		return false

	var surface_position: Vector3 = (
		_surface_sampler.get_surface_position(
			candidate_direction
		)
		+ candidate_normal * land_surface_offset_m
	)

	var yaw_rad: float = _spawn_rng.randf_range(-PI, PI)

	var spawn_basis: Basis = _make_surface_basis(
		candidate_normal,
		yaw_rad
	)

	var spawn_transform: Transform3D = Transform3D(
		spawn_basis,
		surface_position
	)

	return _spawn_creature(
		profile,
		spawn_transform,
		candidate_normal
	)


func _try_spawn_flying_creature(profile: CreatureProfile) -> bool:
	if _spawn_anchor == null:
		return false

	var anchor_local_position: Vector3 = to_local(
		_spawn_anchor.global_position
	)

	## Flying creatures orbit at a fixed altitude above the surface -
	## spawn them on a random point of that orbit shell near the
	## anchor, not on the terrain itself.
	var random_direction: Vector3 = Vector3(
		_spawn_rng.randf_range(-1.0, 1.0),
		_spawn_rng.randf_range(-1.0, 1.0),
		_spawn_rng.randf_range(-1.0, 1.0)
	)

	if random_direction.length_squared() < 0.0001:
		random_direction = Vector3.UP
	else:
		random_direction = random_direction.normalized()

	var anchor_direction: Vector3 = anchor_local_position.normalized()

	if anchor_direction.length_squared() < 0.0001:
		anchor_direction = Vector3.UP

	var bearing_rad: float = _spawn_rng.randf_range(0.0, TAU)
	var horizontal_distance_m: float = _spawn_rng.randf_range(
		spawn_min_distance_m,
		spawn_max_distance_m
	)

	var tangent_a: Vector3 = anchor_direction.cross(Vector3.UP)

	if tangent_a.length_squared() < 0.0001:
		tangent_a = anchor_direction.cross(Vector3.RIGHT)

	tangent_a = tangent_a.normalized()

	var tangent_b: Vector3 = anchor_direction.cross(
		tangent_a
	).normalized()

	var angular_distance_rad: float = (
		horizontal_distance_m
		/ maxf(_planet_data.radius_m + profile.flight_altitude_m, 0.001)
	)

	var tangent_direction: Vector3 = (
		tangent_a * cos(bearing_rad)
		+ tangent_b * sin(bearing_rad)
	).normalized()

	var candidate_direction: Vector3 = (
		anchor_direction * cos(angular_distance_rad)
		+ tangent_direction * sin(angular_distance_rad)
	).normalized()

	var orbit_radius_m: float = (
		_planet_data.radius_m + profile.flight_altitude_m
	)

	var spawn_position: Vector3 = (
		candidate_direction * orbit_radius_m
	)

	var yaw_rad: float = _spawn_rng.randf_range(-PI, PI)
	var spawn_basis: Basis = _make_surface_basis(
		candidate_direction,
		yaw_rad
	)

	var spawn_transform: Transform3D = Transform3D(
		spawn_basis,
		spawn_position
	)

	return _spawn_creature(
		profile,
		spawn_transform,
		candidate_direction
	)


func _try_spawn_swimming_creature(profile: CreatureProfile) -> bool:
	if _spawn_anchor == null:
		return false

	var anchor_local_position: Vector3 = to_local(
		_spawn_anchor.global_position
	)

	var anchor_direction: Vector3 = anchor_local_position.normalized()

	if anchor_direction.length_squared() < 0.0001:
		return false

	var tangent_a: Vector3 = anchor_direction.cross(Vector3.UP)

	if tangent_a.length_squared() < 0.0001:
		tangent_a = anchor_direction.cross(Vector3.RIGHT)

	tangent_a = tangent_a.normalized()

	var tangent_b: Vector3 = anchor_direction.cross(
		tangent_a
	).normalized()

	## Steep coastal terrain shrinks the underwater slice of the search
	## ring - retry several bearings/distances before giving up, instead
	## of failing the whole attempt on the first dry roll.
	const MAX_GEOMETRY_RETRIES: int = 8

	for _retry_index: int in MAX_GEOMETRY_RETRIES:
		var bearing_rad: float = _spawn_rng.randf_range(0.0, TAU)
		var surface_distance_m: float = _spawn_rng.randf_range(
			spawn_min_distance_m,
			spawn_max_distance_m
		)

		var angular_distance_rad: float = (
			surface_distance_m
			/ maxf(_planet_data.radius_m, 0.001)
		)

		var tangent_direction: Vector3 = (
			tangent_a * cos(bearing_rad)
			+ tangent_b * sin(bearing_rad)
		).normalized()

		var candidate_direction: Vector3 = (
			anchor_direction * cos(angular_distance_rad)
			+ tangent_direction * sin(angular_distance_rad)
		).normalized()

		if not _surface_sampler.is_underwater(candidate_direction):
			continue

		var candidate_normal: Vector3 = (
			_surface_sampler.get_surface_normal(
				candidate_direction
			).normalized()
		)

		var sea_level_radius_m: float = (
			_surface_sampler.get_sea_level_radius_m()
		)
		var surface_radius_m: float = (
			_surface_sampler.get_surface_radius_m(candidate_direction)
		)

		var swim_depth_ratio: float = _spawn_rng.randf_range(0.2, 0.8)
		var swim_radius_m: float = lerpf(
			surface_radius_m,
			sea_level_radius_m,
			swim_depth_ratio
		)

		var spawn_position: Vector3 = (
			candidate_direction * swim_radius_m
		)

		var yaw_rad: float = _spawn_rng.randf_range(-PI, PI)
		var spawn_basis: Basis = _make_surface_basis(
			candidate_normal,
			yaw_rad
		)

		var spawn_transform: Transform3D = Transform3D(
			spawn_basis,
			spawn_position
		)

		return _spawn_creature(
			profile,
			spawn_transform,
			candidate_normal
		)

	return false


func _get_active_creature_count() -> int:
	var count: int = 0

	for child: Node in get_children():
		if child is CreatureBody:
			count += 1

	return count


func _get_alive_count_for_profile(profile: CreatureProfile) -> int:
	var count: int = 0

	for child: Node in get_children():
		var creature: CreatureBody = child as CreatureBody

		if creature == null:
			continue

		if creature.creature_profile == profile:
			count += 1

	return count


func _spawn_creature(
	profile: CreatureProfile,
	spawn_transform: Transform3D,
	surface_normal: Vector3
) -> bool:
	if profile == null:
		return false

	if profile.creature_scene == null:
		push_warning(
			"CreatureSpawner: profile '%s' has no creature_scene"
			% profile.display_name
		)
		return false

	var instance: Node = profile.creature_scene.instantiate()
	var creature: CreatureBody = instance as CreatureBody

	if creature == null:
		push_error(
			"CreatureSpawner: scene root for '%s' "
			+ "is not CreatureBody"
			% profile.display_name
		)
		instance.queue_free()
		return false

	add_child(creature)

	creature.setup(
		profile,
		spawn_transform,
		surface_normal,
		Vector3.ZERO,
		_surface_sampler
	)

	_next_instance_seed += 1

	if debug_logging:
		print(
			"CreatureSpawner: spawned %s at %s "
			% [profile.display_name, spawn_transform.origin]
		)

	return true


func _clear_spawned() -> void:
	for child: Node in get_children():
		if child is CreatureBody:
			child.queue_free()


func _make_surface_basis(
	surface_normal: Vector3,
	yaw_rad: float
) -> Basis:
	var up: Vector3 = surface_normal.normalized()
	var reference_axis: Vector3 = Vector3.FORWARD

	if absf(reference_axis.dot(up)) > 0.98:
		reference_axis = Vector3.RIGHT

	var right: Vector3 = reference_axis.cross(up).normalized()
	var forward: Vector3 = up.cross(right).normalized()

	var basis: Basis = Basis(right, up, forward)
	return basis.rotated(up, yaw_rad)

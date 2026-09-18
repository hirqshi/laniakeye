class_name SurfaceClingLocomotion
extends CreatureLocomotionStrategy

var _travel_direction: Vector3 = Vector3.FORWARD
var _time_until_next_turn_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _facing_basis: Basis = Basis.IDENTITY
var _has_facing_basis: bool = false


func enter(body: CreatureBody) -> void:
	if body.surface_sampler == null:
		return

	_rng.randomize()

	var direction_from_center: Vector3 = (
		body.position - body.planet_center
	).normalized()

	var surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(
			direction_from_center
		).normalized()
	)

	_travel_direction = _random_tangent(
		surface_normal,
		_rng.randf_range(0.0, TAU)
	)

	_schedule_next_turn(body)
	_has_facing_basis = false
	_snap_to_surface(body, 0.0)


func update(body: CreatureBody, delta: float) -> void:
	if body.creature_profile == null:
		return

	if body.surface_sampler == null:
		return

	if delta <= 0.0:
		return

	var profile: CreatureProfile = body.creature_profile

	var current_direction: Vector3 = (
		body.position - body.planet_center
	).normalized()

	var surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(
			current_direction
		).normalized()
	)

	_travel_direction = _project_on_plane(
		_travel_direction,
		surface_normal
	)

	if _travel_direction.length_squared() < 0.0001:
		_travel_direction = _random_tangent(
			surface_normal,
			_rng.randf_range(0.0, TAU)
		)
	else:
		_travel_direction = _travel_direction.normalized()

	var turn_angle_rad: float = _rng.randf_range(
		-profile.spider_walk_turn_speed_rad_s,
		profile.spider_walk_turn_speed_rad_s
	) * delta

	_travel_direction = _travel_direction.rotated(
		surface_normal,
		turn_angle_rad
	).normalized()

	var surface_radius_m: float = (
		body.surface_sampler.get_surface_radius_m(
			current_direction
		)
	)

	var angular_step_rad: float = (
		profile.spider_walk_speed_mps
		* delta
		/ maxf(surface_radius_m, 0.001)
	)

	var next_direction: Vector3 = (
		current_direction * cos(angular_step_rad)
		+ _travel_direction * sin(angular_step_rad)
	).normalized()

	var next_surface_position: Vector3 = (
		body.planet_center
		+ body.surface_sampler.get_surface_position(
			next_direction
		)
		- body.surface_sampler.get_surface_normal(next_direction)
		* profile.spider_ground_sink_m
	)

	var next_surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(
			next_direction
		).normalized()
	)

	body.surface_up_direction = next_surface_normal
	body.position = next_surface_position

	_orient_body(
		body,
		_travel_direction,
		next_surface_normal,
		delta
	)

	_time_until_next_turn_s -= delta

	if _time_until_next_turn_s <= 0.0:
		_pick_new_travel_direction(next_surface_normal, profile)
		_schedule_next_turn(body)


func _pick_new_travel_direction(
	surface_normal: Vector3,
	profile: CreatureProfile
) -> void:
	var safe_current: Vector3 = _project_on_plane(
		_travel_direction,
		surface_normal
	)

	if safe_current.length_squared() < 0.0001:
		safe_current = _random_tangent(
			surface_normal,
			_rng.randf_range(0.0, TAU)
		)
	else:
		safe_current = safe_current.normalized()

	var reroll_chance: float = clampf(
		profile.spider_walk_direction_reroll_chance,
		0.0,
		1.0
	)

	if _rng.randf() < reroll_chance:
		_travel_direction = _random_tangent(
			surface_normal,
			_rng.randf_range(0.0, TAU)
		)
		return

	var jitter_rad: float = _rng.randf_range(
		-profile.spider_walk_direction_jitter_rad,
		profile.spider_walk_direction_jitter_rad
	)

	_travel_direction = safe_current.rotated(
		surface_normal,
		jitter_rad
	).normalized()


func _schedule_next_turn(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var minimum_interval_s: float = minf(
		profile.spider_walk_turn_interval_min_s,
		profile.spider_walk_turn_interval_max_s
	)
	var maximum_interval_s: float = maxf(
		profile.spider_walk_turn_interval_min_s,
		profile.spider_walk_turn_interval_max_s
	)

	_time_until_next_turn_s = _rng.randf_range(
		minimum_interval_s,
		maximum_interval_s
	)


func _snap_to_surface(body: CreatureBody, delta: float) -> void:
	if body.surface_sampler == null:
		return

	var direction_from_center: Vector3 = (
		body.position - body.planet_center
	).normalized()

	var surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(direction_from_center)
	)

	var sink_m: float = 0.0

	if body.creature_profile != null:
		sink_m = body.creature_profile.spider_ground_sink_m

	var surface_position: Vector3 = (
		body.planet_center
		+ body.surface_sampler.get_surface_position(direction_from_center)
		- surface_normal * sink_m
	)

	body.surface_up_direction = surface_normal
	body.position = surface_position

	_orient_body(body, _travel_direction, surface_normal, delta)


func _orient_body(
	body: CreatureBody,
	forward_direction: Vector3,
	up_direction: Vector3,
	delta: float
) -> void:
	var up: Vector3 = up_direction.normalized()

	var forward: Vector3 = _project_on_plane(
		forward_direction,
		up
	)

	if forward.length_squared() < 0.0001:
		return

	forward = forward.normalized()

	var right: Vector3 = forward.cross(up).normalized()

	if right.length_squared() < 0.0001:
		return

	var target_basis: Basis = Basis(right, up, -forward).orthonormalized()

	if not _has_facing_basis:
		_facing_basis = target_basis
		_has_facing_basis = true
	else:
		var turn_speed: float = 4.0

		if body.creature_profile != null:
			turn_speed = body.creature_profile.spider_turn_smoothing_speed

		var safe_current_basis: Basis = _facing_basis.orthonormalized()

		_facing_basis = safe_current_basis.slerp(
			target_basis,
			clampf(turn_speed * delta, 0.0, 1.0)
		).orthonormalized()

	body.basis = _facing_basis


func _project_on_plane(
	vector: Vector3,
	plane_normal: Vector3
) -> Vector3:
	return vector - plane_normal * vector.dot(plane_normal)


func _random_tangent(
	up: Vector3,
	yaw_rad: float
) -> Vector3:
	var reference_axis: Vector3 = Vector3.FORWARD

	if absf(reference_axis.dot(up)) > 0.98:
		reference_axis = Vector3.RIGHT

	var right: Vector3 = reference_axis.cross(up).normalized()
	var forward: Vector3 = up.cross(right).normalized()

	return (
		right * cos(yaw_rad)
		+ forward * sin(yaw_rad)
	).normalized()

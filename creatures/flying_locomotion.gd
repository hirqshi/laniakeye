class_name FlyingLocomotion
extends CreatureLocomotionStrategy

var _orbit_axis: Vector3 = Vector3.UP
var _orbit_radius_m: float = 0.0
var _target_orbit_radius_m: float = 0.0
var _time_until_next_turn_s: float = 0.0
var _time_until_next_altitude_change_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _facing_basis: Basis = Basis.IDENTITY
var _has_facing_basis: bool = false


func enter(body: CreatureBody) -> void:
	if body.creature_profile == null:
		return

	_rng.randomize()

	var relative_position: Vector3 = (
		body.position - body.planet_center
	)

	_orbit_radius_m = relative_position.length()

	if _orbit_radius_m < 0.001:
		_orbit_radius_m = body.creature_profile.flight_altitude_m
		relative_position = Vector3.UP * _orbit_radius_m
		body.position = body.planet_center + relative_position

	_target_orbit_radius_m = _orbit_radius_m

	var radial_direction: Vector3 = relative_position.normalized()

	_orbit_axis = _random_tangent(
		radial_direction,
		_rng.randf_range(0.0, TAU)
	).cross(radial_direction).normalized()

	if _orbit_axis.length_squared() < 0.0001:
		_orbit_axis = Vector3.UP.cross(radial_direction).normalized()

	if _orbit_axis.length_squared() < 0.0001:
		_orbit_axis = Vector3.RIGHT

	_schedule_next_turn(body)
	_schedule_next_altitude_change(body)

	_orient_body(body, relative_position, 0.0)


func update(body: CreatureBody, delta: float) -> void:
	if body.creature_profile == null:
		return

	if delta <= 0.0:
		return

	var profile: CreatureProfile = body.creature_profile

	var relative_position: Vector3 = (
		body.position - body.planet_center
	)

	if relative_position.length_squared() < 0.0001:
		relative_position = Vector3.UP * maxf(_orbit_radius_m, 0.001)

	var current_radius_m: float = relative_position.length()

	## Constant angular speed keeps linear speed constant too, since
	## the radius barely changes frame to frame - true orbital motion,
	## not velocity integration, so there is nothing to drift or blow up.
	var angular_speed_rad_s: float = (
		profile.flight_speed_mps / maxf(current_radius_m, 0.001)
	)

	var rotation: Basis = Basis(
		_orbit_axis,
		angular_speed_rad_s * delta
	)

	relative_position = rotation * relative_position

	_orbit_radius_m = lerpf(
		_orbit_radius_m,
		_target_orbit_radius_m,
		clampf(profile.flight_altitude_change_speed * delta, 0.0, 1.0)
	)

	relative_position = relative_position.normalized() * _orbit_radius_m

	body.position = body.planet_center + relative_position

	_orient_body(body, relative_position, delta)

	_time_until_next_turn_s -= delta

	if _time_until_next_turn_s <= 0.0:
		_pick_new_orbit_axis(relative_position.normalized())
		_schedule_next_turn(body)

	_time_until_next_altitude_change_s -= delta

	if _time_until_next_altitude_change_s <= 0.0:
		_pick_new_target_altitude(body)
		_schedule_next_altitude_change(body)


func _pick_new_orbit_axis(radial_direction: Vector3) -> void:
	var current_forward: Vector3 = _orbit_axis.cross(
		radial_direction
	).normalized()

	if current_forward.length_squared() < 0.0001:
		current_forward = _random_tangent(
			radial_direction,
			_rng.randf_range(0.0, TAU)
		)

	var jitter_rad: float = _rng.randf_range(
		-PI * 0.35,
		PI * 0.35
	)

	var new_forward: Vector3 = current_forward.rotated(
		radial_direction,
		jitter_rad
	).normalized()

	_orbit_axis = new_forward.cross(radial_direction).normalized()

	if _orbit_axis.length_squared() < 0.0001:
		_orbit_axis = Vector3.UP.cross(radial_direction).normalized()

	if _orbit_axis.length_squared() < 0.0001:
		_orbit_axis = Vector3.RIGHT


func _pick_new_target_altitude(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var altitude_variation_m: float = _rng.randf_range(
		-profile.flight_altitude_variation_m,
		profile.flight_altitude_variation_m
	)

	var base_radius_m: float = _orbit_radius_m

	if body.surface_sampler != null:
		var relative_position: Vector3 = (
			body.position - body.planet_center
		)

		if relative_position.length_squared() > 0.0001:
			base_radius_m = body.surface_sampler.get_surface_radius_m(
				relative_position.normalized()
			)

	_target_orbit_radius_m = maxf(
		base_radius_m + profile.flight_altitude_m + altitude_variation_m,
		0.001
	)


func _schedule_next_turn(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var minimum_interval_s: float = minf(
		profile.flight_turn_interval_min_s,
		profile.flight_turn_interval_max_s
	)
	var maximum_interval_s: float = maxf(
		profile.flight_turn_interval_min_s,
		profile.flight_turn_interval_max_s
	)

	_time_until_next_turn_s = _rng.randf_range(
		minimum_interval_s,
		maximum_interval_s
	)


func _schedule_next_altitude_change(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var minimum_interval_s: float = minf(
		profile.flight_altitude_interval_min_s,
		profile.flight_altitude_interval_max_s
	)
	var maximum_interval_s: float = maxf(
		profile.flight_altitude_interval_min_s,
		profile.flight_altitude_interval_max_s
	)

	_time_until_next_altitude_change_s = _rng.randf_range(
		minimum_interval_s,
		maximum_interval_s
	)


func _orient_body(
	body: CreatureBody,
	relative_position: Vector3,
	delta: float
) -> void:
	var up: Vector3 = relative_position.normalized()

	var orbital_forward: Vector3 = _orbit_axis.cross(up).normalized()

	if orbital_forward.length_squared() < 0.0001:
		return

	var altitude_delta_m: float = _target_orbit_radius_m - _orbit_radius_m
	var pitch_ratio: float = clampf(
		altitude_delta_m / maxf(body.creature_profile.flight_altitude_variation_m, 0.001),
		-1.0,
		1.0
	)

	var desired_forward: Vector3 = (
		orbital_forward - up * pitch_ratio
	).normalized()

	var right: Vector3 = desired_forward.cross(up).normalized()

	if right.length_squared() < 0.0001:
		return

	var target_basis: Basis = Basis(
		right,
		up,
		-desired_forward
	).orthonormalized()

	if not _has_facing_basis:
		_facing_basis = target_basis
		_has_facing_basis = true
	else:
		var turn_speed: float = body.creature_profile.flight_turn_smoothing_speed
		var safe_current_basis: Basis = _facing_basis.orthonormalized()

		_facing_basis = safe_current_basis.slerp(
			target_basis,
			clampf(turn_speed * delta, 0.0, 1.0)
		).orthonormalized()

	body.surface_up_direction = up
	body.basis = _facing_basis


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

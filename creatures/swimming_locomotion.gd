class_name SwimmingLocomotion
extends CreatureLocomotionStrategy

var _swim_axis: Vector3 = Vector3.UP
var _swim_radius_m: float = 0.0
var _target_swim_radius_m: float = 0.0
var _time_until_next_turn_s: float = 0.0
var _time_until_next_depth_change_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _facing_basis: Basis = Basis.IDENTITY
var _has_facing_basis: bool = false


func enter(body: CreatureBody) -> void:
	if body.creature_profile == null:
		return

	if body.surface_sampler == null:
		return

	_rng.randomize()

	var relative_position: Vector3 = (
		body.position - body.planet_center
	)

	if relative_position.length_squared() < 0.0001:
		relative_position = Vector3.UP * 0.001
		body.position = body.planet_center + relative_position

	_swim_radius_m = relative_position.length()
	_swim_radius_m = _clamp_to_water_column(
		body,
		relative_position.normalized(),
		_swim_radius_m
	)
	_target_swim_radius_m = _swim_radius_m

	var radial_direction: Vector3 = relative_position.normalized()

	_swim_axis = _random_tangent(
		radial_direction,
		_rng.randf_range(0.0, TAU)
	).cross(radial_direction).normalized()

	if _swim_axis.length_squared() < 0.0001:
		_swim_axis = Vector3.UP.cross(radial_direction).normalized()

	if _swim_axis.length_squared() < 0.0001:
		_swim_axis = Vector3.RIGHT

	_schedule_next_turn(body)
	_schedule_next_depth_change(body)

	body.position = (
		body.planet_center
		+ radial_direction * _swim_radius_m
	)

	_has_facing_basis = false
	_orient_body(body, radial_direction * _swim_radius_m, 0.0)


func update(body: CreatureBody, delta: float) -> void:
	if body.creature_profile == null:
		return

	if body.surface_sampler == null:
		return

	if delta <= 0.0:
		return

	var profile: CreatureProfile = body.creature_profile

	var relative_position: Vector3 = (
		body.position - body.planet_center
	)

	if relative_position.length_squared() < 0.0001:
		relative_position = Vector3.UP * maxf(_swim_radius_m, 0.001)

	var current_radius_m: float = relative_position.length()

	## Same trick as FlyingLocomotion: rotate the position vector at a
	## fixed angular speed instead of integrating velocity, so linear
	## speed stays constant and there is nothing to accelerate or
	## tunnel through walls with.
	var angular_speed_rad_s: float = (
		profile.swim_speed_mps / maxf(current_radius_m, 0.001)
	)

	var rotation: Basis = Basis(
		_swim_axis,
		angular_speed_rad_s * delta
	)

	relative_position = rotation * relative_position

	_swim_radius_m = lerpf(
		_swim_radius_m,
		_target_swim_radius_m,
		clampf(profile.swim_depth_change_speed * delta, 0.0, 1.0)
	)

	var radial_direction: Vector3 = relative_position.normalized()

	_swim_radius_m = _clamp_to_water_column(
		body,
		radial_direction,
		_swim_radius_m
	)

	relative_position = radial_direction * _swim_radius_m
	body.position = body.planet_center + relative_position

	_orient_body(body, relative_position, delta)

	_time_until_next_turn_s -= delta

	if _time_until_next_turn_s <= 0.0:
		_pick_new_swim_axis(radial_direction)
		_schedule_next_turn(body)

	_time_until_next_depth_change_s -= delta

	if _time_until_next_depth_change_s <= 0.0:
		_pick_new_target_depth(body, radial_direction)
		_schedule_next_depth_change(body)


## Keeps the swim radius strictly between the seafloor and the water
## surface, with a soft margin so the creature turns away from a wall
## instead of clipping through it or hugging it exactly.
func _clamp_to_water_column(
	body: CreatureBody,
	radial_direction: Vector3,
	radius_m: float
) -> float:
	var floor_radius_m: float = body.surface_sampler.get_surface_radius_m(
		radial_direction
	)
	var ceiling_radius_m: float = body.surface_sampler.get_sea_level_radius_m()

	var margin_m: float = body.creature_profile.swim_wall_margin_m

	var min_radius_m: float = floor_radius_m + margin_m
	var max_radius_m: float = ceiling_radius_m - margin_m

	if min_radius_m > max_radius_m:
		## Water column thinner than double the margin (shallow spot) -
		## just center the creature between the two real bounds.
		return (floor_radius_m + ceiling_radius_m) * 0.5

	return clampf(radius_m, min_radius_m, max_radius_m)


func _pick_new_swim_axis(radial_direction: Vector3) -> void:
	var current_forward: Vector3 = _swim_axis.cross(
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

	_swim_axis = new_forward.cross(radial_direction).normalized()

	if _swim_axis.length_squared() < 0.0001:
		_swim_axis = Vector3.UP.cross(radial_direction).normalized()

	if _swim_axis.length_squared() < 0.0001:
		_swim_axis = Vector3.RIGHT


func _pick_new_target_depth(
	body: CreatureBody,
	radial_direction: Vector3
) -> void:
	var profile: CreatureProfile = body.creature_profile

	var floor_radius_m: float = body.surface_sampler.get_surface_radius_m(
		radial_direction
	)
	var ceiling_radius_m: float = body.surface_sampler.get_sea_level_radius_m()

	var preferred_radius_m: float = floor_radius_m + (
		ceiling_radius_m - floor_radius_m
	) * profile.swim_preferred_depth_ratio

	var depth_variation_m: float = _rng.randf_range(
		-profile.swim_depth_variation_m,
		profile.swim_depth_variation_m
	)

	_target_swim_radius_m = _clamp_to_water_column(
		body,
		radial_direction,
		preferred_radius_m + depth_variation_m
	)


func _schedule_next_turn(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var minimum_interval_s: float = minf(
		profile.swim_turn_interval_min_s,
		profile.swim_turn_interval_max_s
	)
	var maximum_interval_s: float = maxf(
		profile.swim_turn_interval_min_s,
		profile.swim_turn_interval_max_s
	)

	_time_until_next_turn_s = _rng.randf_range(
		minimum_interval_s,
		maximum_interval_s
	)


func _schedule_next_depth_change(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var minimum_interval_s: float = minf(
		profile.swim_depth_interval_min_s,
		profile.swim_depth_interval_max_s
	)
	var maximum_interval_s: float = maxf(
		profile.swim_depth_interval_min_s,
		profile.swim_depth_interval_max_s
	)

	_time_until_next_depth_change_s = _rng.randf_range(
		minimum_interval_s,
		maximum_interval_s
	)


func _orient_body(
	body: CreatureBody,
	relative_position: Vector3,
	delta: float
) -> void:
	var up: Vector3 = relative_position.normalized()

	var orbital_forward: Vector3 = _swim_axis.cross(up).normalized()

	if orbital_forward.length_squared() < 0.0001:
		return

	var depth_delta_m: float = _target_swim_radius_m - _swim_radius_m
	var pitch_ratio: float = clampf(
		depth_delta_m / maxf(body.creature_profile.swim_depth_variation_m, 0.001),
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
		var turn_speed: float = body.creature_profile.swim_turn_smoothing_speed
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

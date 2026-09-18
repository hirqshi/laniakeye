class_name SurfaceHopLocomotion
extends CreatureLocomotionStrategy

enum State {
	UNDERGROUND,
	AIRBORNE
}

var _state: State = State.UNDERGROUND
var _time_until_next_hop_s: float = 0.0
var _air_velocity: Vector3 = Vector3.ZERO
var _arc_axis: Vector3 = Vector3.RIGHT
var _travel_direction: Vector3 = Vector3.FORWARD
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _has_left_ground: bool = false


func enter(body: CreatureBody) -> void:
	if body.creature_profile == null:
		return

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

	_snap_underground(body)
	_schedule_next_hop(body)


func update(body: CreatureBody, delta: float) -> void:
	if body.creature_profile == null:
		return

	if body.surface_sampler == null:
		return

	if delta <= 0.0:
		return

	match _state:
		State.UNDERGROUND:
			_update_underground(body, delta)
		State.AIRBORNE:
			_update_airborne(body, delta)


func _update_underground(
	body: CreatureBody,
	delta: float
) -> void:
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
		-profile.burrow_turn_speed_rad_s,
		profile.burrow_turn_speed_rad_s
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
		profile.burrow_speed_mps
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
	)

	var next_surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(
			next_direction
		).normalized()
	)

	body.surface_up_direction = next_surface_normal
	body.position = (
		next_surface_position
		- next_surface_normal * profile.burrow_depth_m
	)

	_orient_body(
		body,
		_travel_direction,
		next_surface_normal
	)

	_time_until_next_hop_s -= delta

	if _time_until_next_hop_s > 0.0:
		return

	_launch(body, next_direction, next_surface_normal)


func _update_airborne(
	body: CreatureBody,
	delta: float
) -> void:
	var profile: CreatureProfile = body.creature_profile

	var previous_position: Vector3 = body.position
	var previous_relative_position: Vector3 = (
		previous_position - body.planet_center
	)

	if previous_relative_position.length_squared() < 0.0001:
		_state = State.UNDERGROUND
		_schedule_next_hop(body)
		return

	var previous_direction: Vector3 = (
		previous_relative_position.normalized()
	)

	var local_up: Vector3 = (
		body.surface_sampler.get_surface_normal(
			previous_direction
		).normalized()
	)

	body.surface_up_direction = local_up

	## Constant-speed arc: rotate the velocity vector instead of
	## accelerating it. Rotation preserves the vector's length, so the
	## worm's flight speed never changes - no gravity, no ramp-up.
	_air_velocity = _air_velocity.rotated(
		_arc_axis,
		-profile.hop_arc_turn_rate_rad_s * delta
	)

	var integrated_position: Vector3 = (
		previous_position + _air_velocity * delta
	)
	var integrated_relative_position: Vector3 = (
		integrated_position - body.planet_center
	)

	if integrated_relative_position.length_squared() < 0.0001:
		_state = State.UNDERGROUND
		_schedule_next_hop(body)
		return

	var integrated_direction: Vector3 = (
		integrated_relative_position.normalized()
	)

	var terrain_position: Vector3 = (
		body.planet_center
		+ body.surface_sampler.get_surface_position(
			integrated_direction
		)
	)

	var integrated_radius_m: float = (
		integrated_relative_position.length()
	)
	var terrain_radius_m: float = (
		terrain_position - body.planet_center
	).length()

	if integrated_radius_m > terrain_radius_m:
		_has_left_ground = true
		body.position = integrated_position
		_orient_body(body, _air_velocity, local_up)
		return

	if not _has_left_ground:
		## Still rising through the ground on the way out - keep flying,
		## this is not a landing yet.
		body.position = integrated_position
		_orient_body(body, _air_velocity, local_up)
		return

	## Landing. Find where along this frame's motion the body actually
	## crosses the terrain instead of teleporting from wherever it
	## overshot to - keeps head speed continuous through touchdown.
	var previous_radius_m: float = (
		previous_relative_position.length()
	)
	var radius_delta_m: float = (
		previous_radius_m - integrated_radius_m
	)

	var impact_t: float = 1.0

	if radius_delta_m > 0.0001:
		impact_t = clampf(
			(previous_radius_m - terrain_radius_m) / radius_delta_m,
			0.0,
			1.0
		)

	var impact_position: Vector3 = previous_position.lerp(
		integrated_position,
		impact_t
	)

	var impact_direction: Vector3 = (
		impact_position - body.planet_center
	).normalized()

	var landing_surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(
			impact_direction
		).normalized()
	)

	_travel_direction = _project_on_plane(
		_air_velocity,
		landing_surface_normal
	).normalized()

	if _travel_direction.length_squared() < 0.0001:
		_travel_direction = _random_tangent(
			landing_surface_normal,
			_rng.randf_range(0.0, TAU)
		)

	body.surface_up_direction = landing_surface_normal
	body.position = (
		impact_position
		- landing_surface_normal * profile.burrow_depth_m
	)

	_orient_body(
		body,
		_travel_direction,
		landing_surface_normal
	)

	_state = State.UNDERGROUND
	_schedule_next_hop(body)


func _launch(
	body: CreatureBody,
	direction_from_center: Vector3,
	surface_normal: Vector3
) -> void:
	var profile: CreatureProfile = body.creature_profile

	_travel_direction = _pick_new_travel_direction(
		_travel_direction,
		surface_normal,
		profile
	)

	_air_velocity = (
		surface_normal * profile.hop_launch_speed_mps
		+ _travel_direction * profile.hop_horizontal_speed_mps
	)

	_arc_axis = _travel_direction.cross(surface_normal).normalized()

	if _arc_axis.length_squared() < 0.0001:
		_arc_axis = Vector3.RIGHT

	_has_left_ground = false

	_orient_body(
		body,
		_travel_direction,
		surface_normal
	)

	_state = State.AIRBORNE


func _pick_new_travel_direction(
	current_direction: Vector3,
	surface_normal: Vector3,
	profile: CreatureProfile
) -> Vector3:
	var safe_current: Vector3 = _project_on_plane(
		current_direction,
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
		profile.hop_direction_reroll_chance,
		0.0,
		1.0
	)

	if _rng.randf() < reroll_chance:
		return _random_tangent(
			surface_normal,
			_rng.randf_range(0.0, TAU)
		)

	var jitter_rad: float = _rng.randf_range(
		-profile.hop_direction_jitter_rad,
		profile.hop_direction_jitter_rad
	)

	return safe_current.rotated(
		surface_normal,
		jitter_rad
	).normalized()


func _snap_underground(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var direction_from_center: Vector3 = (
		body.position - body.planet_center
	).normalized()

	if direction_from_center.length_squared() < 0.0001:
		return

	var surface_position: Vector3 = (
		body.planet_center
		+ body.surface_sampler.get_surface_position(
			direction_from_center
		)
	)

	var surface_normal: Vector3 = (
		body.surface_sampler.get_surface_normal(
			direction_from_center
		).normalized()
	)

	body.surface_up_direction = surface_normal
	body.position = (
		surface_position
		- surface_normal * profile.burrow_depth_m
	)

	_reset_worm_trail_if_needed(body)

	_travel_direction = _project_on_plane(
		_travel_direction,
		surface_normal
	).normalized()

	if _travel_direction.length_squared() < 0.0001:
		_travel_direction = _random_tangent(
			surface_normal,
			_rng.randf_range(0.0, TAU)
		)

	_orient_body(
		body,
		_travel_direction,
		surface_normal
	)


func _schedule_next_hop(body: CreatureBody) -> void:
	var profile: CreatureProfile = body.creature_profile

	var minimum_interval_s: float = minf(
		profile.hop_interval_min_s,
		profile.hop_interval_max_s
	)
	var maximum_interval_s: float = maxf(
		profile.hop_interval_min_s,
		profile.hop_interval_max_s
	)

	_time_until_next_hop_s = _rng.randf_range(
		minimum_interval_s,
		maximum_interval_s
	)


func _orient_body(
	body: CreatureBody,
	forward_direction: Vector3,
	up_direction: Vector3
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

	body.basis = Basis(
		right,
		up,
		-forward
	)


func _reset_worm_trail_if_needed(body: CreatureBody) -> void:
	if body.creature_profile == null:
		return

	if body.creature_profile.creature_type != CreatureProfile.CreatureType.WORM:
		return

	body.reset_worm_trail()


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

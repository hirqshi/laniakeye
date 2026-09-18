class_name LeviathanLocomotion
extends RefCounted

var _travel_direction: Vector3 = Vector3.FORWARD
var _time_until_next_course_change_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _facing_basis: Basis = Basis.IDENTITY
var _has_facing_basis: bool = false


func enter(body: Node3D, profile: LeviathanProfile) -> void:
	_rng.randomize()

	_travel_direction = _random_direction()
	_schedule_next_course_change(profile)

	_has_facing_basis = false
	_orient_body(body, _travel_direction, 0.0)


func update(
	body: Node3D,
	profile: LeviathanProfile,
	obstacles: Array[Dictionary],
	delta: float
) -> void:
	if delta <= 0.0:
		return

	var avoidance_direction: Vector3 = _get_avoidance_direction(
		body.global_position,
		profile,
		obstacles
	)

	if avoidance_direction != Vector3.ZERO:
		_travel_direction = _travel_direction.slerp(
			avoidance_direction,
			clampf(profile.avoidance_turn_speed_rad_s * delta, 0.0, 1.0)
		).normalized()
	else:
		_time_until_next_course_change_s -= delta

		if _time_until_next_course_change_s <= 0.0:
			_pick_new_course(profile)
			_schedule_next_course_change(profile)

	var speed_mps: float = profile.get_effective_speed_mps()
	body.global_position += _travel_direction * speed_mps * delta

	_orient_body(body, _travel_direction, delta)


## Simple distance-based steering: look ahead along the current travel
## direction, and if any obstacle's surface (plus margin) would be
## crossed within avoidance_lookahead_m, steer away from it. Deliberately
## not a full physics avoidance solver - leviathans just need to visibly
## dodge planets/moons/the star, not navigate a dense asteroid field.
func _get_avoidance_direction(
	position: Vector3,
	profile: LeviathanProfile,
	obstacles: Array[Dictionary]
) -> Vector3:
	var strongest_avoidance: Vector3 = Vector3.ZERO
	var closest_distance_m: float = INF

	for obstacle: Dictionary in obstacles:
		var obstacle_center: Vector3 = obstacle.get("center", Vector3.ZERO)
		var obstacle_radius_m: float = obstacle.get("radius_m", 0.0)

		var to_obstacle: Vector3 = obstacle_center - position
		var distance_m: float = to_obstacle.length()

		var danger_radius_m: float = (
			obstacle_radius_m + profile.avoidance_margin_m
		)

		if distance_m > profile.avoidance_lookahead_m + danger_radius_m:
			continue

		var along_travel_m: float = to_obstacle.dot(_travel_direction)

		if along_travel_m <= 0.0:
			## Obstacle is behind us relative to travel direction - not
			## on a collision course, ignore it.
			continue

		var closest_approach: Vector3 = (
			to_obstacle - _travel_direction * along_travel_m
		)
		var closest_approach_distance_m: float = closest_approach.length()

		if closest_approach_distance_m >= danger_radius_m:
			continue

		if distance_m >= closest_distance_m:
			continue

		closest_distance_m = distance_m

		var away_from_obstacle: Vector3 = -closest_approach

		if away_from_obstacle.length_squared() < 0.0001:
			away_from_obstacle = _travel_direction.cross(Vector3.UP)

			if away_from_obstacle.length_squared() < 0.0001:
				away_from_obstacle = _travel_direction.cross(Vector3.RIGHT)

		strongest_avoidance = (
			_travel_direction + away_from_obstacle.normalized()
		).normalized()

	return strongest_avoidance


func _pick_new_course(profile: LeviathanProfile) -> void:
	var jitter: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	)

	if jitter.length_squared() < 0.0001:
		return

	var jitter_axis: Vector3 = _travel_direction.cross(
		jitter.normalized()
	).normalized()

	if jitter_axis.length_squared() < 0.0001:
		return

	var jitter_angle_rad: float = _rng.randf_range(
		0.0,
		profile.course_change_jitter_rad
	)

	_travel_direction = _travel_direction.rotated(
		jitter_axis,
		jitter_angle_rad
	).normalized()


func _schedule_next_course_change(profile: LeviathanProfile) -> void:
	_time_until_next_course_change_s = _rng.randf_range(
		profile.course_change_interval_min_s,
		profile.course_change_interval_max_s
	)


func _orient_body(
	body: Node3D,
	forward_direction: Vector3,
	delta: float
) -> void:
	var forward: Vector3 = forward_direction.normalized()

	if forward.length_squared() < 0.0001:
		return

	var reference_up: Vector3 = Vector3.UP

	if absf(forward.dot(reference_up)) > 0.98:
		reference_up = Vector3.RIGHT

	var right: Vector3 = forward.cross(reference_up).normalized()
	var up: Vector3 = right.cross(forward).normalized()

	var target_basis: Basis = Basis(right, up, -forward).orthonormalized()

	if not _has_facing_basis:
		_facing_basis = target_basis
		_has_facing_basis = true
	else:
		var safe_current_basis: Basis = _facing_basis.orthonormalized()

		_facing_basis = safe_current_basis.slerp(
			target_basis,
			clampf(2.0 * delta, 0.0, 1.0)
		).orthonormalized()

	body.basis = _facing_basis


func _random_direction() -> Vector3:
	var direction: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	)

	if direction.length_squared() < 0.0001:
		return Vector3.FORWARD

	return direction.normalized()

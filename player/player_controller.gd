extends CharacterBody3D

## Handles three movement modes: PLANET (gravity toward sphere center),
## FLAT (ship interior, gravity along a moving body's local -Y), ZERO_G.
##
## HARD GROUND LOCK: while grounded and not jumping, vertical physics is
## disabled - each frame we raycast down and force global_position to sit
## exactly at ground_offset_m above the hit point. move_and_slide() only
## resolves horizontal collisions while locked.
##
## FIX (velocity carryover on gravity mode switch): set_planet_gravity /
## set_flat_gravity / set_zero_g now all zero out velocity explicitly.
##
## FIX (ground probe scaled per-planet): ground_probe_distance_m and
## ground_lock_tolerance_m now scale off the planet's actual radius via
## _recalibrate_ground_probe_for_source(), instead of one fixed value for
## every planet regardless of size.
##
## FIX (jump height varies wildly with planet gravity): jump_velocity is
## rescaled per-gravity via GravityBodyMath.get_effective_jump_velocity()
## so jump HEIGHT stays roughly constant across different planet
## gravities (3.0 to 16.0).
##
## FIX (idle drift/jitter on rotating planets): _run_locked_ground_frame
## now re-derives position from the cached _local_offset via to_global()
## instead of re-raycasting every single frame while stationary - avoids
## chasing a noisy terrain-mesh raycast that could land on a slightly
## different triangle/height frame to frame.
##
## FIX (FLAT-mode velocity spike on jump, e.g. inside a ship): when there
## is no horizontal input, _local_planar_offset is now resynced to the
## body's ACTUAL current local X/Z every frame instead of trusting a
## carried-over value. Previously, any frame where the real position
## drifted even slightly from the stored offset (most visibly right as a
## jump launched) created a permanent gap between them. Since
## horizontal_velocity = (to_global(offset) - global_position) / delta,
## that gap gets amplified by 1/delta (60x at 60 fps) into a huge spurious
## velocity that shoved the body sideways every subsequent frame - this is
## what was launching players into the ceiling/walls after jumping inside
## a stationary ship, with the HUD speedometer showing up to ~30 m/s.
##
## FIX (camera sinking into/below floor on slopes): removed the old
## camera vertical smoothing hack. With the hard ground lock in place, ANY
## vertical movement while grounded is fully intentional and authoritative
## - the raycast lock IS the correct ground-following mechanism.
##
## REFACTOR: gravity falloff curve and jump velocity scaling now delegate
## to GravityBodyMath (generation/gravity_body_math.gd) instead of local
## private methods - ship_controller.gd used an identical copy of the
## falloff curve, this kills the duplication. Debug print() calls
## replaced with DebugLog.physics() (core/debug_log.gd), which no-ops
## unless explicitly enabled and always no-ops in release exports.

signal moved(is_moving: bool, is_running: bool)
signal jumped
signal gravity_mode_changed(is_zero_g: bool)
signal landed

enum GravityMode { PLANET, FLAT, ZERO_G }

@export var body_pivot: Node3D
@export var camera_pivot: Node3D
@export var player_camera: Camera3D

@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var zero_g_speed: float = 5.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.003
@export var pitch_clamp_deg: float = 89.0
@export var gravity_fade_curve_power: float = 1.5
@export var gravity_multiplier: float = 1.0
@export var floor_max_angle_deg: float = 55.0
@export var collision_safe_margin_m: float = 0.005
@export var max_horizontal_speed_multiplier: float = 2.5

## hard ground lock settings - TUNE ground_offset_m to your capsule shape
@export var ground_offset_m: float = 1.0
@export var ground_probe_start_offset_m: float = 0.5
@export var ground_probe_distance_m: float = 3.0
@export var ground_lock_tolerance_m: float = 0.3
@export_flags_3d_physics var ground_probe_collision_mask: int = 1

var gravity_mode: GravityMode = GravityMode.ZERO_G
var surface_gravity_strength: float = 9.8
var gravity_source: Node3D = null
var _vertical_speed: float = 0.0
var _is_ground_locked: bool = false
var _jump_active: bool = false

# sphere mode carrier (planet walking - pinned radius from center)
var _local_offset: Vector3 = Vector3.ZERO
var _local_offset_initialized: bool = false
var _local_carrier_radius: float = 0.0
var _orientation_slerp_speed: float = 10.0

# flat mode carrier (ship deck walking - pinned local X/Z, free local Y)
var _local_planar_offset: Vector2 = Vector2.ZERO
var _local_planar_initialized: bool = false

var pitch_rad: float = 0.0
var is_running: bool = false
var is_controllable: bool = true

func _ready() -> void:
	SpawnAnchorService.set_active_anchor(self)
	FloatingOriginManager.origin_shifted.connect(_on_origin_shifted)
	add_to_group("player")
	floor_max_angle = deg_to_rad(floor_max_angle_deg)
	floor_stop_on_slope = true
	safe_margin = collision_safe_margin_m

func _on_origin_shifted(shift: Vector3) -> void:
	set_physics_process(false)
	global_position += shift
	call_deferred("_reenable_physics_process")

func _reenable_physics_process() -> void:
	set_physics_process(true)

func set_planet_gravity(source: Node3D, strength: float) -> void:
	DebugLog.physics("MODE SWITCH to PLANET: player_pos=%s source=%s" % [global_position, source])
	if gravity_source != source:
		_local_offset_initialized = false
		_recalibrate_ground_probe_for_source(source)

	gravity_source = source
	surface_gravity_strength = strength
	gravity_mode = GravityMode.PLANET
	_vertical_speed = 0.0
	_is_ground_locked = false
	_jump_active = false
	velocity = Vector3.ZERO
	gravity_mode_changed.emit(false)
	_update_planet_ambient(source)

func _update_planet_ambient(source: Node3D) -> void:
	if not is_instance_valid(source) or not source.has_method("get_ambient_loop"):
		AudioManager.set_planet_ambient(null)
		return

	AudioManager.set_planet_ambient(source.call("get_ambient_loop"))

func set_flat_gravity(source: Node3D, strength: float) -> void:
	DebugLog.physics("MODE SWITCH to FLAT: player_pos=%s source=%s" % [global_position, source])
	gravity_source = source
	surface_gravity_strength = strength
	gravity_mode = GravityMode.FLAT
	_vertical_speed = 0.0
	_is_ground_locked = false
	_jump_active = false
	_local_planar_initialized = false
	velocity = Vector3.ZERO
	gravity_mode_changed.emit(false)
	AudioManager.set_planet_ambient(null)

func set_zero_g() -> void:
	DebugLog.physics("MODE SWITCH to ZERO_G: player_pos=%s" % global_position)
	gravity_source = null
	gravity_mode = GravityMode.ZERO_G
	up_direction = Vector3.UP
	_is_ground_locked = false
	_jump_active = false
	_local_offset_initialized = false
	_local_planar_initialized = false
	velocity = Vector3.ZERO
	gravity_mode_changed.emit(true)
	AudioManager.set_planet_ambient(null)

func get_current_gravity_source() -> Node3D:
	return gravity_source

func get_player_camera() -> Camera3D:
	return player_camera

func set_controllable(value: bool) -> void:
	is_controllable = value

func _physics_process(delta: float) -> void:
	if not is_controllable:
		return

	match gravity_mode:
		GravityMode.PLANET:
			if is_instance_valid(gravity_source):
				_process_sphere_movement(delta)
			else:
				set_zero_g()
				_process_zero_g_movement(delta)
		GravityMode.FLAT:
			if is_instance_valid(gravity_source):
				_process_flat_surface_movement(delta)
			else:
				set_zero_g()
				_process_zero_g_movement(delta)
		GravityMode.ZERO_G:
			_process_zero_g_movement(delta)

func _process_sphere_movement(delta: float) -> void:
	if not _local_offset_initialized:
		_local_offset = gravity_source.to_local(global_position)
		_local_carrier_radius = _local_offset.length()
		_local_offset_initialized = true

	up_direction = (global_position - gravity_source.global_position).normalized()

	var current_basis: Basis = _basis_from_up(up_direction, global_transform.basis)

	var distance_to_center: float = global_position.distance_to(gravity_source.global_position)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1
	var speed: float = run_speed if is_running else walk_speed
	if gravity_source.has_method("is_point_underwater") and gravity_source.call("is_point_underwater", global_position):
		speed *= gravity_source.call("get_underwater_speed_multiplier")

	var world_move_dir: Vector3 = (current_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() if input_dir.length() > 0.01 else Vector3.ZERO
	var local_move_dir: Vector3 = gravity_source.global_transform.basis.inverse() * world_move_dir
	var local_horizontal_delta: Vector3 = local_move_dir * speed * delta

	_local_offset += local_horizontal_delta
	var horizontal_target_world_pos: Vector3 = gravity_source.to_global(_local_offset)
	var horizontal_velocity: Vector3 = (horizontal_target_world_pos - global_position) / delta if delta > 0.0 else Vector3.ZERO
	horizontal_velocity -= horizontal_velocity.project(up_direction)

	var max_horizontal_speed: float = (run_speed + gravity_source.call("get_radius") * 0.2) * max_horizontal_speed_multiplier if gravity_source.has_method("get_radius") else run_speed * max_horizontal_speed_multiplier
	if horizontal_velocity.length() > max_horizontal_speed:
		horizontal_velocity = horizontal_velocity.normalized() * max_horizontal_speed

	global_transform.basis = global_transform.basis.slerp(current_basis, _orientation_slerp_speed * delta).orthonormalized()

	var gravity_strength: float = _get_falloff_gravity_strength(distance_to_center)
	var ground_probe: Dictionary = _probe_ground()
	var grounded_in_range: bool = ground_probe.found and ground_probe.distance <= ground_offset_m + ground_lock_tolerance_m
	var jump_requested: bool = Input.is_action_just_pressed("jump")

	# a jump, once triggered, stays "active" (locking disabled) until the
	# body is falling back down AND ground is back in range - prevents
	# the lock from re-engaging one frame later and cutting the jump short
	if _jump_active and _vertical_speed <= 0.0 and grounded_in_range:
		_jump_active = false
		landed.emit()

	if grounded_in_range and not _jump_active and not jump_requested:
		_run_locked_ground_frame(horizontal_velocity, not _is_ground_locked)
	elif grounded_in_range and not _jump_active and jump_requested:
		_vertical_speed = GravityBodyMath.get_effective_jump_velocity(jump_velocity, gravity_strength)
		_jump_active = true
		_is_ground_locked = false
		jumped.emit()
		_vertical_speed -= gravity_strength * delta
		velocity = horizontal_velocity + up_direction * _vertical_speed
		move_and_slide()
	else:
		_is_ground_locked = false
		_vertical_speed -= gravity_strength * delta
		velocity = horizontal_velocity + up_direction * _vertical_speed
		move_and_slide()

	_local_offset = gravity_source.to_local(global_position)
	if _local_carrier_radius > 0.0:
		_local_offset = _local_offset.normalized() * _local_carrier_radius

	moved.emit(input_dir.length() > 0.1, is_running)

func _process_flat_surface_movement(delta: float) -> void:
	if gravity_source.has_method("get_platform_motion_delta"):
		var platform_motion_delta: Vector3 = gravity_source.call("get_platform_motion_delta")
		if not platform_motion_delta.is_zero_approx():
			global_position += platform_motion_delta

	var current_local_position: Vector3 = gravity_source.to_local(global_position)

	if not _local_planar_initialized:
		_local_planar_offset = Vector2(current_local_position.x, current_local_position.z)
		_local_planar_initialized = true
		DebugLog.physics("FLAT INIT: local_pos=%s ship_pos=%s" % [current_local_position, gravity_source.global_position])

	up_direction = gravity_source.global_transform.basis.y.normalized()

	var current_basis: Basis = _basis_from_up(up_direction, global_transform.basis)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1
	var speed: float = run_speed if is_running else walk_speed

	var has_input: bool = input_dir.length() > 0.01
	var horizontal_velocity: Vector3 = Vector3.ZERO

	if has_input:
		var world_move_dir: Vector3 = (current_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		var local_move_dir: Vector3 = gravity_source.global_transform.basis.inverse() * world_move_dir
		var local_horizontal_delta: Vector2 = Vector2(local_move_dir.x, local_move_dir.z) * speed * delta

		_local_planar_offset += local_horizontal_delta

		var horizontal_target_local_pos: Vector3 = Vector3(_local_planar_offset.x, current_local_position.y, _local_planar_offset.y)
		var horizontal_target_world_pos: Vector3 = gravity_source.to_global(horizontal_target_local_pos)
		horizontal_velocity = (horizontal_target_world_pos - global_position) / delta if delta > 0.0 else Vector3.ZERO
		horizontal_velocity -= horizontal_velocity.project(up_direction)

		var max_horizontal_speed: float = run_speed * max_horizontal_speed_multiplier
		if horizontal_velocity.length() > max_horizontal_speed:
			horizontal_velocity = horizontal_velocity.normalized() * max_horizontal_speed
	else:
		# no input - don't round-trip position through to_local()/to_global()
		# every frame, that repeated matrix inverse+multiply at large world
		# coordinates introduces tiny orientation-dependent floating point
		# error that compounds every physics frame into a slow directional
		# drift. Just keep the offset in sync without touching global_position.
		_local_planar_offset = Vector2(current_local_position.x, current_local_position.z)

	global_transform.basis = global_transform.basis.slerp(current_basis, 10.0 * delta).orthonormalized()

	var ground_probe: Dictionary = _probe_ground()
	var grounded_in_range: bool = ground_probe.found and ground_probe.distance <= ground_offset_m + ground_lock_tolerance_m
	var jump_requested: bool = Input.is_action_just_pressed("jump")
	var pos_before_frame: Vector3 = global_position

	if _jump_active and _vertical_speed <= 0.0 and grounded_in_range:
		_jump_active = false
		landed.emit()

	if grounded_in_range and not _jump_active and not jump_requested:
		_run_locked_ground_frame(horizontal_velocity, not _is_ground_locked)
	elif grounded_in_range and not _jump_active and jump_requested:
		_vertical_speed = GravityBodyMath.get_effective_jump_velocity(jump_velocity, surface_gravity_strength * gravity_multiplier)
		DebugLog.physics("FLAT JUMP START: launch_v=%s gravity=%s pos=%s" % [_vertical_speed, surface_gravity_strength * gravity_multiplier, global_position])
		_jump_active = true
		_is_ground_locked = false
		jumped.emit()
		_vertical_speed -= surface_gravity_strength * gravity_multiplier * delta
		velocity = horizontal_velocity + up_direction * _vertical_speed
		move_and_slide()
	else:
		_is_ground_locked = false
		_vertical_speed -= surface_gravity_strength * gravity_multiplier * delta
		velocity = horizontal_velocity + up_direction * _vertical_speed
		move_and_slide()

	if _jump_active and abs(_vertical_speed) > 15.0:
		DebugLog.physics("FLAT JUMP RUNAWAY: v_speed=%s grounded_in_range=%s ground_probe_found=%s ground_probe_dist=%s pos=%s ship_pos=%s" % [_vertical_speed, grounded_in_range, ground_probe.found, ground_probe.distance, global_position, gravity_source.global_position])

	if global_position.distance_to(pos_before_frame) > 2.0:
		DebugLog.physics("FLAT TELEPORT: before=%s after=%s h_vel=%s ground_probe_found=%s ground_probe_dist=%s grounded_in_range=%s up_dir=%s ship_pos=%s" % [pos_before_frame, global_position, horizontal_velocity, ground_probe.found, ground_probe.distance, grounded_in_range, up_direction, gravity_source.global_position])

	var post_move_local_position: Vector3 = gravity_source.to_local(global_position)
	_local_planar_offset = Vector2(post_move_local_position.x, post_move_local_position.z)

	moved.emit(input_dir.length() > 0.1, is_running)

## Runs one frame of hard-locked ground movement: horizontal-only velocity
## goes through move_and_slide() for wall collisions, then the resulting
## position is forcibly re-pinned to the ground surface via a fresh
## raycast, completely overriding whatever vertical drift move_and_slide
## introduced. No sliding, no separation, no floor-snap flicker.
func _run_locked_ground_frame(horizontal_velocity: Vector3, was_falling: bool) -> void:
	_vertical_speed = 0.0

	var can_use_frozen_anchor: bool = false
	var frozen_anchor_target: Vector3 = global_position

	if gravity_mode == GravityMode.PLANET and _local_offset_initialized:
		can_use_frozen_anchor = true
		frozen_anchor_target = gravity_source.to_global(_local_offset)
	elif gravity_mode == GravityMode.FLAT and _local_planar_initialized:
		can_use_frozen_anchor = true
		var current_local_position: Vector3 = gravity_source.to_local(global_position)
		var target_local: Vector3 = Vector3(_local_planar_offset.x, current_local_position.y, _local_planar_offset.y)
		frozen_anchor_target = gravity_source.to_global(target_local)

	if horizontal_velocity.length() < 0.001 and _is_ground_locked and can_use_frozen_anchor:
		global_position = frozen_anchor_target
		velocity = Vector3.ZERO
		move_and_slide()
		return

	velocity = horizontal_velocity
	move_and_slide()

	var post_move_probe: Dictionary = _probe_ground()
	if post_move_probe.found:
		var target_position: Vector3 = post_move_probe.hit_point + up_direction * ground_offset_m
		if was_falling:
			# easing the very first lock-in frame instead of an instant
			# snap - the gap here is at most ground_lock_tolerance_m, so
			# a fast lerp closes it in a couple of frames, imperceptibly
			global_position = global_position.lerp(target_position, 0.4)
		else:
			global_position = target_position

	_is_ground_locked = true

## Casts a ray from slightly above the body straight down (along
## -up_direction) to find the actual ground surface. Returns whether a
## hit was found, the hit point, and the signed distance from the body's
## origin to that point along up_direction.
func _probe_ground() -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_start: Vector3 = global_position + up_direction * ground_probe_start_offset_m
	var ray_end: Vector3 = global_position - up_direction * ground_probe_distance_m

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [self]
	query.collision_mask = ground_probe_collision_mask

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return {"found": false, "hit_point": Vector3.ZERO, "distance": INF}

	var hit_point: Vector3 = result.position
	var distance: float = (global_position - hit_point).dot(up_direction)
	return {"found": true, "hit_point": hit_point, "distance": distance}

## Scales the ground probe's reach and lock tolerance to the actual
## planet's radius, once, whenever gravity_source changes to a different
## body - a fixed probe window doesn't work equally well for a 40m moon
## and a 140m planet.
func _recalibrate_ground_probe_for_source(source: Node3D) -> void:
	if not source.has_method("get_radius"):
		return
	var radius_m: float = source.call("get_radius")
	ground_probe_distance_m = clamp(radius_m * 0.05, 1.0, 6.0)
	ground_lock_tolerance_m = clamp(radius_m * 0.01, 0.15, 0.6)
	# smaller planets have sharper curvature relative to walking speed,
	# so up_direction changes faster underfoot - the body's orientation
	# needs to catch up proportionally faster or it visibly lags behind
	# the actual surface normal, throwing jumps sideways instead of up
	_orientation_slerp_speed = clamp(400.0 / radius_m, 8.0, 30.0)

func _get_falloff_gravity_strength(distance_to_center: float) -> float:
	var strength: float = GravityBodyMath.get_falloff_gravity_strength(
		distance_to_center,
		surface_gravity_strength,
		gravity_multiplier,
		gravity_source,
		gravity_fade_curve_power
	)

	if gravity_source.has_method("is_point_underwater") and gravity_source.call("is_point_underwater", global_position):
		strength *= gravity_source.call("get_underwater_gravity_multiplier")

	return strength

func _process_zero_g_movement(delta: float) -> void:
	var input_dir: Vector3 = Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("move_forward", "move_back")
	)
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1

	var speed: float = zero_g_speed * (1.5 if is_running else 1.0)
	var move_dir: Vector3 = (global_transform.basis * input_dir).normalized() if input_dir.length() > 0.01 else Vector3.ZERO
	velocity = velocity.lerp(move_dir * speed, 8.0 * delta)
	move_and_slide()
	moved.emit(input_dir.length() > 0.1, is_running)

func _basis_from_up(new_up: Vector3, current_basis: Basis) -> Basis:
	var forward: Vector3 = -current_basis.z
	forward = (forward - new_up * forward.dot(new_up)).normalized()

	if forward.length_squared() < 0.001:
		forward = current_basis.x.cross(new_up).normalized()

	if forward.length_squared() < 0.001:
		var safe_axis: Vector3 = Vector3.FORWARD if absf(new_up.y) < 0.99 else Vector3.RIGHT
		forward = (safe_axis - new_up * safe_axis.dot(new_up)).normalized()

	var right: Vector3 = forward.cross(new_up).normalized()
	return Basis(right, new_up, -forward)

func _unhandled_input(event: InputEvent) -> void:
	if not is_controllable:
		return
	if event is InputEventMouseMotion:
		match gravity_mode:
			GravityMode.PLANET, GravityMode.FLAT:
				_apply_planet_look(event.relative)
			GravityMode.ZERO_G:
				_apply_zero_g_look(event.relative)

func _apply_planet_look(mouse_delta: Vector2) -> void:
	rotate_object_local(Vector3.UP, -mouse_delta.x * mouse_sensitivity)

	var pitch_limit: float = deg_to_rad(pitch_clamp_deg)
	pitch_rad = clamp(pitch_rad - mouse_delta.y * mouse_sensitivity, -pitch_limit, pitch_limit)
	camera_pivot.rotation.x = pitch_rad

func _apply_zero_g_look(mouse_delta: Vector2) -> void:
	rotate_object_local(Vector3.UP, -mouse_delta.x * mouse_sensitivity)
	rotate_object_local(Vector3.RIGHT, -mouse_delta.y * mouse_sensitivity)

func _exit_tree() -> void:
	SpawnAnchorService.clear_active_anchor(self)

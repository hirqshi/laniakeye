extends CharacterBody3D

## Handles three movement modes: PLANET (gravity toward sphere center),
## FLAT (ship interior, gravity along a moving body's local -Y), ZERO_G.
##
## HARD GROUND LOCK: while grounded and not jumping, vertical physics is
## disabled - each frame we raycast down and force global_position to sit
## exactly at ground_offset_m above the hit point. move_and_slide() only
## resolves horizontal collisions while locked.
##
## FIX (camera sinking into/below floor on slopes): removed the old
## camera vertical smoothing hack (_update_camera_vertical_smoothing).
## It was designed to hide RESIDUAL, UNINTENTIONAL vertical noise from the
## days of relying on move_and_slide's automatic floor snap. With the hard
## ground lock now in place, ANY vertical movement while grounded (walking
## down/up a slope, following bumpy terrain) is fully intentional and
## authoritative - the raycast lock IS the correct ground-following
## mechanism, there's no more "noise" to hide. The smoothing hack was
## comparing actual vertical movement against velocity's vertical
## component (which is always exactly zero while locked, by design) and
## treating ALL real slope-following motion as "unexpected", subtracting
## it into a clamped camera offset that got stuck at its negative clamp
## while walking downhill for any stretch - visually sinking the camera
## toward/below the floor until the slope leveled out. No smoothing is
## needed anymore; the camera should simply follow the body 1:1.

signal moved(is_moving: bool, is_running: bool)
signal jumped
signal gravity_mode_changed(is_zero_g: bool)

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

# flat mode carrier (ship deck walking - pinned local X/Z, free local Y)
var _local_planar_offset: Vector2 = Vector2.ZERO
var _local_planar_initialized: bool = false

var pitch_rad: float = 0.0
var is_running: bool = false
var is_controllable: bool = true

func _ready() -> void:
	add_to_group("player")
	floor_max_angle = deg_to_rad(floor_max_angle_deg)
	floor_stop_on_slope = true
	safe_margin = collision_safe_margin_m

func set_planet_gravity(source: Node3D, strength: float) -> void:
	gravity_source = source
	surface_gravity_strength = strength
	gravity_mode = GravityMode.PLANET
	_vertical_speed = 0.0
	_is_ground_locked = false
	_jump_active = false
	_local_offset_initialized = false
	gravity_mode_changed.emit(false)

func set_flat_gravity(source: Node3D, strength: float) -> void:
	gravity_source = source
	surface_gravity_strength = strength
	gravity_mode = GravityMode.FLAT
	_vertical_speed = 0.0
	_is_ground_locked = false
	_jump_active = false
	_local_planar_initialized = false
	gravity_mode_changed.emit(false)

func set_zero_g() -> void:
	gravity_source = null
	gravity_mode = GravityMode.ZERO_G
	up_direction = Vector3.UP
	_is_ground_locked = false
	_jump_active = false
	_local_offset_initialized = false
	_local_planar_initialized = false
	gravity_mode_changed.emit(true)

func get_current_gravity_source() -> Node3D:
	return gravity_source

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

	global_transform.basis = global_transform.basis.slerp(current_basis, 10.0 * delta).orthonormalized()

	var gravity_strength: float = _get_falloff_gravity_strength(distance_to_center)
	var ground_probe: Dictionary = _probe_ground()
	var grounded_in_range: bool = ground_probe.found and ground_probe.distance <= ground_offset_m + ground_lock_tolerance_m
	var jump_requested: bool = Input.is_action_just_pressed("jump")

	# a jump, once triggered, stays "active" (locking disabled) until the
	# body is falling back down AND ground is back in range - prevents
	# the lock from re-engaging one frame later and cutting the jump short
	if _jump_active and _vertical_speed <= 0.0 and grounded_in_range:
		_jump_active = false

	if grounded_in_range and not _jump_active and not jump_requested:
		_run_locked_ground_frame(horizontal_velocity)
	elif grounded_in_range and not _jump_active and jump_requested:
		_vertical_speed = jump_velocity
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

	var local_body_position: Vector3 = gravity_source.to_local(global_position)
	if local_body_position.length_squared() > 0.000001:
		_local_offset = local_body_position.normalized() * _local_carrier_radius

	moved.emit(input_dir.length() > 0.1, is_running)

func _process_flat_surface_movement(delta: float) -> void:
	var current_local_position: Vector3 = gravity_source.to_local(global_position)

	if not _local_planar_initialized:
		_local_planar_offset = Vector2(current_local_position.x, current_local_position.z)
		_local_planar_initialized = true

	up_direction = gravity_source.global_transform.basis.y.normalized()

	var current_basis: Basis = _basis_from_up(up_direction, global_transform.basis)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1
	var speed: float = run_speed if is_running else walk_speed

	var world_move_dir: Vector3 = (current_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() if input_dir.length() > 0.01 else Vector3.ZERO
	var local_move_dir: Vector3 = gravity_source.global_transform.basis.inverse() * world_move_dir
	var local_horizontal_delta: Vector2 = Vector2(local_move_dir.x, local_move_dir.z) * speed * delta

	_local_planar_offset += local_horizontal_delta

	var horizontal_target_local_pos: Vector3 = Vector3(_local_planar_offset.x, current_local_position.y, _local_planar_offset.y)
	var horizontal_target_world_pos: Vector3 = gravity_source.to_global(horizontal_target_local_pos)
	var horizontal_velocity: Vector3 = (horizontal_target_world_pos - global_position) / delta if delta > 0.0 else Vector3.ZERO
	horizontal_velocity -= horizontal_velocity.project(up_direction)

	var max_horizontal_speed: float = run_speed * max_horizontal_speed_multiplier
	if horizontal_velocity.length() > max_horizontal_speed:
		horizontal_velocity = horizontal_velocity.normalized() * max_horizontal_speed

	global_transform.basis = global_transform.basis.slerp(current_basis, 10.0 * delta).orthonormalized()

	var ground_probe: Dictionary = _probe_ground()
	var grounded_in_range: bool = ground_probe.found and ground_probe.distance <= ground_offset_m + ground_lock_tolerance_m
	var jump_requested: bool = Input.is_action_just_pressed("jump")

	if _jump_active and _vertical_speed <= 0.0 and grounded_in_range:
		_jump_active = false

	if grounded_in_range and not _jump_active and not jump_requested:
		_run_locked_ground_frame(horizontal_velocity)
	elif grounded_in_range and not _jump_active and jump_requested:
		_vertical_speed = jump_velocity
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

	var post_move_local_position: Vector3 = gravity_source.to_local(global_position)
	_local_planar_offset = Vector2(post_move_local_position.x, post_move_local_position.z)

	moved.emit(input_dir.length() > 0.1, is_running)

## Runs one frame of hard-locked ground movement: horizontal-only velocity
## goes through move_and_slide() for wall collisions, then the resulting
## position is forcibly re-pinned to the ground surface via a fresh
## raycast, completely overriding whatever vertical drift move_and_slide
## introduced. No sliding, no separation, no floor-snap flicker.
func _run_locked_ground_frame(horizontal_velocity: Vector3) -> void:
	_vertical_speed = 0.0
	velocity = horizontal_velocity
	move_and_slide()

	var post_move_probe: Dictionary = _probe_ground()
	if post_move_probe.found:
		global_position = post_move_probe.hit_point + up_direction * ground_offset_m

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

func _get_falloff_gravity_strength(distance_to_center: float) -> float:
	var base_strength: float = surface_gravity_strength * gravity_multiplier

	if not gravity_source.has_method("get_radius") or not gravity_source.has_method("get_gravity_zone_radius"):
		return base_strength

	var surface_radius: float = gravity_source.call("get_radius")
	var zone_radius: float = gravity_source.call("get_gravity_zone_radius")

	if distance_to_center <= surface_radius:
		return base_strength

	if distance_to_center >= zone_radius:
		return 0.0

	var zone_depth: float = zone_radius - surface_radius
	var distance_past_surface: float = distance_to_center - surface_radius
	var fade_ratio: float = 1.0 - clamp(distance_past_surface / zone_depth, 0.0, 1.0)
	return base_strength * pow(fade_ratio, gravity_fade_curve_power)

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

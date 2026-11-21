class_name LkPlayerController
extends CharacterBody3D

## Player controller for the coordinate/gravity foundation (core/refactor_v1).
## Gravity and "up" come from LkGravityService sampled at the player's
## ABSOLUTE position - no gravity zones, no gravity_source nodes, no ground
## raycast lock. Movement is plain move_and_slide() + floor snap.
## NOT yet wired into the main game. Untested in Godot.

signal moved(is_moving: bool, is_running: bool)
signal jumped
signal landed
signal gravity_mode_changed(is_zero_g: bool)

@export var camera_pivot: Node3D
@export var player_camera: Camera3D

@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var zero_g_speed: float = 5.0
@export var jump_height_m: float = 1.2
@export var ground_acceleration: float = 40.0
@export var air_acceleration: float = 8.0
@export var align_speed: float = 12.0
@export var mouse_sensitivity: float = 0.003
@export var pitch_clamp_deg: float = 89.0
@export var floor_max_angle_deg: float = 55.0
@export var floor_snap_m: float = 0.35
@export var gravity_switch_ratio: float = 1.1
@export var rebase_after_move: bool = true
@export var eva_gravity_threshold: float = 0.05

var is_controllable: bool = true
var is_running: bool = false
var pitch_rad: float = 0.0
var dominant_body_id: StringName = &""
var gravity_acceleration: Vector3 = Vector3.ZERO

var _frame: LkCoordinateFrame
var _gravity: LkGravityService
var _has_gravity: bool = false
var _was_on_floor: bool = false
var _carrier_id: StringName = &""
var _carry_residual: LkPosition64 = LkPosition64.new()
var _eva: LkEvaDrive = LkEvaDrive.new()


func setup(frame: LkCoordinateFrame, gravity: LkGravityService) -> void:
	_frame = frame
	_gravity = gravity


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_max_angle = deg_to_rad(floor_max_angle_deg)
	floor_stop_on_slope = true
	floor_snap_length = floor_snap_m
	if player_camera != null:
		player_camera.current = true
	else:
		push_error("LkPlayerController: player_camera is null")
	if _frame != null:
		_frame.register_root(self)


func _exit_tree() -> void:
	if _frame != null:
		_frame.unregister_root(self)


func get_absolute_position() -> LkPosition64:
	return _frame.to_absolute(global_position)


func set_controllable(value: bool) -> void:
	is_controllable = value


# Spawn / seat exit: the body is already at rest relative to the surface,
# so no velocity conversion happens here.
func attach_to_frame(frame: LkRotatingFrame) -> void:
	_carrier_id = frame.body_id
	_carry_residual = LkPosition64.new()


func detach_from_frame() -> void:
	_carrier_id = &""
	_carry_residual = LkPosition64.new()


func carry_with_frame(frame: LkRotatingFrame, step_angle: float, max_distance_m: float = INF) -> void:
	if not is_controllable or _frame == null:
		return
	var rel: LkPosition64 = frame.relative_position(_frame.get_origin(), global_position)
	var should_carry: bool = dominant_body_id == frame.body_id and rel.length() <= max_distance_m
	var carried_now: bool = _carrier_id == frame.body_id
	if should_carry and not carried_now:
		velocity = frame.to_relative_velocity(velocity, rel)
		_carrier_id = frame.body_id
		_carry_residual = LkPosition64.new()
	elif not should_carry and carried_now:
		velocity = frame.to_inertial_velocity(velocity, rel)
		_carrier_id = &""
	if not should_carry:
		_carry_residual = LkPosition64.new()
		return
	# Error feedback: the float32 position cannot represent small per-tick
	# displacements exactly, so carry what was NOT applied into the next tick.
	var total: LkPosition64 = frame.carry_displacement64(rel, step_angle).plus(_carry_residual)
	var before: Vector3 = global_position
	global_position = before + Vector3(total.x, total.y, total.z)
	var after: Vector3 = global_position
	_carry_residual = total.minus(LkPosition64.new(float(after.x) - float(before.x), float(after.y) - float(before.y), float(after.z) - float(before.z)))
	var step: Basis = frame.step_basis(step_angle)
	global_basis = (step * global_basis).orthonormalized()
	velocity = step * velocity


func _physics_process(delta: float) -> void:
	if not is_controllable or _frame == null or _gravity == null:
		return

	var sample: Dictionary = _gravity.sample(get_absolute_position(), dominant_body_id, gravity_switch_ratio)
	dominant_body_id = sample["dominant_id"]
	var has_up: bool = sample["has_up"]
	_set_gravity_state(has_up)

	if has_up:
		gravity_acceleration = sample["acceleration"]
		up_direction = sample["up"]
		if gravity_acceleration.length() > eva_gravity_threshold:
			_walk(delta)
		else:
			_fly(delta)
	else:
		gravity_acceleration = Vector3.ZERO
		_fly(delta)

	if rebase_after_move:
		_frame.maybe_shift(global_position)


func _set_gravity_state(has_gravity: bool) -> void:
	if has_gravity == _has_gravity:
		return
	_has_gravity = has_gravity
	if has_gravity:
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	else:
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		# fold camera pitch into the body so free flight keeps the view
		rotate_object_local(Vector3.RIGHT, pitch_rad)
		pitch_rad = 0.0
		if camera_pivot != null:
			camera_pivot.rotation.x = 0.0
	gravity_mode_changed.emit(not has_gravity)


func _walk(delta: float) -> void:
	var up: Vector3 = up_direction
	_align_to_up(up, delta)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1
	var speed: float = run_speed if is_running else walk_speed

	var wish: Vector3 = Vector3.ZERO
	if input_dir.length() > 0.01:
		wish = global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		wish -= up * wish.dot(up)
		wish = wish.normalized() * speed

	var on_floor: bool = is_on_floor()
	var vertical_speed: float = velocity.dot(up)
	var horizontal: Vector3 = velocity - up * vertical_speed
	var accel: float = ground_acceleration if on_floor else air_acceleration
	horizontal = horizontal.move_toward(wish, accel * delta)

	var g: float = gravity_acceleration.length()
	if on_floor and vertical_speed < 0.0:
		vertical_speed = 0.0
	if on_floor and Input.is_action_just_pressed("jump"):
		vertical_speed = sqrt(2.0 * g * jump_height_m)
		jumped.emit()
	vertical_speed -= g * delta

	velocity = horizontal + up * vertical_speed
	move_and_slide()

	var now_on_floor: bool = is_on_floor()
	if now_on_floor and not _was_on_floor:
		landed.emit()
	_was_on_floor = now_on_floor
	moved.emit(input_dir.length() > 0.1, is_running)


func _fly(delta: float) -> void:
	var input_dir: Vector3 = Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("move_forward", "move_back")
	)
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1
	var braking: bool = Input.is_action_pressed("eva_brake")
	velocity = _eva.step(velocity, global_basis, input_dir, braking, delta)
	move_and_slide()
	_was_on_floor = false
	moved.emit(input_dir.length() > 0.1, is_running)


func _align_to_up(up: Vector3, delta: float) -> void:
	var target: Basis = _basis_from_up(up, global_basis)
	var weight: float = clampf(align_speed * delta, 0.0, 1.0)
	global_basis = global_basis.slerp(target, weight).orthonormalized()


func _basis_from_up(new_up: Vector3, current: Basis) -> Basis:
	var forward: Vector3 = -current.z
	forward = forward - new_up * forward.dot(new_up)
	if forward.length_squared() < 0.001:
		forward = current.x.cross(new_up)
	if forward.length_squared() < 0.001:
		var axis: Vector3 = Vector3.FORWARD if absf(new_up.y) < 0.99 else Vector3.RIGHT
		forward = axis - new_up * axis.dot(new_up)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(new_up).normalized()
	return Basis(right, new_up, -forward)


func _unhandled_input(event: InputEvent) -> void:
	if not is_controllable or not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion: InputEventMouseMotion = event
	rotate_object_local(Vector3.UP, -motion.relative.x * mouse_sensitivity)
	if _has_gravity:
		var limit: float = deg_to_rad(pitch_clamp_deg)
		pitch_rad = clampf(pitch_rad - motion.relative.y * mouse_sensitivity, -limit, limit)
		if camera_pivot != null:
			camera_pivot.rotation.x = pitch_rad
	else:
		rotate_object_local(Vector3.RIGHT, -motion.relative.y * mouse_sensitivity)

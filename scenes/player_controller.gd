extends CharacterBody3D

## Handles two distinct movement modes:
## - planet mode: gravity toward a center point, character "up" aligns with
##   the surface normal, camera pitch is clamped (standard FPS feel).
## - zero-g mode: no gravity, free 6DOF-style rotation, no pitch clamp.
## All child references are exported, not fetched via @onready + $paths.

signal moved(is_moving: bool, is_running: bool)
signal jumped
signal gravity_mode_changed(is_zero_g: bool)

enum GravityMode { PLANET, ZERO_G }

@export var body_pivot: Node3D
@export var camera_pivot: Node3D
@export var player_camera: Camera3D

@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var zero_g_speed: float = 5.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.003
@export var pitch_clamp_deg: float = 89.0

var gravity_mode: GravityMode = GravityMode.ZERO_G
var gravity_strength: float = 9.8
var planet_center: Vector3 = Vector3.ZERO
var up_direction: Vector3 = Vector3.UP

var pitch_rad: float = 0.0
var is_running: bool = false
var is_controllable: bool = true

func set_planet_gravity(center: Vector3, strength: float) -> void:
	planet_center = center
	gravity_strength = strength
	gravity_mode = GravityMode.PLANET
	gravity_mode_changed.emit(false)

func set_zero_g() -> void:
	gravity_mode = GravityMode.ZERO_G
	gravity_mode_changed.emit(true)

func set_controllable(value: bool) -> void:
	is_controllable = value

func _physics_process(delta: float) -> void:
	if not is_controllable:
		return

	match gravity_mode:
		GravityMode.PLANET:
			_process_planet_movement(delta)
		GravityMode.ZERO_G:
			_process_zero_g_movement(delta)

	move_and_slide()

func _process_planet_movement(delta: float) -> void:
	up_direction = (global_position - planet_center).normalized()

	var target_basis: Basis = _basis_from_up(up_direction, global_transform.basis)
	global_transform.basis = global_transform.basis.slerp(target_basis, 10.0 * delta).orthonormalized()

	velocity += -up_direction * gravity_strength * delta

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_running = Input.is_action_pressed("run") and input_dir.length() > 0.1

	var speed: float = run_speed if is_running else walk_speed
	var move_dir: Vector3 = (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var horizontal_velocity: Vector3 = move_dir * speed

	var vertical_velocity: Vector3 = velocity.project(up_direction)

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		vertical_velocity = up_direction * jump_velocity
		jumped.emit()

	velocity = horizontal_velocity + vertical_velocity
	moved.emit(input_dir.length() > 0.1, is_running)

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
	moved.emit(input_dir.length() > 0.1, is_running)

func _basis_from_up(new_up: Vector3, current_basis: Basis) -> Basis:
	var forward: Vector3 = -current_basis.z
	forward = (forward - new_up * forward.dot(new_up)).normalized()
	if forward.length_squared() < 0.001:
		forward = current_basis.x.cross(new_up).normalized()
	var right: Vector3 = forward.cross(new_up).normalized()
	return Basis(right, new_up, -forward)

func _unhandled_input(event: InputEvent) -> void:
	if not is_controllable:
		return
	if event is InputEventMouseMotion:
		match gravity_mode:
			GravityMode.PLANET:
				_apply_planet_look(event.relative)
			GravityMode.ZERO_G:
				_apply_zero_g_look(event.relative)

func _apply_planet_look(mouse_delta: Vector2) -> void:
	rotate_object_local(Vector3.UP, -mouse_delta.x * mouse_sensitivity)

	var pitch_limit: float = deg_to_rad(pitch_clamp_deg)
	pitch_rad = clamp(pitch_rad - mouse_delta.y * mouse_sensitivity, -pitch_limit, pitch_limit)
	camera_pivot.rotation.x = pitch_rad

func _apply_zero_g_look(mouse_delta: Vector2) -> void:
	# full 360 freedom, no clamp: rotate the whole body on both axes
	# using local-space rotation to avoid gimbal lock at the poles.
	rotate_object_local(Vector3.UP, -mouse_delta.x * mouse_sensitivity)
	rotate_object_local(Vector3.RIGHT, -mouse_delta.y * mouse_sensitivity)

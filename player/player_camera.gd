extends Node3D

## Owns camera "feel": head bob and FOV kick.
## Head bob only applies in planet mode (walking/running on a surface).
## Zero-g and jumping/airborne states disable bob entirely.
## Ship movement can also request an FOV kick via apply_external_fov_kick().

@export var player_camera: Camera3D
@export var player_controller: CharacterBody3D

@export var base_fov: float = 75.0
@export var walk_fov_kick: float = 4.0
@export var run_fov_kick: float = 10.0
@export var ship_fov_kick: float = 8.0
@export var fov_lerp_speed: float = 6.0

@export var bob_walk_frequency: float = 8.0
@export var bob_walk_amplitude: float = 0.035
@export var bob_run_frequency: float = 12.0
@export var bob_run_amplitude: float = 0.07
@export var bob_lerp_speed: float = 10.0

var _target_fov: float = 75.0
var _bob_time: float = 0.0
var _bob_offset: float = 0.0
var _is_moving: bool = false
var _is_running: bool = false
var _is_zero_g: bool = true
var _external_fov_kick: float = 0.0
var _camera_base_local_pos: Vector3

func _ready() -> void:
	_target_fov = base_fov
	player_camera.fov = base_fov
	_camera_base_local_pos = player_camera.position

	if player_controller.has_signal("moved"):
		player_controller.moved.connect(_on_player_moved)
	if player_controller.has_signal("gravity_mode_changed"):
		player_controller.gravity_mode_changed.connect(_on_gravity_mode_changed)

func _on_player_moved(is_moving: bool, is_running: bool) -> void:
	_is_moving = is_moving
	_is_running = is_running

func _on_gravity_mode_changed(is_zero_g: bool) -> void:
	_is_zero_g = is_zero_g
	if is_zero_g:
		_bob_offset = 0.0

func set_external_fov_kick(amount: float) -> void:
	_external_fov_kick = amount

func _process(delta: float) -> void:
	_update_fov(delta)
	_update_bob(delta)

func _update_fov(delta: float) -> void:
	var kick: float = 0.0
	if not _is_zero_g and _is_moving:
		kick = run_fov_kick if _is_running else walk_fov_kick
	kick += _external_fov_kick

	_target_fov = base_fov + kick
	player_camera.fov = lerp(player_camera.fov, _target_fov, fov_lerp_speed * delta)

func _update_bob(delta: float) -> void:
	var should_bob: bool = not _is_zero_g and _is_moving
	var frequency: float = bob_run_frequency if _is_running else bob_walk_frequency
	var amplitude: float = bob_run_amplitude if _is_running else bob_walk_amplitude

	if should_bob:
		_bob_time += delta * frequency
		var target_offset: float = sin(_bob_time) * amplitude
		_bob_offset = lerp(_bob_offset, target_offset, bob_lerp_speed * delta)
	else:
		_bob_time = 0.0
		_bob_offset = lerp(_bob_offset, 0.0, bob_lerp_speed * delta)

	player_camera.position = _camera_base_local_pos + Vector3(0.0, _bob_offset, 0.0)

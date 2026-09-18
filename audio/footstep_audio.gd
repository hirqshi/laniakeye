class_name FootstepAudio
extends Node

@export var camera_bob: Node3D
@export var player_controller: CharacterBody3D
@export var footstep_streams: Array[AudioStream] = []

@export_range(0.5, 2.0, 0.01) var min_pitch_scale: float = 0.92
@export_range(0.5, 2.0, 0.01) var max_pitch_scale: float = 1.08
@export_range(-24.0, 6.0, 0.1) var walk_volume_db: float = -6.0
@export_range(-24.0, 6.0, 0.1) var run_volume_db: float = -2.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

	if camera_bob != null and camera_bob.has_signal("footstep"):
		camera_bob.connect("footstep", _on_footstep)

func _on_footstep() -> void:
	if footstep_streams.is_empty() or not is_instance_valid(player_controller):
		return

	var is_running: bool = bool(player_controller.get("is_running"))
	var volume_db: float = run_volume_db if is_running else walk_volume_db
	var pitch_scale: float = _rng.randf_range(min_pitch_scale, max_pitch_scale)

	var stream: AudioStream = footstep_streams[
		_rng.randi_range(0, footstep_streams.size() - 1)
	]

	AudioManager.play_sfx_3d(
		stream,
		player_controller.global_position,
		volume_db,
		pitch_scale
	)

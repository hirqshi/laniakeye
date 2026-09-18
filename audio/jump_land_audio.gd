class_name JumpLandAudio
extends Node

@export var player_controller: CharacterBody3D
@export var jump_stream: AudioStream
@export var land_streams: Array[AudioStream] = []

@export_range(-24.0, 6.0, 0.1) var jump_volume_db: float = -4.0
@export_range(-24.0, 6.0, 0.1) var land_volume_db: float = -4.0
@export_range(0.5, 2.0, 0.01) var min_pitch_scale: float = 0.95
@export_range(0.5, 2.0, 0.01) var max_pitch_scale: float = 1.05

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

	if not is_instance_valid(player_controller):
		return

	if player_controller.has_signal("jumped"):
		player_controller.jumped.connect(_on_jumped)

	if player_controller.has_signal("landed"):
		player_controller.landed.connect(_on_landed)

func _on_jumped() -> void:
	AudioManager.play_sfx_3d(
		jump_stream,
		player_controller.global_position,
		jump_volume_db,
		_rng.randf_range(min_pitch_scale, max_pitch_scale)
	)

func _on_landed() -> void:
	if land_streams.is_empty():
		return

	var stream: AudioStream = land_streams[
		_rng.randi_range(0, land_streams.size() - 1)
	]

	AudioManager.play_sfx_3d(
		stream,
		player_controller.global_position,
		land_volume_db,
		_rng.randf_range(min_pitch_scale, max_pitch_scale)
	)

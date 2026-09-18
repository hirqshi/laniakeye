class_name ShipDoor
extends MeshInstance3D

## Slides the door mesh up/down along its own local Y, relative to
## whatever position was set in the inspector at scene build time.
## Physical collision toggles instantly with is_open, same as the
## existing (non-animated) behavior - not synced to animation progress.

@export var static_body: StaticBody3D
@export var door_collision_shape: CollisionShape3D
@export var interaction_area: Area3D
@export var interaction_label: Label3D

@export_range(0.1, 10.0, 0.01, "suffix:m") var slide_distance_m: float = 2.0
@export_range(0.1, 5.0, 0.01, "suffix:s") var slide_duration_s: float = 1.0

@export var door_open_stream: AudioStream
@export var door_close_stream: AudioStream
@export_range(-24.0, 6.0, 0.1) var door_audio_volume_db: float = -4.0

var is_open: bool = false
var _player_in_range: bool = false
var _closed_local_position: Vector3 = Vector3.ZERO
var _tween: Tween

func _ready() -> void:
	_closed_local_position = position

	if interaction_label != null:
		interaction_label.visible = false

	if interaction_area != null:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	_player_in_range = true

	if interaction_label != null:
		interaction_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	_player_in_range = false

	if interaction_label != null:
		interaction_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return

	if event.is_action_pressed("interact"):
		_toggle()

func _toggle() -> void:
	is_open = not is_open
	_set_collision_enabled(not is_open)

	var target_position: Vector3 = (
		_closed_local_position + Vector3.UP * slide_distance_m
		if is_open
		else _closed_local_position
	)

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "position", target_position, slide_duration_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var stream: AudioStream = door_open_stream if is_open else door_close_stream
	AudioManager.play_sfx_3d(stream, global_position, door_audio_volume_db)

func _set_collision_enabled(value: bool) -> void:
	if door_collision_shape != null:
		door_collision_shape.disabled = not value

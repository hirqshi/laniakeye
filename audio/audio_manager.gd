extends Node

## Global audio singleton. Owns ONLY the always-on background ambient
## loop and a generic one-shot SFX playback API. Does not know about
## footsteps, ships, or planets - those systems call into this, this
## never reaches out to them.

@export var global_ambient_stream: AudioStream
@export_range(-80.0, 24.0, 0.1) var global_ambient_volume_db: float = -18.0

@export_range(0.0, 10.0, 0.1, "suffix:s")
var planet_ambient_crossfade_s: float = 1.5

var _global_ambient_player: AudioStreamPlayer
var _planet_ambient_player_a: AudioStreamPlayer
var _planet_ambient_player_b: AudioStreamPlayer
var _planet_ambient_active_is_a: bool = true
var _planet_ambient_tween: Tween
var _current_planet_ambient_stream: AudioStream

func _ready() -> void:
	_global_ambient_player = _create_looping_player(
		global_ambient_volume_db,
		"Master"
	)

	_planet_ambient_player_a = _create_looping_player(-80.0, "Master")
	_planet_ambient_player_b = _create_looping_player(-80.0, "Master")

	if global_ambient_stream != null:
		_global_ambient_player.stream = global_ambient_stream
		_global_ambient_player.play()

func _create_looping_player(
	volume_db: float,
	bus: StringName
) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.volume_db = volume_db
	player.bus = bus
	add_child(player)
	return player

## One-shot non-positional SFX (UI, HUD feedback, global cues).
func play_sfx_2d(
	stream: AudioStream,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0,
	bus: StringName = &"Master"
) -> void:
	if stream == null:
		return

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.bus = bus
	player.finished.connect(player.queue_free)

	add_child(player)
	player.play()

## One-shot positional SFX (footsteps, jump, land, seat, impacts).
## Attaches a temporary AudioStreamPlayer3D at world_position and frees
## itself when done - callers don't manage player lifetime.
func play_sfx_3d(
	stream: AudioStream,
	world_position: Vector3,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0,
	bus: StringName = &"Master"
) -> void:
	if stream == null:
		return

	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.bus = bus
	player.finished.connect(player.queue_free)

	add_child(player)
	player.global_position = world_position
	player.play()

## Crossfades the planet ambient loop to a new stream. Passing null
## fades the current planet ambient out to silence (e.g. leaving every
## gravity zone / floating in space).
func set_planet_ambient(stream: AudioStream) -> void:
	if stream == _current_planet_ambient_stream:
		return

	_current_planet_ambient_stream = stream

	var incoming_player: AudioStreamPlayer = (
		_planet_ambient_player_b if _planet_ambient_active_is_a
		else _planet_ambient_player_a
	)
	var outgoing_player: AudioStreamPlayer = (
		_planet_ambient_player_a if _planet_ambient_active_is_a
		else _planet_ambient_player_b
	)

	if _planet_ambient_tween != null and _planet_ambient_tween.is_valid():
		_planet_ambient_tween.kill()

	if stream != null:
		incoming_player.stream = stream
		incoming_player.volume_db = -80.0
		incoming_player.play()

	_planet_ambient_tween = create_tween().set_parallel(true)

	if stream != null:
		_planet_ambient_tween.tween_property(
			incoming_player,
			"volume_db",
			0.0,
			planet_ambient_crossfade_s
		)

	_planet_ambient_tween.tween_property(
		outgoing_player,
		"volume_db",
		-80.0,
		planet_ambient_crossfade_s
	)

	if outgoing_player.playing:
		_planet_ambient_tween.chain().tween_callback(
			outgoing_player.stop
		)

	_planet_ambient_active_is_a = not _planet_ambient_active_is_a

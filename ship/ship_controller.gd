extends CharacterBody3D

## Ship as CharacterBody3D - no physics solver fighting us, we fully own
## velocity every frame.
##
## AXIS FIX: Godot's convention is -Z = forward, +Z = back. Input.get_axis
## (negative, positive) returns +1 when the POSITIVE action is pressed, so
## "move_forward" giving +1 on local Z would mean backward - negated
## explicitly below, same for up/down.
##
## GRAVITY: implements the same duck-typed interface the player uses
## (set_planet_gravity / set_zero_g / get_current_gravity_source).
##
## PARKED ANCHOR: while parked, BOTH position and orientation are tracked
## relative to gravity_source's own local space and re-derived from
## gravity_source's current transform every frame.
##
## LANDING MAGNET: uses an exported RayCast3D (landing_raycast) pointed
## along the ship's local -Y.
##
## SEAT BRIDGE: exposes get_seat_exit_transform() so World can teleport the
## player back to the ship's seat exit point without reaching into the
## ship's internal node structure directly.
##
## HULL LAG (fix): the previous version overwrote ship_model.transform.
## basis DIRECTLY with the lag basis, which wiped out whatever rotation
## was already set on ship_model in the editor (e.g. a 90 degree offset
## to align an off-axis model). Fixed by capturing ship_model's ORIGINAL
## local basis once in _ready() and always composing the lag on TOP of
## it (base_basis * lag_basis) instead of replacing it outright - the
## inspector-set orientation is now preserved and the lag is purely
## additive on top of it.
##
## REFACTOR: gravity falloff curve now delegates to GravityBodyMath
## (generation/gravity_body_math.gd) - player_controller.gd used an
## identical copy of this curve, this kills the duplication.

signal speed_changed(speed_ratio: float)

signal player_seated
signal player_unseated

@export var ship_model: Node3D
@export var ship_seat: Node3D

@export var thrust_acceleration: float = 20.0
@export var strafe_acceleration: float = 14.0
@export var max_speed: float = 60.0
@export var linear_damping: float = 0.4
@export var rotation_speed: float = 1.5
@export var mouse_sensitivity: float = 0.002

## hull lag (visual only, see class comment above)
@export var hull_lag_amount_deg: float = 6.0
@export var hull_lag_recovery_speed: float = 4.0

## landing magnet settings - TUNE landing_offset_m to your hull shape.
@export var landing_raycast: RayCast3D
@export var landing_offset_m: float = 1.0
@export var landing_engage_distance_m: float = 6.0
@export var landing_align_speed: float = 3.0
@export var landing_position_smoothing_speed: float = 12.0
@export var landing_vertical_release_threshold: float = 0.15
@export var landing_max_reorientation_deg: float = 75.0

## gravity - mirrors player_controller's falloff curve
@export var gravity_fade_curve_power: float = 1.5
@export var gravity_multiplier: float = 1.0

@export var flight_loop_stream: AudioStream
@export_range(-24.0, 6.0, 0.1) var flight_loop_max_volume_db: float = -2.0
@export_range(0.1, 5.0, 0.1, "suffix:s") var flight_loop_fade_s: float = 0.4

var _flight_audio_player: AudioStreamPlayer3D

var is_piloted: bool = false
var _is_parked: bool = false

var gravity_source: Node3D = null
var surface_gravity_strength: float = 9.8

# parked anchor - keeps a landed ship glued to its spot on a
# rotating/moving gravity_source, in BOTH position and orientation.
var _parked_local_offset: Vector3 = Vector3.ZERO
var _parked_local_basis: Basis = Basis.IDENTITY
var _parked_anchor_valid: bool = false
var _parked_prev_position: Vector3 = Vector3.ZERO
var _parked_velocity_estimate: Vector3 = Vector3.ZERO
var _parked_motion_delta: Vector3 = Vector3.ZERO

# hull lag state - local counter-rotation applied on top of ship_model's
# ORIGINAL (inspector-set) basis, never replacing it.
var _ship_model_base_basis: Basis = Basis.IDENTITY
var _hull_lag_basis: Basis = Basis.IDENTITY

func _ready() -> void:
	process_physics_priority = -50
	if landing_raycast == null:
		push_error("ShipController (%s): 'Landing Raycast' export is not assigned" % name)
	elif not landing_raycast.enabled:
		push_warning("ShipController (%s): landing_raycast is disabled, landing magnet will never engage" % name)

	if ship_seat:
		if ship_seat.has_signal("player_seated"):
			ship_seat.connect("player_seated", func(): player_seated.emit())
		if ship_seat.has_signal("player_unseated"):
			ship_seat.connect("player_unseated", func(): player_unseated.emit())

	if ship_model == null:
		push_warning("ShipController (%s): 'Ship Model' export is not assigned, hull lag effect will not run" % name)
	else:
		_ship_model_base_basis = ship_model.transform.basis

	if flight_loop_stream != null:
		_setup_flight_audio()

func set_piloted(value: bool) -> void:
	is_piloted = value

func _setup_flight_audio() -> void:
	if flight_loop_stream is AudioStreamOggVorbis or flight_loop_stream is AudioStreamMP3:
		flight_loop_stream.loop = true
	elif flight_loop_stream is AudioStreamWAV:
		flight_loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_flight_audio_player = AudioStreamPlayer3D.new()
	_flight_audio_player.stream = flight_loop_stream
	_flight_audio_player.volume_db = -80.0
	_flight_audio_player.unit_size = 20.0
	add_child(_flight_audio_player)
	_flight_audio_player.play()

func get_seat_camera() -> Camera3D:
	if ship_seat == null:
		return null
	return ship_seat.get("seat_camera")

## Duck-typed gravity interface, matching what the player exposes.
func set_planet_gravity(source: Node3D, strength: float) -> void:
	gravity_source = source
	surface_gravity_strength = strength

func set_zero_g() -> void:
	gravity_source = null
	_parked_anchor_valid = false

func get_current_gravity_source() -> Node3D:
	return gravity_source

func get_platform_motion_delta() -> Vector3:
	return _parked_motion_delta

func get_current_velocity() -> Vector3:
	if _is_parked:
		# velocity is force-zeroed while parked (position is driven
		# directly via to_global(), not through physics velocity), but
		# the ship is still actually moving through world space if
		# gravity_source is rotating/orbiting fast. _parked_velocity_estimate
		# tracks the REAL frame-to-frame motion so anyone leaving the ship
		# (the player) inherits it instead of a false zero that leaves
		# them behind as the planet rotates out from under them.
		return _parked_velocity_estimate
	return velocity

## Exposes the ship seat's exit transform to external systems (World's
## spawn/"return to ship" logic) without them needing to know ShipSeat's
## internal node path or reach into the ship's scene structure directly.
func get_seat_exit_transform() -> Transform3D:
	if ship_seat == null:
		push_error("ShipController (%s): 'Ship Seat' export is not assigned" % name)
		return global_transform

	var exit_position: Node3D = ship_seat.get("exit_position")
	if exit_position == null:
		push_error("ShipController (%s): ship_seat has no valid 'exit_position' assigned" % name)
		return global_transform

	return exit_position.global_transform

func _physics_process(delta: float) -> void:
	if not is_piloted:
		_process_unpiloted(delta)
		_update_hull_lag(delta)
		return

	var strafe_input: float = Input.get_axis("move_left", "move_right")
	var vertical_input: float = Input.get_axis("move_down", "move_up")
	var forward_input: float = Input.get_axis("move_back", "move_forward")

	# forward_input is +1 when pressing "move_forward", but local -Z is
	# forward in Godot, so we feed it as negative Z here.
	var input_dir: Vector3 = Vector3(strafe_input, vertical_input, -forward_input)

	_update_flight_audio(input_dir.length() > 0.01, delta)

	var wants_liftoff: bool = vertical_input > landing_vertical_release_threshold
	var probe: Dictionary = _probe_landing_surface()
	var can_magnet: bool = probe.found and probe.distance <= landing_engage_distance_m and not wants_liftoff

	if can_magnet:
		_run_magnet_landing_frame(input_dir, probe, delta)
		_update_hull_lag(delta)
		return

	_is_parked = false
	_parked_anchor_valid = false

	if input_dir.length() > 0.01:
		var accel_dir: Vector3 = (global_transform.basis * input_dir).normalized()
		var accel: float = thrust_acceleration if absf(forward_input) > 0.01 else strafe_acceleration
		velocity += accel_dir * accel * delta
	else:
		velocity = velocity.lerp(Vector3.ZERO, linear_damping * delta)

	_apply_gravity(delta)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

	move_and_slide()

	_update_hull_lag(delta)

	var speed_ratio: float = clamp(velocity.length() / max_speed, 0.0, 1.0)
	speed_changed.emit(speed_ratio)

func _update_flight_audio(has_input: bool, delta: float) -> void:
	if _flight_audio_player == null:
		return

	var target_volume_db: float = flight_loop_max_volume_db if has_input else -80.0

	_flight_audio_player.volume_db = move_toward(
		_flight_audio_player.volume_db,
		target_volume_db,
		(80.0 / flight_loop_fade_s) * delta
	)

## Handles the unpiloted case: either the ship is parked (glued to its
## spot on gravity_source in both position AND orientation) or it's
## coasting/falling freely.
func _process_unpiloted(delta: float) -> void:
	if _flight_audio_player != null:
		_flight_audio_player.volume_db = move_toward(
			_flight_audio_player.volume_db,
			-80.0,
			80.0 * delta
		)

	if _is_parked and is_instance_valid(gravity_source):
		if not _parked_anchor_valid:
			_parked_local_offset = gravity_source.to_local(global_position)
			_parked_local_basis = gravity_source.global_transform.basis.inverse() * global_transform.basis
			_parked_anchor_valid = true
			_parked_prev_position = global_position
			_parked_motion_delta = Vector3.ZERO

		var previous_position: Vector3 = global_position

		global_position = gravity_source.to_global(_parked_local_offset)
		global_transform.basis = (
			gravity_source.global_transform.basis * _parked_local_basis
		).orthonormalized()

		_parked_motion_delta = global_position - previous_position

		if delta > 0.0:
			_parked_velocity_estimate = _parked_motion_delta / delta
		else:
			_parked_velocity_estimate = Vector3.ZERO

		_parked_prev_position = global_position
		velocity = Vector3.ZERO

		# Важно: parked Ship не надо move_and_slide()'ить.
		# Иначе safe_margin может снова дать ему паразитный сдвиг
		# от игрока, находящегося внутри корпуса.
		speed_changed.emit(0.0)
		return

	if _is_parked:
		_parked_motion_delta = Vector3.ZERO
		_parked_velocity_estimate = Vector3.ZERO
		velocity = Vector3.ZERO
		speed_changed.emit(0.0)
		return

	if not is_instance_valid(gravity_source) and velocity.is_zero_approx():
		_parked_motion_delta = Vector3.ZERO
		_parked_velocity_estimate = Vector3.ZERO
		speed_changed.emit(0.0)
		return

	_parked_motion_delta = Vector3.ZERO
	velocity = velocity.lerp(Vector3.ZERO, linear_damping * delta)
	_apply_gravity(delta)
	move_and_slide()
	speed_changed.emit(0.0)

## Adds gravitational acceleration toward gravity_source's center to
## velocity, using the same inverse-falloff curve as the player
## controller. No-op if there's no active gravity source.
func _apply_gravity(delta: float) -> void:
	if not is_instance_valid(gravity_source):
		return

	var to_center: Vector3 = gravity_source.global_position - global_position
	var distance_to_center: float = to_center.length()
	if distance_to_center < 0.01:
		return

	var gravity_dir: Vector3 = to_center / distance_to_center
	var gravity_strength: float = GravityBodyMath.get_falloff_gravity_strength(
		distance_to_center,
		surface_gravity_strength,
		gravity_multiplier,
		gravity_source,
		gravity_fade_curve_power
	)
	velocity += gravity_dir * gravity_strength * delta

## Runs one frame of magnet-locked landing: orientation smoothly aligns to
## the surface normal, horizontal thrust input still allows taxiing, and
## position eases onto the surface via lerp.
func _run_magnet_landing_frame(input_dir: Vector3, probe: Dictionary, delta: float) -> void:
	var tangential_input: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	var is_taxiing: bool = tangential_input.length() > 0.01

	if _is_parked and _parked_anchor_valid and not is_taxiing:
		global_position = gravity_source.to_global(_parked_local_offset) if is_instance_valid(gravity_source) else global_position
		if is_instance_valid(gravity_source):
			global_transform.basis = (gravity_source.global_transform.basis * _parked_local_basis).orthonormalized()

		if delta > 0.0:
			_parked_velocity_estimate = (global_position - _parked_prev_position) / delta
		_parked_prev_position = global_position

		velocity = Vector3.ZERO
		move_and_slide()
		speed_changed.emit(0.0)
		return

	var safe_current_basis: Basis = global_transform.basis.orthonormalized()
	var target_basis: Basis = _basis_from_up(probe.normal, safe_current_basis)

	var basis_angle_to_target: float = safe_current_basis.get_rotation_quaternion().angle_to(target_basis.get_rotation_quaternion())
	if basis_angle_to_target < deg_to_rad(0.5):
		global_transform.basis = target_basis
	else:
		global_transform.basis = safe_current_basis.slerp(target_basis, landing_align_speed * delta).orthonormalized()

	var horizontal_velocity: Vector3 = Vector3.ZERO

	if is_taxiing:
		var accel_dir: Vector3 = (global_transform.basis * tangential_input).normalized()
		accel_dir -= accel_dir.project(probe.normal)
		if accel_dir.length() > 0.001:
			horizontal_velocity = accel_dir.normalized() * strafe_acceleration

	velocity = horizontal_velocity
	move_and_slide()

	var post_probe: Dictionary = _probe_landing_surface()
	if post_probe.found:
		var target_position: Vector3 = post_probe.hit_point + post_probe.normal * landing_offset_m
		if global_position.distance_to(target_position) < 0.02:
			global_position = target_position
		else:
			global_position = global_position.lerp(target_position, clamp(landing_position_smoothing_speed * delta, 0.0, 1.0))

	if is_instance_valid(gravity_source):
		_parked_local_offset = gravity_source.to_local(global_position)
		_parked_local_basis = gravity_source.global_transform.basis.inverse() * global_transform.basis
		_parked_anchor_valid = true
	else:
		_parked_anchor_valid = false

	_is_parked = true

	var speed_ratio: float = clamp(horizontal_velocity.length() / max_speed, 0.0, 1.0)
	speed_changed.emit(speed_ratio)

## Reads the exported RayCast3D to look for a nearby surface to land on.
func _probe_landing_surface() -> Dictionary:
	var not_found: Dictionary = {"found": false, "hit_point": Vector3.ZERO, "normal": Vector3.ZERO, "distance": INF}

	if landing_raycast == null or not landing_raycast.enabled:
		return not_found

	landing_raycast.force_raycast_update()
	if not landing_raycast.is_colliding():
		return not_found

	var normal: Vector3 = landing_raycast.get_collision_normal()
	if normal.length_squared() < 0.0001:
		return not_found
	normal = normal.normalized()

	var ship_up: Vector3 = global_transform.basis.y.normalized()
	var max_reorientation_cos: float = cos(deg_to_rad(landing_max_reorientation_deg))
	if normal.dot(ship_up) < max_reorientation_cos:
		return not_found

	var hit_point: Vector3 = landing_raycast.get_collision_point()
	var distance: float = (global_position - hit_point).dot(ship_up)
	return {"found": true, "hit_point": hit_point, "normal": normal, "distance": distance}

## Builds an orthonormal basis with the given up direction, preserving as
## much of the current forward heading as possible.
func _basis_from_up(raw_new_up: Vector3, current_basis: Basis) -> Basis:
	var new_up: Vector3 = raw_new_up.normalized()
	if new_up.length_squared() < 0.0001:
		new_up = current_basis.y.normalized()

	var forward: Vector3 = -current_basis.z
	forward = (forward - new_up * forward.dot(new_up)).normalized()

	if forward.length_squared() < 0.001:
		forward = current_basis.x.cross(new_up).normalized()

	if forward.length_squared() < 0.001:
		var safe_axis: Vector3 = Vector3.FORWARD if absf(new_up.y) < 0.99 else Vector3.RIGHT
		forward = (safe_axis - new_up * safe_axis.dot(new_up)).normalized()

	var right: Vector3 = forward.cross(new_up).normalized()
	return Basis(right, new_up, -forward)

## Decays the hull's local counter-rotation back toward identity every
## frame, then composes it ON TOP OF ship_model's original inspector-set
## basis - never replaces that base orientation outright.
func _update_hull_lag(delta: float) -> void:
	if ship_model == null:
		return

	_hull_lag_basis = _hull_lag_basis.slerp(Basis.IDENTITY, clamp(hull_lag_recovery_speed * delta, 0.0, 1.0)).orthonormalized()
	ship_model.transform.basis = (_hull_lag_basis * _ship_model_base_basis).orthonormalized()

func _unhandled_input(event: InputEvent) -> void:
	if not is_piloted:
		return
	if event is InputEventMouseMotion:
		var yaw_delta: float = -event.relative.x * mouse_sensitivity
		var pitch_delta: float = -event.relative.y * mouse_sensitivity

		rotate_object_local(Vector3.UP, yaw_delta)
		rotate_object_local(Vector3.RIGHT, pitch_delta)
		global_transform.basis = global_transform.basis.orthonormalized()

		# hull lag: counter-rotate the visual mesh by roughly the turn we
		# just applied to the body (scaled/clamped by hull_lag_amount_deg),
		# so the immediate visible result is the hull staying behind while
		# the body (and therefore flight direction) has already turned -
		# _update_hull_lag() then eases this back to zero every frame.
		if ship_model != null:
			var lag_yaw: float = clamp(yaw_delta, -deg_to_rad(hull_lag_amount_deg), deg_to_rad(hull_lag_amount_deg))
			var lag_pitch: float = clamp(pitch_delta, -deg_to_rad(hull_lag_amount_deg), deg_to_rad(hull_lag_amount_deg))

			var counter_rotation: Basis = Basis(Vector3.UP, -lag_yaw) * Basis(Vector3.RIGHT, -lag_pitch)
			_hull_lag_basis = (counter_rotation * _hull_lag_basis).orthonormalized()

class_name LkEvaDrive
extends RefCounted

## Inertial EVA thrust model for bodies with near-zero gravity.
## Pure velocity integrator: no scene access, no gravity changes, no ground lock.
## Thrust adds acceleration in the player's local axes; releasing the keys keeps
## the velocity (no lerp-to-zero). Braking is an explicit, bounded deceleration.
## Gravity of the dominant body is applied every tick, so a body with g > 0
## keeps pulling the player even while they are in EVA.
##
## Usage (from LkPlayerController._fly when gravity is weak):
##   velocity = _eva.step(velocity, global_basis, input_dir, Input.is_action_pressed("eva_brake"), delta, carrier_velocity, gravity_accel)
##   move_and_slide()
## carrier_velocity is the velocity of the reference body surface at the
## player's position (Vector3.ZERO = inertial frame). Braking and the speed cap
## act on velocity RELATIVE to that reference.

var thrust_accel: float = 3.0
var brake_accel: float = 4.0
var max_relative_speed: float = 25.0


func step(velocity: Vector3, basis: Basis, input: Vector3, braking: bool, delta: float, reference_velocity: Vector3 = Vector3.ZERO, gravity_accel: Vector3 = Vector3.ZERO) -> Vector3:
	var rel: Vector3 = velocity - reference_velocity
	if braking:
		rel = rel.move_toward(Vector3.ZERO, brake_accel * delta)
	elif input.length_squared() > 0.0001:
		var strength: float = minf(input.length(), 1.0)
		var wish_dir: Vector3 = (basis * input).normalized()
		var candidate: Vector3 = rel + wish_dir * thrust_accel * strength * delta
		# the cap only blocks thrust that would raise speed above it
		if candidate.length() > max_relative_speed and candidate.length() > rel.length():
			candidate = candidate.normalized() * maxf(max_relative_speed, rel.length())
		rel = candidate
	# gravity always applies, even while thrusting or braking
	rel += gravity_accel * delta
	return reference_velocity + rel

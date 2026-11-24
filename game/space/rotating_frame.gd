class_name LkRotatingFrame
extends RefCounted

## Rotation of one body about a fixed axis through its centre, expressed in
## the nonrotating absolute frame. Pure math, no nodes, no physics.
## All large-magnitude work happens in 64-bit scalars (LkPosition64); only
## small per-tick displacements are returned as Vector3.
## Velocity convention: a body carried by this frame stores velocity
## RELATIVE to the surface. Use to_inertial_velocity() when it leaves.

var body_id: StringName
var center: LkPosition64
var angular_speed_rad_s: float
var angle_rad: float = 0.0

var _axis: LkPosition64


func _init(id: StringName, body_center: LkPosition64, axis: Vector3, angular_speed: float, initial_angle: float = 0.0) -> void:
	body_id = id
	center = body_center.copy()
	angular_speed_rad_s = angular_speed
	angle_rad = initial_angle
	var length: float = sqrt(float(axis.x) * float(axis.x) + float(axis.y) * float(axis.y) + float(axis.z) * float(axis.z))
	if length < 0.000001:
		push_error("LkRotatingFrame: zero axis, falling back to +Y")
		_axis = LkPosition64.new(0.0, 1.0, 0.0)
	else:
		_axis = LkPosition64.new(axis.x / length, axis.y / length, axis.z / length)


func get_axis() -> Vector3:
	return Vector3(_axis.x, _axis.y, _axis.z)


# Advances the frame angle and returns the angle of THIS step.
func advance(delta: float) -> float:
	var step: float = angular_speed_rad_s * delta
	angle_rad = fposmod(angle_rad + step, TAU)
	return step


# Planet node basis for the current angle (drive the node from this, do not
# call rotate_y separately).
func planet_basis() -> Basis:
	return Basis(get_axis(), angle_rad)


# Position relative to the body centre, in doubles.
func relative_position(origin: LkPosition64, local_point: Vector3) -> LkPosition64:
	return origin.minus(center).plus_local(local_point)


# Exact rotation of a centre-relative position by an arbitrary angle.
func rotate(rel: LkPosition64, angle: float) -> LkPosition64:
	var c: float = cos(angle)
	var s: float = sin(angle)
	var along: float = (_axis.x * rel.x + _axis.y * rel.y + _axis.z * rel.z) * (1.0 - c)
	var cr: LkPosition64 = _cross_axis(rel)
	return LkPosition64.new(
		rel.x * c + cr.x * s + _axis.x * along,
		rel.y * c + cr.y * s + _axis.y * along,
		rel.z * c + cr.z * s + _axis.z * along
	)


# Displacement of a surface-fixed point over one step (rotated - original),
# computed without cancelling two huge numbers.
func carry_displacement64(rel: LkPosition64, step_angle: float) -> LkPosition64:
	var s: float = sin(step_angle)
	var half_sin: float = sin(step_angle * 0.5)
	var h: float = 2.0 * half_sin * half_sin
	var kv: LkPosition64 = _cross_axis(rel)
	var kkv: LkPosition64 = _cross_axis(kv)
	return LkPosition64.new(kv.x * s + kkv.x * h, kv.y * s + kkv.y * h, kv.z * s + kkv.z * h)


func carry_displacement(rel: LkPosition64, step_angle: float) -> Vector3:
	var d: LkPosition64 = carry_displacement64(rel, step_angle)
	return Vector3(d.x, d.y, d.z)


# Rotation to apply to a carried body's basis and relative velocity.
func step_basis(step_angle: float) -> Basis:
	return Basis(get_axis(), step_angle)


# Inertial velocity of a surface-fixed point: omega x r.
func surface_velocity(rel: LkPosition64) -> Vector3:
	var kv: LkPosition64 = _cross_axis(rel)
	return Vector3(kv.x * angular_speed_rad_s, kv.y * angular_speed_rad_s, kv.z * angular_speed_rad_s)


func to_inertial_velocity(relative_velocity: Vector3, rel: LkPosition64) -> Vector3:
	return relative_velocity + surface_velocity(rel)


func to_relative_velocity(inertial_velocity: Vector3, rel: LkPosition64) -> Vector3:
	return inertial_velocity - surface_velocity(rel)


func _cross_axis(v: LkPosition64) -> LkPosition64:
	return LkPosition64.new(
		_axis.y * v.z - _axis.z * v.y,
		_axis.z * v.x - _axis.x * v.z,
		_axis.x * v.y - _axis.y * v.x
	)

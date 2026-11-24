class_name LkGravityBody
extends RefCounted

var body_id: StringName
var center: LkPosition64
var radius_m: float
var mu_m3_s2: float

func _init(id: StringName, position: LkPosition64, radius: float, mu: float) -> void:
	body_id = id
	center = position.copy()
	radius_m = maxf(radius, 0.0)
	mu_m3_s2 = maxf(mu, 0.0)

func acceleration_at(point: LkPosition64) -> Vector3:
	var offset: LkPosition64 = center.minus(point)
	var distance: float = offset.length()
	if distance <= 0.000000001 or mu_m3_s2 <= 0.0:
		return Vector3.ZERO
	# Uniform-density interior: continuous at the surface, zero at center.
	var denominator: float = maxf(distance, radius_m)
	var factor: float = mu_m3_s2 / (denominator * denominator * denominator)
	return Vector3(offset.x * factor, offset.y * factor, offset.z * factor)

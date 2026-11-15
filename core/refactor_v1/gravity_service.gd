class_name LkGravityService
extends RefCounted

var bodies: Array[LkGravityBody] = []

func sample(point: LkPosition64, previous_id: StringName = &"", switch_ratio: float = 1.1) -> Dictionary:
	var total: Vector3 = Vector3.ZERO
	var strongest: LkGravityBody = null
	var strongest_squared: float = 0.0
	var previous: LkGravityBody = null
	var previous_squared: float = 0.0
	for body: LkGravityBody in bodies:
		var acceleration: Vector3 = body.acceleration_at(point)
		var strength_squared: float = acceleration.length_squared()
		total += acceleration
		if strength_squared > strongest_squared:
			strongest = body
			strongest_squared = strength_squared
		if body.body_id == previous_id:
			previous = body
			previous_squared = strength_squared
	# Dominant body is metadata, not an abrupt switch of physical force.
	var ratio: float = maxf(switch_ratio, 1.0)
	if previous != null and previous_squared > 0.0 and strongest_squared <= previous_squared * ratio * ratio:
		strongest = previous
	var has_up: bool = total.length_squared() > 0.000000000001
	var up: Vector3 = -total.normalized() if has_up else Vector3.ZERO
	var dominant_id: StringName = strongest.body_id if strongest != null else &""
	return {"acceleration": total, "up": up, "has_up": has_up, "dominant_id": dominant_id}

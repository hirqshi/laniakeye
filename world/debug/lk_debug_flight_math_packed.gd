class_name LkDebugFlightMathPacked
extends RefCounted

const FlightMath = preload("res://world/debug/lk_debug_flight_math.gd")

# Exact port of LkDebugFlightMath.safe_step for packed sphere buffers.
# Entire segment tested; endpoint beyond far side is NOT safe.
static func safe_step_packed(direction: Vector3, requested: float, centers: PackedFloat64Array, radii: PackedFloat64Array) -> float:
	if not direction.is_finite() or not is_finite(requested) or requested <= 0.0 or direction.length_squared() < 1.0e-12:
		return 0.0
	var ray: Array = FlightMath.unit_direction(direction)
	var allowed: float = requested
	var count: int = radii.size()
	for index: int in range(count):
		var cx: float = centers[3 * index]
		var cy: float = centers[3 * index + 1]
		var cz: float = centers[3 * index + 2]
		var radius: float = radii[index] + 0.25
		var along: float = cx * float(ray[0]) + cy * float(ray[1]) + cz * float(ray[2])
		var squared: float = cx * cx + cy * cy + cz * cz
		if squared < radius * radius:
			if along > 0.0:
				return 0.0
			continue
		if along <= 0.0:
			continue
		var perpendicular: float = 0.0
		for axis: int in range(3):
			var component: float = 0.0
			match axis:
				0: component = cx - along * float(ray[0])
				1: component = cy - along * float(ray[1])
				2: component = cz - along * float(ray[2])
			perpendicular += component * component
		var disc: float = radius * radius - perpendicular
		if disc < 0.0:
			continue
		var entry: float = along - sqrt(maxf(disc, 0.0))
		allowed = minf(allowed, maxf(0.0, entry - 0.25))
	return allowed

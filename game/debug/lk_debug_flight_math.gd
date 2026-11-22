class_name LkDebugFlightMath
extends RefCounted

static func speed_at_height(height: float, multiplier: float = 1.0) -> float:
	if not is_finite(height) or not is_finite(multiplier) or multiplier <= 0.0:
		return 0.0
	return clampf((5.0 + 0.4 * pow(clampf(height, 0.0, 1.0e12), 1.35)) * clampf(multiplier, 1.0 / 1024.0, 4096.0), 0.001, 1.0e11)

static func unit_direction(direction: Vector3) -> Array:
	if not direction.is_finite():
		return [0.0, 0.0, 0.0]
	var x: float = direction.x
	var y: float = direction.y
	var z: float = direction.z
	var length: float = sqrt(x * x + y * y + z * z)
	if length < 1.0e-12:
		return [0.0, 0.0, 0.0]
	return [x / length, y / length, z / length]

# Centres in observer-relative DOUBLE scalar arrays, never astronomical Vector3.
# Entire segment is tested: an endpoint beyond the far side is NOT considered safe.
static func safe_step(direction: Vector3, requested: float, spheres: Array) -> float:
	if not direction.is_finite() or not is_finite(requested) or requested <= 0.0 or direction.length_squared() < 1.0e-12:
		return 0.0
	var ray: Array = unit_direction(direction)
	var allowed: float = requested
	for sphere: Dictionary in spheres:
		var c: Array = sphere["center"]
		var radius: float = float(sphere["radius"]) + 0.25
		var along: float = float(c[0]) * float(ray[0]) + float(c[1]) * float(ray[1]) + float(c[2]) * float(ray[2])
		var squared: float = float(c[0]) * float(c[0]) + float(c[1]) * float(c[1]) + float(c[2]) * float(c[2])
		if squared < radius * radius:
			if along > 0.0:
				return 0.0
			continue # Already inside: permit outward recovery, not deeper penetration.
		if along <= 0.0:
			continue
		var perpendicular: float = 0.0
		for axis: int in range(3):
			var component: float = float(c[axis]) - along * float(ray[axis])
			perpendicular += component * component
		var disc: float = radius * radius - perpendicular
		if disc < 0.0:
			continue
		var entry: float = along - sqrt(maxf(disc, 0.0))
		allowed = minf(allowed, maxf(0.0, entry - 0.25))
	return allowed

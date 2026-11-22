class_name LkDebugFlightCarry
extends RefCounted

const EARTH_RADIUS_M: float = 6371000.0
const EARTH_GRAVITY: float = 9.81

# Debug camera tuning, not an atmosphere, orbital SOI or physical gravity cutoff.
static func band(radius_m: float, gravity: float, reference_height_m: float = 250000.0,
	adaptive: bool = true, override_height_m: float = 0.0) -> Dictionary:
	if not is_finite(radius_m) or not is_finite(gravity) or not is_finite(reference_height_m) or not is_finite(override_height_m) or radius_m <= 0.0 or gravity < 0.0 or reference_height_m <= 0.0 or override_height_m < 0.0:
		return {"ok": false, "inner_m": 0.0, "middle_m": 0.0, "outer_m": 0.0}
	var height: float = reference_height_m
	if override_height_m > 0.0:
		height = clampf(override_height_m, 1.0, 5000000.0)
	elif adaptive:
		height *= sqrt(radius_m / EARTH_RADIUS_M) * pow(gravity / EARTH_GRAVITY, 0.25)
		var upper: float = minf(5000000.0, radius_m * 0.25)
		var lower: float = minf(100.0, upper)
		height = clampf(height, lower, upper)
	else:
		height = clampf(height, 1.0, 5000000.0)
	return {"ok": true, "inner_m": height * 0.8, "middle_m": height, "outer_m": height * 1.2}

static func weight(height_m: float, limits: Dictionary) -> float:
	if not limits.get("ok", false) or not is_finite(height_m):
		return 0.0
	var inner: float = limits["inner_m"]
	var outer: float = limits["outer_m"]
	if outer <= inner:
		return 0.0
	var t: float = clampf((height_m - inner) / (outer - inner), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)

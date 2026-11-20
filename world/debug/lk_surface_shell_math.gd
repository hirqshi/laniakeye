class_name LkSurfaceShellMath
extends RefCounted

static func coefficients(distance: float, radius: float) -> Dictionary:
	if not is_finite(distance) or not is_finite(radius) or distance <= 0.0 or radius <= 0.0:
		return {"valid": false, "stable": false, "c": 0.0, "height_m": 0.0, "radius_relative": 0.0}
	var height: float = distance - radius
	var valid: bool = height > 0.0
	var stable: bool = valid and height <= radius * 0.25
	var constant: float = (height / distance) * (1.0 + radius / distance) if stable else 0.0
	return {"valid": valid, "stable": stable, "c": constant, "height_m": height, "radius_relative": radius / distance}

# CPU reference for the new ACTIVE-body branch, not the other bodies' geometry.
static func entry_relative(along: float, state: Dictionary) -> float:
	if not state["valid"] or not is_finite(along) or along <= 0.0:
		return -1.0
	if state["stable"]:
		var near_disc: float = along * along - float(state["c"])
		if near_disc < 0.0:
			return -1.0
		var denominator: float = along + sqrt(maxf(near_disc, 0.0))
		if denominator <= 0.0:
			return -1.0
		return float(state["c"]) / denominator
	var radius: float = state["radius_relative"]
	var disc: float = radius * radius - maxf(0.0, 1.0 - along * along)
	if disc < 0.0:
		return -1.0
	var hit: float = along - sqrt(disc)
	return hit if hit > 0.0 else -1.0

static func slope_degrees(normal: Vector3, up: Vector3) -> float:
	if not normal.is_finite() or not up.is_finite() or normal.length_squared() < 1.0e-12 or up.length_squared() < 1.0e-12:
		return INF
	return rad_to_deg(acos(clampf(normal.normalized().dot(up.normalized()), -1.0, 1.0)))

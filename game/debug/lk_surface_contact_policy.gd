extends RefCounted

# Capsule axis is radial up. Clearance is measured along the support normal.
static func center_height(height: float, radius: float, normal_dot_up: float, clearance: float = 0.03) -> float:
	if not is_finite(height) or not is_finite(radius) or not is_finite(normal_dot_up) or not is_finite(clearance) or radius <= 0.0 or height < 2.0 * radius or normal_dot_up <= 0.0 or clearance <= 0.0:
		return INF
	var stem: float = height * 0.5 - radius
	return stem + (radius + clearance) / minf(normal_dot_up, 1.0)

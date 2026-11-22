class_name LkStellarLighting
extends RefCounted

const Kepler = preload("res://game/world/generation/lk_kepler_motion.gd")
# Single-star, planet context: star is at origin of the nonrotating system frame.
# q_body is an observer position measured from the planet centre in BODY axes.
# No sector coordinate or floating-origin offset enters this calculation.
static func evaluate(orbit: Dictionary, spin: Dictionary, time_s: float, q_body: Array) -> Dictionary:
	if q_body.size() != 3:
		return {}
	var radius_squared: float = 0.0
	for value in q_body:
		if not is_finite(float(value)):
			return {}
		radius_squared += float(value) * float(value)
	if radius_squared <= 0.0:
		return {}
	var translation: Dictionary = Kepler.evaluate(orbit, time_s)
	var orientation: Dictionary = Kepler.spin_state(spin, time_s)
	if translation.is_empty() or orientation.is_empty():
		return {}
	var axes: Array = orientation["body_to_system_axes"]
	var observer: Array[float] = []
	var distance_squared: float = 0.0
	for i: int in range(3):
		var local: float = float(axes[0][i]) * float(q_body[0]) + float(axes[1][i]) * float(q_body[1]) + float(axes[2][i]) * float(q_body[2])
		observer.append(local)
		var to_star: float = -float(translation["position_m"][i]) - local
		distance_squared += to_star * to_star
	if distance_squared <= 0.0:
		return {}
	var distance: float = sqrt(distance_squared)
	var radius: float = sqrt(radius_squared)
	var direction: Array[float] = []
	var body_direction: Array[float] = []
	var sine_altitude: float = 0.0
	for i: int in range(3):
		var component: float = (-float(translation["position_m"][i]) - observer[i]) / distance
		direction.append(component)
		sine_altitude += component * observer[i] / radius
	for i: int in range(3):
		body_direction.append(float(axes[i][0]) * direction[0] + float(axes[i][1]) * direction[1] + float(axes[i][2]) * direction[2])
	sine_altitude = clampf(sine_altitude, -1.0, 1.0)
	return {
		"to_star_system": direction, "to_star_body": body_direction,
		"distance_m": distance, "sin_altitude": sine_altitude,
		"altitude_rad": asin(sine_altitude), "above_horizon": sine_altitude > 0.0,
		# A local patch cannot shadow itself with the missing rest of the sphere.
		# Suppress sunlight below the observer's geometric horizon. The first
		# ~1.15 degrees above it are an ARTISTIC smooth fade, not an atmosphere.
		"horizon_visibility": smoothstep(0.0, 0.02, sine_altitude),
	}


# DirectionalLight3D emits along -Z. Its +Z must point TOWARD the star.
# Input is a unit-sized direction, never a huge absolute position.
static func directional_basis(to_star: Array) -> Basis:
	var z: Vector3 = Vector3(to_star[0], to_star[1], to_star[2]).normalized()
	var hint: Vector3 = Vector3.UP
	if absf(z.dot(hint)) > 0.99:
		hint = Vector3.RIGHT
	var x: Vector3 = hint.cross(z).normalized()
	var y: Vector3 = z.cross(x).normalized()
	return Basis(x, y, z).orthonormalized()

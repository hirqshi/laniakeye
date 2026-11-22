class_name LkSurfaceApproachForecast
extends RefCounted

const FlightMath = preload("res://game/debug/lk_debug_flight_math.gd")
const Carry = preload("res://game/debug/lk_debug_flight_carry.gd")
const GUARD_HEIGHT_M: float = 32.5

static func _dot(a: Array, b: Array) -> float:
	return float(a[0]) * float(b[0]) + float(a[1]) * float(b[1]) + float(a[2]) * float(b[2])

static func predict(q: LkPosition64, desired_body: LkPosition64, radius: float, omega: float,
	multiplier: float, carry_band: Dictionary, samples: int = 192) -> Dictionary:
	var length: float = q.length()
	if not is_finite(length) or length <= 0.0 or not is_finite(radius) or radius <= 0.0 or not is_finite(omega) or not is_finite(multiplier) or multiplier <= 0.0:
		return {"ok": false}
	var position: Array = [q.x, q.y, q.z]
	var scale: float = (radius + 1.0) / length
	var fallback: Dictionary = {"ok": true, "point": LkPosition64.new(q.x * scale, q.y * scale, q.z * scale), "predicted": false, "eta_s": INF, "drift_s": 0.0}
	var d: Array = [desired_body.x, desired_body.y, desired_body.z]
	var norm: float = sqrt(_dot(d, d))
	if not is_finite(norm) or norm < 1.0e-12 or length <= radius + GUARD_HEIGHT_M:
		return fallback
	for i: int in range(3):
		d[i] /= norm
	var along: float = -_dot(position, d)
	if along <= 0.0:
		return fallback
	var perpendicular: Array = []
	for i: int in range(3):
		perpendicular.append(float(position[i]) + along * float(d[i]))
	var guard_radius: float = radius + GUARD_HEIGHT_M
	var disc: float = guard_radius * guard_radius - _dot(perpendicular, perpendicular)
	if disc < 0.0:
		return fallback
	var distance: float = along - sqrt(disc)
	if distance <= 0.0:
		return fallback
	var steps: int = clampi(samples, 16, 512)
	var ds: float = distance / float(steps)
	var elapsed: float = 0.0
	var drift: float = 0.0
	for index: int in range(steps):
		var s: float = (float(index) + 0.5) * ds
		var p: Array = [q.x + float(d[0]) * s, q.y + float(d[1]) * s, q.z + float(d[2]) * s]
		var height: float = maxf(0.0, sqrt(_dot(p, p)) - radius)
		var speed: float = FlightMath.speed_at_height(height, multiplier)
		if speed <= 0.0:
			return fallback
		var dt: float = ds / speed
		elapsed += dt
		drift += dt * (1.0 - Carry.weight(height, carry_band))
	var hit: Array = [q.x + float(d[0]) * distance, q.y + float(d[1]) * distance, q.z + float(d[2]) * distance]
	# In BODY axes spin pole is +Y. Account for residual rotation not carried by
	# debug flight, assuming held direction/multiplier and the active-body speed.
	var angle: float = -omega * drift
	var c: float = cos(angle)
	var sn: float = sin(angle)
	var rotated: LkPosition64 = LkPosition64.new(float(hit[0]) * c + float(hit[2]) * sn, hit[1], -float(hit[0]) * sn + float(hit[2]) * c)
	var projection: float = (radius + 1.0) / rotated.length()
	return {"ok": true, "point": LkPosition64.new(rotated.x * projection, rotated.y * projection, rotated.z * projection), "predicted": true, "eta_s": elapsed, "drift_s": drift}

extends RefCounted

# Coordinates are in common nonrotating system axes, relative to each body.
# Keep small offsets OUT of Vector3. Roundtrip/error are measured, not assumed0.
static func rebase(states: Dictionary, from_id: String, to_id: String, observer: LkPosition64, epoch: float) -> Dictionary:
	if states.get("time_s", NAN) != epoch or not is_finite(epoch):
		return {"ok": false, "error": "epoch_mismatch"}
	var a: Dictionary = {}
	var b: Dictionary = {}
	for state: Dictionary in states.get("bodies", []):
		if state["id"] == from_id:
			a = state
		if state["id"] == to_id:
			b = state
	if a.is_empty() or b.is_empty() or from_id == to_id:
		return {"ok": false, "error": "body_scope_invalid"}
	var p: Array = a["position_m"]
	var q: Array = b["position_m"]
	var dx: float = float(q[0]) - float(p[0])
	var dy: float = float(q[1]) - float(p[1])
	var dz: float = float(q[2]) - float(p[2])
	var next: LkPosition64 = LkPosition64.new(observer.x - dx, observer.y - dy, observer.z - dz)
	if not is_finite(next.x) or not is_finite(next.y) or not is_finite(next.z):
		return {"ok": false, "error": "nonfinite_position"}
	var ex: float = (next.x + dx) - observer.x
	var ey: float = (next.y + dy) - observer.y
	var ez: float = (next.z + dz) - observer.z
	var sx: float = (float(q[0]) + next.x) - (float(p[0]) + observer.x)
	var sy: float = (float(q[1]) + next.y) - (float(p[1]) + observer.y)
	var sz: float = (float(q[2]) + next.z) - (float(p[2]) + observer.z)
	return {"ok": true, "observer": next, "epoch": epoch,
		"roundtrip_error_m": sqrt(ex * ex + ey * ey + ez * ez),
		"system_error_m": sqrt(sx * sx + sy * sy + sz * sz)}

# Same horizon model as StellarLighting, but translation is the FULL state
# position (including parent orbit for moons), not the moon's local orbit.
static func lighting(state: Dictionary, q_body: Array) -> Dictionary:
	var axes: Array = state["body_to_system_axes"]
	var translation: Array = state["position_m"]
	var radius_squared: float = 0.0
	var distance_squared: float = 0.0
	var observer: Array[float] = []
	for value in q_body:
		radius_squared += float(value) * float(value)
	if radius_squared <= 0.0:
		return {}
	for i: int in range(3):
		var local: float = float(axes[0][i]) * float(q_body[0]) + float(axes[1][i]) * float(q_body[1]) + float(axes[2][i]) * float(q_body[2])
		observer.append(local)
		var to_star: float = -float(translation[i]) - local
		distance_squared += to_star * to_star
	if distance_squared <= 0.0:
		return {}
	var distance: float = sqrt(distance_squared)
	var radius: float = sqrt(radius_squared)
	var direction: Array[float] = []
	var body_direction: Array[float] = []
	var sine_altitude: float = 0.0
	for i: int in range(3):
		var component: float = (-float(translation[i]) - observer[i]) / distance
		direction.append(component)
		sine_altitude += component * observer[i] / radius
	for i: int in range(3):
		body_direction.append(float(axes[i][0]) * direction[0] + float(axes[i][1]) * direction[1] + float(axes[i][2]) * direction[2])
	sine_altitude = clampf(sine_altitude, -1.0, 1.0)
	return {"to_star_system": direction, "to_star_body": body_direction,
		"distance_m": distance, "sin_altitude": sine_altitude,
		"altitude_rad": asin(sine_altitude), "above_horizon": sine_altitude > 0.0,
		"horizon_visibility": smoothstep(0.0, 0.02, sine_altitude)}

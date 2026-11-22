class_name LkKeplerMotion
extends RefCounted


static func period_s(a_m: float, mu: float) -> float:
	return TAU * sqrt(a_m * a_m * a_m / mu)


# Right handed system frame: +Y is reference north, orbit plane is XZ.
# p and q span the orbit plane; p cross q points along orbital north.
static func orbital_axes(node: float, inclination: float, periapsis: float) -> Array:
	var co: float = cos(node)
	var so: float = sin(node)
	var ci: float = cos(inclination)
	var si: float = sin(inclination)
	var cw: float = cos(periapsis)
	var sw: float = sin(periapsis)
	return [
		[co * cw - so * ci * sw, si * sw, -so * cw - co * ci * sw],
		[-co * sw - so * ci * cw, si * cw, so * sw - co * ci * cw],
	]


static func evaluate(orbit: Dictionary, time_s: float) -> Dictionary:
	var a: float = orbit["semi_major_axis_m"]
	var e: float = orbit["eccentricity"]
	var mu: float = orbit["primary_mu_m3_s2"]
	if not is_finite(time_s) or not is_finite(a) or not is_finite(e) or not is_finite(mu):
		push_error("LkKeplerMotion: non-finite input")
		return {}
	if a <= 0.0 or mu <= 0.0 or e < 0.0 or e > 0.8:
		push_error("LkKeplerMotion: requires a > 0, mu > 0, 0 <= e <= 0.8")
		return {}

	var period: float = period_s(a, mu)
	var mean: float = fposmod(
		float(orbit["mean_anomaly_at_epoch_rad"])
		+ TAU * (fposmod(time_s, period) / period), TAU
	)
	var eccentric: float = mean
	for iteration: int in range(24):
		var residual: float = eccentric - e * sin(eccentric) - mean
		var correction: float = residual / (1.0 - e * cos(eccentric))
		eccentric -= correction
		if absf(correction) < 1.0e-14:
			break

	var ce: float = cos(eccentric)
	var se: float = sin(eccentric)
	var root: float = sqrt(1.0 - e * e)
	var n: float = TAU / period
	var rate: float = n / (1.0 - e * ce)
	var px: float = a * (ce - e)
	var py: float = a * root * se
	var vx: float = -a * se * rate
	var vy: float = a * root * ce * rate
	var axes: Array = orbital_axes(
		orbit["ascending_node_rad"], orbit["inclination_rad"],
		orbit["argument_of_periapsis_rad"]
	)
	var p: Array = axes[0]
	var q: Array = axes[1]
	var position: Array[float] = []
	var velocity: Array[float] = []
	for axis: int in range(3):
		position.append(float(p[axis]) * px + float(q[axis]) * py)
		velocity.append(float(p[axis]) * vx + float(q[axis]) * vy)
	return {
		"position_m": position,
		"velocity_m_s": velocity,
		"period_s": period,
		"kepler_residual_rad": absf(eccentric - e * sin(eccentric) - mean),
	}


static func _rotate_y(v: Array, angle: float) -> Array:
	var c: float = cos(angle)
	var s: float = sin(angle)
	return [c * float(v[0]) + s * float(v[2]), float(v[1]),
		-s * float(v[0]) + c * float(v[2])]


# Axes are columns of the body-to-system rotation, not Euler angles.
static func spin_state(spin: Dictionary, time_s: float) -> Dictionary:
	var period: float = spin["period_s"]
	if not is_finite(time_s) or period <= 0.0 or not is_finite(period):
		push_error("LkKeplerMotion: invalid spin time or period")
		return {}
	var direction: float = spin["direction"]
	if direction != 1.0 and direction != -1.0:
		push_error("LkKeplerMotion: spin direction must be +1 or -1")
		return {}
	var angle: float = fposmod(
		float(spin["phase_at_epoch_rad"])
		+ direction * TAU * fposmod(time_s, period) / period, TAU
	)
	var tilt: float = spin["axis_tilt_to_system_y_rad"]
	var azimuth: float = spin["pole_azimuth_rad"]
	var ct: float = cos(tilt)
	var st: float = sin(tilt)
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var x: Array = _rotate_y([ct * ca, st * ca, -sa], azimuth)
	var y: Array = _rotate_y([-st, ct, 0.0], azimuth)
	var z: Array = _rotate_y([ct * sa, st * sa, ca], azimuth)
	var omega: float = direction * TAU / period
	return {
		"body_to_system_axes": [x, y, z],
		"angular_velocity_rad_s": [
			float(y[0]) * omega, float(y[1]) * omega, float(y[2]) * omega,
		],
	}

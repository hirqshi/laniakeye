extends RefCounted

const Motion = preload("res://world/generation/lk_kepler_motion.gd")
var profile_enabled: bool = false
var orbit_us: int = 0
var spin_us: int = 0
var pack_us: int = 0
var _id: String
var _parent_id: String
var _a: float
var _e: float
var _period: float
var _phase: float
var _root: float
var _n: float
var _p: Array
var _q: Array
var _spin_period: float
var _spin_direction: float
var _spin_phase: float
var _ct: float
var _st: float
var _caz: float
var _saz: float
var _spin_y: Array
var _angular: Array

# Input is an entry from a previously validated immutable SafeOrbitLayout.
func configure(entry: Dictionary) -> bool:
	var orbit: Dictionary = entry["orbit"]
	var spin: Dictionary = entry["spin"]
	_id = entry["body"]["id"]
	_parent_id = entry["body"]["parent_id"]
	_a = orbit["semi_major_axis_m"]
	_e = orbit["eccentricity"]
	var mu: float = orbit["primary_mu_m3_s2"]
	if not is_finite(_a) or not is_finite(_e) or not is_finite(mu) or _a <= 0.0 or mu <= 0.0 or _e < 0.0 or _e > 0.8:
		return false
	_period = Motion.period_s(_a, mu)
	_phase = orbit["mean_anomaly_at_epoch_rad"]
	_root = sqrt(1.0 - _e * _e)
	_n = TAU / _period
	var axes: Array = Motion.orbital_axes(orbit["ascending_node_rad"], orbit["inclination_rad"], orbit["argument_of_periapsis_rad"])
	_p = axes[0]
	_q = axes[1]
	_spin_period = spin["period_s"]
	_spin_direction = spin["direction"]
	_spin_phase = spin["phase_at_epoch_rad"]
	if not is_finite(_period) or _period <= 0.0 or not is_finite(_spin_period) or _spin_period <= 0.0 or (_spin_direction != 1.0 and _spin_direction != -1.0):
		return false
	_ct = cos(float(spin["axis_tilt_to_system_y_rad"]))
	_st = sin(float(spin["axis_tilt_to_system_y_rad"]))
	_caz = cos(float(spin["pole_azimuth_rad"]))
	_saz = sin(float(spin["pole_azimuth_rad"]))
	# Keep the exact _rotate_y arithmetic, including its zero terms.
	_spin_y = [_caz * (-_st) + _saz * 0.0, _ct, -_saz * (-_st) + _caz * 0.0]
	var omega: float = _spin_direction * TAU / _spin_period
	_angular = [float(_spin_y[0]) * omega, float(_spin_y[1]) * omega, float(_spin_y[2]) * omega]
	for value: float in [_phase, _spin_phase, _ct, _st, _caz, _saz]:
		if not is_finite(value):
			return false
	for axis: int in range(3):
		if not is_finite(float(_p[axis])) or not is_finite(float(_q[axis])):
			return false
	return true

func evaluate(time_s: float, parent_position: Array, parent_velocity: Array) -> Dictionary:
	var started: int = Time.get_ticks_usec() if profile_enabled else 0
	var mean: float = fposmod(_phase + TAU * (fposmod(time_s, _period) / _period), TAU)
	var eccentric: float = mean
	for _iteration: int in range(24):
		var residual: float = eccentric - _e * sin(eccentric) - mean
		var correction: float = residual / (1.0 - _e * cos(eccentric))
		eccentric -= correction
		if absf(correction) < 1.0e-14:
			break
	var ce: float = cos(eccentric)
	var se: float = sin(eccentric)
	var rate: float = _n / (1.0 - _e * ce)
	var px: float = _a * (ce - _e)
	var py: float = _a * _root * se
	var vx: float = -_a * se * rate
	var vy: float = _a * _root * ce * rate
	var local_position: Array[float] = []
	var local_velocity: Array[float] = []
	for axis: int in range(3):
		local_position.append(float(_p[axis]) * px + float(_q[axis]) * py)
		local_velocity.append(float(_p[axis]) * vx + float(_q[axis]) * vy)
	if profile_enabled:
		var now: int = Time.get_ticks_usec()
		orbit_us += now - started
		started = now
	var angle: float = fposmod(_spin_phase + _spin_direction * TAU * fposmod(time_s, _spin_period) / _spin_period, TAU)
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var x0: float = _ct * ca
	var z0: float = _ct * sa
	var x: Array = [_caz * x0 + _saz * (-sa), _st * ca, -_saz * x0 + _caz * (-sa)]
	var z: Array = [_caz * z0 + _saz * ca, _st * sa, -_saz * z0 + _caz * ca]
	var body_axes: Array = [x, _spin_y.duplicate(), z]
	var angular: Array = _angular.duplicate()
	if profile_enabled:
		var now: int = Time.get_ticks_usec()
		spin_us += now - started
		started = now
	var position: Array[float] = []
	var velocity: Array[float] = []
	for axis: int in range(3):
		position.append(float(parent_position[axis]) + float(local_position[axis]))
		velocity.append(float(parent_velocity[axis]) + float(local_velocity[axis]))
	var result: Dictionary = {
		"id": _id, "parent_id": _parent_id,
		"position_m": position, "velocity_m_s": velocity,
		"relative_position_m": local_position,
		"relative_velocity_m_s": local_velocity,
		"body_to_system_axes": body_axes,
		"angular_velocity_rad_s": angular,
	}
	if profile_enabled:
		pack_us += Time.get_ticks_usec() - started
	return result

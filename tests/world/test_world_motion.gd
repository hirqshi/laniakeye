extends SceneTree

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Motion = preload("res://game/world/generation/lk_kepler_motion.gd")
const SystemMotion = preload("res://game/world/generation/lk_system_motion.gd")

var _failures: int = 0
var _worst_residual: float = 0.0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("WorldMotion: FAIL " + label)


func _dot(a: Array, b: Array) -> float:
	return float(a[0]) * float(b[0]) + float(a[1]) * float(b[1]) + float(a[2]) * float(b[2])


func _norm(v: Array) -> float:
	return sqrt(_dot(v, v))


func _cross(a: Array, b: Array) -> Array:
	return [float(a[1]) * float(b[2]) - float(a[2]) * float(b[1]),
		float(a[2]) * float(b[0]) - float(a[0]) * float(b[2]),
		float(a[0]) * float(b[1]) - float(a[1]) * float(b[0])]


func _orbit(e: float) -> Dictionary:
	return {
		"semi_major_axis_m": 1.0e8, "eccentricity": e,
		"primary_mu_m3_s2": 1.0e14, "mean_anomaly_at_epoch_rad": 0.0,
		"ascending_node_rad": 0.0, "inclination_rad": 0.0,
		"argument_of_periapsis_rad": 0.0,
	}


func _initialize() -> void:
	var a: float = 1.0e8
	var mu: float = 1.0e14
	var period: float = Motion.period_s(a, mu)
	var circular: Dictionary = Motion.evaluate(_orbit(0.0), period * 0.25)
	_check(absf(circular["position_m"][0]) / a < 1.0e-12, "circular quarter x")
	_check(absf(circular["position_m"][2] + a) / a < 1.0e-12, "circular quarter z")
	for e: float in [0.0, 0.2, 0.75, 0.8]:
		var orbit: Dictionary = _orbit(e)
		var peri: Dictionary = Motion.evaluate(orbit, 0.0)
		var apo: Dictionary = Motion.evaluate(orbit, period * 0.5)
		_check(absf(_norm(peri["position_m"]) - a * (1.0 - e)) / a < 1.0e-12, "periapsis")
		_check(absf(_norm(apo["position_m"]) - a * (1.0 + e)) / a < 1.0e-12, "apoapsis")
		for fraction: float in [-2.3, -0.1, 0.0, 0.13, 0.5, 0.9, 3.7]:
			var t: float = fraction * period
			var state: Dictionary = Motion.evaluate(orbit, t)
			var position: Array = state["position_m"]
			var velocity: Array = state["velocity_m_s"]
			var energy: float = 0.5 * _dot(velocity, velocity) - mu / _norm(position)
			_check(absf(energy + mu / (2.0 * a)) / (mu / (2.0 * a)) < 1.0e-11, "orbital energy")
			_worst_residual = maxf(_worst_residual, state["kepler_residual_rad"])
			var repeat_state: Dictionary = Motion.evaluate(orbit, t + period)
			for axis: int in range(3):
				_check(absf(position[axis] - repeat_state["position_m"][axis]) / a < 1.0e-11, "orbital periodicity")
			var before: Dictionary = Motion.evaluate(orbit, t - 0.1)
			var after: Dictionary = Motion.evaluate(orbit, t + 0.1)
			for axis: int in range(3):
				var fd: float = (after["position_m"][axis] - before["position_m"][axis]) / 0.2
				_check(absf(fd - float(velocity[axis])) / sqrt(mu / a) < 1.0e-6, "velocity derivative")

	_check(_worst_residual < 1.0e-12, "Kepler residual")
	for direction: float in [-1.0, 1.0]:
		var spin: Dictionary = {
			"period_s": 86400.0, "direction": direction,
			"axis_tilt_to_system_y_rad": 0.6, "pole_azimuth_rad": 1.2,
			"phase_at_epoch_rad": 0.3,
		}
		var rotation: Dictionary = Motion.spin_state(spin, -12345.0)
		var axes: Array = rotation["body_to_system_axes"]
		for i: int in range(3):
			_check(absf(_norm(axes[i]) - 1.0) < 1.0e-12, "unit spin axis")
			_check(absf(_dot(axes[i], axes[(i + 1) % 3])) < 1.0e-12, "orthogonal spin axes")
		_check(_dot(_cross(axes[0], axes[1]), axes[2]) > 0.999999999999, "right-handed spin")
		var before: Dictionary = Motion.spin_state(spin, -12345.1)
		var after: Dictionary = Motion.spin_state(spin, -12344.9)
		var derivative: Array = _cross(rotation["angular_velocity_rad_s"], axes[0])
		for i: int in range(3):
			var fd: float = (after["body_to_system_axes"][0][i] - before["body_to_system_axes"][0][i]) / 0.2
			_check(absf(fd - float(derivative[i])) < 1.0e-12, "angular velocity derivative")

	var catalog = Catalog.new(Identity.universe_id("laniakeye-development-v1"), 1)
	var tested: int = 0
	for x: int in range(-2, 3):
		var sector: Dictionary = catalog.describe_sector(0, x, 0, 0)
		for system: Dictionary in sector["systems"]:
			var definition: Dictionary = SystemMotion.build(system)
			_check(definition == SystemMotion.build(system), "repeatable motion definition")
			var baseline: Dictionary = SystemMotion.evaluate(definition, 1234567.0)
			var unrelated: Dictionary = SystemMotion.evaluate(definition, -9876543.0)
			_check(not unrelated.is_empty(), "negative world time")
			_check(baseline == SystemMotion.evaluate(definition, 1234567.0), "time query order")
			_check(baseline["bodies"].size() == system["planets"].size() + 1, "body count")
			for body: Dictionary in baseline["bodies"]:
				for coordinate: float in body["position_m"]:
					_check(is_finite(coordinate), "finite system position")
			tested += 1
	_check(tested > 0, "nonempty catalog sample")
	print("WorldMotion: systems=%d max_kepler_residual=%.16f rad" % [tested, _worst_residual])
	if _failures == 0:
		print("WorldMotion: PASS Kepler, energy, velocity, spin, determinism")
	quit(0 if _failures == 0 else 1)

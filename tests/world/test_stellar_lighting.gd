extends SceneTree

const StellarLighting = preload("res://world/runtime/lk_stellar_lighting.gd")
const Kepler = preload("res://world/generation/lk_kepler_motion.gd")
const BodyFrame = preload("res://world/runtime/lk_catalog_body_frame.gd")
const Context = preload("res://world/runtime/lk_body_context.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")
const VisualScene = preload("res://scenes/world/test_catalog_stellar_light.gd")

var _failures: int = 0
var _worst_direction_error: float = 0.0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("StellarLighting: FAIL " + label)


func _dot(a: Array, b: Array) -> float:
	return float(a[0]) * float(b[0]) + float(a[1]) * float(b[1]) + float(a[2]) * float(b[2])


func _initialize() -> void:
	var radius: float = 13000000.0
	var a: float = 1.0e11
	var orbit_period: float = 1.0e12
	var orbit: Dictionary = {
		"semi_major_axis_m": a, "eccentricity": 0.0,
		"primary_mu_m3_s2": a * a * a * pow(TAU / orbit_period, 2.0),
		"inclination_rad": 0.0, "ascending_node_rad": 0.0,
		"argument_of_periapsis_rad": 0.0, "mean_anomaly_at_epoch_rad": 0.0,
	}
	var spin: Dictionary = {
		"period_s": 1200.0, "direction": 1.0,
		"axis_tilt_to_system_y_rad": 0.0,
		"pole_azimuth_rad": 0.0, "phase_at_epoch_rad": 0.0,
	}
	var q: Array = [-radius, 0.0, 0.0]
	var noon: Dictionary = StellarLighting.evaluate(orbit, spin, 0.0, q)
	var midnight: Dictionary = StellarLighting.evaluate(orbit, spin, 600.0, q)
	_check(noon["sin_altitude"] > 0.999999, "day side faces star")
	_check(midnight["sin_altitude"] < -0.999999, "night side faces away")
	_check(noon["horizon_visibility"] == 1.0 and midnight["horizon_visibility"] == 0.0, "horizon masking")
	_check(absf(noon["distance_m"] - (a - radius)) < 0.001, "observer offset included")
	var back_orbit: Dictionary = StellarLighting.evaluate(orbit, spin, orbit_period * 0.5, q)
	_check(_dot(noon["to_star_system"], back_orbit["to_star_system"]) < -0.99999, "orbital direction changes sunlight")
	var retrograde: Dictionary = spin.duplicate(true)
	retrograde["direction"] = -1.0
	var forward: Dictionary = StellarLighting.evaluate(orbit, spin, 150.0, q)
	var reverse: Dictionary = StellarLighting.evaluate(orbit, retrograde, 150.0, q)
	_check(float(forward["to_star_body"][2]) * float(reverse["to_star_body"][2]) < 0.0, "retrograde changes apparent motion")
	for direction: Array in [[0.0, 1.0, 0.0], [0.0, -1.0, 0.0], [1.0, 0.0, 0.0]]:
		var basis: Basis = StellarLighting.directional_basis(direction)
		_check(basis.is_finite() and absf(basis.determinant() - 1.0) < 1.0e-5, "finite pole-safe light basis")
		_check(basis.z.dot(Vector3(direction[0], direction[1], direction[2])) > 0.99999, "+Z points toward star")

	var definition = Definition.new()
	var contexts: Array[Dictionary] = []
	for slot: int in [0, 1]:
		var context: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, slot)
		_check(not context.is_empty(), "target context " + str(slot))
		if not context.is_empty():
			contexts.append(context)
	for context: Dictionary in contexts:
		var period: float = context["spin"]["period_s"]
		var r: float = context["body"]["radius_m"]
		var point: Array = [r / sqrt(2.0), r / sqrt(2.0), 0.0]
		var saw_day: bool = false
		var saw_night: bool = false
		for sample: int in range(121):
			var time_s: float = period * float(sample) / 120.0
			var result: Dictionary = StellarLighting.evaluate(context["orbit"], context["spin"], time_s, point)
			_check(not result.is_empty(), "catalog lighting sample")
			if result.is_empty():
				continue
			var to_star: Array = result["to_star_system"]
			_check(absf(_dot(to_star, to_star) - 1.0) < 1.0e-12, "unit star direction")
			# Independent system-frame observer reconstruction through runtime adapter.
			var frame = BodyFrame.new(StringName(context["body"]["id"]), context["spin"], time_s)
			var relative: LkPosition64 = frame.body_to_inertial(LkPosition64.new(point[0], point[1], point[2]))
			var position: Array = Kepler.evaluate(context["orbit"], time_s)["position_m"]
			var expected: LkPosition64 = LkPosition64.new(-float(position[0]) - relative.x, -float(position[1]) - relative.y, -float(position[2]) - relative.z)
			var length: float = expected.length()
			var error: float = Vector3(expected.x / length - float(to_star[0]), expected.y / length - float(to_star[1]), expected.z / length - float(to_star[2])).length()
			_worst_direction_error = maxf(_worst_direction_error, error)
			saw_day = saw_day or bool(result["above_horizon"])
			saw_night = saw_night or not bool(result["above_horizon"])
			_check(result == StellarLighting.evaluate(context["orbit"], context["spin"], time_s, point), "repeatable, no origin-dependent state")
		print("StellarLighting: body=%s period=%.3f min day_seen=%s night_seen=%s" % [
			context["body"]["id"], period / 60.0, saw_day, saw_night,
		])
		# Do not require day+night at an arbitrary latitude: polar day/night is valid.
	_check(_worst_direction_error < 1.0e-10, "runtime frame and lighting agree")
	if contexts.size() == 2:
		var first: Dictionary = StellarLighting.evaluate(contexts[0]["orbit"], contexts[0]["spin"], 0.0, [radius, 0.0, 0.0])
		StellarLighting.evaluate(contexts[1]["orbit"], contexts[1]["spin"], 100.0, [radius, 0.0, 0.0])
		_check(first == StellarLighting.evaluate(contexts[0]["orbit"], contexts[0]["spin"], 0.0, [radius, 0.0, 0.0]), "A-B-A sample isolation")
	print("StellarLighting: direction_error=%.12f" % _worst_direction_error)
	if _failures == 0:
		print("StellarLighting: PASS day/night, ray sign, orbit, retrograde, poles, frame agreement, scene parse")
	quit(0 if _failures == 0 else 1)

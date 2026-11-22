extends SceneTree

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Samples = preload("res://game/world/generation/lk_world_samples.gd")
const Rotation = preload("res://game/world/generation/lk_rotation_periods.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Layout = preload("res://game/world/generation/lk_safe_orbit_layout.gd")
const Validator = preload("res://game/world/generation/lk_orbit_layout_validator.gd")
const Motion = preload("res://game/world/generation/lk_kepler_motion.gd")
const BodyFrame = preload("res://game/world/runtime/lk_catalog_body_frame.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const Context = preload("res://game/world/runtime/lk_body_context.gd")

var _failures: int = 0
var _worst_inverse: float = 0.0
var _worst_carry: float = 0.0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("RotationPeriods: FAIL " + label)


func _legacy_period(id: String) -> float:
	return 21600.0 + 410400.0 * Samples.unit(id, "layout/spin_period", 1)


func _test_entry(entry: Dictionary) -> void:
	var id: String = entry["body"]["id"]
	var spin: Dictionary = entry["spin"]
	_check(spin["rotation_version"] == Rotation.VERSION, "rotation recipe version")
	_check(spin["period_s"] == Rotation.period_s(id), "single authoritative period")
	var old_spin: Dictionary = spin.duplicate(true)
	old_spin.erase("rotation_version")
	old_spin["period_s"] = _legacy_period(id)
	# At epoch zero only the period changed, not pole/direction/phase.
	_check(Motion.spin_state(spin, 0.0)["body_to_system_axes"] == Motion.spin_state(old_spin, 0.0)["body_to_system_axes"], "initial orientation unchanged")
	entry["spin"] = old_spin


func _initialize() -> void:
	_check(is_equal_approx(Rotation.from_samples(0.0, 0.0), 1200.0), "20 minute endpoint")
	_check(is_equal_approx(Rotation.from_samples(0.04, 1.0), 1800.0), "fast upper endpoint")
	_check(is_equal_approx(Rotation.from_samples(0.05, 0.0), 1800.0), "core lower endpoint")
	_check(is_equal_approx(Rotation.from_samples(0.899, 1.0), 10800.0), "core upper endpoint")
	_check(is_equal_approx(Rotation.from_samples(0.90, 0.0), 10800.0), "slow lower endpoint")
	_check(is_equal_approx(Rotation.from_samples(1.0, 1.0), 144000.0), "40 hour endpoint")
	var universe: String = Identity.universe_id("laniakeye-development-v1")
	var ids: Array[String] = []
	var periods: Array[float] = []
	var counts: Array[int] = [0, 0, 0]
	for i: int in range(20000):
		var id: String = Identity.child_id(universe, "rotation_fixture", str(i))
		var period: float = Rotation.period_s(id)
		_check(is_finite(period) and period >= 1200.0 and period <= 144000.0, "period in bounds")
		var band: int = 0 if period < 1800.0 else (1 if period < 10800.0 else 2)
		counts[band] += 1
		ids.append(id)
		periods.append(period)
	for i: int in range(ids.size() - 1, -1, -1):
		_check(Rotation.period_s(ids[i]) == periods[i], "reverse order determinism")
	for i: int in range(3):
		var expected: float = [0.05, 0.85, 0.10][i]
		_check(absf(float(counts[i]) / 20000.0 - expected) < 0.02, "distribution band " + str(i))

	var catalog = Catalog.new(universe, 1)
	var physical: Dictionary = Bodies.build(catalog.describe_system(0, 0, 0, 0, 0))
	var original_physical: Dictionary = physical.duplicate(true)
	var layout: Dictionary = Layout.build(physical)
	_check(physical == original_physical, "physical data not mutated")
	_check(Validator.validate(layout).is_empty(), "layout still valid")
	var legacy: Dictionary = layout.duplicate(true)
	for entry: Dictionary in legacy["planets"]:
		_test_entry(entry)
		for moon: Dictionary in entry["moons"]:
			_test_entry(moon)
	for time_s: float in [-10000.0, 0.0, 123456.0]:
		var current: Array = Layout.evaluate(layout, time_s)["bodies"]
		var previous: Array = Layout.evaluate(legacy, time_s)["bodies"]
		_check(current.size() == previous.size(), "same body count")
		for i: int in range(current.size()):
			_check(current[i]["position_m"] == previous[i]["position_m"], "orbital position unaffected")
			_check(current[i]["velocity_m_s"] == previous[i]["velocity_m_s"], "orbital velocity unaffected")

	var q: LkPosition64 = LkPosition64.new(13000000.0, 0.0, 0.0)
	for period_s: float in [1200.0, 1800.0, 10800.0, 144000.0]:
		for direction: float in [-1.0, 1.0]:
			for hz: float in [30.0, 60.0, 120.0]:
				var spin: Dictionary = {
					"period_s": period_s, "direction": direction,
					"axis_tilt_to_system_y_rad": 0.73, "pole_azimuth_rad": 1.17,
					"phase_at_epoch_rad": 2.03,
				}
				var frame = BodyFrame.new(&"rotation_fixture", spin, -2.0)
				for tick: int in range(180):
					var before: LkPosition64 = frame.body_to_inertial(q)
					var step: float = frame.advance(1.0 / hz)
					var after: LkPosition64 = frame.body_to_inertial(q)
					var carry_error: float = after.minus(before).minus(frame.carry_displacement64(before, step)).length()
					_worst_carry = maxf(_worst_carry, carry_error)
					_worst_inverse = maxf(_worst_inverse, frame.inertial_to_body(after).minus(q).length())
				_check(absf(frame.angular_speed_rad_s - direction * TAU / period_s) < 1.0e-14, "matching angular speed")
	_check(_worst_inverse < 1.0e-6, "inverse precision at 13000 km radius")
	_check(_worst_carry < 1.0e-6, "carry precision including 20 minute spin")
	var definition = Definition.new()
	var context: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, 0)
	_check(not context.is_empty(), "runtime context")
	if not context.is_empty():
		_check(context["spin"]["period_s"] == Rotation.period_s(context["body"]["id"]), "runtime uses generated period")
		_check(not context["manifest"].has("rotation_version"), "terrain journal manifest not tied to spin recipe")
		print("RotationPeriods: body=%s period=%.3f min" % [context["body"]["id"], float(context["spin"]["period_s"]) / 60.0])
	print("RotationPeriods: sample=20000 fast=%d core=%d slow=%d inverse_error=%.9f m carry_error=%.9f m" % [
		counts[0], counts[1], counts[2], _worst_inverse, _worst_carry,
	])
	if _failures == 0:
		print("RotationPeriods: PASS bounds, distribution, determinism, layout, orbit invariance, frame, fast carry")
	quit(0 if _failures == 0 else 1)

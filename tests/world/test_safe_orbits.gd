extends SceneTree

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Layout = preload("res://game/world/generation/lk_safe_orbit_layout.gd")
const Validator = preload("res://game/world/generation/lk_orbit_layout_validator.gd")

var _failures: int = 0
var _systems: int = 0
var _moons: int = 0
var _fixture: Dictionary = {}
var _smallest_gap: float = INF


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SafeOrbits: FAIL " + label)


func _norm(v: Array) -> float:
	return sqrt(float(v[0]) * float(v[0]) + float(v[1]) * float(v[1]) + float(v[2]) * float(v[2]))


func _initialize() -> void:
	var catalog = Catalog.new(Identity.universe_id("laniakeye-development-v1"), 1)
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			for z: int in range(-2, 3):
				var sector: Dictionary = catalog.describe_sector(0, x, y, z)
				for source: Dictionary in sector["systems"]:
					var physical: Dictionary = Bodies.build(source)
					var original: Dictionary = physical.duplicate(true)
					var layout: Dictionary = Layout.build(physical)
					var errors: Array[String] = Validator.validate(layout)
					_check(errors.is_empty(), "analytic validation: " + str(errors))
					_check(physical == original, "physical input unchanged")
					_check(layout == Layout.build(physical), "deterministic layout")
					_systems += 1
					for planet: Dictionary in layout["planets"]:
						_moons += planet["moons"].size()
						if _fixture.is_empty() and planet["body"]["family"] == "gas_giant":
							_fixture = physical.duplicate(true)
	_check(not _fixture.is_empty(), "stress fixture source")
	if not _fixture.is_empty():
		var parent: Dictionary = {}
		for candidate: Dictionary in _fixture["planets"]:
			if candidate["family"] == "gas_giant":
				parent = candidate.duplicate(true)
				break
		parent["moons"] = Bodies.make_moons(parent, 115)
		_fixture["planets"] = [parent]
		var stress: Dictionary = Layout.build(_fixture)
		_check(stress["planets"][0]["moons"].size() == 115, "115 moon count preserved")
		_check(Validator.validate(stress).is_empty(), "115 moon analytic safety")
		var planet: Dictionary = stress["planets"][0]
		var radius_au: float = float(planet["orbit"]["semi_major_axis_m"]) / 149597870700.0
		print("SafeOrbits: stress_moons=115 planet_a=%.3f AU moon_envelope=%.3f million_km" % [
			radius_au, float(planet["envelope_radius_m"]) / 1.0e9,
		])

		var snapshot: Dictionary = Layout.evaluate(stress, 1234567.0)
		var ignored: Dictionary = Layout.evaluate(stress, -9876543.0)
		_check(not ignored.is_empty(), "negative time")
		_check(snapshot == Layout.evaluate(stress, 1234567.0), "evaluation order independence")
		_check(snapshot["bodies"].size() == 117, "star planet and 115 moons")
		for body: Dictionary in snapshot["bodies"]:
			for coordinate: float in body["position_m"]:
				_check(is_finite(coordinate), "finite evaluated position")
		# Finite-time checks supplement, but do not replace analytic safety.
		for t: float in [-1.0e8, 0.0, 1234567.0, 1.0e9]:
			var states: Dictionary = Layout.evaluate(stress, t)
			var ps: Dictionary = states["bodies"][1]
			for i: int in range(2, states["bodies"].size()):
				var ms: Dictionary = states["bodies"][i]
				var relative: Array = ms["relative_position_m"]
				_check(_norm(relative) <= float(planet["envelope_radius_m"]), "moon within envelope at sampled time")
				for axis: int in range(3):
					var reconstructed: float = float(ps["position_m"][axis]) + float(relative[axis])
					_check(reconstructed == float(ms["position_m"][axis]), "hierarchical position composition")

		var damaged: Dictionary = stress.duplicate(true)
		damaged["planets"][0]["envelope_radius_m"] = 1.0
		_check(not Validator.validate(damaged).is_empty(), "reject forged envelope")
		damaged = stress.duplicate(true)
		damaged["planets"][0]["moons"][0]["orbit"]["semi_major_axis_m"] = 1.0
		_check(not Validator.validate(damaged).is_empty(), "reject moon inside planet")
		damaged = stress.duplicate(true)
		damaged["planets"][0]["moons"][1]["orbit"] = damaged["planets"][0]["moons"][0]["orbit"].duplicate(true)
		_check(not Validator.validate(damaged).is_empty(), "reject overlapping moon orbits")
		damaged = stress.duplicate(true)
		damaged["planets"][0]["orbit"]["semi_major_axis_m"] = 1.0
		_check(not Validator.validate(damaged).is_empty(), "reject planet system inside star")
		damaged = stress.duplicate(true)
		damaged["planets"][0]["moons"][0]["body"]["parent_id"] = stress["star"]["id"]
		_check(not Validator.validate(damaged).is_empty(), "reject incorrect moon parent")
		damaged = stress.duplicate(true)
		damaged["planets"][0]["moons"][0]["orbit"]["primary_mu_m3_s2"] *= 2.0
		_check(not Validator.validate(damaged).is_empty(), "reject incorrect primary gravity")
	print("SafeOrbits: systems=%d natural_moons=%d" % [_systems, _moons])
	if _failures == 0:
		print("SafeOrbits: PASS analytic bounds, Roche/Hill policy, 115 moons, motion, negative fixtures")
	quit(0 if _failures == 0 else 1)

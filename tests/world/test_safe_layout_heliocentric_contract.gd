extends SceneTree

const SafeLayout = preload("res://world/generation/lk_safe_orbit_layout.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SafeLayoutHelioContract: FAIL " + label)

func _orbit(id: String, q: float, mu: float) -> Dictionary:
	return {
		"semi_major_axis_m": q,
		"eccentricity": 0.0,
		"primary_mu_m3_s2": mu,
		"inclination_rad": 0.0,
		"ascending_node_rad": 0.0,
		"argument_of_periapsis_rad": 0.0,
		"mean_anomaly_at_epoch_rad": 0.0,
	}

func _spin(id: String) -> Dictionary:
	return {
		"rotation_version": 1,
		"period_s": 3600.0,
		"direction": 1.0,
		"axis_tilt_to_system_y_rad": 0.0,
		"pole_azimuth_rad": 0.0,
		"phase_at_epoch_rad": 0.0,
	}

func _body(id: String, parent_id: String, radius: float, mass: float, mu: float) -> Dictionary:
	return {
		"id": id, "parent_id": parent_id, "kind": "planet",
		"radius_m": radius, "physical_bound_radius_m": radius,
		"mass_kg": mass, "mu_m3_s2": mu, "density_kg_m3": 1000.0,
	}

func _initialize() -> void:
	var star: Dictionary = {
		"id": "star", "parent_id": "", "kind": "star",
		"radius_m": 1000.0, "physical_bound_radius_m": 1000.0,
		"mass_kg": 1.0e30, "mu_m3_s2": 6.674e20, "density_kg_m3": 1000.0,
	}
	var planet: Dictionary = _body("planet", "star", 100.0, 1.0e24, 6.674e13)
	var moon: Dictionary = _body("moon", "planet", 10.0, 1.0e22, 6.674e11)
	var layout: Dictionary = {
		"system_id": "test", "body_schema_version": 1, "layout_version": 1,
		"epoch_s": 0.0, "star": star,
		"planets": [{
			"body": planet, "orbit": _orbit("planet", 10000.0, 6.674e20),
			"spin": _spin("planet"), "envelope_radius_m": 100.0,
			"moon_gap_m": 100.0,
			"moons": [{
				"body": moon, "orbit": _orbit("moon", 1000.0, 6.674e13),
				"spin": _spin("moon"),
			}],
		}],
		"planet_gap_m": 1000000.0, "hill_fraction": 0.25, "roche_factor": 2.44,
	}
	var states: Dictionary = SafeLayout.evaluate(layout, 0.0)
	_check(not states.is_empty(), "layout evaluates")
	if states.is_empty():
		print("SafeLayoutHelioContract: FAIL layout evaluation")
		quit(1)
		return
	var by_id: Dictionary = {}
	for state: Dictionary in states["bodies"]:
		by_id[state["id"]] = state
	_check(by_id.has("star") and by_id.has("planet") and by_id.has("moon"), "all bodies present")
	var star_position: Array = by_id["star"]["position_m"]
	_check(star_position[0] == 0.0 and star_position[1] == 0.0 and star_position[2] == 0.0, "star at origin")
	var planet_position: Array = by_id["planet"]["position_m"]
	var planet_relative: Array = by_id["planet"]["relative_position_m"]
	_check(planet_position[0] == planet_relative[0] and planet_position[1] == planet_relative[1] and planet_position[2] == planet_relative[2], "planet is heliocentric")
	var moon_position: Array = by_id["moon"]["position_m"]
	var moon_relative: Array = by_id["moon"]["relative_position_m"]
	var expected: Array[float] = [
		float(planet_position[0]) + float(moon_relative[0]),
		float(planet_position[1]) + float(moon_relative[1]),
		float(planet_position[2]) + float(moon_relative[2]),
	]
	_check(moon_position[0] == expected[0] and moon_position[1] == expected[1] and moon_position[2] == expected[2], "moon position is planet position plus relative position")
	var moon_squared: float = float(moon_position[0]) * float(moon_position[0]) + float(moon_position[1]) * float(moon_position[1]) + float(moon_position[2]) * float(moon_position[2])
	_check(moon_squared > 0.0, "moon has nonzero heliocentric position")
	if _failures == 0:
		print("SafeLayoutHelioContract: PASS star origin, planet heliocentric, moon parent-sum")
	print("SafeLayoutHelioContract: -position/|position| is the direction toward the origin star")
	quit(0 if _failures == 0 else 1)

class_name LkSafeOrbitLayout
extends RefCounted

const Samples = preload("res://world/generation/lk_world_samples.gd")
const Motion = preload("res://world/generation/lk_kepler_motion.gd")
const VERSION: int = 1
const HILL_FRACTION: float = 0.25
const ROCHE_FACTOR: float = 2.44


static func _u(id: String, key: String) -> float:
	return Samples.unit(id, "layout/" + key, VERSION)


static func _orbit(id: String, q: float, e: float, mu: float, moon: bool) -> Dictionary:
	var inclination: float = 0.15 * _u(id, "inclination")
	if moon:
		inclination = 0.4 * _u(id, "inclination")
		if _u(id, "irregular") < 0.2:
			inclination = PI * _u(id, "irregular_inclination")
	return {
		"semi_major_axis_m": q / (1.0 - e),
		"eccentricity": e,
		"primary_mu_m3_s2": mu,
		"inclination_rad": inclination,
		"ascending_node_rad": TAU * _u(id, "node"),
		"argument_of_periapsis_rad": TAU * _u(id, "periapsis"),
		"mean_anomaly_at_epoch_rad": TAU * _u(id, "phase"),
	}


static func _spin(id: String) -> Dictionary:
	var direction: float = 1.0
	if _u(id, "retrograde_spin") < 0.15:
		direction = -1.0
	return {
		"period_s": 21600.0 + 410400.0 * _u(id, "spin_period"),
		"direction": direction,
		"axis_tilt_to_system_y_rad": PI * 0.5 * _u(id, "spin_tilt"),
		"pole_azimuth_rad": TAU * _u(id, "spin_pole"),
		"phase_at_epoch_rad": TAU * _u(id, "spin_phase"),
	}


static func build(physical: Dictionary) -> Dictionary:
	if physical.is_empty() or int(physical.get("body_schema_version", -1)) != 1:
		push_error("SafeOrbitLayout: expected body schema v1")
		return {}
	var stars: Array = physical["stars"]
	if stars.size() != 1:
		push_error("SafeOrbitLayout: requires one star")
		return {}
	var star: Dictionary = stars[0].duplicate(true)
	var star_radius: float = star["physical_bound_radius_m"]
	var planet_gap: float = maxf(1000000.0, star_radius * 0.1)
	var planet_cursor: float = star_radius
	var planets: Array[Dictionary] = []
	for source: Dictionary in physical["planets"]:
		var body: Dictionary = source.duplicate(true)
		body.erase("moons")
		var parent_radius: float = body["physical_bound_radius_m"]
		var moon_gap: float = maxf(1000.0, parent_radius * 0.02)
		var moon_cursor: float = parent_radius
		var moons: Array[Dictionary] = []
		for source_moon: Dictionary in source["moons"]:
			var moon: Dictionary = source_moon.duplicate(true)
			var radius: float = moon["physical_bound_radius_m"]
			var roche: float = ROCHE_FACTOR * float(body["radius_m"]) * pow(
				float(body["density_kg_m3"]) / float(moon["density_kg_m3"]), 1.0 / 3.0
			)
			var q: float = maxf(moon_cursor + moon_gap + radius, roche * 1.05) * 1.000001
			var e: float = minf(
				0.15 * _u(moon["id"], "eccentricity"),
				0.25 * (moon_gap + 2.0 * radius) / q
			)
			var orbit: Dictionary = _orbit(moon["id"], q, e, body["mu_m3_s2"], true)
			moon_cursor = float(orbit["semi_major_axis_m"]) * (1.0 + e) + radius
			moons.append({"body": moon, "orbit": orbit, "spin": _spin(moon["id"])})
		var envelope: float = maxf(parent_radius, moon_cursor)
		var q: float = planet_cursor + planet_gap + envelope
		if not moons.is_empty():
			var hill_scale: float = pow(float(body["mass_kg"]) / (3.0 * float(star["mass_kg"])), 1.0 / 3.0)
			q = maxf(q, envelope / (HILL_FRACTION * hill_scale))
		q *= 1.000001
		var e: float = 0.25 * _u(body["id"], "eccentricity")
		var orbit: Dictionary = _orbit(body["id"], q, e, star["mu_m3_s2"], false)
		planet_cursor = float(orbit["semi_major_axis_m"]) * (1.0 + e) + envelope
		planets.append({
			"body": body, "orbit": orbit, "spin": _spin(body["id"]),
			"moons": moons, "envelope_radius_m": envelope,
			"moon_gap_m": moon_gap,
		})
	return {
		"system_id": physical["system_id"],
		"body_schema_version": 1, "layout_version": VERSION, "epoch_s": 0.0,
		"star": star, "planets": planets, "planet_gap_m": planet_gap,
		"hill_fraction": HILL_FRACTION, "roche_factor": ROCHE_FACTOR,
	}


static func _state(entry: Dictionary, time_s: float, parent_position: Array, parent_velocity: Array) -> Dictionary:
	var local: Dictionary = Motion.evaluate(entry["orbit"], time_s)
	var spin: Dictionary = Motion.spin_state(entry["spin"], time_s)
	if local.is_empty() or spin.is_empty():
		return {}
	var position: Array[float] = []
	var velocity: Array[float] = []
	for axis: int in range(3):
		position.append(float(parent_position[axis]) + float(local["position_m"][axis]))
		velocity.append(float(parent_velocity[axis]) + float(local["velocity_m_s"][axis]))
	return {
		"id": entry["body"]["id"], "parent_id": entry["body"]["parent_id"],
		"position_m": position, "velocity_m_s": velocity,
		"relative_position_m": local["position_m"],
		"relative_velocity_m_s": local["velocity_m_s"],
		"body_to_system_axes": spin["body_to_system_axes"],
		"angular_velocity_rad_s": spin["angular_velocity_rad_s"],
	}


# Input must first pass LkOrbitLayoutValidator.validate().
# Moon orbital axes use the system frame, NOT the spinning planet frame.
static func evaluate(layout: Dictionary, time_s: float) -> Dictionary:
	if int(layout.get("layout_version", -1)) != VERSION or not is_finite(time_s):
		push_error("SafeOrbitLayout: invalid evaluation request")
		return {}
	var elapsed: float = time_s - float(layout["epoch_s"])
	var zero: Array = [0.0, 0.0, 0.0]
	var result: Array[Dictionary] = [{
		"id": layout["star"]["id"], "position_m": zero.duplicate(),
		"velocity_m_s": zero.duplicate(),
		"body_to_system_axes": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
		"angular_velocity_rad_s": zero.duplicate(),
	}]
	for planet: Dictionary in layout["planets"]:
		var state: Dictionary = _state(planet, elapsed, zero, zero)
		if state.is_empty():
			return {}
		result.append(state)
		for moon: Dictionary in planet["moons"]:
			var moon_state: Dictionary = _state(moon, elapsed, state["position_m"], state["velocity_m_s"])
			if moon_state.is_empty():
				return {}
			result.append(moon_state)
	return {"system_id": layout["system_id"], "time_s": time_s, "bodies": result}

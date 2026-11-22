class_name LkOrbitLayoutValidator
extends RefCounted

const Identity = preload("res://game/world/generation/lk_world_identity.gd")


static func _number(value: float, positive: bool = false) -> bool:
	return is_finite(value) and (not positive or value > 0.0)


static func _body(body: Dictionary, seen: Dictionary, errors: Array[String]) -> bool:
	var id: String = body.get("id", "")
	var valid: bool = true
	if not Identity.is_valid_id(id) or seen.has(id):
		errors.append("invalid or duplicate body ID")
		valid = false
	seen[id] = true
	for field: String in ["radius_m", "physical_bound_radius_m", "mass_kg", "mu_m3_s2"]:
		if not _number(float(body.get(field, -1.0)), true):
			errors.append("invalid physical field: " + field)
			valid = false
	if float(body.get("physical_bound_radius_m", -1.0)) < float(body.get("radius_m", 0.0)):
		errors.append("physical bound smaller than nominal radius")
		valid = false
	return valid


static func _interval(entry: Dictionary, parent: Dictionary, radius: float, errors: Array[String]) -> Array:
	var body: Dictionary = entry["body"]
	if body.get("parent_id", "") != parent["id"]:
		errors.append("incorrect parent ID")
	var orbit: Dictionary = entry["orbit"]
	for key: String in ["semi_major_axis_m", "eccentricity", "primary_mu_m3_s2", "inclination_rad", "ascending_node_rad", "argument_of_periapsis_rad", "mean_anomaly_at_epoch_rad"]:
		if not _number(float(orbit.get(key, NAN))):
			errors.append("nonfinite or missing orbital field: " + key)
			return []
	var a: float = orbit["semi_major_axis_m"]
	var e: float = orbit["eccentricity"]
	if a <= 0.0 or e < 0.0 or e > 0.8:
		errors.append("unsupported orbital shape")
		return []
	var parent_mu: float = parent["mu_m3_s2"]
	if absf(float(orbit["primary_mu_m3_s2"]) - parent_mu) > parent_mu * 1.0e-12:
		errors.append("orbit uses incorrect primary mu")
	var q: float = a * (1.0 - e)
	var ap: float = a * (1.0 + e)
	if not is_finite(q) or not is_finite(ap):
		errors.append("orbital interval overflow")
		return []
	return [q - radius, ap + radius, q, ap]


static func _separate(intervals: Array, gap: float, errors: Array[String], label: String) -> void:
	# Sorting is independent of builder order; adjacent separation proves all pairs.
	var sorted_intervals: Array = intervals.duplicate(true)
	sorted_intervals.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in range(1, sorted_intervals.size()):
		if float(sorted_intervals[i][0]) - float(sorted_intervals[i - 1][1]) < gap:
			errors.append(label + " radial intervals overlap or violate gap")


# Structural prerequisite: dictionaries/arrays follow SafeOrbitLayout v1 schema.
# Returns diagnostics without logging expected failures in negative tests.
static func validate(layout: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(layout.get("layout_version", -1)) != 1:
		errors.append("unsupported layout version")
		return errors
	if not _number(float(layout.get("epoch_s", NAN))):
		errors.append("invalid epoch")
	var star: Dictionary = layout["star"]
	var seen: Dictionary = {}
	if not _body(star, seen, errors):
		return errors
	var planet_gap: float = layout["planet_gap_m"]
	if not _number(planet_gap, true):
		errors.append("invalid planet gap")
		return errors
	if float(layout.get("hill_fraction", -1.0)) != 0.25 or float(layout.get("roche_factor", -1.0)) != 2.44:
		errors.append("unsupported safety policy")
		return errors
	var planet_intervals: Array = []
	for planet: Dictionary in layout["planets"]:
		var body: Dictionary = planet["body"]
		if not _body(body, seen, errors):
			continue
		var moon_gap: float = planet["moon_gap_m"]
		if not _number(moon_gap, true):
			errors.append("invalid moon gap")
			continue
		var envelope: float = body["physical_bound_radius_m"]
		var moon_intervals: Array = []
		for moon: Dictionary in planet["moons"]:
			var mb: Dictionary = moon["body"]
			if not _body(mb, seen, errors):
				continue
			var interval: Array = _interval(moon, body, mb["physical_bound_radius_m"], errors)
			if interval.is_empty():
				continue
			if float(interval[0]) < float(body["physical_bound_radius_m"]) + moon_gap:
				errors.append("moon intersects parent or violates parent gap")
			var pd: float = body.get("density_kg_m3", -1.0)
			var md: float = mb.get("density_kg_m3", -1.0)
			if not _number(pd, true) or not _number(md, true):
				errors.append("invalid density for Roche check")
			else:
				var roche: float = 2.44 * float(body["radius_m"]) * pow(pd / md, 1.0 / 3.0)
				if float(interval[2]) < roche:
					errors.append("moon violates conservative Roche policy")
			moon_intervals.append(interval)
			envelope = maxf(envelope, float(interval[1]))
		_separate(moon_intervals, moon_gap, errors, "moons")
		var stored: float = planet.get("envelope_radius_m", -1.0)
		if not _number(stored, true) or absf(stored - envelope) > maxf(0.001, envelope * 1.0e-12):
			errors.append("stored envelope disagrees with recomputed envelope")
		var interval: Array = _interval(planet, star, envelope, errors)
		if interval.is_empty():
			continue
		if float(interval[0]) < float(star["physical_bound_radius_m"]) + planet_gap:
			errors.append("planet system intersects star or violates gap")
		if not planet["moons"].is_empty():
			var hill: float = float(interval[2]) * pow(float(body["mass_kg"]) / (3.0 * float(star["mass_kg"])), 1.0 / 3.0)
			if envelope > hill * 0.25:
				errors.append("moon system outside conservative Hill budget")
		planet_intervals.append(interval)
	_separate(planet_intervals, planet_gap, errors, "planet systems")
	return errors

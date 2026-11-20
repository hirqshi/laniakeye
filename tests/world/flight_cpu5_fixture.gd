extends RefCounted

static func _entry(id: String, parent_id: String, index: int, moon: bool) -> Dictionary:
	var eccentricities: Array = [0.0, 0.15, 0.25, 0.8]
	return {
		"body": {"id": id, "parent_id": parent_id},
		"orbit": {
			"semi_major_axis_m": 10000000.0 + float(index) * 1000000.0 if moon else 10000000000.0 + float(index) * 1000000000.0,
			"eccentricity": eccentricities[index % 4],
			"primary_mu_m3_s2": 3.986e14 if moon else 1.327e20,
			"mean_anomaly_at_epoch_rad": float(index) * 0.31,
			"ascending_node_rad": float(index) * 0.17,
			"inclination_rad": float(index) * 0.13,
			"argument_of_periapsis_rad": float(index) * 0.23,
		},
		"spin": {
			"period_s": 60.0 + float(index) * 17.0,
			"direction": -1.0 if index % 2 == 0 else 1.0,
			"phase_at_epoch_rad": float(index) * 0.11,
			"axis_tilt_to_system_y_rad": float(index) * 0.07,
			"pole_azimuth_rad": float(index) * 0.19,
		},
		"moons": [],
	}

# Numeric evaluator fixture, NOT a physically validated world-layout fixture.
static func make_layout() -> Dictionary:
	var planets: Array[Dictionary] = []
	for index: int in range(13):
		var id: String = "planet_%02d" % index
		var entry: Dictionary = _entry(id, "star", index, false)
		for moon_index: int in range(22 if index == 0 else 19):
			entry["moons"].append(_entry("%s_moon_%02d" % [id, moon_index], id, moon_index + index, true))
		planets.append(entry)
	return {"layout_version": 1, "body_schema_version": 1, "system_id": "cpu5_numeric_fixture", "epoch_s": 1234.5, "star": {"id": "star"}, "planets": planets}

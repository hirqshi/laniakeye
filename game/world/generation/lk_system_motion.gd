class_name LkSystemMotion
extends RefCounted

const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Samples = preload("res://game/world/generation/lk_world_samples.gd")
const Motion = preload("res://game/world/generation/lk_kepler_motion.gd")

const MOTION_VERSION: int = 1
const AU_M: float = 149597870700.0
# Technical central parameter until star physics is introduced.
const REFERENCE_MU_M3_S2: float = 1.32712440018e20


static func build(system: Dictionary) -> Dictionary:
	if system.is_empty() or int(system.get("catalog_version", -1)) != 1:
		push_error("LkSystemMotion: requires a catalog v1 system")
		return {}
	var stars: Array = system["stars"]
	if stars.size() != 1:
		push_error("LkSystemMotion: only one-star systems are supported")
		return {}
	var planets: Array[Dictionary] = []
	for descriptor: Dictionary in system["planets"]:
		var id: String = descriptor["id"]
		var slot: int = descriptor["slot"]
		var direction: float = 1.0
		if Samples.unit(id, "motion/spin_direction", MOTION_VERSION) < 0.15:
			direction = -1.0
		planets.append({
			"id": id,
			"primary_id": descriptor["primary_id"],
			"orbit": {
				"semi_major_axis_m": 0.35 * AU_M * pow(1.8, float(slot)),
				"eccentricity": 0.2 * Samples.unit(id, "motion/eccentricity", MOTION_VERSION),
				"primary_mu_m3_s2": REFERENCE_MU_M3_S2,
				"inclination_rad": 0.1 * Samples.unit(id, "motion/inclination", MOTION_VERSION),
				"ascending_node_rad": TAU * Samples.unit(id, "motion/node", MOTION_VERSION),
				"argument_of_periapsis_rad": TAU * Samples.unit(id, "motion/periapsis", MOTION_VERSION),
				"mean_anomaly_at_epoch_rad": TAU * Samples.unit(id, "motion/anomaly", MOTION_VERSION),
			},
			"spin": {
				"period_s": 21600.0 + 410400.0 * Samples.unit(id, "motion/spin_period", MOTION_VERSION),
				"direction": direction,
				"axis_tilt_to_system_y_rad": PI * 0.5 * Samples.unit(id, "motion/tilt", MOTION_VERSION),
				"pole_azimuth_rad": TAU * Samples.unit(id, "motion/pole", MOTION_VERSION),
				"phase_at_epoch_rad": TAU * Samples.unit(id, "motion/spin_phase", MOTION_VERSION),
			},
		})
	return {
		"system_id": system["id"],
		"motion_version": MOTION_VERSION,
		"epoch_s": 0.0,
		"primary_id": stars[0]["id"],
		"primary_mu_m3_s2": REFERENCE_MU_M3_S2,
		"planets": planets,
	}


static func evaluate(definition: Dictionary, time_s: float) -> Dictionary:
	if definition.is_empty() or int(definition.get("motion_version", -1)) != MOTION_VERSION:
		push_error("LkSystemMotion: unsupported motion definition")
		return {}
	if not is_finite(time_s):
		push_error("LkSystemMotion: non-finite time")
		return {}
	var elapsed: float = time_s - float(definition["epoch_s"])
	var bodies: Array[Dictionary] = [{
		"id": definition["primary_id"],
		"position_m": [0.0, 0.0, 0.0],
		"velocity_m_s": [0.0, 0.0, 0.0],
		"body_to_system_axes": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
		"angular_velocity_rad_s": [0.0, 0.0, 0.0],
	}]
	for planet: Dictionary in definition["planets"]:
		var state: Dictionary = Motion.evaluate(planet["orbit"], elapsed)
		var rotation: Dictionary = Motion.spin_state(planet["spin"], elapsed)
		if state.is_empty() or rotation.is_empty():
			return {}
		state["id"] = planet["id"]
		state["primary_id"] = planet["primary_id"]
		state.merge(rotation)
		bodies.append(state)
	return {"system_id": definition["system_id"], "time_s": time_s, "bodies": bodies}

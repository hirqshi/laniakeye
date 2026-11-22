extends RefCounted

const Body = preload("res://game/debug/lk_compiled_kepler_body.gd")
var evaluations: int = 0
var _profile_evaluations: int = 0
var _profiling: bool = false
var _system_id: String = ""
var _star_id: String = ""
var _epoch_s: float = 0.0
var _bodies: Array = []
var _parents: Array[int] = []

func configure(layout: Dictionary) -> bool:
	_system_id = ""
	_bodies.clear()
	_parents.clear()
	evaluations = 0
	_profile_evaluations = 0
	_profiling = false
	if layout.get("layout_version", -1) != 1 or not layout.has_all(["system_id", "star", "epoch_s", "planets"]):
		return false
	_epoch_s = float(layout["epoch_s"])
	if not is_finite(_epoch_s):
		return false
	for planet: Dictionary in layout["planets"]:
		var planet_index: int = _bodies.size() + 1
		if not _append(planet, 0):
			return false
		for moon: Dictionary in planet["moons"]:
			if not _append(moon, planet_index):
				return false
	_system_id = layout["system_id"]
	_star_id = layout["star"]["id"]
	return not _system_id.is_empty()

func _append(entry: Dictionary, parent_index: int) -> bool:
	var body = Body.new()
	if not body.configure(entry):
		return false
	_bodies.append(body)
	_parents.append(parent_index)
	return true

func set_profile_enabled(enabled: bool) -> void:
	_profiling = enabled
	for body in _bodies:
		body.profile_enabled = enabled

func profile_summary() -> Dictionary:
	var orbit: int = 0
	var spin: int = 0
	var pack: int = 0
	for body in _bodies:
		orbit += body.orbit_us
		spin += body.spin_us
		pack += body.pack_us
	var divisor: float = 1000.0 * maxf(1.0, float(_profile_evaluations))
	return {"evaluations": evaluations, "profiled_evaluations": _profile_evaluations, "orbit_ms": float(orbit) / divisor, "spin_ms": float(spin) / divisor, "body_pack_ms": float(pack) / divisor}

# Fresh snapshots per epoch: never overwrite arrays retained by prior consumers.
func evaluate(time_s: float) -> Dictionary:
	if _system_id.is_empty() or not is_finite(time_s):
		return {}
	var elapsed: float = time_s - _epoch_s
	if not is_finite(elapsed):
		return {}
	var zero: Array = [0.0, 0.0, 0.0]
	var result: Array[Dictionary] = [{
		"id": _star_id, "position_m": zero.duplicate(), "velocity_m_s": zero.duplicate(),
		"body_to_system_axes": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
		"angular_velocity_rad_s": zero.duplicate(),
	}]
	for index: int in range(_bodies.size()):
		var parent: Dictionary = result[_parents[index]]
		result.append(_bodies[index].evaluate(elapsed, parent["position_m"], parent["velocity_m_s"]))
	evaluations += 1
	if _profiling:
		_profile_evaluations += 1
	return {"system_id": _system_id, "time_s": time_s, "bodies": result}

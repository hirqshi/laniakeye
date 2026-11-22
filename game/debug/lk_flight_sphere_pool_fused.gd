extends "res://game/debug/lk_flight_sphere_pool.gd"

# Same borrowed Array/Dictionary interface and fail-closed result as CPU4.
# Scratch rows may be partially overwritten on invalid input; never consume them
# after valid=false. No scratch rows may escape the current main-thread tick.
func build(states: Dictionary, observer: LkPosition64, epoch: float, local_ready: bool) -> Array:
	valid = false
	error = "invalid_state_scope"
	nearest_height = INF
	nearest_label = ""
	if _system_id.is_empty() or states.get("system_id", "") != _system_id or states.get("time_s", NAN) != epoch or not is_finite(epoch):
		return []
	if not states.get("bodies", null) is Array:
		return []
	var bodies: Array = states["bodies"]
	var n: int = _ids.size()
	if bodies.size() != n or not is_finite(observer.x) or not is_finite(observer.y) or not is_finite(observer.z):
		return []
	if _active_index < 0 or _active_index >= n or not bodies[_active_index] is Dictionary:
		return []
	var active: Variant = bodies[_active_index].get("position_m", null)
	if not active is Array or active.size() != 3:
		error = "body_order_or_position_mismatch"
		return []
	var ax: float = float(active[0])
	var ay: float = float(active[1])
	var az: float = float(active[2])
	if not is_finite(ax) or not is_finite(ay) or not is_finite(az):
		error = "nonfinite_body_position"
		return []
	# Remove only the approach-sphere tail appended by the existing caller.
	_rows.resize(n)
	for index: int in range(n):
		if not bodies[index] is Dictionary:
			error = "body_order_or_position_mismatch"
			return []
		var state: Dictionary = bodies[index]
		var position: Variant = state.get("position_m", null)
		if state.get("id", "") != _ids[index] or not position is Array or position.size() != 3:
			error = "body_order_or_position_mismatch"
			return []
		var px: float = float(position[0])
		var py: float = float(position[1])
		var pz: float = float(position[2])
		if not is_finite(px) or not is_finite(py) or not is_finite(pz):
			error = "nonfinite_body_position"
			return []
		var x: float = -observer.x
		var y: float = -observer.y
		var z: float = -observer.z
		if index != _active_index:
			x += px - ax
			y += py - ay
			z += pz - az
		var radius: float = _radii[index]
		var distance: float = sqrt(x * x + y * y + z * z)
		var height: float = distance - radius
		if height < nearest_height:
			nearest_height = height
			nearest_label = _labels[index]
		var row: Dictionary = _rows[index]
		var center: Array = row["center"]
		center[0] = x
		center[1] = y
		center[2] = z
		row["radius"] = radius + (32.0 if index != _active_index or not local_ready else 0.0)
	valid = true
	error = ""
	calls += 1
	return _rows

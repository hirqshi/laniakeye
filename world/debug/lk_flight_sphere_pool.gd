class_name LkFlightSpherePool
extends RefCounted

var valid: bool = false
var error: String = "not_bound"
var nearest_height: float = INF
var nearest_label: String = ""
var calls: int = 0
var _system_id: String = ""
var _ids: Array[String] = []
var _labels: Array[String] = []
var _radii: PackedFloat64Array = []
var _rows: Array = []
var _active_index: int = -1

func configure(layout: Dictionary, active_id: String) -> bool:
	valid = false
	error = "invalid_layout"
	_system_id = ""
	_ids.clear()
	_labels.clear()
	_radii.clear()
	_rows.clear()
	_active_index = -1
	calls = 0
	if int(layout.get("layout_version", -1)) != 1 or String(layout.get("system_id", "")).is_empty() or not layout.has_all(["star", "planets"]):
		return false
	var descriptors: Array = [layout["star"]]
	for entry: Dictionary in layout["planets"]:
		descriptors.append(entry["body"])
		for moon: Dictionary in entry["moons"]:
			descriptors.append(moon["body"])
	var seen: Dictionary = {}
	for body: Dictionary in descriptors:
		var id: String = String(body.get("id", ""))
		var radius: float = float(body.get("radius_m", -1.0))
		if id.is_empty() or seen.has(id) or not is_finite(radius) or radius <= 0.0:
			return false
		seen[id] = true
		if id == active_id:
			_active_index = _ids.size()
		_ids.append(id)
		_labels.append(id.left(8))
		_radii.append(radius)
		_rows.append({"center": [0.0, 0.0, 0.0], "radius": radius})
	if _active_index < 0:
		error = "active_body_missing"
		return false
	_system_id = layout["system_id"]
	valid = true
	error = ""
	return true

# BORROWED until next build. This array/rows must not escape the flight tick.
# The audited AutoSurface caller may append one approach sphere; resize removes
# that tail before next build. Metadata and centre arrays are never input states.
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
	if bodies.size() != _ids.size() or not is_finite(observer.x) or not is_finite(observer.y) or not is_finite(observer.z):
		return []
	# Full row-order validation: never silently attach a radius to another ID.
	for index: int in range(bodies.size()):
		var state: Dictionary = bodies[index]
		var position: Variant = state.get("position_m", null)
		if state.get("id", "") != _ids[index] or not position is Array or position.size() != 3:
			error = "body_order_or_position_mismatch"
			return []
		if not is_finite(float(position[0])) or not is_finite(float(position[1])) or not is_finite(float(position[2])):
			error = "nonfinite_body_position"
			return []
	var active: Array = bodies[_active_index]["position_m"]
	_rows.resize(_ids.size())
	for index: int in range(bodies.size()):
		var position: Array = bodies[index]["position_m"]
		# Preserve legacy arithmetic order, including exact active-body centre.
		var x: float = -observer.x
		var y: float = -observer.y
		var z: float = -observer.z
		if index != _active_index:
			x += float(position[0]) - float(active[0])
			y += float(position[1]) - float(active[1])
			z += float(position[2]) - float(active[2])
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

class_name LkFlightSpherePoolPacked
extends RefCounted

var valid: bool = false
var error: String = "not_bound"
var nearest_height: float = INF
var nearest_label: String = ""
var calls: int = 0
var count: int = 0
var centers: PackedFloat64Array = PackedFloat64Array()
var radii: PackedFloat64Array = PackedFloat64Array()
var _system_id: String = ""
var _ids: Array[String] = []
var _labels: Array[String] = []
var _base_radii: PackedFloat64Array = PackedFloat64Array()
var _active_index: int = -1

func configure(layout: Dictionary, active_id: String) -> bool:
	valid = false
	error = "invalid_layout"
	_system_id = ""
	_ids.clear()
	_labels.clear()
	_base_radii.clear()
	centers.clear()
	radii.clear()
	count = 0
	calls = 0
	_active_index = -1
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
		_base_radii.append(radius)
	if _active_index < 0:
		error = "active_body_missing"
		return false
	_system_id = layout["system_id"]
	valid = false
	error = "no_build_yet"
	return true

# BORROWED until next build. Centers/radii are reused packed buffers.
# Do not retain them across ticks or mutate them.
func build_packed(states: Dictionary, observer: LkPosition64, epoch: float, local_ready: bool) -> bool:
	valid = false
	error = "invalid_state_scope"
	nearest_height = INF
	nearest_label = ""
	count = 0
	if _system_id.is_empty() or states.get("system_id", "") != _system_id or states.get("time_s", NAN) != epoch or not is_finite(epoch):
		return false
	if not states.get("bodies", null) is Array:
		return false
	var bodies: Array = states["bodies"]
	var n: int = _ids.size()
	if bodies.size() != n or not is_finite(observer.x) or not is_finite(observer.y) or not is_finite(observer.z):
		return false
	for index: int in range(n):
		var state: Dictionary = bodies[index]
		var position: Variant = state.get("position_m", null)
		if state.get("id", "") != _ids[index] or not position is Array or position.size() != 3:
			error = "body_order_or_position_mismatch"
			return false
		if not is_finite(float(position[0])) or not is_finite(float(position[1])) or not is_finite(float(position[2])):
			error = "nonfinite_body_position"
			return false
	if centers.size() != 3 * n:
		centers.resize(3 * n)
	if radii.size() != n:
		radii.resize(n)
	var active: Array = bodies[_active_index]["position_m"]
	for index: int in range(n):
		var position: Array = bodies[index]["position_m"]
		# Preserve legacy arithmetic order, including exact active-body centre.
		var x: float = -observer.x
		var y: float = -observer.y
		var z: float = -observer.z
		if index != _active_index:
			x += float(position[0]) - float(active[0])
			y += float(position[1]) - float(active[1])
			z += float(position[2]) - float(active[2])
		var base_radius: float = _base_radii[index]
		var distance: float = sqrt(x * x + y * y + z * z)
		var height: float = distance - base_radius
		if height < nearest_height:
			nearest_height = height
			nearest_label = _labels[index]
		centers[3 * index] = x
		centers[3 * index + 1] = y
		centers[3 * index + 2] = z
		radii[index] = base_radius + (32.0 if index != _active_index or not local_ready else 0.0)
	count = n
	valid = true
	error = ""
	calls += 1
	return true

class_name LkFarBodySnapshot
extends RefCounted

const SafeLayout = preload("res://world/generation/lk_safe_orbit_layout.gd")


static func build(layout: Dictionary, active_id: String, observer: LkPosition64, epoch_s: float, provided_states: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var states: Dictionary = provided_states
	if not states.is_empty() and (states.get("system_id", "") != layout.get("system_id", "") or states.get("time_s", NAN) != epoch_s):
		push_error("FarSnapshot: provided state scope/time mismatch")
		return result
	if states.is_empty():
		states = SafeLayout.evaluate(layout, epoch_s)
	if states.is_empty():
		return result
	var descriptors: Dictionary = {layout["star"]["id"]: layout["star"]}
	for entry: Dictionary in layout["planets"]:
		descriptors[entry["body"]["id"]] = entry["body"]
		for moon: Dictionary in entry["moons"]:
			descriptors[moon["body"]["id"]] = moon["body"]
	var by_id: Dictionary = {}
	for state: Dictionary in states["bodies"]:
		by_id[state["id"]] = state
	if not by_id.has(active_id):
		return result
	var active_position: Array = by_id[active_id]["position_m"]
	for state: Dictionary in states["bodies"]:
		var id: String = state["id"]
		var body: Dictionary = descriptors[id]
		var p: Array = state["position_m"]
		var center: Array[float] = []
		var distance_squared: float = 0.0
		var offsets: Array = [observer.x, observer.y, observer.z]
		for axis: int in range(3):
			# Exact body-local relative centre for the active body; no cancellation
			# of two astronomical planet positions near its surface.
			var c: float = -float(offsets[axis])
			if id != active_id:
				c += float(p[axis]) - float(active_position[axis])
			center.append(c)
			distance_squared += c * c
		if distance_squared <= 0.0:
			continue
		var distance: float = sqrt(distance_squared)
		var radius: float = body["radius_m"]
		var direction: Array = [center[0] / distance, center[1] / distance, center[2] / distance]
		var star: bool = body["kind"] == "star"
		var sun: Array = [0.0, 1.0, 0.0]
		if not star:
			var length: float = sqrt(float(p[0]) * float(p[0]) + float(p[1]) * float(p[1]) + float(p[2]) * float(p[2]))
			sun = [-float(p[0]) / length, -float(p[1]) / length, -float(p[2]) / length]
		result.append({
			"id": id, "active": id == active_id, "star": star,
			"family": body.get("family", "star"), "radius_m": radius,
			"center_m": center, "direction": direction, "distance_m": distance,
			"radius_relative": radius / distance,
			"angular_radius_rad": asin(clampf(radius / distance, 0.0, 1.0)),
			"sun_direction": sun,
			"inside": distance < radius - 0.5,
		})
	return result


# GPU budget is explicit. Keep active sphere and star, then largest angular discs
# not wholly behind the view hemisphere. Report every omitted candidate.
static func select(records: Array[Dictionary], forward: Vector3, max_count: int, min_angle: float) -> Dictionary:
	var chosen: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	var filtered: int = 0
	for record: Dictionary in records:
		if record["active"]:
			chosen.push_front(record)
		elif record["star"]:
			chosen.append(record)
		else:
			var d: Array = record["direction"]
			var facing: float = float(d[0]) * forward.x + float(d[1]) * forward.y + float(d[2]) * forward.z
			if float(record["angular_radius_rad"]) < min_angle or facing < -sin(float(record["angular_radius_rad"])):
				filtered += 1
			else:
				others.append(record)
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["angular_radius_rad"] == b["angular_radius_rad"]:
			return String(a["id"]) < String(b["id"])
		return float(a["angular_radius_rad"]) > float(b["angular_radius_rad"])
	)
	var budget: int = maxi(max_count - chosen.size(), 0)
	var included: int = mini(budget, others.size())
	for index: int in range(included):
		chosen.append(others[index])
	return {"bodies": chosen, "total": records.size(), "filtered": filtered, "budget_omitted": others.size() - included}


# CPU equivalent of normalized sphere intersection in the batch shader.
static func ray_distance(record: Dictionary, ray: Array) -> float:
	var c: Array = record["direction"]
	var along: float = float(c[0]) * float(ray[0]) + float(c[1]) * float(ray[1]) + float(c[2]) * float(ray[2])
	var perpendicular_squared: float = 0.0
	for i: int in range(3):
		var v: float = float(c[i]) - along * float(ray[i])
		perpendicular_squared += v * v
	var radius: float = record["radius_relative"]
	var disc: float = radius * radius - perpendicular_squared
	if disc < 0.0:
		return -1.0
	var root: float = sqrt(disc)
	var hit: float = along - root
	if hit <= 0.0:
		hit = along + root
	return hit * float(record["distance_m"]) if hit > 0.0 else -1.0

# SNAPSHOT_CPU3_OPTIONAL_STATES_V1: callers without fifth argument unchanged.

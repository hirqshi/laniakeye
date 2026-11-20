extends RefCounted

# Exact scalar expansion of NavSnapshot.ray_distance inside the original loop.
# No broad-phase cutoff, approximate geometry, cached rays or omitted bodies.
static func occluded(records: Array, relative: Array, distance: float, ignore_body: String = "") -> bool:
	if distance < 0.01:
		return false
	var rx: float = relative[0] / distance
	var ry: float = relative[1] / distance
	var rz: float = relative[2] / distance
	for record: Dictionary in records:
		if record["id"] == ignore_body:
			continue
		var c: Array = record["direction"]
		var cx: float = float(c[0])
		var cy: float = float(c[1])
		var cz: float = float(c[2])
		var along: float = cx * rx + cy * ry + cz * rz
		var perpendicular_squared: float = 0.0
		var v: float = cx - along * rx
		perpendicular_squared += v * v
		v = cy - along * ry
		perpendicular_squared += v * v
		v = cz - along * rz
		perpendicular_squared += v * v
		var radius: float = record["radius_relative"]
		var disc: float = radius * radius - perpendicular_squared
		if disc < 0.0:
			continue
		var root: float = sqrt(disc)
		var hit: float = along - root
		if hit <= 0.0:
			hit = along + root
		var metric_hit: float = hit * float(record["distance_m"]) if hit > 0.0 else -1.0
		if metric_hit > 0.0 and metric_hit < distance - 2.0:
			return true
	return false
